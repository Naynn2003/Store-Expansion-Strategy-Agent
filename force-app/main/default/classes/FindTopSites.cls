/**
 * FindTopSites
 * Agentforce InvocableMethod — Site Recommendation Action
 *
 * Given optional filters (city, region, min demand score, competition level),
 * returns ranked expansion site recommendations with scores and financials.
 * Used by the Agentforce agent topic: "Site Recommendation"
 */
public with sharing class FindTopSites {

    public class Request {
        @InvocableVariable(label='City' description='Filter by city name (optional)')
        public String city;

        @InvocableVariable(label='Region' description='Filter by region: North, South, East, West, Central (optional)')
        public String region;

        @InvocableVariable(label='Minimum Demand Score' description='Minimum demand score threshold 0–100 (optional)')
        public Decimal minDemandScore;

        @InvocableVariable(label='Competition Level' description='Filter by competition: Low, Medium, High (optional)')
        public String competitionLevel;

        @InvocableVariable(label='Max Results' description='Number of results to return (default 5)')
        public Integer maxResults;
    }

    public class SiteResult {
        @InvocableVariable(label='Site Name')
        public String siteName;

        @InvocableVariable(label='Address')
        public String address;

        @InvocableVariable(label='City')
        public String city;

        @InvocableVariable(label='State')
        public String state;

        @InvocableVariable(label='Area Type')
        public String areaType;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Recommended')
        public Boolean recommended;

        @InvocableVariable(label='Competition Level')
        public String competitionLevel;

        @InvocableVariable(label='Demand Score')
        public Decimal demandScore;

        @InvocableVariable(label='Accessibility Score')
        public Decimal accessibilityScore;

        @InvocableVariable(label='Estimated Monthly Revenue (INR)')
        public Decimal estMonthlyRevenue;

        @InvocableVariable(label='Estimated Annual Revenue (INR)')
        public Decimal estAnnualRevenue;

        @InvocableVariable(label='Setup Cost (INR)')
        public Decimal setupCost;

        @InvocableVariable(label='Payback Period (Months)')
        public Decimal paybackPeriodMonths;

        @InvocableVariable(label='Population Density')
        public Decimal populationDensity;

        @InvocableVariable(label='Average Household Income (INR)')
        public Decimal avgHouseholdIncome;

        @InvocableVariable(label='Foot Traffic Index')
        public Decimal footTrafficIndex;

        @InvocableVariable(label='Distance to Nearest Store (km)')
        public Decimal distanceNearestStore;

        @InvocableVariable(label='Site Score (if evaluated)')
        public Decimal siteScore;

        @InvocableVariable(label='Notes')
        public String notes;
    }

    public class Result {
        @InvocableVariable(label='Sites Found')
        public Integer sitesFound;

        @InvocableVariable(label='Top Sites Summary')
        public String summary;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Find Top Expansion Sites'
        description='Returns ranked expansion site recommendations filtered by city, region, demand score, or competition level.'
        category='Store Expansion'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<Expansion_Site__c> allSites = [
            SELECT Name, Address__c, City__c, State__c, Region__c, Area_Type__c,
                   Status__c, Recommended__c, Competition_Level__c,
                   Demand_Score__c, Accessibility_Score__c,
                   Est_Monthly_Revenue__c, Est_Annual_Revenue__c,
                   Setup_Cost__c, Payback_Period_Months__c,
                   Population_Density__c, Avg_Household_Income__c,
                   Foot_Traffic_Index__c, Distance_Nearest_Store_km__c, Notes__c,
                   (SELECT Total_Score__c FROM Site_Scores__r ORDER BY Scoring_Date__c DESC LIMIT 1)
            FROM Expansion_Site__c
            WHERE Status__c != 'Rejected'
            WITH SECURITY_ENFORCED
            ORDER BY Recommended__c DESC, Accessibility_Score__c DESC NULLS LAST
        ];

        for (Request req : requests) {
            results.add(processRequest(req, allSites));
        }

        return results;
    }

    private static Result processRequest(Request req, List<Expansion_Site__c> allSites) {
        Result res = new Result();
        Integer resultLimit = (req != null && req.maxResults != null && req.maxResults > 0)
            ? req.maxResults
            : 5;
        List<Expansion_Site__c> matches = new List<Expansion_Site__c>();

        for (Expansion_Site__c site : allSites) {
            if (siteMatchesRequest(site, req)) {
                matches.add(site);
            }
            if (matches.size() >= resultLimit) {
                break;
            }
        }

        if (matches.isEmpty()) {
            res.sitesFound = 0;
            res.errorMessage = 'No expansion sites found matching the given filters.';
            return res;
        }

        res.sitesFound = matches.size();
        res.summary = buildSitesSummary(matches);
        return res;
    }

    private static Boolean siteMatchesRequest(Expansion_Site__c site, Request req) {
        if (req == null) {
            return true;
        }
        return matchesCity(site, req)
            && matchesRegion(site, req)
            && matchesDemandScore(site, req)
            && matchesCompetitionLevel(site, req);
    }

    private static Boolean matchesCity(Expansion_Site__c site, Request req) {
        if (String.isBlank(req.city)) {
            return true;
        }
        String requestCity = req.city.trim().toLowerCase();
        String siteCity = site.City__c != null ? site.City__c.toLowerCase() : '';
        return siteCity.contains(requestCity);
    }

    private static Boolean matchesRegion(Expansion_Site__c site, Request req) {
        if (String.isBlank(req.region)) {
            return true;
        }
        return site.Region__c != null && site.Region__c.equalsIgnoreCase(req.region.trim());
    }

    private static Boolean matchesDemandScore(Expansion_Site__c site, Request req) {
        if (req.minDemandScore == null) {
            return true;
        }
        return site.Demand_Score__c != null && site.Demand_Score__c >= req.minDemandScore;
    }

    private static Boolean matchesCompetitionLevel(Expansion_Site__c site, Request req) {
        if (String.isBlank(req.competitionLevel)) {
            return true;
        }
        return site.Competition_Level__c != null
            && site.Competition_Level__c.equalsIgnoreCase(req.competitionLevel.trim());
    }

    private static String buildSitesSummary(List<Expansion_Site__c> sites) {
        List<String> lines = new List<String>();
        Integer rank = 1;
        for (Expansion_Site__c site : sites) {
            lines.add(buildSiteDetailLine(site, rank));
            rank++;
        }
        return String.join(lines, '\n\n');
    }

    private static String buildSiteDetailLine(Expansion_Site__c site, Integer rank) {
        String scoreStr = '';
        if (site.Site_Scores__r != null && !site.Site_Scores__r.isEmpty()) {
            scoreStr = ' | Score: ' + site.Site_Scores__r[0].Total_Score__c + '/100';
        }

        return '#' + rank + ' ' + site.Name + ' (' + site.City__c + ', ' + site.State__c + ')'
            + '\n   ' + site.Address__c
            + '\n   Area: ' + site.Area_Type__c
            + ' | Competition: ' + site.Competition_Level__c
            + (site.Demand_Score__c != null ? ' | Demand Score: ' + site.Demand_Score__c : '')
            + (site.Accessibility_Score__c != null ? ' | Accessibility: ' + site.Accessibility_Score__c : '')
            + scoreStr
            + '\n   Est. Monthly Revenue: ₹' + formatCrore(site.Est_Monthly_Revenue__c)
            + ' | Setup Cost: ₹' + formatCrore(site.Setup_Cost__c)
            + ' | Payback: ' + site.Payback_Period_Months__c + ' months'
            + (site.Recommended__c ? ' ✅ RECOMMENDED' : '')
            + (String.isNotBlank(site.Notes__c) ? '\n   Note: ' + site.Notes__c : '');
    }

    private static String formatCrore(Decimal val) {
        if (val == null) { return 'N/A'; }
        Decimal crore = val / 10000000;
        return crore.setScale(1) + ' Cr';
    }
}