/**
 * Api_GoogleMapsService
 * =====================
 * Isolated service for all Google Maps Platform API calls.
 * Covers three distinct Google APIs:
 *   1. Places (New) – computeInsights    → competitor count per city
 *   2. Places (New) – Text Search        → lat/lng + placeId for a store
 *   3. Places (New) – Place Details      → rating for a known placeId
 *   4. Distance Matrix                   → driving distance between two coordinates
 *
 * Improvements over DynamicDataService (which remains untouched):
 *   [+] Retry via ApiCalloutRetry (up to 2 additional attempts on 5xx)
 *   [+] Structured logging to API_Log__c via ApiLogger
 *   [+] In-transaction lat/lng cache: searchPlace results keyed by store Name
 *     -- avoids duplicate Text Search calls for the same store in the same chunk
 *   [+] Skip-if-populated guard: getStoreCoordinates() returns null immediately
 *     if Latitude__c is already set, saving billable API calls
 *
 * NAMED CREDENTIAL ENDPOINTS (active)
 * -------------------------------------
 * All callouts go through Named Credentials — the Google API key is stored
 * exclusively in the Google_Maps_EC External Credential principal and is
 * never visible in Apex code or source control.
 *
 * Activation: ApiConfigService.isActive('Google_Maps') reads Is_Active__c
 * from API_Config__mdt.  The API key field on that record is now unused
 * and should be set to 'NC_MANAGED' as a visual indicator.
 */
