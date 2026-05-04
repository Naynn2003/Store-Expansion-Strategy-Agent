/**
 * ApiLogger
 * =========
 * Session-scoped buffer for API_Log__c records.
 * Collects log entries in memory throughout a batch execute() call,
 * then flushes them to the database in one bulk insert during finish().
 *
 * Usage inside a service class:
 *   ApiLogger.log(ApiLogger.entry('World_Bank', endpoint, result, 'MARKET_ANALYSIS', null));
 *
 * Usage inside the batch finish():
 *   ApiLogger.flush();
 *
 * Design notes:
 *   - static buffer = lives for the duration of one Apex transaction.
 *   - In Database.Stateful batch, each execute() runs in its own transaction,
 *     so flush() is called from finish() after the last execute() completes OR
 *     each service class can call flush() at the end of its own execute() chunk.
 *   - insert is done with allOrNone=false so logging never causes a rollback.
 *   - Endpoint is truncated to 255 chars to fit the field length.
 */
public with sharing class ApiLogger {

    // ── Buffer ────────────────────────────────────────────────────────────────
    @TestVisible
    private static List<API_Log__c> buffer = new List<API_Log__c>();

    // ── Context wrapper: reduces method parameter count for PMD compliance ────
    public class LogContext {
        public String  provider;
        public String  endpoint;
        public String  batchMode;
        public String  relatedRecordId;
        public Decimal estimatedCostUsd;

        /** Core 3-param constructor. Use fluent setters for optional metadata. */
        public LogContext(String provider, String endpoint, String batchMode) {
            this.provider  = provider;
            this.endpoint  = endpoint;
            this.batchMode = batchMode;
        }

        /** Fluent setter for relatedRecordId. Returns this for chaining. */
        public LogContext withRecordId(String id) {
            this.relatedRecordId = id;
            return this;
        }

        /**
         * Fluent setter for estimated USD cost of this API call.
         * Set once per call site using the service class cost constant.
         * Example: .withEstimatedCost(Api_GoogleMapsService.COST_TEXT_SEARCH)
         */
        public LogContext withEstimatedCost(Decimal cost) {
            this.estimatedCostUsd = cost;
            return this;
        }
    }

    // ── Entry builder ─────────────────────────────────────────────────────────

    /**
     * Builds a log entry from an ApiCalloutRetry.Result + contextual metadata.
     * @param ctx     LogContext containing provider, endpoint, batchMode, relatedRecordId.
     * @param result  Result returned by ApiCalloutRetry.execute().
     */
    public static API_Log__c entry(LogContext ctx, ApiCalloutRetry.Result result) {
        Integer statusCode = result.response != null ? result.response.getStatusCode() : 0;
        String  errorMsg   = result.lastError;

        // Capture response body snippet on failure for debugging
        if (!result.isOk() && result.response != null && String.isBlank(errorMsg)) {
            errorMsg = result.response.getBody()?.left(255);
        }

        return new API_Log__c(
            API_Provider__c       = ctx.provider,
            Endpoint__c           = ctx.endpoint?.left(255),
            Status_Code__c        = statusCode,
            Is_Success__c         = result.isOk(),
            Is_Rate_Limited__c    = (statusCode == 429),
            Estimated_Cost_USD__c = ctx.estimatedCostUsd,
            Retry_Count__c        = result.retryCount,
            Error_Message__c      = errorMsg,
            Batch_Mode__c         = ctx.batchMode,
            Related_Record_Id__c  = ctx.relatedRecordId
        );
    }

    /**
     * Builds a log entry for a failed call where no HttpResponse was received.
     * @param ctx          LogContext containing provider, endpoint, batchMode, relatedRecordId.
     * @param errorMessage Descriptive error message.
     */
    public static API_Log__c errorEntry(LogContext ctx, String errorMessage) {
        return new API_Log__c(
            API_Provider__c       = ctx.provider,
            Endpoint__c           = ctx.endpoint?.left(255),
            Status_Code__c        = 0,
            Is_Success__c         = false,
            Is_Rate_Limited__c    = false,
            Estimated_Cost_USD__c = ctx.estimatedCostUsd,
            Retry_Count__c        = 0,
            Error_Message__c      = errorMessage?.left(32768),
            Batch_Mode__c         = ctx.batchMode,
            Related_Record_Id__c  = ctx.relatedRecordId
        );
    }

    // ── Buffer management ─────────────────────────────────────────────────────

    /** Add a pre-built log entry to the buffer. */
    public static void log(API_Log__c logEntry) {
        if (logEntry != null) {
            buffer.add(logEntry);
        }
    }

    /**
     * Flush buffered log entries to the database.
     * Safe to call multiple times -- a no-op when the buffer is already empty.
     * Uses allOrNone=false so a failed log insert never blocks business logic.
     */
    public static void flush() {
        if (buffer.isEmpty()) {
            return;
        }

        // CRUD check: only insert if the running user can create API_Log__c records
        if (Schema.sObjectType.API_Log__c.isCreateable()) {
            Database.insert(buffer, false);
        }
        buffer.clear();
    }

    /** Returns current buffer size (useful for tests). */
    @TestVisible
    public static Integer getBufferSize() {
        return buffer.size();
    }

    /** Clears the buffer without inserting (test teardown helper). */
    @TestVisible
    public static void clearBuffer() {
        buffer.clear();
    }
}