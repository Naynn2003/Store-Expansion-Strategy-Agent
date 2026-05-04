/**
 * ApiCalloutRetry
 * ===============
 * Lightweight retry wrapper for all HTTP callouts.
 * Retries on 5xx responses (server-side errors) and on exceptions.
 * Does NOT retry on 4xx responses (client errors – fix the request, not the retry).
 *
 * Usage:
 *   HttpRequest req = ...;
 *   ApiCalloutRetry.Result result = ApiCalloutRetry.execute(req, 2);
 *   if (result.isSuccess()) { ... }
 *
 * Note on governor limits:
 *   Each retry counts as a separate callout. With maxRetries = 2, worst-case
 *   is 3 callouts per call site. Size batch scopes accordingly.
 */
public with sharing class ApiCalloutRetry {

    /** Wraps both the raw response and retry metadata together. */
    public class Result {
        public HttpResponse response    { get; private set; }
        public Integer      retryCount  { get; private set; }
        public String       lastError   { get; private set; }

        public Result(HttpResponse res, Integer retries, String err) {
            this.response   = res;
            this.retryCount = retries;
            this.lastError  = err;
        }

        /** True only when the response arrived and the status code is < 500. */
        public Boolean isSuccess() {
            return response != null && response.getStatusCode() < 500;
        }

        /** True when the response arrived with an HTTP 200. */
        public Boolean isOk() {
            return response != null && response.getStatusCode() == 200;
        }

        /**
         * True when the API responded with HTTP 429 (Too Many Requests / rate limited).
         *
         * In synchronous Apex there is no sleep or wait primitive, so retrying
         * immediately will receive another 429.  When this returns true, callers
         * should log the event and defer the work to a Queueable or Platform Event
         * consumer rather than retrying inline.
         */
        public Boolean isRateLimited() {
            return response != null && response.getStatusCode() == 429;
        }
    }

    // ── Default retry cap ─────────────────────────────────────────────────────
    public static final Integer DEFAULT_MAX_RETRIES = 2;

    // ── Retry policy ─────────────────────────────────────────────────────────
    /**
     * Controls which HTTP status codes trigger a retry attempt.
     *
     * Default policy (standardPolicy()):
     *   - 5xx  → retry (transient server error)
     *   - 429  → do NOT retry synchronously (no sleep in Apex; inspect isRateLimited())
     *   - 4xx  → do NOT retry (client error; fix the request)
     *   - 2xx/3xx → do NOT retry (success / redirect)
     */
    public class RetryPolicy {
        public Integer maxRetries { get; private set; }
        public Boolean retryOn429 { get; private set; }

        public RetryPolicy(Integer maxRetries, Boolean retryOn429) {
            this.maxRetries = maxRetries;
            this.retryOn429 = retryOn429;
        }

        /**
         * Returns true when another attempt should be made for the given status code.
         * 5xx                     → retryable (transient server fault).
         * 429 + retryOn429=true   → retryable (only use in async/Queueable context).
         * everything else         → not retryable.
         */
        public Boolean shouldRetry(Integer statusCode) {
            if (statusCode == 429) { return retryOn429; }
            return statusCode >= 500;
        }
    }

    /**
     * Standard synchronous policy: retry on 5xx only.
     * 429 is treated as a terminal result so the caller can inspect
     * Result.isRateLimited() and schedule a deferred retry.
     */
    public static RetryPolicy standardPolicy() {
        return new RetryPolicy(DEFAULT_MAX_RETRIES, false);
    }

    /**
     * Execute an HTTP request with retry behaviour controlled by a RetryPolicy.
     * Use ApiCalloutRetry.standardPolicy() for the default synchronous policy.
     *
     * @param req     Fully configured HttpRequest.
     * @param policy  RetryPolicy specifying maxRetries and which status codes to retry.
     * @return        Result containing the last HttpResponse + retry metadata.
     */
    public static Result execute(HttpRequest req, RetryPolicy policy) {
        Integer      attempts  = 0;
        String       lastError = null;
        HttpResponse lastRes   = null;

        while (attempts <= policy.maxRetries) {
            try {
                lastRes = new Http().send(req);

                Integer code = lastRes.getStatusCode();
                if (!policy.shouldRetry(code)) {
                    // 2xx, 3xx, 4xx (incl. 429 on standard policy) — stop and return
                    return new Result(lastRes, attempts, null);
                }

                // Retryable status: record the error and loop
                lastError = 'HTTP ' + code + ' on attempt ' + (attempts + 1);

            } catch (Exception e) {
                lastError = e.getMessage();
            }

            attempts++;
        }

        // Exhausted all attempts — return last known state for logging
        return new Result(lastRes, attempts - 1, lastError);
    }

    /**
     * Execute with explicit maxRetries count (retries on 5xx only).
     * @param req         Fully configured HttpRequest.
     * @param maxRetries  Extra attempts after the first try (0 = no retry).
     */
    public static Result execute(HttpRequest req, Integer maxRetries) {
        return execute(req, new RetryPolicy(maxRetries, false));
    }

    /**
     * Convenience overload using DEFAULT_MAX_RETRIES and the standard policy.
     */
    public static Result execute(HttpRequest req) {
        return execute(req, standardPolicy());
    }
}