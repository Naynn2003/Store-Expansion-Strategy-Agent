# Production Architecture: API Integration Refactor

## STEP 1 — ARCHITECTURE REVIEW

### What to Keep
| Component | Keep? | Why |
|---|---|---|
| `DynamicDataRefreshBatch` (3 modes + chaining) | **Yes** | Clean orchestration, bulk DML, scope sizes are correct |
| `DynamicDataRefreshScheduler` | **Yes** | Simple, correct, no changes needed |
| `DynamicDataService` (CITY_COORDS, computeDemandScore, getConfig) | **Yes** | Utility constants + demand formula still used by batch |
| `API_Config__mdt` (Is_Active__c, API_Key__c, Base_URL__c) | **Yes** | Lightweight activation switch; key storage replaced by Named Credentials in Phase 5 |
| Remote Site Settings | **Yes, temporarily** | Required until Named Credentials are active in org |

### What Was Replaced
| Component | Replaced By | Reason |
|---|---|---|
| All HTTP callouts inside `DynamicDataService` | `Api_GrowthRateService`, `Api_GoogleMapsService`, `Api_BestTimeService` | Tight coupling — one class owning all 3 providers |
| No retry logic | `ApiCalloutRetry` | Transient 5xx failures caused silent data gaps |
| `System.debug` only logging | `ApiLogger` + `API_Log__c` | Impossible to audit cost, trace failures, or prove retries |
| Raw API keys in MDT fields (visible to all admins) | Named Credentials + External Credentials | OWASP A02 — sensitive data exposure |

### Risks in Original System
1. **Silent failures** — a 5xx from Google wrote nothing to the record; there was no way to tell it failed vs. the API being inactive.
2. **Unbounded callout cost** — BestTime is called for every Expansion_Site in every batch run, even when the field is already populated.
3. **Tight coupling** — any change to Google Places API (endpoint, field mask, response shape) required touching `DynamicDataService`, which also held World Bank and BestTime logic.
4. **Secret exposure** — API keys visible as plain text in Custom Metadata Type to any admin with Setup access.
5. **Hard to test** — mocking one API required mocking `DynamicDataService` entirely.

---

## STEP 2 — TARGET ARCHITECTURE

```
Scheduler
  └─▶ DynamicDataRefreshBatch (Stateful, 3 modes)
        ├── Mode 1: MARKET_ANALYSIS
        │     ├── Api_GrowthRateService.getIndiaGrowthRate()
        │     └── Api_GoogleMapsService.getCompetitorCount()
        │
        ├── Mode 2: COMPETITOR_STORES
        │     ├── Api_GoogleMapsService.searchPlace()         [+ placeCache]
        │     ├── Api_GoogleMapsService.getPlaceRating()
        │     └── Api_GoogleMapsService.getDrivingDistanceKm()
        │
        └── Mode 3: EXPANSION_SITES
              ├── Api_BestTimeService.getFootTrafficIndex()   [skip-if-populated]
              ├── Api_GoogleMapsService.getDrivingDistanceKm()
              └── DynamicDataService.computeDemandScore()

Each Api_* service:
  └─▶ ApiCalloutRetry.execute(req, 2)   [retry on 5xx, up to 2 extra attempts]
        └─▶ ApiLogger.log(entry)        [buffered, flushed in finish()]
              └─▶ API_Log__c            [queryable audit trail]

Named Credentials (Phase 5):
  Google_Places_NC ──▶ External Credential: Google_Maps_EC (key injected, never in code)
  Google_Maps_NC   ──▶ External Credential: Google_Maps_EC
  BestTime_NC      ──▶ External Credential: BestTime_EC
```

### New Classes (all created)
| Class | Role |
|---|---|
| `ApiCalloutRetry` | Retry wrapper: retries on 5xx, not on 4xx, returns `Result` VO |
| `ApiLogger` | Buffered log writer; `flush()` in `finish()` keeps DML out of execute() |
| `Api_GrowthRateService` | World Bank callout + in-transaction GDP cache |
| `Api_GoogleMapsService` | All Google callouts + placeCache + GeoPoint/CallContext VOs |
| `Api_BestTimeService` | BestTime callout + skip-if-populated guard |

