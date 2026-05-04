/**
 * GetFinancialProjection
 * Agentforce InvocableMethod — Financial Feasibility Action
 *
 * Given an expansion site name or city, returns financial projections:
 * setup cost, monthly revenue/profit, payback period, ROI, and
 * investment recommendation. Used by agent topic: "Financial Feasibility"
 */
public with sharing class GetFinancialProjection {

    private class RequestContext {
        String requestedSiteName;
        String requestedCity;
    }

    public class Request {
        @InvocableVariable(label='Expansion Site Name' description='Site name to get projection for (e.g. Malad West - 400064)')
        public String expansionSiteName;

        @InvocableVariable(label='City' description='City to get all projections for (optional if site name given)')
        public String city;
    }

    public class Result {
        @InvocableVariable(label='Site Name')
        public String siteName;

        @InvocableVariable(label='City')
        public String city;

        @InvocableVariable(label='Setup Cost (INR)')
        public Decimal setupCost;

        @InvocableVariable(label='Monthly Rent (INR)')
        public Decimal monthlyRent;

        @InvocableVariable(label='Monthly Operating Cost (INR)')
        public Decimal monthlyOperating;

        @InvocableVariable(label='Monthly Revenue (INR)')
        public Decimal monthlyRevenue;

        @InvocableVariable(label='Monthly Profit (INR)')
        public Decimal monthlyProfit;

        @InvocableVariable(label='Payback Period (Months)')
        public Decimal paybackMonths;

        @InvocableVariable(label='Revenue Confidence')
        public String revenueConfidence;

        @InvocableVariable(label='Assumptions')
        public String assumptions;

        @InvocableVariable(label='Projection Date')
        public String projectionDate;

        @InvocableVariable(label='Annual ROI (%)')
        public Decimal annualRoi;

        @InvocableVariable(label='Investment Recommendation')
        public String investmentRecommendation;

        @InvocableVariable(label='Full Financial Summary')
        public String financialSummary;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Get Financial Projection'
        description='Returns financial projections for an expansion site: setup cost, monthly revenue, profit, payback period, and ROI.'
        category='Store Expansion'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<RequestContext> requestContexts = buildRequestContexts(requests);
        List<Expansion_Site__c> sites = loadSites();

        for (RequestContext requestContext : requestContexts) {
            results.add(buildResult(requestContext, sites));
        }

        return results;
    }

    private static List<RequestContext> buildRequestContexts(List<Request> requests) {
        List<RequestContext> contexts = new List<RequestContext>();
        for (Request requestItem : requests) {
            RequestContext context = new RequestContext();
            context.requestedSiteName = normalizeValue(requestItem.expansionSiteName);
            context.requestedCity = normalizeValue(requestItem.city);
            contexts.add(context);
        }
        return contexts;
    }

    private static List<Expansion_Site__c> loadSites() {
        if (!Schema.sObjectType.Expansion_Site__c.isAccessible()) {
            return new List<Expansion_Site__c>();
        }

        return [
            SELECT Name, City__c, State__c,
                   Est_Monthly_Revenue__c, Setup_Cost__c, Payback_Period_Months__c,
                   (SELECT Projection_Date__c, Setup_Cost__c, Monthly_Rent__c,
                           Monthly_Operating__c, Monthly_Revenue__c,
                           Monthly_Profit__c, Payback_Months__c,
                           Revenue_Confidence__c, Assumptions__c
                    FROM Financial_Projections__r
                    ORDER BY Projection_Date__c DESC
                    LIMIT 1)
            FROM Expansion_Site__c
            WITH SECURITY_ENFORCED
            ORDER BY Est_Monthly_Revenue__c DESC NULLS LAST
        ];
    }

    private static Result buildResult(RequestContext requestContext, List<Expansion_Site__c> sites) {
        Result validationError = validateRequest(requestContext);
        if (validationError != null) {
            return validationError;
        }

        Expansion_Site__c matchingSite = findBestMatchingSite(requestContext, sites);
        if (matchingSite == null) {
            return buildMissingSiteResult(requestContext);
        }

        Result result = initializeResult(matchingSite);
        if (hasFinancialProjection(matchingSite)) {
            populateDetailedProjection(result, matchingSite);
        } else {
            populateEstimateOnlyProjection(result, matchingSite);
        }
        return result;
    }

    private static Result validateRequest(RequestContext requestContext) {
        if (String.isNotBlank(requestContext.requestedSiteName) || String.isNotBlank(requestContext.requestedCity)) {
            return null;
        }

        Result result = new Result();
        result.errorMessage = 'Provide either an Expansion Site Name or a City.';
        return result;
    }

    private static Expansion_Site__c findBestMatchingSite(
        RequestContext requestContext,
        List<Expansion_Site__c> sites
    ) {
        for (Expansion_Site__c site : sites) {
            if (matchesRequest(site, requestContext)) {
                return site;
            }
        }
        return null;
    }

    private static Boolean matchesRequest(Expansion_Site__c site, RequestContext requestContext) {
        if (String.isNotBlank(requestContext.requestedSiteName)) {
            return containsIgnoreCase(site.Name, requestContext.requestedSiteName);
        }
        return containsIgnoreCase(site.City__c, requestContext.requestedCity);
    }

    private static Boolean containsIgnoreCase(String sourceValue, String searchValue) {
        if (String.isBlank(sourceValue) || String.isBlank(searchValue)) {
            return false;
        }
        return sourceValue.toLowerCase().contains(searchValue.toLowerCase());
    }

    private static Result buildMissingSiteResult(RequestContext requestContext) {
        Result result = new Result();
        String searchTerm = String.isNotBlank(requestContext.requestedSiteName)
            ? requestContext.requestedSiteName
            : requestContext.requestedCity;
        result.errorMessage = 'No expansion site found matching: ' + searchTerm;
        return result;
    }

    private static Result initializeResult(Expansion_Site__c site) {
        Result result = new Result();
        result.siteName = site.Name;
        result.city = site.City__c;
        return result;
    }

    private static Boolean hasFinancialProjection(Expansion_Site__c site) {
        return site.Financial_Projections__r != null && !site.Financial_Projections__r.isEmpty();
    }

    private static void populateDetailedProjection(Result result, Expansion_Site__c site) {
        Financial_Projection__c projection = site.Financial_Projections__r[0];
        result.setupCost = projection.Setup_Cost__c;
        result.monthlyRent = projection.Monthly_Rent__c;
        result.monthlyOperating = projection.Monthly_Operating__c;
        result.monthlyRevenue = projection.Monthly_Revenue__c;
        result.monthlyProfit = projection.Monthly_Profit__c;
        result.paybackMonths = projection.Payback_Months__c;
        result.revenueConfidence = projection.Revenue_Confidence__c;
        result.assumptions = projection.Assumptions__c;
        result.projectionDate = projection.Projection_Date__c != null ? projection.Projection_Date__c.format() : null;
        result.annualRoi = calculateAnnualRoi(projection);
        result.investmentRecommendation = buildRecommendation(
            result.annualRoi,
            projection.Payback_Months__c,
            projection.Revenue_Confidence__c
        );
        result.financialSummary = buildDetailedSummary(result, site, projection);
    }

    private static void populateEstimateOnlyProjection(Result result, Expansion_Site__c site) {
        result.monthlyRevenue = site.Est_Monthly_Revenue__c;
        result.setupCost = site.Setup_Cost__c;
        result.paybackMonths = site.Payback_Period_Months__c;
        result.financialSummary = buildEstimateSummary(site);
    }

    private static Decimal calculateAnnualRoi(Financial_Projection__c projection) {
        if (projection.Monthly_Profit__c == null || projection.Setup_Cost__c == null || projection.Setup_Cost__c <= 0) {
            return null;
        }
        Decimal annualProfit = projection.Monthly_Profit__c * 12;
        return (annualProfit / projection.Setup_Cost__c * 100).setScale(1);
    }

    private static String buildDetailedSummary(
        Result result,
        Expansion_Site__c site,
        Financial_Projection__c projection
    ) {
        String summary =
            '📍 ' + site.Name + ' (' + site.City__c + ')' +
            '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' +
            '\n💰 Setup Cost:        ₹' + formatCrore(projection.Setup_Cost__c) +
            '\n🏠 Monthly Rent:      ₹' + formatLakh(projection.Monthly_Rent__c) +
            '\n⚙️  Monthly OpEx:      ₹' + formatLakh(projection.Monthly_Operating__c) +
            '\n📈 Monthly Revenue:   ₹' + formatCrore(projection.Monthly_Revenue__c) +
            '\n✅ Monthly Profit:    ₹' + formatLakh(projection.Monthly_Profit__c) +
            '\n⏱️  Payback Period:    ' + projection.Payback_Months__c + ' months' +
            buildAnnualRoiLine(result.annualRoi) +
            '\n🎯 Confidence:        ' + projection.Revenue_Confidence__c +
            '\n💡 Recommendation:   ' + result.investmentRecommendation;

        if (String.isNotBlank(projection.Assumptions__c)) {
            summary += '\n📋 Assumptions: ' + projection.Assumptions__c;
        }
        return summary;
    }

    private static String buildEstimateSummary(Expansion_Site__c site) {
        return
            '📍 ' + site.Name + ' (' + site.City__c + ') — Estimates only (no detailed projection loaded)' +
            '\n💰 Setup Cost:     ₹' + formatCrore(site.Setup_Cost__c) +
            '\n📈 Est. Revenue:   ₹' + formatCrore(site.Est_Monthly_Revenue__c) + '/month' +
            '\n⏱️  Payback:        ' + site.Payback_Period_Months__c + ' months';
    }

    private static String buildAnnualRoiLine(Decimal annualRoi) {
        return annualRoi != null ? '\n📊 Annual ROI:        ' + annualRoi + '%' : '';
    }

    private static String normalizeValue(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String buildRecommendation(Decimal roi, Decimal paybackMonths, String confidence) {
        if (roi == null || paybackMonths == null) { return 'Insufficient data for recommendation.'; }

        if (roi >= 30 && paybackMonths <= 24 && confidence == 'High') {
            return 'STRONG BUY — High ROI with fast payback and high confidence.';
        } else if (roi >= 20 && paybackMonths <= 36) {
            return 'BUY — Solid returns within acceptable payback window.';
        } else if (roi >= 12 && paybackMonths <= 48) {
            return 'CONSIDER — Moderate returns; validate with field visit before committing.';
        } else {
            return 'HOLD — Lower returns or long payback period. Explore cost optimization.';
        }
    }

    private static String formatCrore(Decimal val) {
        if (val == null) { return 'N/A'; }
        return (val / 10000000).setScale(1) + ' Cr';
    }

    private static String formatLakh(Decimal val) {
        if (val == null) { return 'N/A'; }
        return (val / 100000).setScale(1) + ' L';
    }
}