/**
 * DynamicDataRefreshBatch
 * =======================
 * Scheduled batch that populates all dynamic API-sourced fields across
 * three Salesforce objects. Runs in 3 chained modes:
 *
 *   MODE 1 → MARKET_ANALYSIS
 *     • Growth_Rate__c     ← World Bank GDP growth (1 call, applied to all 23 records)
 *     • Competitor_Count__c← Google Places computeInsights (1 call per city)
 *
 *   MODE 2 → COMPETITOR_STORES
 *     • Latitude__c        ← Google Places Text Search
 *     • Longitude__c       ← Google Places Text Search
 *     • Geolocation__c     ← derived from Lat/Lng
 *     • Rating__c          ← Google Place Details
 *     • Distance_km__c     ← Google Distance Matrix to nearest Expansion_Site
 *     • Est_Monthly_Revenue__c ← formula: Store_Size_Sqft × rate/sqft
 *
 *   MODE 3 → EXPANSION_SITES
 *     • Foot_Traffic_Index__c      ← BestTime.app
 *     • Distance_Nearest_Store_km__c ← Google Distance Matrix to nearest RetailStore
 *     • Demand_Score__c            ← computed (DynamicDataService.computeDemandScore)
 *
 * After Mode 3 finishes, it is NOT auto-chained — the scheduler controls the cycle.
 *
 * Usage (from Anonymous Apex or Scheduler):
 *   Database.executeBatch(new DynamicDataRefreshBatch('MARKET_ANALYSIS'), 5);
 */
public class DynamicDataRefreshBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful { // NOPMD - batch orchestrator delegates work across three mode-specific flows

    // ── Mode constants ────────────────────────────────────────────────────────
    public static final String MODE_MARKET_ANALYSIS  = 'MARKET_ANALYSIS';
    public static final String MODE_COMPETITOR_STORES = 'COMPETITOR_STORES';
    public static final String MODE_EXPANSION_SITES  = 'EXPANSION_SITES';

    // ── State ─────────────────────────────────────────────────────────────────
    private String batchMode;
    private Decimal cachedGrowthRate;      // fetched once in Mode 1 start()
    private Integer recordsUpdated = 0;
    private Integer recordsFailed  = 0;
    private List<String> errorLog  = new List<String>();

    // ── Expansion site coords cache for distance calculations (Mode 2) ────────
    private Map<String, Decimal[]> expansionSiteCoords; // Name → [lat, lng]

    // ── RetailStore address cache for distance calculations (Mode 3) ──────────
    private Map<String, Decimal[]> retailStoreCoords;   // Name → [lat, lng]

    private class CompetitorEnrichmentContext {
        Competitor_Store__c record;
        Competitor_Store__c upd;
        Api_GoogleMapsService.PlaceResult place;
    }