public with sharing class Api_GoogleMapsService {

    // ── Provider key (matches API_Config__mdt DeveloperName) ─────────────────
    private static final String PROVIDER = 'Google_Maps';

    // ── Named Credential endpoints ──────────────────────────────────────────
    // Keys are injected by Google_Maps_EC External Credential — never in code.
    private static final String PLACES_BASE_URL   = 'callout:Google_Places_NC/v1';
    private static final String DISTANCE_BASE_URL = 'callout:Google_Maps_NC/maps/api/distancematrix/json';
    private static final Integer TIMEOUT_MS       = 15000;

    // ── Cost constants (USD per call, Google Maps Platform pricing) ───────────
    public static final Decimal COST_COMPUTE_INSIGHTS = 0.005;
    public static final Decimal COST_TEXT_SEARCH       = 0.017;
    public static final Decimal COST_PLACE_DETAILS     = 0.017;
    public static final Decimal COST_DISTANCE_MATRIX   = 0.005;

    // ── GeoPoint: groups lat+lng to avoid long param lists on distance calls ─
    public class GeoPoint {
        public Decimal lat;
        public Decimal lng;
        public GeoPoint(Decimal lat, Decimal lng) {
            this.lat = lat;
            this.lng = lng;
        }
    }

    // ── In-transaction result cache ───────────────────────────────────────────
    // Key = store name (as used in the Text Search query), Value = PlaceResult.
    // Prevents duplicate searchPlace calls for the same store within one execute() chunk.
    @TestVisible
    private static Map<String, PlaceResult> placeCache = new Map<String, PlaceResult>();

    // ─────────────────────────────────────────────────────────────────────────
    // CALL CONTEXT -- reduces parameter counts for PMD compliance
    // ─────────────────────────────────────────────────────────────────────────
    public class CallContext {
        public String batchMode;
        public String recordId;   // 18-char Salesforce record Id for log traceability
        public String cacheKey;   // dedup key used by placeCache (typically store Name)

        public CallContext(String batchMode, String recordId) {
            this.batchMode = batchMode;
            this.recordId  = recordId;
        }

        public CallContext withCacheKey(String key) {
            this.cacheKey = key;
            return this;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VALUE OBJECT – replaces DynamicDataService.PlaceSearchResult
    // ─────────────────────────────────────────────────────────────────────────
    public class PlaceResult {
        public String  placeId;
        public Decimal latitude;
        public Decimal longitude;
    }

    /**
     * Returns the count of supermarket + grocery_store Places within 15 km of a city centre.
     * Returns null when the config is inactive, coordinates are missing, or the call fails.
     *
     * @param cityLat  City centre latitude.
     * @param cityLng  City centre longitude.
     * @param ctx      CallContext (batchMode + recordId for logging).
     */
    public static Integer getCompetitorCount(Decimal cityLat, Decimal cityLng, CallContext ctx) {
        if (cityLat == null || cityLng == null) { return null; }

        // City-level cache: prevents duplicate computeInsights calls for the same city
        // across records within one batch chunk (and future multi-record city grouping).
        String cKey = CacheService.cityKey(cityLat, cityLng);
        if (CacheService.hasCompetitorCount(cKey)) {
            return CacheService.getCompetitorCount(cKey);
        }

        if (!ApiConfigService.isActive(PROVIDER)) { return null; }

        String endpoint = PLACES_BASE_URL + '/places:computeInsights';
        String body     = buildComputeInsightsBody(cityLat, cityLng);

        HttpRequest req = buildPlacesPostRequest(endpoint, body);
        req.setHeader('X-Goog-FieldMask', 'insightsResult.placeInsights.insight');

        ApiCalloutRetry.Result result = ApiCalloutRetry.execute(req);
        ApiLogger.LogContext logCtx = new ApiLogger.LogContext(PROVIDER, endpoint, ctx.batchMode)
            .withEstimatedCost(COST_COMPUTE_INSIGHTS);
        ApiLogger.log(ApiLogger.entry(logCtx, result));

        if (!result.isOk()) { return null; }
        Integer count = parseCompetitorCount(result.response.getBody());
        CacheService.putCompetitorCount(cKey, count);
        return count;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. searchPlace -- Text Search for lat/lng + placeId
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Resolves a text query (e.g. "DMart, Mumbai, India") to coordinates + placeId.
     * Results are cached in-transaction by ctx.cacheKey to prevent duplicate calls.
     *
     * @param query  Free-text search query.
     * @param ctx    CallContext -- set cacheKey to the store Name for dedup.
     */
    public static PlaceResult searchPlace(String query, CallContext ctx) {
        if (String.isBlank(query)) { return null; }

        // Return from in-transaction cache if already fetched this chunk
        if (placeCache.containsKey(ctx.cacheKey)) {
            return placeCache.get(ctx.cacheKey);
        }

        if (!ApiConfigService.isActive(PROVIDER)) { return null; }

        String endpoint = PLACES_BASE_URL + '/places:searchText';
        String body     = buildTextSearchBody(query);

        HttpRequest req = buildPlacesPostRequest(endpoint, body);
        req.setHeader('X-Goog-FieldMask', 'places.id,places.location');

        ApiCalloutRetry.Result result2 = ApiCalloutRetry.execute(req);
        ApiLogger.LogContext logCtx2 = new ApiLogger.LogContext(PROVIDER, endpoint, ctx.batchMode)
            .withRecordId(ctx.recordId)
            .withEstimatedCost(COST_TEXT_SEARCH);
        ApiLogger.log(ApiLogger.entry(logCtx2, result2));

        if (!result2.isOk()) { return null; }

        PlaceResult parsed = parseSearchPlace(result2.response.getBody());
        if (parsed != null) {
            placeCache.put(ctx.cacheKey, parsed);
        }
        return parsed;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. getPlaceRating -- Place Details fetch
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns the Google rating (0-5) for a known placeId.
     *
     * @param placeId  Google Place ID.
     * @param ctx      CallContext (batchMode + recordId for logging).
     */
    public static Decimal getPlaceRating(String placeId, CallContext ctx) {
        if (String.isBlank(placeId)) { return null; }

        if (!ApiConfigService.isActive(PROVIDER)) { return null; }

        String endpoint = PLACES_BASE_URL + '/places/' + EncodingUtil.urlEncode(placeId, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('X-Goog-FieldMask', 'rating,userRatingCount');
        req.setTimeout(TIMEOUT_MS);

        ApiCalloutRetry.Result result3 = ApiCalloutRetry.execute(req);
        ApiLogger.LogContext logCtx3 = new ApiLogger.LogContext(PROVIDER, endpoint, ctx.batchMode)
            .withRecordId(ctx.recordId)
            .withEstimatedCost(COST_PLACE_DETAILS);
        ApiLogger.log(ApiLogger.entry(logCtx3, result3));

        if (!result3.isOk()) { return null; }
        return parseRating(result3.response.getBody());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. getDrivingDistanceKm -- Distance Matrix
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Driving distance in km between an origin and destination GeoPoint pair.
     *
     * @param origin  Origin GeoPoint (lat + lng).
     * @param dest    Destination GeoPoint (lat + lng).
     * @param ctx     CallContext (batchMode + recordId for logging).
     */
    public static Decimal getDrivingDistanceKm(GeoPoint origin, GeoPoint dest, CallContext ctx) {
        // Single guard replaces two separate null-check blocks (reduces cognitive complexity)
        if (isGeoInvalid(origin) || isGeoInvalid(dest)) { return null; }

        // Distance cache: same origin/destination pair is served from cache without a callout.
        // Expansion sites repeatedly measured against the same distribution centre lat/lng
        // only incur one billable call per batch run.
        String originStr = origin.lat + ',' + origin.lng;
        String destStr   = dest.lat   + ',' + dest.lng;
        String dKey      = CacheService.distanceKey(originStr, destStr);
        if (CacheService.hasDistance(dKey)) {
            return CacheService.getDistance(dKey);
        }

        if (!ApiConfigService.isActive(PROVIDER)) { return null; }

        String endpoint = DISTANCE_BASE_URL
            + '?origins='      + EncodingUtil.urlEncode(originStr, 'UTF-8')
            + '&destinations=' + EncodingUtil.urlEncode(destStr, 'UTF-8')
            + '&mode=driving';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(TIMEOUT_MS);

        ApiCalloutRetry.Result result4 = ApiCalloutRetry.execute(req);
        ApiLogger.LogContext logCtx4 = new ApiLogger.LogContext(PROVIDER, DISTANCE_BASE_URL, ctx.batchMode)
            .withRecordId(ctx.recordId)
            .withEstimatedCost(COST_DISTANCE_MATRIX);
        ApiLogger.log(ApiLogger.entry(logCtx4, result4));

        if (!result4.isOk()) { return null; }
        Decimal km = parseDistanceKm(result4.response.getBody());
        CacheService.putDistance(dKey, km);
        return km;
    }

    // ─────────────────────────────────────────────────────────────────────────

    // PRIVATE — Request builders
    // ─────────────────────────────────────────────────────────────────────────

    // API key is injected by Named Credential — never passed as a parameter.
    private static HttpRequest buildPlacesPostRequest(String endpoint, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(body);
        req.setTimeout(TIMEOUT_MS);
        return req;
    }

    private static String buildComputeInsightsBody(Decimal lat, Decimal lng) {
        return JSON.serialize(new Map<String, Object>{
            'insights' => new List<String>{ 'INSIGHT_COUNT' },
            'filter'   => new Map<String, Object>{
                'locationFilter' => new Map<String, Object>{
                    'circle' => new Map<String, Object>{
                        'center' => new Map<String, Object>{
                            'latitude'  => lat,
                            'longitude' => lng
                        },
                        'radius' => 15000
                    }
                },
                'typeFilter' => new Map<String, Object>{
                    'includedTypes' => new List<String>{ 'supermarket', 'grocery_store' }
                }
            }
        });
    }

    private static String buildTextSearchBody(String query) {
        return JSON.serialize(new Map<String, Object>{
            'textQuery'      => query,
            'locationBias'   => new Map<String, Object>{
                'circle' => new Map<String, Object>{
                    'center' => new Map<String, Object>{
                        'latitude'  => 20.5937,
                        'longitude' => 78.9629
                    },
                    'radius' => 2000000
                }
            },
            'maxResultCount' => 1
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PRIVATE — Response parsers
    // ─────────────────────────────────────────────────────────────────────────

    /** Returns true when the GeoPoint is null or has a null coordinate. */
    private static Boolean isGeoInvalid(GeoPoint p) {
        return p == null || p.lat == null || p.lng == null;
    }

    private static Integer parseCompetitorCount(String body) {
        try {
            Map<String, Object> r  = (Map<String, Object>) JSON.deserializeUntyped(body);
            List<Object> pi        = (List<Object>) ((Map<String, Object>) r.get('insightsResult')).get('placeInsights');
            return Integer.valueOf(String.valueOf(((Map<String, Object>) pi[0]).get('count')));
        } catch (Exception e) {
            return 0;
        }
    }

    private static PlaceResult parseSearchPlace(String body) {
        try {
            Map<String, Object> r     = (Map<String, Object>) JSON.deserializeUntyped(body);
            Map<String, Object> place = (Map<String, Object>) ((List<Object>) r.get('places'))[0];
            Map<String, Object> loc   = (Map<String, Object>) place.get('location');
            PlaceResult pr = new PlaceResult();
            pr.placeId   = (String) place.get('id');
            pr.latitude  = Decimal.valueOf(String.valueOf(loc.get('latitude')));
            pr.longitude = Decimal.valueOf(String.valueOf(loc.get('longitude')));
            return pr;
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal parseRating(String body) {
        try {
            Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(body);
            return Decimal.valueOf(String.valueOf(r.get('rating'))).setScale(1);
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal parseDistanceKm(String body) {
        try {
            Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(body);
            // API-level errors require explicit checks (not NullPointerException territory)
            if (!'OK'.equals((String) r.get('status'))) { return null; }
            List<Object> elements = (List<Object>) ((Map<String, Object>) ((List<Object>) r.get('rows'))[0]).get('elements');
            Map<String, Object> el = (Map<String, Object>) elements[0];
            if (!'OK'.equals((String) el.get('status'))) { return null; }
            Integer metres = Integer.valueOf(String.valueOf(((Map<String, Object>) el.get('distance')).get('value')));
            return (Decimal.valueOf(metres) / 1000).setScale(2);
        } catch (Exception e) {
            return null;
        }
    }
}