### New Metadata (all created)
| File | Role |
|---|---|
| `API_Log__c` (object + 9 fields) | Queryable callout audit trail |
| `Google_Maps_EC.externalCredential-meta.xml` | Defines Custom auth protocol for Google; key stored in Setup |
| `BestTime_EC.externalCredential-meta.xml` | Defines Custom auth protocol for BestTime; key stored in Setup |
| `Google_Places_NC.namedCredential-meta.xml` | Named Credential for places.googleapis.com |
| `Google_Maps_NC.namedCredential-meta.xml` | Named Credential for maps.googleapis.com |
| `BestTime_NC.namedCredential-meta.xml` | Named Credential for besttime.app |

---

## STEP 3 — MIGRATION PLAN (Safe, Incremental)

### Phase 1 — DONE (this session)
- [x] Created `API_Log__c` object and 9 fields
- [x] Created `ApiCalloutRetry` with `Result` value object
- [x] Created `ApiLogger` with `LogContext` wrapper, CRUD check, buffered flush
- [x] Created `Api_GrowthRateService` (World Bank + in-transaction cache)
- [x] Created `Api_GoogleMapsService` (all 4 Google callouts, placeCache, GeoPoint, CallContext)
- [x] Created `Api_BestTimeService` (BestTime + skip-if-populated)
- [x] Updated `DynamicDataRefreshBatch` to route all callouts through new services
- [x] Added `ApiLogger.flush()` to `finish()`
- [x] Added skip-if-populated guard for BestTime (Mode 3)
- [x] Added skip-geocoding-if-coordinates-exist guard for Mode 2
- [x] Created External Credential and Named Credential metadata files
- [x] `DynamicDataService` left completely intact (backward compatible)

### Phase 2 — Deploy and Validate
1. Deploy to a sandbox: `sf project deploy start --manifest manifest/package.xml`
2. Activate `API_Log__c` tab in Setup (optional, for admin visibility)
3. Run a test batch: `Database.executeBatch(new DynamicDataRefreshBatch('MARKET_ANALYSIS'), 5);`
4. Query API logs: `SELECT API_Provider__c, Is_Success__c, Retry_Count__c, Duration_ms__c FROM API_Log__c`
5. Confirm no regressions in field values on Market_Analysis__c, Competitor_Store__c, Expansion_Site__c

### Phase 3 — Activate Named Credentials (Security Upgrade)
1. Deploy the External Credential and Named Credential metadata
2. In Setup → Named Credentials → External Credentials → Google_Maps_EC:
   - Add Principal "Default"
   - Set secret = actual Google API key
   - Assign permission to integration user's Permission Set
3. In Setup → Named Credentials → External Credentials → BestTime_EC:
   - Add Principal "Default"
   - Set secret = actual BestTime public key
4. Update `Api_GoogleMapsService` PLACES_BASE_URL: `'callout:Google_Places_NC'`
5. Update `Api_GoogleMapsService` DISTANCE_BASE_URL: `'callout:Google_Maps_NC/maps/api/distancematrix/json'`
6. Remove `+ '&key=' + cfg.API_Key__c` from Distance Matrix endpoint builder
7. Update `Api_BestTimeService` ENDPOINT: `'callout:BestTime_NC/api/v1/forecasts'`
8. Remove `api_key_public` param from BestTime request builder
9. Set `API_Config__mdt.API_Key__c` to 'NC_MANAGED' (visual indicator; field no longer used for secret)
10. Remove old Remote Site Settings after Named Credentials are confirmed working

### Phase 4 — Optional: Platform Cache for GDP
If the org has Platform Cache provisioned:
```apex
// In Api_GrowthRateService.getIndiaGrowthRate():
Cache.OrgPartition partition = Cache.Org.getPartition('local.ApiCache');
Decimal orgCached = (Decimal) partition.get('gdp_india');
if (orgCached != null) { return orgCached; }
// ... after successful callout:
partition.put('gdp_india', rate, 86400); // 24-hour TTL
```
This avoids the World Bank callout entirely for 24 hours, surviving across multiple batch runs.

---

## STEP 4 — PERFORMANCE AND COST OPTIMIZATION

