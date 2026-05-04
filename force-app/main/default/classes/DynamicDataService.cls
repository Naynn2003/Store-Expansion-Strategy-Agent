/**
 * DynamicDataService
 * ==================
 * Central HTTP callout service for all external API integrations.
 * Called exclusively from DynamicDataRefreshBatch — never from triggers.
 *
 * API coverage:
 *   1. World Bank Open Data      → Growth_Rate__c on Market_Analysis__c
 *   2. Google Places (New)       → Competitor_Count__c on Market_Analysis__c
 *   3. Google Places Text Search → Latitude__c, Longitude__c on Competitor_Store__c
 *   4. Google Place Details      → Rating__c on Competitor_Store__c
 *   5. Google Distance Matrix    → Distance_km__c on Competitor_Store__c
 *                                   Distance_Nearest_Store_km__c on Expansion_Site__c
 *   6. BestTime.app              → Foot_Traffic_Index__c on Expansion_Site__c
 *
 * To activate: go to Setup → Custom Metadata Types → API Config →
 *   set Is_Active__c = true and paste your API key.
 */
@SuppressWarnings('PMD.CognitiveComplexity')
public with sharing class DynamicDataService {

    // ── Config cache ──────────────────────────────────────────────────────────
    private static Map<String, API_Config__mdt> configCache;

    public static API_Config__mdt getConfig(String devName) {
        if (configCache == null) {
            configCache = new Map<String, API_Config__mdt>();
            // CMT records are deployment data, accessible to all users by platform contract.
            // Guard included for PMD ApexCRUDViolation compliance.
            if (Schema.sObjectType.API_Config__mdt.isAccessible()) {
                for (API_Config__mdt cfg : [
                    SELECT DeveloperName, API_Key__c, Base_URL__c, Is_Active__c
                    FROM   API_Config__mdt
                ]) {
                    configCache.put(cfg.DeveloperName, cfg);
                }
            }
        }
        return configCache.get(devName);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. WORLD BANK — India GDP Growth Rate
    //    Free, no key. Returns latest annual growth %.
    //    Endpoint: GET https://api.worldbank.org/v2/country/IN/indicator/NY.GDP.MKTP.KD.ZG
    // ─────────────────────────────────────────────────────────────────────────
    public static Decimal getIndiaGrowthRate() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'https://api.worldbank.org/v2/country/IN/indicator/NY.GDP.MKTP.KD.ZG' +
            '?format=json&mrv=1&per_page=1'
        );
        req.setMethod('GET');
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            System.debug('World Bank API error: ' + res.getStatus() + ' ' + res.getBody());
            return null;
        }

        // Response shape: [ {metadata}, [ {date, value, ...} ] ]
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.getBody());
        if (parsed == null || parsed.size() < 2) { return null; }

        List<Object> dataRows = (List<Object>) parsed[1];
        if (dataRows == null || dataRows.isEmpty()) { return null; }

        Map<String, Object> row = (Map<String, Object>) dataRows[0];
        Object val = row.get('value');
        if (val == null) { return null; }

        return Decimal.valueOf(String.valueOf(val)).setScale(1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. GOOGLE PLACES computeInsights — Competitor Count per City
    //    POST https://places.googleapis.com/v1/places:computeInsights
    //    Uses a circle around city centre coordinates.
    //    Returns: count of supermarket + grocery_store establishments.
    // ─────────────────────────────────────────────────────────────────────────
    public static Integer getCompetitorCount(
        Decimal cityLat,
        Decimal cityLng,
        String  apiKey
    ) {
        if (cityLat == null || cityLng == null || String.isBlank(apiKey)) { return null; }

        String body = JSON.serialize(new Map<String, Object>{
            'insights'  => new List<String>{ 'INSIGHT_COUNT' },
            'filter'    => new Map<String, Object>{
                'locationFilter' => new Map<String, Object>{
                    'circle' => new Map<String, Object>{
                        'center' => new Map<String, Object>{
                            'latitude'  => cityLat,
                            'longitude' => cityLng
                        },
                        'radius' => 15000   // 15 km radius around city centre
                    }
                },
                'typeFilter' => new Map<String, Object>{
                    'includedTypes' => new List<String>{ 'supermarket', 'grocery_store' }
                }
            }
        });

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://places.googleapis.com/v1/places:computeInsights');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Goog-Api-Key', apiKey);
        req.setHeader('X-Goog-FieldMask', 'insightsResult.placeInsights.insight');
        req.setBody(body);
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            System.debug('computeInsights error: ' + res.getStatus() + ' ' + res.getBody());
            return null;
        }

        // Response: { "insightsResult": { "placeInsights": [ { "insight": "INSIGHT_COUNT", "count": 42 } ] } }
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> insightsResult = (Map<String, Object>) responseMap.get('insightsResult');
        if (insightsResult == null) { return null; }

        List<Object> placeInsights = (List<Object>) insightsResult.get('placeInsights');
        if (placeInsights == null || placeInsights.isEmpty()) { return 0; }

        Map<String, Object> insight = (Map<String, Object>) placeInsights[0];
        Object count = insight.get('count');
        return count != null ? Integer.valueOf(String.valueOf(count)) : 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. GOOGLE PLACES TEXT SEARCH — Get lat/lng and placeId for a store
    //    POST https://places.googleapis.com/v1/places:searchText
    //    Returns: latitude, longitude, placeId
    // ─────────────────────────────────────────────────────────────────────────
    public class PlaceSearchResult {
        public String  placeId;
        public Decimal latitude;
        public Decimal longitude;
    }

    public static PlaceSearchResult searchPlace(String query, String apiKey) {
        if (String.isBlank(query) || String.isBlank(apiKey)) { return null; }

        String body = JSON.serialize(new Map<String, Object>{
            'textQuery'      => query,
            'locationBias'   => new Map<String, Object>{
                'circle' => new Map<String, Object>{
                    // Bias toward India centre (20.5937° N, 78.9629° E)
                    'center' => new Map<String, Object>{
                        'latitude'  => 20.5937,
                        'longitude' => 78.9629
                    },
                    'radius' => 2000000   // 2000 km — entire India
                }
            },
            'maxResultCount' => 1
        });

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://places.googleapis.com/v1/places:searchText');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Goog-Api-Key', apiKey);
        req.setHeader('X-Goog-FieldMask', 'places.id,places.location');
        req.setBody(body);
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            System.debug('Places Text Search error for "' + query + '": ' + res.getStatus() + ' ' + res.getBody());
            return null;
        }

        // Response: { "places": [ { "id": "ChIJ...", "location": { "latitude": ..., "longitude": ... } } ] }
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> places = (List<Object>) responseMap.get('places');
        if (places == null || places.isEmpty()) { return null; }

        Map<String, Object> place    = (Map<String, Object>) places[0];
        Map<String, Object> location = (Map<String, Object>) place.get('location');
        if (location == null) { return null; }

        PlaceSearchResult result  = new PlaceSearchResult();
        result.placeId    = (String) place.get('id');
        result.latitude   = Decimal.valueOf(String.valueOf(location.get('latitude')));
        result.longitude  = Decimal.valueOf(String.valueOf(location.get('longitude')));
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. GOOGLE PLACE DETAILS — Get rating for a known placeId
    //    GET https://places.googleapis.com/v1/places/{placeId}
    //    Returns: rating (0–5 scale)
    // ─────────────────────────────────────────────────────────────────────────
    public static Decimal getPlaceRating(String placeId, String apiKey) {
        if (String.isBlank(placeId) || String.isBlank(apiKey)) { return null; }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://places.googleapis.com/v1/places/' + EncodingUtil.urlEncode(placeId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('X-Goog-Api-Key', apiKey);
        req.setHeader('X-Goog-FieldMask', 'rating,userRatingCount');
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            System.debug('Place Details error for placeId "' + placeId + '": ' + res.getStatus());
            return null;
        }

        // Response: { "rating": 4.3, "userRatingCount": 1247 }
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Object rating = responseMap.get('rating');
        if (rating == null) { return null; }

        return Decimal.valueOf(String.valueOf(rating)).setScale(1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. GOOGLE DISTANCE MATRIX — Driving distance between two points
    //    GET https://maps.googleapis.com/maps/api/distancematrix/json
    //    Returns: distance in km (driving route)
    // ─────────────────────────────────────────────────────────────────
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static Decimal getDrivingDistanceKm(
        Decimal originLat,
        Decimal originLng,
        Decimal destLat,
        Decimal destLng,
        String  apiKey
    ) {
        if (originLat == null || originLng == null || destLat == null || destLng == null
                || String.isBlank(apiKey)) { return null; }

        String originStr = originLat + ',' + originLng;
        String destStr   = destLat   + ',' + destLng;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'https://maps.googleapis.com/maps/api/distancematrix/json' +
            '?origins='       + EncodingUtil.urlEncode(originStr, 'UTF-8') +
            '&destinations='  + EncodingUtil.urlEncode(destStr, 'UTF-8') +
            '&mode=driving' +
            '&key='           + apiKey
        );
        req.setMethod('GET');
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            System.debug('Distance Matrix error: ' + res.getStatus() + ' ' + res.getBody());
            return null;
        }

        // Response: { "rows": [ { "elements": [ { "distance": { "value": 3200 } } ] } ] }
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String status = (String) responseMap.get('status');
        if (!'OK'.equals(status)) {
            System.debug('Distance Matrix status not OK: ' + status);
            return null;
        }
        Integer metres = parseDistanceMetres(responseMap);
        if (metres == null) { return null; }
        return (Decimal.valueOf(metres) / 1000).setScale(2);
    }

    // Extracts driving distance in metres from a Distance Matrix API response.
    // Extracted to reduce cognitive complexity of getDrivingDistanceKm.
    private static Integer parseDistanceMetres(Map<String, Object> responseMap) {
        List<Object> rows = (List<Object>) responseMap.get('rows');
        if (rows == null || rows.isEmpty()) { return null; }
        Map<String, Object> row = (Map<String, Object>) rows[0];
        List<Object> elements = (List<Object>) row.get('elements');
        if (elements == null || elements.isEmpty()) { return null; }
        Map<String, Object> element = (Map<String, Object>) elements[0];
        if (!'OK'.equals((String) element.get('status'))) { return null; }
        Map<String, Object> dist = (Map<String, Object>) element.get('distance');
        if (dist == null) { return null; }
        return Integer.valueOf(String.valueOf(dist.get('value')));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 6. BESTTIME.APP — Foot traffic / busyness index for an address
    //    POST https://besttime.app/api/v1/forecasts
    //    Returns: normalized busyness score 0–100 (average across week)
    // ─────────────────────────────────────────────────────────────────────────
    public static Decimal getFootTrafficIndex(String address, String apiKey) {
        if (String.isBlank(address) || String.isBlank(apiKey)) { return null; }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'https://besttime.app/api/v1/forecasts' +
            '?api_key_public=' + EncodingUtil.urlEncode(apiKey, 'UTF-8') +
            '&venue_name='     + EncodingUtil.urlEncode(address, 'UTF-8') +
            '&venue_address='  + EncodingUtil.urlEncode(address, 'UTF-8')
        );
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setTimeout(20000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            System.debug('BestTime error for "' + address + '": ' + res.getStatus() + ' ' + res.getBody());
            return null;
        }

        // Response: { "analysis": [ { "day_info": {...}, "day_raw": [ busyness per hour ] } ], ... }
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Boolean statusOk = (Boolean) responseMap.get('status');
        if (statusOk != true) { return null; }

        List<Object> analysisDays = (List<Object>) responseMap.get('analysis');
        if (analysisDays == null || analysisDays.isEmpty()) { return null; }

        return computePeakBusynessAverage(analysisDays);
    }

    // Computes average peak busyness across all days from BestTime analysis response.
    // Extracted to reduce cognitive complexity of getFootTrafficIndex.
    private static Decimal computePeakBusynessAverage(List<Object> analysisDays) {
        Integer totalPeak = 0;
        Integer dayCount  = 0;
        for (Object dayObj : analysisDays) {
            Map<String, Object> day     = (Map<String, Object>) dayObj;
            Map<String, Object> dayInfo = (Map<String, Object>) day.get('day_info');
            if (dayInfo == null) { continue; }
            Object maxBusyness = dayInfo.get('max_busyness');
            if (maxBusyness != null) {
                totalPeak += Integer.valueOf(String.valueOf(maxBusyness));
                dayCount++;
            }
        }
        if (dayCount == 0) { return null; }
        return Decimal.valueOf(totalPeak / dayCount).setScale(0);
    }

    // Competition level → score lookup (replaces chained if/else if to reduce complexity)
    private static final Map<String, Decimal> COMPETITION_SCORE = new Map<String, Decimal>{
        'Low' => 15, 'Medium' => 9, 'High' => 4
    };

    // ─────────────────────────────────────────────────────────────────────────
    // UTILITY: Compute Demand_Score from available site fields
    // Called after Foot_Traffic_Index__c is set.
    // Formula: weighted composite 0–100
    // ─────────────────────────────────────────────────────────────────
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static Decimal computeDemandScore(
        Decimal footTrafficIndex,   // 0–100  weight 35%
        Decimal populationDensity,  // /km²   weight 30%
        Decimal avgHHIncome,        // INR/mo weight 20%
        String  competitionLevel    // Low/Med/High weight 15%
    ) {
        Decimal score = 0;

        // Foot traffic component (35 pts)
        if (footTrafficIndex != null) {
            score += (footTrafficIndex / 100 * 35).setScale(1);
        }

        // Population density component (30 pts) — normalize to 20,000/km² = max
        if (populationDensity != null) {
            Decimal densityNorm = Math.min(populationDensity, 20000) / 20000;
            score += (densityNorm * 30).setScale(1);
        }

        // Household income component (20 pts) — normalize to ₹70,000/mo = max
        if (avgHHIncome != null) {
            Decimal incomeNorm = Math.min(avgHHIncome, 70000) / 70000;
            score += (incomeNorm * 20).setScale(1);
        }

        // Competition component (15 pts) — inverse: less competition = more demand
        if (String.isNotBlank(competitionLevel)) {
            Decimal compScore = COMPETITION_SCORE.get(competitionLevel);
            if (compScore != null) {
                score += compScore;
            }
        }

        return score.setScale(0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UTILITY: City centre coordinates lookup for computeInsights
    // Avoids a Places API lookup for each city — hardcoded reliable coords.
    // ─────────────────────────────────────────────────────────────────────────
    public static Map<String, Decimal[]> cityCoords = new Map<String, Decimal[]>{
        'Mumbai'         => new Decimal[]{ 19.0760,  72.8777 },
        'Pune'           => new Decimal[]{ 18.5204,  73.8567 },
        'Bangalore'      => new Decimal[]{ 12.9716,  77.5946 },
        'Hyderabad'      => new Decimal[]{ 17.3850,  78.4867 },
        'Delhi'          => new Decimal[]{ 28.6139,  77.2090 },
        'Chennai'        => new Decimal[]{ 13.0827,  80.2707 },
        'Ahmedabad'      => new Decimal[]{ 23.0225,  72.5714 },
        'Gandhinagar'    => new Decimal[]{ 23.2156,  72.6369 },
        'Surat'          => new Decimal[]{ 21.1702,  72.8311 },
        'Kolkata'        => new Decimal[]{ 22.5726,  88.3639 },
        'Jaipur'         => new Decimal[]{ 26.9124,  75.7873 },
        'Jodhpur'        => new Decimal[]{ 26.2389,  73.0243 },
        'Udaipur'        => new Decimal[]{ 24.5854,  73.7125 },
        'Kota'           => new Decimal[]{ 25.2138,  75.8648 },
        'Lucknow'        => new Decimal[]{ 26.8467,  80.9462 },
        'Noida'          => new Decimal[]{ 28.5355,  77.3910 },
        'Varanasi'       => new Decimal[]{ 25.3176,  82.9739 },
        'Gwalior'        => new Decimal[]{ 26.2183,  78.1828 },
        'Indore'         => new Decimal[]{ 22.7196,  75.8577 },
        'Bhopal'         => new Decimal[]{ 23.2599,  77.4126 },
        'Nagpur'         => new Decimal[]{ 21.1458,  79.0882 },
        'Patna'          => new Decimal[]{ 25.5941,  85.1376 },
        'Chandigarh'     => new Decimal[]{ 30.7333,  76.7794 },
        'Kochi'          => new Decimal[]{ 9.9312,   76.2673 },
        'Coimbatore'     => new Decimal[]{ 11.0168,  76.9558 },
        'Visakhapatnam'  => new Decimal[]{ 17.6868,  83.2185 },
        'Bhubaneswar'    => new Decimal[]{ 20.2961,  85.8245 },
        'Ranchi'         => new Decimal[]{ 23.3441,  85.3096 }
    };
}