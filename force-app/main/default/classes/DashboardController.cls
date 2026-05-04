/**
 * DashboardController
 * @AuraEnabled backend for the Store Expansion Strategy LWC dashboard.
 * Provides data for all 6 tabs and routes chat messages to the correct
 * @InvocableMethod action.
 */
public with sharing class DashboardController {

    // ── Summary Metrics ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getSummaryMetrics() {
        Map<String, Object> m = new Map<String, Object>();
        m.put('totalSites',        Database.countQuery('SELECT COUNT() FROM Expansion_Site__c WITH SECURITY_ENFORCED'));
        m.put('totalMarkets',      Database.countQuery('SELECT COUNT() FROM Market_Analysis__c WITH SECURITY_ENFORCED'));
        m.put('totalCompetitors',  Database.countQuery('SELECT COUNT() FROM Competitor_Store__c WITH SECURITY_ENFORCED'));
        m.put('recommendedSites',  Database.countQuery('SELECT COUNT() FROM Expansion_Site__c WHERE Recommended__c = true WITH SECURITY_ENFORCED'));

        AggregateResult[] tamAgg = [SELECT AVG(TAM__c) avgTam FROM Market_Analysis__c WITH SECURITY_ENFORCED];
        if (!tamAgg.isEmpty() && tamAgg[0].get('avgTam') != null) {
            Decimal avgTam = (Decimal) tamAgg[0].get('avgTam');
            m.put('avgTamCrore', (avgTam / 10000000).setScale(0));
        }

        List<Expansion_Site__c> topSite = [
            SELECT Name, City__c, Demand_Score__c
            FROM Expansion_Site__c
            WHERE Recommended__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Demand_Score__c DESC NULLS LAST
            LIMIT 1
        ];
        if (!topSite.isEmpty()) {
            m.put('topSiteName',  topSite[0].Name);
            m.put('topSiteCity',  topSite[0].City__c);
            m.put('topSiteScore', topSite[0].Demand_Score__c);
        }
        return m;
    }

    // ── Markets ────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Market_Analysis__c> getMarkets() {
        return [
            SELECT Id, Name, City__c, State__c, Region__c,
                   TAM__c, Growth_Rate__c, Competitor_Count__c,
                   Analysis_Date__c, Confidence__c
            FROM Market_Analysis__c
            WITH SECURITY_ENFORCED
            ORDER BY TAM__c DESC NULLS LAST
        ];
    }

    // ── Sites ──────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Expansion_Site__c> getSites() {
        return [
            SELECT Id, Name, City__c, State__c, Region__c,
                   Demand_Score__c, Competition_Level__c, Accessibility_Score__c,
                   Est_Monthly_Revenue__c, Payback_Period_Months__c,
                   Foot_Traffic_Index__c, Recommended__c, Status__c
            FROM Expansion_Site__c
            WITH SECURITY_ENFORCED
            ORDER BY Demand_Score__c DESC NULLS LAST
        ];
    }

    // ── Competitors ────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Competitor_Store__c> getCompetitors() {
        return [
            SELECT Id, Name, Brand__c, City__c, State__c,
                   Store_Format__c, Rating__c, Distance_km__c,
                   Store_Size_Sqft__c, Category__c
            FROM Competitor_Store__c
            WITH SECURITY_ENFORCED
            ORDER BY City__c ASC, Rating__c DESC NULLS LAST
        ];
    }

    // ── Financials (pre-computed wrapper) ─────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<FinancialRow> getFinancials() {
        List<FinancialRow> rows = new List<FinancialRow>();
        for (Financial_Projection__c fp : [
            SELECT Id, Name,
                   Expansion_Site__r.Name, Expansion_Site__r.City__c,
                   Setup_Cost__c, Monthly_Revenue__c, Monthly_Profit__c,
                   Payback_Months__c, Revenue_Confidence__c
            FROM Financial_Projection__c
            WITH SECURITY_ENFORCED
            ORDER BY Payback_Months__c ASC NULLS LAST
        ]) {
            FinancialRow row = new FinancialRow();
            row.rowId            = fp.Id;
            row.siteName         = fp.Expansion_Site__r != null ? fp.Expansion_Site__r.Name : fp.Name;
            row.city             = fp.Expansion_Site__r != null ? fp.Expansion_Site__r.City__c : '';
            row.setupCostCrore   = fp.Setup_Cost__c     != null ? (fp.Setup_Cost__c   / 10000000).setScale(1) : null;
            row.monthlyRevLakh   = fp.Monthly_Revenue__c != null ? (fp.Monthly_Revenue__c / 100000).setScale(1) : null;
            row.monthlyProfitLakh = fp.Monthly_Profit__c != null ? (fp.Monthly_Profit__c / 100000).setScale(1) : null;
            row.paybackMonths    = fp.Payback_Months__c;
            if (fp.Setup_Cost__c != null && fp.Setup_Cost__c > 0 && fp.Monthly_Profit__c != null) {
                row.annualRoiPct = ((fp.Monthly_Profit__c * 12 / fp.Setup_Cost__c) * 100).setScale(1);
            }
            row.confidence = fp.Revenue_Confidence__c;
            rows.add(row);
        }
        return rows;
    }

    public class FinancialRow {
        @AuraEnabled public String  rowId;
        @AuraEnabled public String  siteName;
        @AuraEnabled public String  city;
        @AuraEnabled public Decimal setupCostCrore;
        @AuraEnabled public Decimal monthlyRevLakh;
        @AuraEnabled public Decimal monthlyProfitLakh;
        @AuraEnabled public Decimal paybackMonths;
        @AuraEnabled public Decimal annualRoiPct;
        @AuraEnabled public String  confidence;
    }

    // ── Scores ─────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ScoreRow> getScores() {
        List<ScoreRow> rows = new List<ScoreRow>();
        for (Site_Score__c s : [
            SELECT Id, Name,
                   Expansion_Site__r.Name, Expansion_Site__r.City__c,
                   Total_Score__c, Demand_Factor__c, Demographics_Factor__c,
                   Competition_Factor__c, Accessibility_Factor__c,
                   Scoring_Date__c, Scored_By__c
            FROM Site_Score__c
            WITH SECURITY_ENFORCED
            ORDER BY Total_Score__c DESC NULLS LAST
        ]) {
            ScoreRow row = new ScoreRow();
            row.rowId             = s.Id;
            row.siteName          = s.Expansion_Site__r != null ? s.Expansion_Site__r.Name : s.Name;
            row.city              = s.Expansion_Site__r != null ? s.Expansion_Site__r.City__c : '';
            row.totalScore        = s.Total_Score__c;
            row.demandFactor      = s.Demand_Factor__c;
            row.demographicsFactor = s.Demographics_Factor__c;
            row.competitionFactor = s.Competition_Factor__c;
            row.accessFactor      = s.Accessibility_Factor__c;
            row.scoringDate       = s.Scoring_Date__c != null ? String.valueOf(s.Scoring_Date__c) : '';
            row.scoredBy          = s.Scored_By__c;
            rows.add(row);
        }
        return rows;
    }

    public class ScoreRow {
        @AuraEnabled public String  rowId;
        @AuraEnabled public String  siteName;
        @AuraEnabled public String  city;
        @AuraEnabled public Decimal totalScore;
        @AuraEnabled public Decimal demandFactor;
        @AuraEnabled public Decimal demographicsFactor;
        @AuraEnabled public Decimal competitionFactor;
        @AuraEnabled public Decimal accessFactor;
        @AuraEnabled public String  scoringDate;
        @AuraEnabled public String  scoredBy;
    }

    // ── Keyword lists for chat routing ────────────────────────────────────────

    private static final List<String> FINANCIAL_KW  = new List<String>{
        'roi','return','payback','financ','profit','revenue','cost','invest'
    };
    private static final List<String> COMPETITOR_KW = new List<String>{
        'competit','brand','dmart','reliance','nearby','rival'
    };
    private static final List<String> SCORE_KW      = new List<String>{
        'score','grade','evaluate','assess'
    };
    private static final List<String> TOPSITE_KW    = new List<String>{
        'top site','best site','recommend','where to open','which site'
    };

    private static Boolean containsAny(String lower, List<String> keywords) {
        for (String kw : keywords) {
            if (lower.contains(kw)) { return true; }
        }
        return false;
    }

    private static String routeMessage(String message) {
        String lower = message.toLowerCase();
        if (containsAny(lower, FINANCIAL_KW))  { return handleFinancial(message); }
        if (containsAny(lower, COMPETITOR_KW)) { return handleCompetitor(message); }
        if (containsAny(lower, SCORE_KW))      { return handleScore(message); }
        if (containsAny(lower, TOPSITE_KW))    { return handleTopSites(message); }
        return handleMarket(message);
    }

    // ── Agent Chat ─────────────────────────────────────────────────────────────

    @AuraEnabled
    public static String chat(String message) {
        if (String.isBlank(message)) {
            return 'Please enter a question.';
        }
        try {
            return routeMessage(message);
        } catch (Exception e) {
            return 'Sorry, an error occurred: ' + e.getMessage();
        }
    }

    private static String handleMarket(String message) {
        AnalyzeMarket.Request req = new AnalyzeMarket.Request();
        req.city = extractCity(message);
        if (String.isBlank(req.city)) { req.city = 'Mumbai'; }
        AnalyzeMarket.Result r = AnalyzeMarket.execute(new List<AnalyzeMarket.Request>{ req })[0];
        if (String.isNotBlank(r.errorMessage)) { return '\u274C ' + r.errorMessage; }
        return '\uD83D\uDCCA Market Analysis: ' + r.city + '\n\n' +
               '\u2022 TAM: \u20B9' + formatCrore(r.tam) + ' Cr\n' +
               '\u2022 Growth Rate: ' + r.growthRate + '%\n' +
               '\u2022 Competitors: ' + r.competitorCount + '\n' +
               '\u2022 Confidence: ' + r.confidence + '\n\n' +
               '\uD83C\uDFC6 Top Sites:\n' + nullSafe(r.topSites) + '\n\n' +
               '\u26A0\uFE0F Risks:\n' + nullSafe(r.blindSpots);
    }

    private static String handleTopSites(String message) {
        FindTopSites.Request req = new FindTopSites.Request();
        req.city = extractCity(message);
        req.maxResults = 5;
        FindTopSites.Result r = FindTopSites.execute(new List<FindTopSites.Request>{ req })[0];
        if (String.isNotBlank(r.errorMessage)) { return '\u274C ' + r.errorMessage; }
        return '\uD83C\uDFEA Top Expansion Sites (' + r.sitesFound + ' found)\n\n' + nullSafe(r.summary);
    }

    private static String handleCompetitor(String message) {
        GetCompetitorIntel.Request req = new GetCompetitorIntel.Request();
        req.city = extractCity(message);
        if (String.isBlank(req.city)) { req.city = 'Mumbai'; }
        GetCompetitorIntel.Result r = GetCompetitorIntel.execute(new List<GetCompetitorIntel.Request>{ req })[0];
        if (String.isNotBlank(r.errorMessage)) { return '\u274C ' + r.errorMessage; }
        return '\uD83C\uDFEA Competitors in ' + r.city + '\n\n' +
               '\u2022 Count: ' + r.competitorCount + '\n' +
               '\u2022 Brands: ' + nullSafe(r.brandsPresent) + '\n' +
               '\u2022 Intensity: ' + nullSafe(r.competitiveIntensity) + '\n\n' +
               nullSafe(r.competitorSummary) + '\n\n' +
               '\u26A0\uFE0F ' + nullSafe(r.marketRiskNotes);
    }

    private static String handleFinancial(String message) {
        GetFinancialProjection.Request req = new GetFinancialProjection.Request();
        String city = extractCity(message);
        if (String.isNotBlank(city)) {
            req.city = city;
        } else {
            req.expansionSiteName = message.trim();
        }
        GetFinancialProjection.Result r = GetFinancialProjection.execute(new List<GetFinancialProjection.Request>{ req })[0];
        if (String.isNotBlank(r.errorMessage)) { return '\u274C ' + r.errorMessage; }
        return '\uD83D\uDCB0 Financial Projection: ' + nullSafe(r.siteName) + '\n\n' +
               '\u2022 Setup Cost: \u20B9' + formatCrore(r.setupCost) + ' Cr\n' +
               '\u2022 Monthly Revenue: \u20B9' + formatLakh(r.monthlyRevenue) + ' L\n' +
               '\u2022 Monthly Profit: \u20B9' + formatLakh(r.monthlyProfit) + ' L\n' +
               '\u2022 Payback: ' + r.paybackMonths + ' months\n' +
               '\u2022 Annual ROI: ' + r.annualRoi + '%\n\n' +
               '\u2705 ' + nullSafe(r.investmentRecommendation);
    }

    private static String handleScore(String message) {
        ScoreSite.Request req = new ScoreSite.Request();
        req.expansionSiteName = extractSiteName(message);
        if (String.isBlank(req.expansionSiteName)) { req.expansionSiteName = 'Malad'; }
        req.saveScore = false;
        ScoreSite.Result r = ScoreSite.execute(new List<ScoreSite.Request>{ req })[0];
        if (String.isNotBlank(r.errorMessage)) { return '\u274C ' + r.errorMessage; }
        return '\uD83D\uDCCA Site Score: ' + nullSafe(r.siteName) + '\n\n' +
               '\u2022 Total: ' + r.totalScore + '/100 (Grade: ' + nullSafe(r.scoreGrade) + ')\n' +
               '\u2022 Demand: ' + r.demandFactor + '\n' +
               '\u2022 Demographics: ' + r.demographicsFactor + '\n' +
               '\u2022 Competition: ' + r.competitionFactor + '\n' +
               '\u2022 Accessibility: ' + r.accessibilityFactor + '\n\n' +
               (r.recommended == true ? '\u2705 RECOMMENDED' : '\u26A0\uFE0F Review Needed');
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private static String extractCity(String message) {
        List<String> cities = new List<String>{
            'Mumbai', 'Pune', 'Bengaluru', 'Bangalore', 'Hyderabad', 'Chennai',
            'Kolkata', 'Delhi', 'Jaipur', 'Lucknow', 'Ahmedabad', 'Surat',
            'Nagpur', 'Indore', 'Bhopal', 'Chandigarh', 'Kochi', 'Coimbatore',
            'Varanasi', 'Agra', 'Vadodara', 'Rajkot', 'Mysuru', 'Visakhapatnam', 'Vizag'
        };
        String lower = message.toLowerCase();
        for (String city : cities) {
            if (lower.contains(city.toLowerCase())) {
                return resolveAlias(city);
            }
        }
        return null;
    }

    private static String resolveAlias(String city) {
        if (city == 'Bangalore') { return 'Bengaluru'; }
        if (city == 'Vizag')     { return 'Visakhapatnam'; }
        return city;
    }

    private static String extractSiteName(String message) {
        if (message.length() < 80 && !message.contains('?')) {
            return message.trim();
        }
        return null;
    }

    private static String formatCrore(Decimal v) {
        return v != null ? String.valueOf((v / 10000000).setScale(1)) : '\u2014';
    }

    private static String formatLakh(Decimal v) {
        return v != null ? String.valueOf((v / 100000).setScale(1)) : '\u2014';
    }

    private static String nullSafe(String s) {
        return s != null ? s : '';
    }
}