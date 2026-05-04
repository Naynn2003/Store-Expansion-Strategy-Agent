/**
 * AnalyzeMarket
 * Agentforce InvocableMethod — Market Analysis Action
 *
 * Given a city name, returns the full market analysis summary including
 * TAM, top sites, risks, demographic overview, and growth context.
 * Used by the Agentforce agent topic: "Market Research"
 */
public with sharing class AnalyzeMarket {

    private class AnalysisContext {
        public Map<String, Market_Analysis__c> analysisByCity = new Map<String, Market_Analysis__c>();
        public Map<String, List<Market_Top_Site__c>> topSitesByCity = new Map<String, List<Market_Top_Site__c>>();
        public Map<String, List<Market_Risk__c>> risksByCity = new Map<String, List<Market_Risk__c>>();
        public Map<String, List<Demographic_Data__c>> demosByCity = new Map<String, List<Demographic_Data__c>>();
    }

    public class Request {
        @InvocableVariable(label='City Name' description='City to analyze, e.g. Mumbai' required=true)
        public String city;
    }

    public class Result {
        @InvocableVariable(label='City')
        public String city;

        @InvocableVariable(label='State')
        public String state;

        @InvocableVariable(label='Region')
        public String region;

        @InvocableVariable(label='Total Addressable Market (INR)')
        public Decimal tam;

        @InvocableVariable(label='Growth Rate (%)')
        public Decimal growthRate;

        @InvocableVariable(label='Competitor Count')
        public Integer competitorCount;

        @InvocableVariable(label='Top Sites Summary')
        public String topSites;

        @InvocableVariable(label='Blind Spots / Risks Summary')
        public String blindSpots;

        @InvocableVariable(label='Analysis Date')
        public String analysisDate;

        @InvocableVariable(label='Data Source')
        public String source;

        @InvocableVariable(label='Confidence Level')
        public String confidence;

        @InvocableVariable(label='Top Ranked Sites (structured)')
        public String topRankedSites;

        @InvocableVariable(label='Key Risks (structured)')
        public String keyRisks;

        @InvocableVariable(label='Demographic Snapshot')
        public String demographicSnapshot;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Analyze Market'
        description='Returns full market analysis for a given city: TAM, growth, top sites, risks, and demographics.'
        category='Store Expansion'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        AnalysisContext context = loadContext();

        for (Request req : requests) {
            results.add(buildResult(req, context));
        }

        return results;
    }

    private static AnalysisContext loadContext() {
        AnalysisContext context = new AnalysisContext();
        context.analysisByCity = loadAnalysesByCity();
        context.topSitesByCity = loadTopSitesByCity();
        context.risksByCity = loadRisksByCity();
        context.demosByCity = loadDemographicsByCity();
        return context;
    }

    private static Map<String, Market_Analysis__c> loadAnalysesByCity() {
        Map<String, Market_Analysis__c> analysisByCity = new Map<String, Market_Analysis__c>();
        for (Market_Analysis__c analysis : [
            SELECT Name, City__c, State__c, Region__c,
                   TAM__c, Growth_Rate__c, Competitor_Count__c,
                   Top_Sites__c, Blind_Spots__c,
                   Analysis_Date__c, Primary_Source__c,
                   Source_Version__c, Confidence__c
            FROM Market_Analysis__c
            WITH SECURITY_ENFORCED
            ORDER BY Analysis_Date__c DESC
        ]) {
            String cityKey = normalizeCity(analysis.City__c);
            if (cityKey != null && !analysisByCity.containsKey(cityKey)) {
                analysisByCity.put(cityKey, analysis);
            }
        }
        return analysisByCity;
    }

    private static Map<String, List<Market_Top_Site__c>> loadTopSitesByCity() {
        Map<String, List<Market_Top_Site__c>> topSitesByCity = new Map<String, List<Market_Top_Site__c>>();
        for (Market_Top_Site__c topSite : [
            SELECT Site_Name__c, Rank__c, Demand_Score__c, Revenue_Potential__c,
                   Market_Analysis__r.City__c
            FROM Market_Top_Site__c
            WITH SECURITY_ENFORCED
            ORDER BY Rank__c ASC
        ]) {
            addTopSite(topSitesByCity, topSite);
        }
        return topSitesByCity;
    }

    private static Map<String, List<Market_Risk__c>> loadRisksByCity() {
        Map<String, List<Market_Risk__c>> risksByCity = new Map<String, List<Market_Risk__c>>();
        for (Market_Risk__c risk : [
            SELECT Risk_Type__c, Severity__c, Summary__c,
                   Market_Analysis__r.City__c
            FROM Market_Risk__c
            WITH SECURITY_ENFORCED
            ORDER BY Severity__c ASC
        ]) {
            addRisk(risksByCity, risk);
        }
        return risksByCity;
    }

    private static Map<String, List<Demographic_Data__c>> loadDemographicsByCity() {
        Map<String, List<Demographic_Data__c>> demosByCity = new Map<String, List<Demographic_Data__c>>();
        for (Demographic_Data__c demographic : [
            SELECT City__c, Pin_Code__c, Total_Population__c, Avg_Household_Income__c,
                   Income_Bracket__c, Age_18_35_Pct__c
            FROM Demographic_Data__c
            WITH SECURITY_ENFORCED
            ORDER BY Avg_Household_Income__c DESC NULLS LAST
        ]) {
            addDemographic(demosByCity, demographic);
        }
        return demosByCity;
    }

    private static void addTopSite(
        Map<String, List<Market_Top_Site__c>> topSitesByCity,
        Market_Top_Site__c topSite
    ) {
        String cityKey = normalizeCity(topSite.Market_Analysis__r.City__c);
        if (cityKey == null) {
            return;
        }
        if (!topSitesByCity.containsKey(cityKey)) {
            topSitesByCity.put(cityKey, new List<Market_Top_Site__c>());
        }
        topSitesByCity.get(cityKey).add(topSite);
    }

    private static void addRisk(
        Map<String, List<Market_Risk__c>> risksByCity,
        Market_Risk__c risk
    ) {
        String cityKey = normalizeCity(risk.Market_Analysis__r.City__c);
        if (cityKey == null) {
            return;
        }
        if (!risksByCity.containsKey(cityKey)) {
            risksByCity.put(cityKey, new List<Market_Risk__c>());
        }
        risksByCity.get(cityKey).add(risk);
    }

    private static void addDemographic(
        Map<String, List<Demographic_Data__c>> demosByCity,
        Demographic_Data__c demographic
    ) {
        String cityKey = normalizeCity(demographic.City__c);
        if (cityKey == null) {
            return;
        }
        if (!demosByCity.containsKey(cityKey)) {
            demosByCity.put(cityKey, new List<Demographic_Data__c>());
        }
        demosByCity.get(cityKey).add(demographic);
    }

    private static Result buildResult(Request req, AnalysisContext context) {
        Result res = new Result();
        if (req == null || String.isBlank(req.city)) {
            res.errorMessage = 'City is required.';
            return res;
        }

        String cityKey = findMatchingKey(context.analysisByCity.keySet(), req.city);
        if (cityKey == null) {
            res.errorMessage = 'No market analysis found for city: ' + req.city;
            return res;
        }

        Market_Analysis__c analysis = context.analysisByCity.get(cityKey);
        res.city = analysis.City__c;
        res.state = analysis.State__c;
        res.region = analysis.Region__c;
        res.tam = analysis.TAM__c;
        res.growthRate = analysis.Growth_Rate__c;
        res.competitorCount = analysis.Competitor_Count__c != null
            ? Integer.valueOf(analysis.Competitor_Count__c)
            : null;
        res.topSites = analysis.Top_Sites__c;
        res.blindSpots = analysis.Blind_Spots__c;
        res.analysisDate = analysis.Analysis_Date__c != null ? analysis.Analysis_Date__c.format() : null;
        res.source = analysis.Primary_Source__c
            + (analysis.Source_Version__c != null ? ' (' + analysis.Source_Version__c + ')' : '');
        res.confidence = analysis.Confidence__c;
        res.topRankedSites = buildTopSitesSummary(context.topSitesByCity.get(cityKey));
        res.keyRisks = buildRisksSummary(context.risksByCity.get(cityKey));
        res.demographicSnapshot = buildDemographicSnapshot(context.demosByCity.get(cityKey));
        return res;
    }

    private static String findMatchingKey(Set<String> keys, String requestedCity) {
        String normalizedRequest = normalizeCity(requestedCity);
        if (normalizedRequest == null) {
            return null;
        }
        if (keys.contains(normalizedRequest)) {
            return normalizedRequest;
        }
        for (String key : keys) {
            if (key.contains(normalizedRequest)) {
                return key;
            }
        }
        return null;
    }

    private static String buildTopSitesSummary(List<Market_Top_Site__c> topSites) {
        if (topSites == null || topSites.isEmpty()) {
            return null;
        }

        Integer resultLimit = Math.min(5, topSites.size());
        List<String> siteLines = new List<String>();
        for (Integer i = 0; i < resultLimit; i++) {
            Market_Top_Site__c topSite = topSites[i];
            String line = '#' + String.valueOf(topSite.Rank__c) + ' ' + topSite.Site_Name__c
                + ' — Demand: ' + topSite.Demand_Score__c;
            if (topSite.Revenue_Potential__c != null) {
                line += ', Revenue Potential: ₹' + formatCrore(topSite.Revenue_Potential__c);
            }
            siteLines.add(line);
        }
        return String.join(siteLines, '\n');
    }

    private static String buildRisksSummary(List<Market_Risk__c> risks) {
        if (risks == null || risks.isEmpty()) {
            return null;
        }

        Integer resultLimit = Math.min(5, risks.size());
        List<String> riskLines = new List<String>();
        for (Integer i = 0; i < resultLimit; i++) {
            Market_Risk__c risk = risks[i];
            riskLines.add('[' + risk.Severity__c + '] ' + risk.Risk_Type__c + ': ' + risk.Summary__c);
        }
        return String.join(riskLines, '\n');
    }

    private static String buildDemographicSnapshot(List<Demographic_Data__c> demographics) {
        if (demographics == null || demographics.isEmpty()) {
            return null;
        }

        Integer resultLimit = Math.min(3, demographics.size());
        List<String> demoLines = new List<String>();
        for (Integer i = 0; i < resultLimit; i++) {
            Demographic_Data__c demographic = demographics[i];
            demoLines.add(
                'Pin ' + demographic.Pin_Code__c
                + (demographic.Income_Bracket__c != null ? ' [' + demographic.Income_Bracket__c + ']' : '')
                + (demographic.Avg_Household_Income__c != null
                    ? ' Avg HH Income: ₹' + demographic.Avg_Household_Income__c.format()
                    : '')
                + (demographic.Age_18_35_Pct__c != null
                    ? ' | 18–35 age: ' + demographic.Age_18_35_Pct__c + '%'
                    : '')
            );
        }
        return String.join(demoLines, '\n');
    }

    private static String normalizeCity(String city) {
        if (String.isBlank(city)) {
            return null;
        }
        return city.trim().toLowerCase();
    }

    private static String formatCrore(Decimal val) {
        if (val == null) { return ''; }
        Decimal crore = val / 10000000;
        return crore.setScale(1) + ' Cr';
    }
}