    public DynamicDataRefreshBatch(String mode) {
        this.batchMode = mode;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // START — return the query locator for the current mode
    // ─────────────────────────────────────────────────────────────────────────
    public Database.QueryLocator start(Database.BatchableContext ctx) {
        System.debug('DynamicDataRefreshBatch starting mode: ' + batchMode);

        if (batchMode == MODE_MARKET_ANALYSIS) {
            return startMarketAnalysisMode();
        }

        if (batchMode == MODE_COMPETITOR_STORES) {
            return startCompetitorStoresMode();
        }

        return startExpansionSitesMode();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXECUTE — process each batch chunk
    // ─────────────────────────────────────────────────────────────────────────
    public void execute(Database.BatchableContext ctx, List<SObject> scope) {

        if (batchMode == MODE_MARKET_ANALYSIS) {
            processMarketAnalysis((List<Market_Analysis__c>) scope);
        } else if (batchMode == MODE_COMPETITOR_STORES) {
            processCompetitorStores((List<Competitor_Store__c>) scope);
        } else {
            processExpansionSites((List<Expansion_Site__c>) scope);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MODE 1: Market Analysis
    // ─────────────────────────────────────────────────────────────────────────
    private void processMarketAnalysis(List<Market_Analysis__c> records) {
        List<Market_Analysis__c> toUpdate = new List<Market_Analysis__c>();

        for (Market_Analysis__c ma : records) {
            Market_Analysis__c upd = buildMarketAnalysisUpdate(ma);
            if (upd != null) {
                toUpdate.add(upd);
            }
        }

        if (!toUpdate.isEmpty()) {
            handleSaveResults(Database.update(toUpdate, false), 'Market_Analysis__c');
        }
        // Flush API logs within this execute() transaction — static buffer resets at chunk boundary
        ApiLogger.flush();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MODE 2: Competitor Stores
    // ─────────────────────────────────────────────────────────────────────────
    private void processCompetitorStores(List<Competitor_Store__c> records) {
        List<Competitor_Store__c> toUpdate = new List<Competitor_Store__c>();

        for (Competitor_Store__c cs : records) {
            Competitor_Store__c upd = buildCompetitorStoreUpdate(cs);
            if (upd != null) {
                toUpdate.add(upd);
            }
        }

        if (!toUpdate.isEmpty()) {
            handleSaveResults(Database.update(toUpdate, false), 'Competitor_Store__c');
        }
        // Flush API logs within this execute() transaction — static buffer resets at chunk boundary
        ApiLogger.flush();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MODE 3: Expansion Sites
    // ─────────────────────────────────────────────────────────────────────────
    private void processExpansionSites(List<Expansion_Site__c> records) {
        List<Expansion_Site__c> toUpdate = new List<Expansion_Site__c>();

        for (Expansion_Site__c es : records) {
            Expansion_Site__c upd = buildExpansionSiteUpdate(es);
            if (upd != null) {
                toUpdate.add(upd);
            }
        }

        if (!toUpdate.isEmpty()) {
            handleSaveResults(Database.update(toUpdate, false), 'Expansion_Site__c');
        }
        // Flush API logs within this execute() transaction — static buffer resets at chunk boundary
        ApiLogger.flush();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FINISH — chain to next mode or log completion
    // ─────────────────────────────────────────────────────────────────────────
    public void finish(Database.BatchableContext ctx) {
        // Flush any buffered API log entries accumulated during this batch run
        ApiLogger.flush();
        System.debug(buildSummary());
        chainNextBatch();
    }

    private Database.QueryLocator startMarketAnalysisMode() {
        preloadGrowthRate();
        return Database.getQueryLocator(
            'SELECT Id, Name, City__c, Growth_Rate__c, Competitor_Count__c ' +
            'FROM Market_Analysis__c ORDER BY City__c'
        );
    }

    private Database.QueryLocator startCompetitorStoresMode() {
        expansionSiteCoords = loadExpansionSiteCoords();
        return Database.getQueryLocator(
            'SELECT Id, Name, Brand__c, Address__c, City__c, State__c, ' +
            '       Store_Size_Sqft__c, Store_Format__c, ' +
            '       Latitude__c, Longitude__c ' +
            'FROM Competitor_Store__c ORDER BY City__c'
        );
    }

    private Database.QueryLocator startExpansionSitesMode() {
        retailStoreCoords = loadRetailStoreCoords();
        return Database.getQueryLocator(
            'SELECT Id, Name, Address__c, City__c, State__c, ' +
            '       Latitude__c, Longitude__c, ' +
            '       Foot_Traffic_Index__c, Distance_Nearest_Store_km__c, Demand_Score__c, ' +
            '       Population_Density__c, Avg_Household_Income__c, Competition_Level__c ' +
            'FROM Expansion_Site__c ORDER BY City__c'
        );
    }

    private void preloadGrowthRate() {
        try {
            cachedGrowthRate = Api_GrowthRateService.getIndiaGrowthRate(batchMode);
            System.debug('World Bank growth rate fetched: ' + cachedGrowthRate + '%');
        } catch (Exception e) {
            errorLog.add('World Bank fetch failed: ' + e.getMessage());
        }
    }

    private Map<String, Decimal[]> loadExpansionSiteCoords() {
        Map<String, Decimal[]> coordsBySite = new Map<String, Decimal[]>();
        for (Expansion_Site__c site : [
            SELECT Name, Latitude__c, Longitude__c FROM Expansion_Site__c
            WHERE Latitude__c != null AND Longitude__c != null
        ]) {
            coordsBySite.put(site.Name, new Decimal[]{ site.Latitude__c, site.Longitude__c });
        }
        return coordsBySite;
    }

    private Map<String, Decimal[]> loadRetailStoreCoords() {
        Map<String, Decimal[]> coordsByStore = new Map<String, Decimal[]>();
        for (RetailStore rs : [
            SELECT Name, Latitude, Longitude FROM RetailStore
            WHERE Latitude != null AND Longitude != null
        ]) {
            coordsByStore.put(rs.Name, new Decimal[]{ rs.Latitude, rs.Longitude });
        }
        return coordsByStore;
    }

    private Market_Analysis__c buildMarketAnalysisUpdate(Market_Analysis__c record) {
        Market_Analysis__c upd = new Market_Analysis__c(Id = record.Id);
        Boolean dirty = applyCachedGrowthRate(upd);
        dirty = applyMarketCompetitorCount(record, upd) || dirty;
        return dirty ? upd : null;
    }

    private Boolean applyCachedGrowthRate(Market_Analysis__c upd) {
        if (cachedGrowthRate == null) {
            return false;
        }
        upd.Growth_Rate__c = cachedGrowthRate;
        return true;
    }

    private Boolean applyMarketCompetitorCount(
        Market_Analysis__c record,
        Market_Analysis__c upd
    ) {
        if (String.isBlank(record.City__c)) {
            return false;
        }

        Decimal[] coords = DynamicDataService.cityCoords.get(record.City__c);
        if (coords == null) {
            return false;
        }

        try {
            Api_GoogleMapsService.CallContext ctx = new Api_GoogleMapsService.CallContext(batchMode, null);
            Integer count = Api_GoogleMapsService.getCompetitorCount(coords[0], coords[1], ctx);
            if (count == null) {
                return false;
            }
            upd.Competitor_Count__c = count;
            return true;
        } catch (Exception e) {
            logFailure('computeInsights failed for ' + record.City__c + ': ' + e.getMessage(), true);
            return false;
        }
    }

    private Competitor_Store__c buildCompetitorStoreUpdate(Competitor_Store__c record) {
        Competitor_Store__c upd = new Competitor_Store__c(Id = record.Id);
        Boolean dirty = applyCompetitorRevenue(record, upd);
        Api_GoogleMapsService.PlaceResult place = enrichCompetitorWithGoogleData(record, upd);
        CompetitorEnrichmentContext context = new CompetitorEnrichmentContext();
        context.record = record;
        context.upd = upd;
        context.place = place;
        dirty = (place != null) || dirty;
        dirty = enrichCompetitorRating(context) || dirty;
        dirty = enrichCompetitorDistance(context) || dirty;
        return dirty ? upd : null;
    }

    private Boolean applyCompetitorRevenue(Competitor_Store__c record, Competitor_Store__c upd) {
        if (record.Store_Size_Sqft__c == null) {
            return false;
        }

        Decimal ratePerSqft = (record.Store_Format__c == 'Supermarket') ? 1800 : 2500;
        upd.Est_Monthly_Revenue__c = (record.Store_Size_Sqft__c * ratePerSqft).setScale(0);
        return true;
    }

    private Api_GoogleMapsService.PlaceResult enrichCompetitorWithGoogleData(
        Competitor_Store__c record,
        Competitor_Store__c upd
    ) {
        // Skip geocoding if coordinates are already populated — saves billable API calls
        if (record.Latitude__c != null && record.Longitude__c != null) {
            Api_GoogleMapsService.PlaceResult cached = new Api_GoogleMapsService.PlaceResult();
            cached.latitude  = record.Latitude__c;
            cached.longitude = record.Longitude__c;
            return cached;  // placeId will be null; rating + distance can still run if needed
        }

        try {
            Api_GoogleMapsService.CallContext ctx =
                new Api_GoogleMapsService.CallContext(batchMode, record.Id).withCacheKey(record.Name);
            Api_GoogleMapsService.PlaceResult place = Api_GoogleMapsService.searchPlace(
                buildCompetitorSearchQuery(record), ctx
            );
            if (place == null) {
                return null;
            }

            upd.Latitude__c = place.latitude;
            upd.Longitude__c = place.longitude;
            upd.Geolocation__Latitude__s = place.latitude;
            upd.Geolocation__Longitude__s = place.longitude;
            return place;
        } catch (Exception e) {
            logFailure('Places search failed for "' + record.Name + '": ' + e.getMessage(), true);
            return null;
        }
    }

    private Boolean enrichCompetitorRating(CompetitorEnrichmentContext context) {
        if (context.place == null || String.isBlank(context.place.placeId)) { // NOPMD
            return false;
        }

        try {
            Api_GoogleMapsService.CallContext ctx = new Api_GoogleMapsService.CallContext(batchMode, context.record.Id);
            Decimal rating = Api_GoogleMapsService.getPlaceRating(context.place.placeId, ctx);
            if (rating == null) {
                return false;
            }
            context.upd.Rating__c = rating;
            return true;
        } catch (Exception e) {
            logFailure('Place Details failed for "' + context.record.Name + '": ' + e.getMessage(), false);
            return false;
        }
    }

    private Boolean enrichCompetitorDistance(CompetitorEnrichmentContext context) {
        if (context.place == null
                || expansionSiteCoords == null
                || expansionSiteCoords.isEmpty()) {
            return false;
        }

        Decimal[] nearest = getNearestCoords(context.place.latitude, context.place.longitude, expansionSiteCoords);
        if (nearest == null) {
            return false;
        }

        try {
            Api_GoogleMapsService.CallContext ctx = new Api_GoogleMapsService.CallContext(batchMode, context.record.Id);
            Api_GoogleMapsService.GeoPoint origin = new Api_GoogleMapsService.GeoPoint(context.place.latitude, context.place.longitude);
            Api_GoogleMapsService.GeoPoint dest   = new Api_GoogleMapsService.GeoPoint(nearest[0], nearest[1]);
            Decimal dist = Api_GoogleMapsService.getDrivingDistanceKm(origin, dest, ctx);
            if (dist == null) {
                return false;
            }
            context.upd.Distance_km__c = dist;
            return true;
        } catch (Exception e) {
            logFailure('Distance Matrix failed for "' + context.record.Name + '": ' + e.getMessage(), false);
            return false;
        }
    }

    private Expansion_Site__c buildExpansionSiteUpdate(Expansion_Site__c record) {
        Expansion_Site__c upd = new Expansion_Site__c(Id = record.Id);
        Boolean dirty = fetchFootTrafficIndex(record, upd);
        dirty = fetchExpansionSiteDistance(record, upd) || dirty;
        dirty = applyDemandScore(record, upd) || dirty;
        return dirty ? upd : null;
    }

    private Boolean fetchFootTrafficIndex(
        Expansion_Site__c record,
        Expansion_Site__c upd
    ) {
        if (String.isBlank(record.Address__c)) {
            return false;
        }

        // Skip if already populated — BestTime credits are finite
        if (record.Foot_Traffic_Index__c != null) {
            return false;
        }

        try {
            Decimal footTraffic = Api_BestTimeService.getFootTrafficIndex(
                buildExpansionSiteSearchQuery(record), batchMode, record.Id
            );
            if (footTraffic == null) {
                return false;
            }
            upd.Foot_Traffic_Index__c = footTraffic;
            return true;
        } catch (Exception e) {
            logFailure('BestTime failed for "' + record.Name + '": ' + e.getMessage(), true);
            return false;
        }
    }

    private Boolean fetchExpansionSiteDistance(
        Expansion_Site__c record,
        Expansion_Site__c upd
    ) {
        if (record.Latitude__c == null || record.Longitude__c == null) {
            return false;
        }
        if (retailStoreCoords == null || retailStoreCoords.isEmpty()) {
            return false;
        }

        Decimal[] nearest = getNearestCoords(record.Latitude__c, record.Longitude__c, retailStoreCoords);
        if (nearest == null) {
            return false;
        }

        try {
            Api_GoogleMapsService.CallContext ctx = new Api_GoogleMapsService.CallContext(batchMode, record.Id);
            Api_GoogleMapsService.GeoPoint origin = new Api_GoogleMapsService.GeoPoint(record.Latitude__c, record.Longitude__c);
            Api_GoogleMapsService.GeoPoint dest   = new Api_GoogleMapsService.GeoPoint(nearest[0], nearest[1]);
            Decimal dist = Api_GoogleMapsService.getDrivingDistanceKm(origin, dest, ctx);
            if (dist == null) {
                return false;
            }
            upd.Distance_Nearest_Store_km__c = dist;
            return true;
        } catch (Exception e) {
            logFailure('Distance Matrix (Expansion Site) failed for "' + record.Name + '": ' + e.getMessage(), false);
            return false;
        }
    }

    private Boolean applyDemandScore(Expansion_Site__c record, Expansion_Site__c upd) {
        Decimal demandScore = DynamicDataService.computeDemandScore(
            resolveFootTraffic(record, upd),
            record.Population_Density__c,
            record.Avg_Household_Income__c,
            record.Competition_Level__c
        );
        if (demandScore == null || demandScore == record.Demand_Score__c) {
            return false;
        }

        upd.Demand_Score__c = demandScore;
        return true;
    }

    private Decimal resolveFootTraffic(Expansion_Site__c record, Expansion_Site__c upd) {
        return upd.Foot_Traffic_Index__c != null ? upd.Foot_Traffic_Index__c : record.Foot_Traffic_Index__c;
    }

    private String buildCompetitorSearchQuery(Competitor_Store__c record) {
        return record.Name + ', ' + record.City__c + ', India';
    }

    private String buildExpansionSiteSearchQuery(Expansion_Site__c record) {
        return record.Address__c + ', ' + record.City__c + ', India';
    }

    private Boolean isActiveConfig(API_Config__mdt config) {
        return config != null && config.Is_Active__c;
    }

    private void handleSaveResults(List<Database.SaveResult> results, String objectLabel) {
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                recordsUpdated++;
            } else {
                recordsFailed++;
                errorLog.add(objectLabel + ' update failed: ' + sr.getErrors()[0].getMessage());
            }
        }
    }

    private void logFailure(String message, Boolean countAsFailure) {
        errorLog.add(message);
        if (countAsFailure) {
            recordsFailed++;
        }
    }

    private String buildSummary() {
        String summary =
            'DynamicDataRefreshBatch [' + batchMode + '] complete. ' +
            'Updated: ' + recordsUpdated + ', Failed: ' + recordsFailed + '.';
        if (!errorLog.isEmpty()) {
            summary += ' Errors: ' + String.join(errorLog, ' | ');
        }
        return summary;
    }

    private void chainNextBatch() {
        if (batchMode == MODE_MARKET_ANALYSIS) {
            System.debug('Chaining to COMPETITOR_STORES batch...');
            Database.executeBatch(new DynamicDataRefreshBatch(MODE_COMPETITOR_STORES), 3);
            return;
        }

        if (batchMode == MODE_COMPETITOR_STORES) {
            System.debug('Chaining to EXPANSION_SITES batch...');
            Database.executeBatch(new DynamicDataRefreshBatch(MODE_EXPANSION_SITES), 5);
            return;
        }

        System.debug('All dynamic data refresh modes complete.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPER: Find nearest coordinates from a map (straight-line approximation)
    // Used to pick the closest expansion site or retail store for distance calc.
    // ─────────────────────────────────────────────────────────────────────────
    private static Decimal[] getNearestCoords(
        Decimal fromLat,
        Decimal fromLng,
        Map<String, Decimal[]> candidateMap
    ) {
        Decimal minDist = null;
        Decimal[] nearest = null;

        for (Decimal[] coords : candidateMap.values()) {
            if (coords == null || coords.size() < 2) { continue; }
            Decimal dLat = fromLat - coords[0];
            Decimal dLng = fromLng - coords[1];
            Decimal dist = (dLat * dLat + dLng * dLng);   // squared euclidean is fine for ranking
            if (minDist == null || dist < minDist) {
                minDist = dist;
                nearest = coords;
            }
        }
        return nearest;
    }
}