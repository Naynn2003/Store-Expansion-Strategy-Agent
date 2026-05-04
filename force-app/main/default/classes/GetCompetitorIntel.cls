/**
 * GetCompetitorIntel
 * Agentforce InvocableMethod — Competitor Analysis Action
 *
 * Given a city or expansion site name, returns competitive landscape:
 * all competitor stores in that city with brand, format, size, and
 * distance info. Used by agent topic: "Competitor Analysis"
 */
public with sharing class GetCompetitorIntel {

    private class RequestContext {
        String requestedCity;
        String requestedSiteName;
        String normalizedCity;
        String resolvedCity;
    }

    private class IntelContext {
        Map<String, String> cityBySiteName;
        Map<String, List<Competitor_Store__c>> competitorsByCity;
        Map<String, List<Market_Risk__c>> risksByCity;
    }

    public class Request {
        @InvocableVariable(label='City' description='City to get competitor intel for (e.g. Mumbai)')
        public String city;

        @InvocableVariable(label='Expansion Site Name' description='Specific site name to find nearby competitors (e.g. Malad West - 400064)')
        public String expansionSiteName;
    }

    public class Result {
        @InvocableVariable(label='City Analyzed')
        public String city;

        @InvocableVariable(label='Competitor Count')
        public Integer competitorCount;

        @InvocableVariable(label='Brands Present')
        public String brandsPresent;

        @InvocableVariable(label='Competitor Summary')
        public String competitorSummary;

        @InvocableVariable(label='Competitive Intensity')
        public String competitiveIntensity;

        @InvocableVariable(label='Market Risk Notes')
        public String marketRiskNotes;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Get Competitor Intelligence'
        description='Returns competitor stores in a city or near an expansion site with brand, format, size, distance, and rating details.'
        category='Store Expansion'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<RequestContext> requestContexts = buildRequestContexts(requests);
        IntelContext intelContext = loadIntelContext(requestContexts);

        for (RequestContext requestContext : requestContexts) {
            results.add(buildResult(requestContext, intelContext));
        }

        return results;
    }

    private static List<RequestContext> buildRequestContexts(List<Request> requests) {
        List<RequestContext> contexts = new List<RequestContext>();
        for (Request requestItem : requests) {
            RequestContext context = new RequestContext();
            context.requestedCity = normalizeCity(requestItem.city);
            context.requestedSiteName = normalizeName(requestItem.expansionSiteName);
            context.normalizedCity = context.requestedCity;
            contexts.add(context);
        }
        return contexts;
    }

    private static IntelContext loadIntelContext(List<RequestContext> requestContexts) {
        IntelContext context = new IntelContext();
        context.cityBySiteName = loadCityBySiteName(requestContexts);

        Set<String> normalizedCities = resolveRequestedCities(requestContexts, context.cityBySiteName);
        context.competitorsByCity = loadCompetitorsByCity(normalizedCities);
        context.risksByCity = loadRisksByCity(normalizedCities);
        return context;
    }

    private static Map<String, String> loadCityBySiteName(List<RequestContext> requestContexts) {
        Map<String, String> cityBySiteName = new Map<String, String>();
        Set<String> siteNames = collectRequestedSiteNames(requestContexts);
        if (siteNames.isEmpty() || !Schema.sObjectType.Expansion_Site__c.isAccessible()) {
            return cityBySiteName;
        }

        for (Expansion_Site__c site : [
            SELECT Name, City__c
            FROM Expansion_Site__c
            WHERE Name IN :siteNames
            WITH SECURITY_ENFORCED
        ]) {
            cityBySiteName.put(normalizeName(site.Name), site.City__c);
        }
        return cityBySiteName;
    }

    private static Set<String> resolveRequestedCities(
        List<RequestContext> requestContexts,
        Map<String, String> cityBySiteName
    ) {
        Set<String> normalizedCities = new Set<String>();
        for (RequestContext context : requestContexts) {
            context.resolvedCity = resolveCity(context, cityBySiteName);
            if (String.isNotBlank(context.resolvedCity)) {
                normalizedCities.add(normalizeCity(context.resolvedCity));
            }
        }
        return normalizedCities;
    }

    private static Map<String, List<Competitor_Store__c>> loadCompetitorsByCity(Set<String> normalizedCities) {
        Map<String, List<Competitor_Store__c>> competitorsByCity = new Map<String, List<Competitor_Store__c>>();
        if (normalizedCities.isEmpty() || !Schema.sObjectType.Competitor_Store__c.isAccessible()) {
            return competitorsByCity;
        }

        for (Competitor_Store__c competitor : [
            SELECT Name, Brand__c, Category__c, Address__c,
                   City__c, State__c, Pin_Code__c,
                   Store_Format__c, Store_Size_Sqft__c,
                   Rating__c, Distance_km__c, Est_Monthly_Revenue__c,
                   Latitude__c, Longitude__c
            FROM Competitor_Store__c
            WHERE City__c != null
            WITH SECURITY_ENFORCED
            ORDER BY Store_Size_Sqft__c DESC NULLS LAST
        ]) {
            addCompetitor(competitorsByCity, competitor, normalizedCities);
        }
        return competitorsByCity;
    }

    private static Map<String, List<Market_Risk__c>> loadRisksByCity(Set<String> normalizedCities) {
        Map<String, List<Market_Risk__c>> risksByCity = new Map<String, List<Market_Risk__c>>();
        if (normalizedCities.isEmpty() || !Schema.sObjectType.Market_Risk__c.isAccessible()) {
            return risksByCity;
        }

        for (Market_Risk__c risk : [
            SELECT Risk_Type__c, Severity__c, Summary__c, Market_Analysis__r.City__c
            FROM Market_Risk__c
            WHERE Risk_Type__c = 'Competition'
            AND Market_Analysis__r.City__c != null
            WITH SECURITY_ENFORCED
        ]) {
            addRisk(risksByCity, risk, normalizedCities);
        }
        return risksByCity;
    }

    private static Result buildResult(RequestContext requestContext, IntelContext intelContext) {
        Result result = validateRequest(requestContext);
        if (result != null) {
            return result;
        }

        String cityKey = normalizeCity(requestContext.resolvedCity);
        List<Competitor_Store__c> competitors = intelContext.competitorsByCity.get(cityKey);
        if (competitors == null || competitors.isEmpty()) {
            return buildMissingCompetitorResult(requestContext.resolvedCity);
        }

        Result populated = new Result();
        populated.city = requestContext.resolvedCity;
        populated.competitorCount = competitors.size();
        populated.brandsPresent = buildBrandSummary(competitors);
        populated.competitiveIntensity = determineCompetitiveIntensity(competitors.size());
        populated.competitorSummary = buildCompetitorSummary(competitors);
        populated.marketRiskNotes = buildRiskNotes(intelContext.risksByCity.get(cityKey));
        return populated;
    }

    private static Result validateRequest(RequestContext requestContext) {
        Result result = new Result();
        if (String.isBlank(requestContext.requestedCity) && String.isBlank(requestContext.requestedSiteName)) {
            result.errorMessage = 'Provide either a City or an Expansion Site Name.';
            return result;
        }
        if (String.isBlank(requestContext.resolvedCity)) {
            result.errorMessage = 'Could not resolve city from expansion site name: ' + requestContext.requestedSiteName;
            return result;
        }
        return null;
    }

    private static Result buildMissingCompetitorResult(String city) {
        Result result = new Result();
        result.city = city;
        result.competitorCount = 0;
        result.errorMessage = 'No competitor stores found in city: ' + city;
        return result;
    }

    private static Set<String> collectRequestedSiteNames(List<RequestContext> requestContexts) {
        Set<String> siteNames = new Set<String>();
        for (RequestContext context : requestContexts) {
            if (String.isNotBlank(context.requestedSiteName)) {
                siteNames.add(context.requestedSiteName);
            }
        }
        return siteNames;
    }

    private static String resolveCity(RequestContext context, Map<String, String> cityBySiteName) {
        if (String.isNotBlank(context.requestedCity)) {
            return context.requestedCity;
        }
        if (String.isBlank(context.requestedSiteName)) {
            return null;
        }
        return cityBySiteName.get(context.requestedSiteName);
    }

    private static void addCompetitor(
        Map<String, List<Competitor_Store__c>> competitorsByCity,
        Competitor_Store__c competitor,
        Set<String> normalizedCities
    ) {
        String cityKey = normalizeCity(competitor.City__c);
        if (!normalizedCities.contains(cityKey)) {
            return;
        }
        if (!competitorsByCity.containsKey(cityKey)) {
            competitorsByCity.put(cityKey, new List<Competitor_Store__c>());
        }
        competitorsByCity.get(cityKey).add(competitor);
    }

    private static void addRisk(
        Map<String, List<Market_Risk__c>> risksByCity,
        Market_Risk__c risk,
        Set<String> normalizedCities
    ) {
        String cityKey = normalizeCity(risk.Market_Analysis__r.City__c);
        if (!normalizedCities.contains(cityKey)) {
            return;
        }
        if (!risksByCity.containsKey(cityKey)) {
            risksByCity.put(cityKey, new List<Market_Risk__c>());
        }
        List<Market_Risk__c> risks = risksByCity.get(cityKey);
        if (risks.size() < 3) {
            risks.add(risk);
        }
    }

    private static String buildBrandSummary(List<Competitor_Store__c> competitors) {
        Map<String, Integer> brandCount = new Map<String, Integer>();
        for (Competitor_Store__c competitor : competitors) {
            incrementBrandCount(brandCount, competitor.Brand__c);
        }

        List<String> brandSummary = new List<String>();
        for (String brand : brandCount.keySet()) {
            brandSummary.add(brand + ' (' + brandCount.get(brand) + ')');
        }
        return String.join(brandSummary, ', ');
    }

    private static void incrementBrandCount(Map<String, Integer> brandCount, String brand) {
        if (String.isBlank(brand)) {
            return;
        }
        Integer count = brandCount.containsKey(brand) ? brandCount.get(brand) : 0;
        brandCount.put(brand, count + 1);
    }

    private static String determineCompetitiveIntensity(Integer competitorCount) {
        if (competitorCount >= 5) {
            return 'Very High';
        }
        if (competitorCount >= 3) {
            return 'High';
        }
        if (competitorCount >= 2) {
            return 'Medium';
        }
        return 'Low';
    }

    private static String buildCompetitorSummary(List<Competitor_Store__c> competitors) {
        List<String> lines = new List<String>();
        for (Competitor_Store__c competitor : competitors) {
            lines.add(buildCompetitorLine(competitor));
        }
        return String.join(lines, '\n\n');
    }

    private static String buildCompetitorLine(Competitor_Store__c competitor) {
        String line = '• ' + competitor.Name + ' [' + competitor.Brand__c + ']'
            + '\n  Format: ' + competitor.Store_Format__c;

        line += appendFormattedValue(competitor.Store_Size_Sqft__c, ' | Size: ', ' sqft');
        line += appendRating(competitor.Rating__c);
        line += appendFormattedValue(competitor.Distance_km__c, ' | Distance to site: ', ' km');
        line += appendRevenue(competitor.Est_Monthly_Revenue__c);
        line += '\n  Address: ' + competitor.Address__c;
        return line;
    }

    private static String appendFormattedValue(Decimal value, String prefix, String suffix) {
        if (value == null) {
            return '';
        }
        return prefix + value.format() + suffix;
    }

    private static String appendRating(Decimal rating) {
        if (rating == null) {
            return '';
        }
        return ' | Rating: ' + rating + '/5';
    }

    private static String appendRevenue(Decimal revenue) {
        if (revenue == null) {
            return '';
        }
        return ' | Est. Monthly Revenue: ₹' + formatCrore(revenue);
    }

    private static String buildRiskNotes(List<Market_Risk__c> risks) {
        if (risks == null || risks.isEmpty()) {
            return null;
        }

        List<String> riskLines = new List<String>();
        for (Market_Risk__c risk : risks) {
            riskLines.add('[' + risk.Severity__c + '] ' + risk.Summary__c);
        }
        return String.join(riskLines, ' | ');
    }

    private static String normalizeCity(String city) {
        return String.isBlank(city) ? null : city.trim();
    }

    private static String normalizeName(String name) {
        return String.isBlank(name) ? null : name.trim();
    }

    private static String formatCrore(Decimal val) {
        if (val == null) { return 'N/A'; }
        Decimal crore = val / 10000000;
        return crore.setScale(1) + ' Cr';
    }
}