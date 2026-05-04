/**
 * ScoreSite
 * Agentforce InvocableMethod — Site Scoring Action
 *
 * Given an expansion site name, calculates or retrieves the composite
 * site score. If RetailVisitKpi data exists, computes fresh from field
 * observations. Otherwise returns the pre-loaded baseline score.
 * Used by agent topic: "Site Recommendation"
 */
@SuppressWarnings('PMD.CognitiveComplexity')
public with sharing class ScoreSite { // NOPMD - invocable orchestrator delegates into many small scoring helpers

    private class RequestContext {
        String requestedSiteName;
        Boolean saveScore;
    }

    private class ScoreOutcome {
        Result result;
        Site_Score__c scoreToInsert;
    }

    private class PendingInsert {
        Integer resultIndex;
        Site_Score__c score;
    }

    private class KpiScoreContext {
        Result result;
        Expansion_Site__c site;
        RequestContext requestContext;
        Map<Id, List<RetailVisitKpi>> kpisByVisitId;
    }

    public class Request {
        @InvocableVariable(label='Expansion Site Name' description='Site name to score (e.g. Malad West - 400064)' required=true)
        public String expansionSiteName;

        @InvocableVariable(label='Save Score' description='Set to true to persist a new Site_Score__c record (default false)')
        public Boolean saveScore;
    }

    public class Result {
        @InvocableVariable(label='Site Name')
        public String siteName;

        @InvocableVariable(label='City')
        public String city;

        @InvocableVariable(label='Demand Factor Score')
        public Decimal demandFactor;

        @InvocableVariable(label='Demographics Factor Score')
        public Decimal demographicsFactor;

        @InvocableVariable(label='Competition Factor Score')
        public Decimal competitionFactor;

        @InvocableVariable(label='Accessibility Factor Score')
        public Decimal accessibilityFactor;

        @InvocableVariable(label='Total Score')
        public Decimal totalScore;

        @InvocableVariable(label='Score Grade')
        public String scoreGrade;

        @InvocableVariable(label='Scoring Method')
        public String scoringMethod;

        @InvocableVariable(label='Scoring Notes')
        public String scoringNotes;

        @InvocableVariable(label='Recommended')
        public Boolean recommended;

        @InvocableVariable(label='Score Summary')
        public String scoreSummary;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Score Expansion Site'
        description='Calculates a composite score for an expansion site from field visit KPIs or returns pre-loaded baseline score.'
        category='Store Expansion'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<RequestContext> requestContexts = buildRequestContexts(requests);
        List<Expansion_Site__c> sites = loadSites();
        Map<Id, List<RetailVisitKpi>> kpisByVisitId = loadKpisByVisitId(collectVisitIds(sites));
        List<PendingInsert> pendingInserts = new List<PendingInsert>();

        for (RequestContext requestContext : requestContexts) {
            ScoreOutcome outcome = buildScoreOutcome(requestContext, sites, kpisByVisitId);
            results.add(outcome.result);
            if (outcome.scoreToInsert != null) {
                PendingInsert pendingInsert = new PendingInsert();
                pendingInsert.resultIndex = results.size() - 1;
                pendingInsert.score = outcome.scoreToInsert;
                pendingInserts.add(pendingInsert);
            }
        }

        insertPendingScores(pendingInserts, results);

        return results;
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static List<RequestContext> buildRequestContexts(List<Request> requests) {
        List<RequestContext> contexts = new List<RequestContext>();
        for (Request requestItem : requests) {
            RequestContext context = new RequestContext();
            context.requestedSiteName = normalizeValue(requestItem.expansionSiteName);
            context.saveScore = requestItem.saveScore == true;
            contexts.add(context);
        }
        return contexts;
    }

    private static List<Expansion_Site__c> loadSites() {
        if (!Schema.sObjectType.Expansion_Site__c.isAccessible()) {
            return new List<Expansion_Site__c>();
        }

        return [
            SELECT Id, Name, City__c, State__c,
                   Demand_Score__c, Accessibility_Score__c,
                   Competition_Level__c, Population_Density__c,
                   Avg_Household_Income__c, Foot_Traffic_Index__c,
                   Recommended__c,
                   (SELECT Total_Score__c, Demand_Factor__c, Demographics_Factor__c,
                           Competition_Factor__c, Accessibility_Factor__c,
                           Scored_By__c, Scoring_Notes__c, Scoring_Date__c
                    FROM Site_Scores__r
                    ORDER BY Scoring_Date__c DESC
                    LIMIT 1),
                   (SELECT Id FROM Field_Visits__r
                    ORDER BY PlannedVisitStartTime DESC
                    LIMIT 1)
            FROM Expansion_Site__c
            WITH SECURITY_ENFORCED
            ORDER BY Name
        ];
    }

    private static Set<Id> collectVisitIds(List<Expansion_Site__c> sites) {
        Set<Id> visitIds = new Set<Id>();
        for (Expansion_Site__c site : sites) {
            if (site.Field_Visits__r != null && !site.Field_Visits__r.isEmpty()) {
                visitIds.add(site.Field_Visits__r[0].Id);
            }
        }
        return visitIds;
    }

    private static Map<Id, List<RetailVisitKpi>> loadKpisByVisitId(Set<Id> visitIds) {
        Map<Id, List<RetailVisitKpi>> kpisByVisitId = new Map<Id, List<RetailVisitKpi>>();
        if (visitIds.isEmpty() || !Schema.sObjectType.RetailVisitKpi.isAccessible()) {
            return kpisByVisitId;
        }

        for (RetailVisitKpi kpi : [
            SELECT VisitId, ActualIntegerValue, AssessmentIndDefinition.Name
            FROM RetailVisitKpi
            WHERE VisitId IN :visitIds
            WITH SECURITY_ENFORCED
        ]) {
            addKpi(kpisByVisitId, kpi);
        }
        return kpisByVisitId;
    }

    private static void addKpi(Map<Id, List<RetailVisitKpi>> kpisByVisitId, RetailVisitKpi kpi) {
        if (!kpisByVisitId.containsKey(kpi.VisitId)) {
            kpisByVisitId.put(kpi.VisitId, new List<RetailVisitKpi>());
        }
        kpisByVisitId.get(kpi.VisitId).add(kpi);
    }

    private static ScoreOutcome buildScoreOutcome(
        RequestContext requestContext,
        List<Expansion_Site__c> sites,
        Map<Id, List<RetailVisitKpi>> kpisByVisitId
    ) {
        ScoreOutcome outcome = new ScoreOutcome();
        Result validationError = validateRequest(requestContext);
        if (validationError != null) {
            outcome.result = validationError;
            return outcome;
        }

        Expansion_Site__c site = findMatchingSite(requestContext, sites);
        if (site == null) {
            outcome.result = buildMissingSiteResult(requestContext);
            return outcome;
        }

        Result result = initializeResult(site);
        KpiScoreContext kpiContext = new KpiScoreContext();
        kpiContext.result = result;
        kpiContext.site = site;
        kpiContext.requestContext = requestContext;
        kpiContext.kpisByVisitId = kpisByVisitId;
        outcome.scoreToInsert = applyKpiScore(kpiContext);
        if (outcome.scoreToInsert == null) {
            applyStoredOrDerivedScore(result, site);
        }

        finalizeResult(result, site);
        outcome.result = result;
        return outcome;
    }

    private static Result validateRequest(RequestContext requestContext) {
        if (String.isNotBlank(requestContext.requestedSiteName)) {
            return null;
        }

        Result result = new Result();
        result.errorMessage = 'Expansion Site Name is required.';
        return result;
    }

    private static Expansion_Site__c findMatchingSite(RequestContext requestContext, List<Expansion_Site__c> sites) {
        for (Expansion_Site__c site : sites) {
            if (containsIgnoreCase(site.Name, requestContext.requestedSiteName)) {
                return site;
            }
        }
        return null;
    }

    private static Boolean containsIgnoreCase(String sourceValue, String searchValue) {
        if (String.isBlank(sourceValue) || String.isBlank(searchValue)) {
            return false;
        }
        return sourceValue.toLowerCase().contains(searchValue.toLowerCase());
    }

    private static Result buildMissingSiteResult(RequestContext requestContext) {
        Result result = new Result();
        result.errorMessage = 'No expansion site found matching: ' + requestContext.requestedSiteName;
        return result;
    }

    private static Result initializeResult(Expansion_Site__c site) {
        Result result = new Result();
        result.siteName = site.Name;
        result.city = site.City__c;
        result.recommended = site.Recommended__c;
        return result;
    }

    private static Site_Score__c applyKpiScore(KpiScoreContext context) {
        Id visitId = getLatestVisitId(context.site);
        if (visitId == null) {
            return null;
        }

        List<RetailVisitKpi> kpis = context.kpisByVisitId.get(visitId);
        if (kpis == null || kpis.isEmpty()) {
            return null;
        }

        Map<String, Decimal> kpiMap = buildKpiMap(kpis);
        populateKpiResult(context.result, visitId, kpiMap);
        if (!context.requestContext.saveScore || context.result.totalScore == null) {
            return null;
        }
        return buildPendingScore(context.site.Id, context.result);
    }

    private static Id getLatestVisitId(Expansion_Site__c site) {
        if (site.Field_Visits__r == null || site.Field_Visits__r.isEmpty()) {
            return null;
        }
        return site.Field_Visits__r[0].Id;
    }

    private static Map<String, Decimal> buildKpiMap(List<RetailVisitKpi> kpis) {
        Map<String, Decimal> kpiMap = new Map<String, Decimal>();
        for (RetailVisitKpi kpi : kpis) {
            if (kpi.AssessmentIndDefinition != null) {
                kpiMap.put(kpi.AssessmentIndDefinition.Name, kpi.ActualIntegerValue);
            }
        }
        return kpiMap;
    }

    private static void populateKpiResult(Result result, Id visitId, Map<String, Decimal> kpiMap) {
        result.demandFactor = kpiMap.get('Footfall_Potential');
        result.demographicsFactor = kpiMap.get('Demographics_Score');
        result.competitionFactor = kpiMap.get('Competition_Density');
        result.accessibilityFactor = kpiMap.get('Accessibility_Score');
        result.totalScore = safeSum(new List<Decimal>{
            result.demandFactor,
            result.demographicsFactor,
            result.competitionFactor,
            result.accessibilityFactor
        });
        result.scoringMethod = 'Field Visit KPIs';
        result.scoringNotes = 'Computed live from RetailVisitKpi observations for visit: ' + visitId;
    }

    private static Site_Score__c buildPendingScore(Id siteId, Result result) {
        return new Site_Score__c(
            Expansion_Site__c = siteId,
            Scoring_Date__c = Date.today(),
            Scored_By__c = 'Agentforce Store Expansion Agent',
            Demand_Factor__c = result.demandFactor,
            Demographics_Factor__c = result.demographicsFactor,
            Competition_Factor__c = result.competitionFactor,
            Accessibility_Factor__c = result.accessibilityFactor,
            Scoring_Notes__c = result.scoringNotes
        );
    }

    private static void applyStoredOrDerivedScore(Result result, Expansion_Site__c site) {
        if (hasStoredScore(site)) {
            applyStoredScore(result, site.Site_Scores__r[0]);
            return;
        }
        applyDerivedScore(result, site);
    }

    private static Boolean hasStoredScore(Expansion_Site__c site) {
        return site.Site_Scores__r != null && !site.Site_Scores__r.isEmpty();
    }

    private static void applyStoredScore(Result result, Site_Score__c storedScore) {
        result.demandFactor = storedScore.Demand_Factor__c;
        result.demographicsFactor = storedScore.Demographics_Factor__c;
        result.competitionFactor = storedScore.Competition_Factor__c;
        result.accessibilityFactor = storedScore.Accessibility_Factor__c;
        result.totalScore = storedScore.Total_Score__c;
        result.scoringMethod = 'Pre-loaded Baseline (' + storedScore.Scored_By__c + ')';
        result.scoringNotes = storedScore.Scoring_Notes__c;
    }

    private static void applyDerivedScore(Result result, Expansion_Site__c site) {
        result.accessibilityFactor = site.Accessibility_Score__c;
        result.demandFactor = site.Demand_Score__c;
        result.competitionFactor = competitionLevelToScore(site.Competition_Level__c);
        result.demographicsFactor = deriveDemographicsScore(
            site.Population_Density__c,
            site.Avg_Household_Income__c
        );
        result.totalScore = safeSum(new List<Decimal>{
            result.demandFactor,
            result.demographicsFactor,
            result.competitionFactor,
            result.accessibilityFactor
        });
        result.scoringMethod = 'Derived from Site Fields';
        result.scoringNotes = 'No Site_Score__c or RetailVisitKpi found — scores derived from Expansion_Site__c fields.';
    }

    private static void finalizeResult(Result result, Expansion_Site__c site) {
        result.scoreGrade = gradeScore(result.totalScore);
        result.scoreSummary = buildScoreSummary(result, site);
    }

    private static String buildScoreSummary(Result result, Expansion_Site__c site) {
        return
            '📍 ' + site.Name + ' (' + site.City__c + ')' +
            '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' +
            '\n📊 Demand Factor:       ' + nullSafe(result.demandFactor) + ' / 25' +
            '\n👥 Demographics Factor: ' + nullSafe(result.demographicsFactor) + ' / 25' +
            '\n🏪 Competition Factor:  ' + nullSafe(result.competitionFactor) + ' / 25' +
            '\n🚗 Accessibility Factor:' + nullSafe(result.accessibilityFactor) + ' / 25' +
            '\n─────────────────────────────' +
            '\n🏆 Total Score:         ' + nullSafe(result.totalScore) + ' / 100  [' + result.scoreGrade + ']' +
            '\n📋 Method: ' + result.scoringMethod +
            appendScoringNotes(result.scoringNotes) +
            appendRecommendation(result.recommended);
    }

    private static String appendScoringNotes(String scoringNotes) {
        return String.isNotBlank(scoringNotes) ? '\n💬 Notes: ' + scoringNotes : '';
    }

    private static String appendRecommendation(Boolean recommended) {
        return recommended == true ? '\n✅ RECOMMENDED for expansion' : '';
    }

    private static void insertPendingScores(List<PendingInsert> pendingInserts, List<Result> results) {
        if (pendingInserts.isEmpty() || !Schema.sObjectType.Site_Score__c.isCreateable()) {
            return;
        }

        List<Site_Score__c> scoresToInsert = new List<Site_Score__c>();
        for (PendingInsert pendingInsert : pendingInserts) {
            scoresToInsert.add(pendingInsert.score);
        }

        List<Database.SaveResult> saveResults = Database.insert(scoresToInsert, false);
        for (Integer index = 0; index < saveResults.size(); index++) {
            Database.SaveResult saveResult = saveResults[index];
            Result result = results[pendingInserts[index].resultIndex];
            if (saveResult.isSuccess()) {
                result.scoringNotes = appendStatusNote(result.scoringNotes, 'Saved as Site_Score__c: ' + saveResult.getId());
                result.scoreSummary += '\n💾 Saved Score Record: ' + saveResult.getId();
            } else {
                result.scoringNotes = appendStatusNote(result.scoringNotes, 'Save failed: ' + saveResult.getErrors()[0].getMessage());
                result.scoreSummary += '\n⚠️ Save failed: ' + saveResult.getErrors()[0].getMessage();
            }
        }
    }

    private static String appendStatusNote(String currentNotes, String statusNote) {
        return String.isBlank(currentNotes) ? statusNote : currentNotes + ' | ' + statusNote;
    }

    private static String normalizeValue(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static Decimal safeSum(List<Decimal> vals) {
        Decimal total = 0;
        Boolean anyNotNull = false;
        for (Decimal v : vals) {
            if (v != null) {
                total += v;
                anyNotNull = true;
            }
        }
        return anyNotNull ? total : null;
    }

    private static String gradeScore(Decimal score) {
        if (score == null) { return 'N/A'; }
        if (score >= 85) { return 'A+ — Excellent'; }
        if (score >= 70) { return 'A  — Strong'; }
        if (score >= 55) { return 'B  — Good'; }
        if (score >= 40) { return 'C  — Average'; }
        return 'D  — Below Average';
    }

    private static Decimal competitionLevelToScore(String level) {
        if (level == 'Low')    { return 22; }
        if (level == 'Medium') { return 15; }
        if (level == 'High')   { return 8; }
        return null;
    }

    private static Decimal deriveDemographicsScore(Decimal density, Decimal income) {
        if (density == null && income == null) { return null; }
        Decimal score = 0;
        if (density != null) {
            // Normalize density: 20,000+/km² = max 12 pts
            score += Math.min(12, (density / 20000 * 12).setScale(1));
        }
        if (income != null) {
            // Normalize income: ₹60,000+/month = max 13 pts
            score += Math.min(13, (income / 60000 * 13).setScale(1));
        }
        return score.setScale(0);
    }

    private static String nullSafe(Decimal val) {
        return val != null ? String.valueOf(val) : '--';
    }
}