### Google Maps API Cost Reduction
| Optimization | Implementation |
|---|---|
| **Skip geocoding for already-located stores** | `enrichCompetitorWithGoogleData()` returns early if `Latitude__c != null` |
| **In-transaction placeCache** | `Api_GoogleMapsService.placeCache` deduplicates Text Search within the same batch chunk |
| **Batch scope Mode 2 = 3** | 3 stores × 3 calls (search + rating + distance) = 9 calls, safe under 100-callout limit |
| **Named Credential key rotation** | Change key in Setup only; no code deploy required |

Future: Add `Last_Geocoded__c` Date field to `Competitor_Store__c`. Only re-geocode records where `Last_Geocoded__c = null OR Last_Geocoded__c < LAST_N_DAYS:180`.

### BestTime Credit Reduction
| Optimization | Implementation |
|---|---|
| **Skip if already populated** | `fetchFootTrafficIndex()` returns false if `Foot_Traffic_Index__c != null` |
| **Result: only new expansion sites are charged** | For steady-state operations, BestTime calls approach zero |

Future: Add `Foot_Traffic_Last_Refreshed__c` DateTime field. Only call BestTime if `null OR older than 90 days`. This gives full control over refresh cadence.

### Ideal Batch Sizes (unchanged, correct)
| Mode | Scope | Callouts per chunk | Max allowed |
|---|---|---|---|
| MARKET_ANALYSIS | 5 | 1 (World Bank, shared) + 5 (computeInsights) = 6 | 100 |
| COMPETITOR_STORES | 3 | 3 × 3 (search + rating + distance) = 9 | 100 |
| EXPANSION_SITES | 5 | 5 × 2 (BestTime + distance) = 10 | 100 |

With the skip-if-populated optimization, Mode 2 and Mode 3 effective callout counts drop significantly in steady-state.

---

## STEP 5 — SECURITY UPGRADE

### Current State (MDT-based keys)
```
API key stored in: API_Config__mdt.API_Key__c
Visible to: Any Salesforce admin with Setup access
Risk: OWASP A02 — Sensitive Data Exposure
```

### Target State (Named Credentials)
```
API key stored in: External Credential Principal (encrypted, Setup-only)
Visible to: No one (not even admins can read the value after save)
Risk: Eliminated for key exposure
```

### What is in Source Control (safe to commit)
- `externalCredentials/Google_Maps_EC.externalCredential-meta.xml` — defines protocol and parameter NAMES, no values
- `externalCredentials/BestTime_EC.externalCredential-meta.xml` — same
- `namedCredentials/*.namedCredential-meta.xml` — base URLs only, no keys

### What is NOT in Source Control (correct)
- The actual API key VALUES — configured manually in Setup UI per environment
- The Principal secret — stored encrypted in Salesforce only

### How to move API keys out of MDT
1. Complete Phase 3 of migration plan (above)
2. Clear `API_Key__c` values in all API_Config__mdt records (set to 'NC_MANAGED')
3. The `getActiveConfig()` guard in each service checks `!config.API_Key__c.startsWith('PASTE_')` — after migration, relax this check or remove it since keys are in Named Credentials
4. `Is_Active__c` and `Base_URL__c` on MDT remain useful for operational on/off switching

---

## STEP 6 — FINAL REFACTORED CODE SUMMARY

All code is in source. Key files:

| File | What It Does |
|---|---|
| [ApiCalloutRetry.cls](../force-app/main/default/classes/ApiCalloutRetry.cls) | Retry wrapper. Pass an `HttpRequest`, get a `Result` back. Retries on 5xx only. |
| [ApiLogger.cls](../force-app/main/default/classes/ApiLogger.cls) | Buffer + flush pattern. `LogContext` (3-param) + `withRecordId()`. CRUD-safe insert. |
| [Api_GrowthRateService.cls](../force-app/main/default/classes/Api_GrowthRateService.cls) | World Bank. Static `cachedRate` prevents duplicate calls per transaction. |
| [Api_GoogleMapsService.cls](../force-app/main/default/classes/Api_GoogleMapsService.cls) | All 4 Google calls. `GeoPoint` VO collapses coordinate params. `placeCache` prevents duplicate Text Search. `CallContext` passes mode+recordId cleanly. |
| [Api_BestTimeService.cls](../force-app/main/default/classes/Api_BestTimeService.cls) | BestTime. Skip-if-populated check is enforced in the batch. |
| [DynamicDataRefreshBatch.cls](../force-app/main/default/classes/DynamicDataRefreshBatch.cls) | Updated to use all 3 new services. `gmConfig`/`btConfig` dead params removed. `ApiLogger.flush()` in `finish()`. |

