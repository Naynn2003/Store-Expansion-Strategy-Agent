/**
 * Api_GrowthRateService
 * =====================
 * Isolated service for the World Bank Open Data API.
 * Responsible for: fetching India GDP growth rate.
 *
 * Improvements over DynamicDataService (which remains untouched):
 *   [+] Retry via ApiCalloutRetry (up to 2 additional attempts on 5xx)
 *   [+] Structured logging to API_Log__c via ApiLogger
 *   [+] In-transaction static cache: World Bank is called ONCE per transaction
 *     regardless of how many times getIndiaGrowthRate() is invoked.
 *
 * The static cache is intentionally per-transaction only (not Platform Cache).
 * World Bank publishes annual data — one fetch per batch run is sufficient.
 * If you need cross-transaction caching, store the result in a Custom Setting
 * or use Platform Cache (org partition) with a 24-hour TTL.
 */
public with sharing class Api_GrowthRateService {

    private static final String PROVIDER    = 'World_Bank';
    private static final String ENDPOINT    =
        'https://api.worldbank.org/v2/country/IN/indicator/NY.GDP.MKTP.KD.ZG' +
        '?format=json&mrv=1&per_page=1';
    private static final Integer TIMEOUT_MS = 15000;

    // ── In-transaction cache ──────────────────────────────────────────────────
    // Populated on first successful call; returned directly on subsequent calls.
    @TestVisible
    private static Decimal cachedRate;

    // ─────────────────────────────────────────────────────────────────────────
    // PUBLIC API
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns India's latest annual GDP growth rate (percent).
     * Returns null if the API is inactive in MDT, the call fails, or data is absent.
     *
     * @param batchMode  Forwarded to API log for traceability.
     */
    public static Decimal getIndiaGrowthRate(String batchMode) {
        if (cachedRate != null) {
            return cachedRate; // already fetched this transaction
        }

        if (!ApiConfigService.isActive(PROVIDER)) {
            return null;
        }

        ApiCalloutRetry.Result result = ApiCalloutRetry.execute(buildRequest());
        ApiLogger.LogContext ctx = new ApiLogger.LogContext(PROVIDER, ENDPOINT, batchMode);
        ApiLogger.log(ApiLogger.entry(ctx, result));

        if (!result.isOk()) {
            return null;
        }

        cachedRate = parseGrowthRate(result.response.getBody());
        return cachedRate;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    private static HttpRequest buildRequest() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT);
        req.setMethod('GET');
        req.setTimeout(TIMEOUT_MS);
        return req;
    }

    // Response shape: [ {page metadata}, [ {date, value, ...} ] ]
    private static Decimal parseGrowthRate(String body) {
        try {
            List<Object> parsed = (List<Object>) JSON.deserializeUntyped(body);
            if (parsed == null || parsed.size() < 2) { return null; }

            List<Object> dataRows = (List<Object>) parsed[1];
            if (dataRows == null || dataRows.isEmpty()) { return null; }

            Map<String, Object> row = (Map<String, Object>) dataRows[0];
            Object val = row.get('value');
            if (val == null) { return null; }

            return Decimal.valueOf(String.valueOf(val)).setScale(1);
        } catch (Exception e) {
            System.debug('Api_GrowthRateService.parseGrowthRate error: ' + e.getMessage());
            return null;
        }
    }
}