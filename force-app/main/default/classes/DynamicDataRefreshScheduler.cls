/**
 * DynamicDataRefreshScheduler
 * ============================
 * Schedulable wrapper for DynamicDataRefreshBatch.
 * Kicks off Mode 1 (MARKET_ANALYSIS), which auto-chains to
 * Mode 2 (COMPETITOR_STORES) → Mode 3 (EXPANSION_SITES) in finish().
 *
 * Default schedule target: every Sunday at 6:00 PM IST.
 *
 * ── To schedule from Setup UI ─────────────────────────────────────────────
 *  Setup → Apex Classes → Schedule Apex → pick DynamicDataRefreshScheduler
 *
 * ── To schedule from Anonymous Apex ───────────────────────────────────────
 *  // If scheduling user timezone is IST:
 *  // Every Sunday at 6:00 PM IST
 *  String cronExpr = '0 0 18 ? * SUN';
 *  System.schedule('Dynamic Data Refresh - Weekly-6PM-IST', cronExpr, new DynamicDataRefreshScheduler());
 *
 * ── To run immediately (one-time, for testing) ────────────────────────────
 *  Database.executeBatch(new DynamicDataRefreshBatch('MARKET_ANALYSIS'), 5);
 *
 * ── To cancel a scheduled job ─────────────────────────────────────────────
 *  // Find job id:
 *  List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name FROM CronTrigger
 *                             WHERE CronJobDetail.Name = 'Dynamic Data Refresh — Weekly'];
 *  System.abortJob(jobs[0].Id);
 */
public without sharing class DynamicDataRefreshScheduler implements Schedulable {

    public void execute(SchedulableContext ctx) {
        System.debug('DynamicDataRefreshScheduler triggered. Starting MARKET_ANALYSIS batch...');

        // Batch scope sizes chosen to stay within per-transaction callout limits:
        //   Mode 1: scope=5  → max 5 computeInsights calls per chunk (+ 1 shared World Bank)
        //   Mode 2: scope=3  → max 3 × 3 calls (search + details + distance) = 9 calls/chunk
        //   Mode 3: scope=5  → max 5 × 2 calls (BestTime + distance) = 10 calls/chunk
        Database.executeBatch(
            new DynamicDataRefreshBatch(DynamicDataRefreshBatch.MODE_MARKET_ANALYSIS),
            5
        );
    }
}