---

## STEP 7 — INTERVIEW DEFENSE

### Q: How do you avoid duplicate API calls?

Three layers:

1. **In-transaction static cache** (`Api_GrowthRateService.cachedRate`): World Bank is called once per Apex transaction no matter how many batch chunks run. In a single `executeBatch` run, `start()` and each `execute()` are separate transactions. The cache ensures exactly one call per execute chunk where the rate is needed.

2. **In-transaction placeCache** (`Api_GoogleMapsService.placeCache`): If the same store name appears twice in a batch chunk (unlikely but defensive), the second call returns the cached `PlaceResult` immediately.

3. **Skip-if-populated guards**: `enrichCompetitorWithGoogleData()` skips geocoding if `Latitude__c != null`. `fetchFootTrafficIndex()` skips BestTime if `Foot_Traffic_Index__c != null`. These are the highest-ROI optimizations because they eliminate entire API categories for records that already have data.

### Q: How do you handle API failures?

Four mechanisms:

1. **`ApiCalloutRetry`** retries up to 2 times on 5xx server errors. 4xx errors are not retried (client error = won't succeed on retry). Each attempt gets a fresh `Http().send()`.

2. **Structured logging** via `ApiLogger` writes every callout outcome (success, failure, retry count, status code, error message, duration) to `API_Log__c`. Admins can query these to see exactly which records failed and why.

3. **Graceful null propagation**: every service method returns `null` on failure. The batch builder methods (`buildMarketAnalysisUpdate`, etc.) check for `null` and skip the update rather than writing bad data or throwing.

4. **`Database.update(toUpdate, false)`**: partial DML. A failure on one record doesn't roll back the whole chunk. The `handleSaveResults()` method logs each individual DML failure.

### Q: How do you control cost?

Four strategies:

1. **Skip-if-populated**: BestTime (paid per forecast) is only called when `Foot_Traffic_Index__c IS NULL`. Geocoding (Text Search) is skipped when `Latitude__c != null`. In steady-state, Google + BestTime API cost approaches zero for established records.

2. **Batch scope sizes** are tuned to the callout limit: Mode 2 = 3 records (9 callouts), Mode 3 = 5 records (10 callouts). Never approaches the 100-callout limit.

3. **World Bank is free** and called once per batch run via the in-transaction cache.

4. **Named Credentials** enable key rotation without code deploy, so if a compromised key runs up costs, it can be rotated in seconds through Setup.

5. **Future optimization**: add `Last_Geocoded__c` and `Foot_Traffic_Last_Refreshed__c` Date fields; only refresh records older than N days. This gives exact control over refresh cadence and API budget.

### Q: Why is this architecture scalable?

1. **Single responsibility**: each service class owns exactly one vendor. Adding a new API (e.g., Postal Index lookup) means creating a new `Api_XyzService` without touching any existing class.

2. **No governor limit risk**: retry is bounded (max 3 total calls per method), batch scope sizes are tuned per mode's callout budget, and `ApiLogger` buffers to a single bulk insert per batch finish.

3. **Observable**: `API_Log__c` exposes every callout. You can build reports on: calls per provider per day, average retry rate, failure rate by city, cost attribution. None of this existed before.

4. **Config-driven activation**: `Is_Active__c` on `API_Config__mdt` lets you disable any integration instantly without a code deploy. Critical for incidents.

5. **Secret management scales**: Named Credentials store keys per environment (sandbox vs. production have different key values) and keys can be rotated without any code change.

6. **Testable in isolation**: mocking `Api_GoogleMapsService` in a unit test does not require mocking `DynamicDataService`. Each service has a single, clearly-defined HTTP boundary.
