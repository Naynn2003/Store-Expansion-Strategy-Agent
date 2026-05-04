/**
 * Api_BestTimeService
 * ====================
 * Isolated service for the BestTime.app Forecasts API.
 * Responsible for: fetching venue foot-traffic busyness index.
 *
 * Improvements over DynamicDataService (which remains untouched):
 *   [+] Retry via ApiCalloutRetry (up to 2 additional attempts on 5xx)
 *   [+] Structured logging to API_Log__c via ApiLogger
 *   [+] Skip-if-populated guard (checked by caller -- see DynamicDataRefreshBatch):
 *     if Foot_Traffic_Index__c is already filled, the batch skips this call,
 *     preserving BestTime credits.
 *
 * BestTime credit optimization:
 *   BestTime charges per forecast. To minimize spend:
 *     1. Only call for Expansion_Site__c records where Foot_Traffic_Index__c IS NULL
 *        (handled by the batch query scope, see startExpansionSitesMode).
 *     2. Once populated, only re-fetch on explicit refresh (e.g., Is_Refresh_Required__c flag).
 *
 * NAMED CREDENTIAL ENDPOINT (active)
 * ------------------------------------
 * The BestTime public API key is stored in the BestTime_EC External Credential
 * principal and is injected as the api_key_public query parameter automatically.
 * It is never present in Apex code or source control.
 *
 * Activation: ApiConfigService.isActive('BestTime') reads Is_Active__c from
 * API_Config__mdt.  The API_Key__c field on that record should be set to
 * 'NC_MANAGED' as a visual indicator that the secret has moved to the NC.
 */
public with sharing class Api_BestTimeService {

    private static final String  PROVIDER    = 'BestTime';
    // Key is injected by BestTime_EC External Credential — never in code.
    private static final String  ENDPOINT    = 'callout:BestTime_NC/api/v1/forecasts';
    private static final Integer TIMEOUT_MS  = 20000;
    // BestTime forecast cost (credit-based; approx. USD equivalent at standard plan rate)
    private static final Decimal COST_PER_CALL = 0.10;

    // ─────────────────────────────────────────────────────────────────────────
    // PUBLIC API
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns a 0–100 busyness index for the given venue address.
     * Returns null when the config is inactive, address is blank, or the call fails.
     *
     * @param address    Full venue address (street, city, country).
     * @param batchMode  Forwarded to API log.
     * @param recordId   18-char Salesforce record ID for log traceability.
     */
    public static Decimal getFootTrafficIndex(
        String address,
        String batchMode,
        String recordId
    ) {
        if (String.isBlank(address)) { return null; }

        if (!ApiConfigService.isActive(PROVIDER)) { return null; }

        HttpRequest req = buildRequest(address);

        ApiCalloutRetry.Result result = ApiCalloutRetry.execute(req);
        ApiLogger.LogContext ctx = new ApiLogger.LogContext(PROVIDER, ENDPOINT, batchMode)
            .withRecordId(recordId)
            .withEstimatedCost(COST_PER_CALL);
        ApiLogger.log(ApiLogger.entry(ctx, result));

        if (!result.isOk()) { return null; }
        return parseBusynessIndex(result.response.getBody());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PRIVATE — Config helper
    // ─────────────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────────
    // PRIVATE — Request builder
    // ─────────────────────────────────────────────────────────────────────────

    // api_key_public is injected by BestTime_EC Named Credential.
    // api_key_private is read from API_Config__mdt.API_Key__c (stored server-side, not in code).
    private static HttpRequest buildRequest(String address) {
        String privateKey = '';
        if (Schema.sObjectType.API_Config__mdt.isAccessible()) {
            List<API_Config__mdt> recs = [SELECT API_Key__c FROM API_Config__mdt WHERE DeveloperName = 'BestTime' LIMIT 1];
            if (!recs.isEmpty() && !String.isBlank(recs[0].API_Key__c)) {
                privateKey = '&api_key_private=' + recs[0].API_Key__c;
            }
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            ENDPOINT
            + '?venue_name='    + EncodingUtil.urlEncode(address, 'UTF-8')
            + '&venue_address=' + EncodingUtil.urlEncode(address, 'UTF-8')
            + privateKey
        );
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setTimeout(TIMEOUT_MS);
        return req;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PRIVATE — Response parser
    // ─────────────────────────────────────────────────────────────────────────

    // Response: { "status": "OK", "venue_info": {...}, "analysis": [ { "day_info": { "day_max": 78 }, ... } ] }
    private static Decimal parseBusynessIndex(String body) {
        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(body);
            Object status = responseMap.get('status');
            if (status == null || status == (Object) 'Error') { return null; }

            List<Object> analysisDays = (List<Object>) responseMap.get('analysis');
            if (analysisDays == null || analysisDays.isEmpty()) { return null; }

            return computePeakAverage(analysisDays);
        } catch (Exception e) {
            System.debug('Api_BestTimeService.parseBusynessIndex error: ' + e.getMessage());
            return null;
        }
    }

    private static Decimal computePeakAverage(List<Object> analysisDays) {
        Integer totalPeak = 0;
        Integer dayCount  = 0;

        for (Object dayObj : analysisDays) {
            Map<String, Object> day     = (Map<String, Object>) dayObj;
            Map<String, Object> dayInfo = (Map<String, Object>) day.get('day_info');
            if (dayInfo == null) { continue; }

            // BestTime returns day_max (peak busyness for that day)
            Object maxBusyness = dayInfo.get('day_max');
            if (maxBusyness == null) { maxBusyness = dayInfo.get('max_busyness'); }
            if (maxBusyness != null) {
                totalPeak += Integer.valueOf(String.valueOf(maxBusyness));
                dayCount++;
            }
        }

        if (dayCount == 0) { return null; }
        return Decimal.valueOf(totalPeak / dayCount).setScale(0);
    }
}