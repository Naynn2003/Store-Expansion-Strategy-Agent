# Store Expansion Strategy Agent — Project Detail Document
**Project:** Salesforce Agentforce Hackathon 2026  
**Org:** YOUR_ORG_ADMIN_EMAIL@example.com  
**Stack:** Salesforce DX · Agentforce · Apex · LWC

---

## 1. Project Overview

The **Store Expansion Strategy Agent** is an AI-powered Salesforce Agentforce agent that helps retail businesses identify, evaluate, and prioritize new store locations. It combines demographic data, competitor intelligence, geolocation scoring, and financial modelling to give executives instant, data-driven site recommendations.

**Target User:** Retail strategy team / expansion managers  
**Business Problem:** Manual site scouting is slow, data-siloed, and inconsistent  
**Solution:** A conversational AI agent that answers questions like:
- _"Which cities have the highest market opportunity?"_
- _"Show me the top 5 expansion sites ranked by demand score"_
- _"What's the ROI if we open at Site X in Pune?"_
- _"Who are our competitors within 5 km of this location?"_

---

## 2. Custom Data Model

### 2.1 Object Relationship Diagram (Text)

```
Account (standard)
  └── RetailStore (CGC) ↔ RetailStoreGroupAssignment ↔ RetailLocationGroup (CGC)
                              RetailStoreKpi (benchmark targets)
                              AssessmentIndicatorDefinition ×6 (scoring templates)

  └── Expansion_Site__c (Lookup: Account)
        ├── Site_Score__c (Master-Detail → Expansion_Site__c)
        ├── Financial_Projection__c (Master-Detail → Expansion_Site__c)
        ├── Competitor_Store__c (Lookup: Nearest_Expansion_Site__c)
        └── Visit (CGC, Lookup: Expansion_Site__c)  ← CUSTOM FK
              ├── AssessmentTask ×5 (ParentId → Visit)
              └── RetailVisitKpi ×5 (VisitId → Visit)

Demographic_Data__c (Lookup from Expansion_Site__c: Demographic_Area__c)
    └── Source_Evidence__c (Lookup: Demographic_Data__c)
Market_Analysis__c (standalone — city/region level)
  ├── Market_Top_Site__c (Master-Detail → Market_Analysis__c)
  ├── Market_Risk__c (Master-Detail → Market_Analysis__c)
  └── Source_Evidence__c (Lookup: Market_Analysis__c)
```

### 2.2 Object Details

#### `Market_Analysis__c` — City/Region Level Market Intelligence
| Field | Type | Purpose |
|-------|------|---------|
| Name | Text | Analysis title |
| City__c | Text | Target city |
| State__c | Text | State |
| Region__c | Text | North/South/East/West/Central |
| TAM__c | Currency | Total Addressable Market (₹) |
| Growth_Rate__c | Percent | YoY market growth % |
| Competitor_Count__c | Number | Known competitors in region |
| Blind_Spots__c | LongText | Unmet market gaps identified |
| Top_Sites__c | LongText | Summary of recommended sites |
| Analysis_Date__c | Date | When analysis was performed |
| Primary_Source__c | Text | Primary dataset/report for the analysis |
| Source_Version__c | Text | Vintage/version of the source used |
| Confidence__c | Picklist | High / Medium / Low confidence in the analysis |

#### `Demographic_Data__c` — Pin Code / Micro-Market Demographics
| Field | Type | Purpose |
|-------|------|---------|
| Name | Text | Area name |
| Pin_Code__c | Text | India postal code |
| City__c / State__c | Text | Location |
| Total_Population__c | Number | Census population |
| Population_Density__c | Number | People per sq km |
| Male_Population__c / Female_Population__c | Number | Gender split |
| Avg_Household_Income__c | Currency | Average HHI (₹) |
| Income_Bracket__c | Picklist | Low / Middle / Upper-Middle / High |
| Literacy_Rate__c | Percent | % literate population |
| Working_Population_Pct__c | Percent | % employed |
| Age_18_35_Pct__c | Percent | Prime retail consumer segment |
| Urban_Rural__c | Picklist | Urban / Semi-Urban / Rural |
| Data_Source__c | Text | Census / NSSO / Proprietary |
| Year__c | Number | Data vintage year |
| Primary_Source__c | Text | Primary official source backing the record |
| Source_Version__c | Text | Source vintage or baseline label |
| Confidence__c | Picklist | High / Medium / Low trust level for the estimate |

#### `Market_Top_Site__c` — Structured Market Recommendations
| Field | Type | Purpose |
|-------|------|---------|
| Name | AutoNumber | MTS-{0000} |
| Market_Analysis__c | Master-Detail | Parent market analysis |
| Site_Name__c | Text | Recommended site label |
| Rank__c | Number | Order within the market recommendation list |
| Demand_Score__c | Number | Summary demand score for the candidate |
| Revenue_Potential__c | Currency | Estimated revenue upside |

#### `Market_Risk__c` — Structured Market Risks / Blind Spots
| Field | Type | Purpose |
|-------|------|---------|
| Name | AutoNumber | MR-{0000} |
| Market_Analysis__c | Master-Detail | Parent market analysis |
| Risk_Type__c | Picklist | Demand / Competition / Accessibility / Supply / Demographics |
| Severity__c | Picklist | High / Medium / Low |
| Summary__c | LongText | Human-readable risk note |

#### `Source_Evidence__c` — Provenance & Verification Links
| Field | Type | Purpose |
|-------|------|---------|
| Name | AutoNumber | SE-{0000} |
| Demographic_Data__c | Lookup(Demographic_Data__c) | Optional link to a demographic record |
| Market_Analysis__c | Lookup(Market_Analysis__c) | Optional link to a market analysis record |
| Source_Label__c | Text | Short source name |
| Source_URL__c | URL | Verification link |
| Source_Type__c | Picklist | API / Official Report / Survey / Municipal Estimate / Internal Model |
| Source_Version__c | Text | Version or year of the source |
| Confidence__c | Picklist | High / Medium / Low |
| Notes__c | LongText | Context for how the source was used |

#### `Expansion_Site__c` — Candidate Store Locations (26 fields)
| Field | Type | Purpose |
|-------|------|---------|
| Name | Text | Site identifier |
| Address__c | Text | Full street address |
| City__c / State__c / Pin_Code__c / Region__c | Text | Location |
| Latitude__c / Longitude__c | Decimal | Coordinates |
| Geolocation__c | Geolocation | SF native geo field |
| Area_Type__c | Picklist | Mall / High Street / Standalone / Transit Hub |
| Status__c | Picklist | Prospecting / Under Review / Approved / Rejected |
| Demand_Score__c | Number | 0–100 demand index |
| Competition_Level__c | Picklist | Low / Medium / High / Very High |
| Est_Monthly_Revenue__c / Est_Annual_Revenue__c | Currency | Revenue estimates |
| Setup_Cost__c | Currency | One-time setup cost |
| Payback_Period_Months__c | Number | Break-even timeline |
| Population_Density__c | Number | Local density |
| Avg_Household_Income__c | Currency | Local income level |
| Nearest_Store__c | Text | Closest existing store name |
| Distance_Nearest_Store_km__c | Number | km to nearest owned store |
| Foot_Traffic_Index__c | Number | 0–100 foot traffic score |
| Accessibility_Score__c | Number | 0–100 transport/parking score |
| Recommended__c | Checkbox | Agent-flagged recommendation |
| Notes__c | LongText | Analyst notes |
| Account__c | Lookup(Account) | Parent retail company |
| Demographic_Area__c | Lookup(Demographic_Data__c) | Linked demographic data |

#### `Competitor_Store__c` — Competitor Retail Locations (15 fields)
| Field | Type | Purpose |
|-------|------|---------|
| Name | Text | Store name |
| Brand__c | Text | DMart / Reliance / BigBazaar / etc. |
| Category__c | Picklist | Grocery / Electronics / Fashion / etc. |
| Address__c / City__c / State__c / Pin_Code__c | Text | Location |
| Latitude__c / Longitude__c / Geolocation__c | Geo | Coordinates |
| Est_Monthly_Revenue__c | Currency | Estimated revenue |
| Store_Size_Sqft__c | Number | Floor area in sq ft |
| Store_Format__c | Picklist | Hypermarket / Supermarket / Mini / Express |
| Rating__c | Number | Customer rating (1–5) |
| Nearest_Expansion_Site__c | Lookup(Expansion_Site__c) | Linked site |
| Distance_km__c | Number | Distance to linked site |

#### `Site_Score__c` — AI-Generated Scoring Breakdown (Master-Detail)
| Field | Type | Purpose |
|-------|------|---------|
| Name | AutoNumber | SS-{0000} |
| Expansion_Site__c | Master-Detail | Parent site |
| Scoring_Date__c | Date | When scored |
| Demand_Factor__c | Number | 0–25 demand sub-score |
| Demographics_Factor__c | Number | 0–25 demographic sub-score |
| Competition_Factor__c | Number | 0–25 competition sub-score |
| Accessibility_Factor__c | Number | 0–25 accessibility sub-score |
| Total_Score__c | Formula(Number) | Sum of all 4 factors |
| Scoring_Notes__c | LongText | Agent reasoning |
| Scored_By__c | Text | "Agentforce" or analyst name |

#### `Financial_Projection__c` — ROI & Payback Analysis (Master-Detail)
| Field | Type | Purpose |
|-------|------|---------|
| Name | AutoNumber | FP-{0000} |
| Expansion_Site__c | Master-Detail | Parent site |
| Projection_Date__c | Date | When projected |
| Setup_Cost__c | Currency | Capex |
| Monthly_Rent__c | Currency | Lease cost |
| Monthly_Operating__c | Currency | Opex |
| Monthly_Revenue__c | Currency | Projected revenue |
| Monthly_Profit__c | Formula(Currency) | Revenue − (Rent + Operating) |
| Payback_Months__c | Formula(Number) | Setup_Cost ÷ Monthly_Profit |
| Comparable_Store__c | Lookup(RetailStore) | Reference store for benchmarking |
| Revenue_Confidence__c | Picklist | Low / Medium / High |
| Assumptions__c | LongText | Model assumptions |

### 2.3 CGC Object Details (Consumer Goods Cloud)

These are **standard Salesforce CGC objects** used without modification except where noted.

#### `RetailStore` (CGC) — Benchmark Stores
| Field | Type | Purpose |
|-------|------|---------|
| Name | Text | Store name |
| AccountId | Lookup(Account) | Parent retail chain |
| Monthly_Revenue__c | Currency | **Custom field** — monthly revenue |
| Store_Format__c | Picklist | **Custom field** — Hypermarket/Supermarket/etc. |
| Store_Size_Sqft__c | Number | **Custom field** — floor area |

#### `RetailLocationGroup` (CGC) — Regional Store Clusters
| Field | Type | Purpose |
|-------|------|---------|
| Name | Text | Group name (e.g. "Mumbai West Region") |
| Description | Text | Group purpose/scope |

#### `RetailStoreGroupAssignment` (CGC) — Store ↔ Group Junction
| Field | Type | Purpose |
|-------|------|---------|
| RetailStoreId | Lookup(RetailStore) | Member store |
| RetailLocationGroupId | Lookup(RetailLocationGroup) | Target group |
| PriorityOrder | Number | Ranking within group |

#### `AssessmentIndicatorDefinition` (CGC) — Scoring Factor Templates
| Field | Type | Purpose |
|-------|------|---------|
| Name | Text | Factor name (e.g. "Footfall Potential") |
| Description | Text | What this factor measures |
| DataType | Picklist | Number / Decimal / Text / Picklist |
| MeasurementFrequency | Picklist | Daily / Weekly / Monthly |

#### `RetailStoreKpi` (CGC) — Revenue Benchmarks per Group
| Field | Type | Purpose |
|-------|------|---------|
| Name | Auto | System-generated |
| KpiType | Picklist | `Revenue` (used); also: Facing, ShareOfShelf, OutOfStock, Price, Inventory |
| TargetDecimalValue | Decimal | Revenue target in rupees |
| RetailStoreGroupId | Lookup(RetailLocationGroup) | Which group this benchmark applies to |
| AssessmentIndDefinitionId | Lookup(AssessmentIndicatorDefinition) | Linked AID |

#### `Visit` (CGC) — Field Surveyor Site Visit
| Field | Type | Purpose |
|-------|------|---------|
| PlaceId | Lookup(RetailStore) | Nearest benchmark store |
| AccountId | Lookup(Account) | Executing client company |
| **Expansion_Site__c** | **Lookup(Expansion_Site__c)** | **Custom field — wires visit to candidate site** |
| VisitType | Picklist | Standard / Special |
| Status | Picklist | New / In Progress / Completed |
| VisitPriority | Picklist | Low / Medium / High |
| InstructionDescription | LongText | Visit briefing |
| PlannedVisitStartTime / PlannedVisitEndTime | DateTime | Schedule |

#### `AssessmentTask` (CGC) — Survey Checklist Tasks
| Field | Type | Purpose |
|-------|------|---------|
| Name | Text | Task name |
| TaskType | Picklist | `ConductInStoreSurveys` (used); 10 other types available |
| Status | Picklist | Not Started / In Progress / Completed |
| ParentId | Polymorphic(Visit) | Parent visit |
| SequenceNumber | Number | Order of execution (1–5) |
| Description | LongText | Detailed instructions |
| IsRequired | Checkbox | Mandatory flag |

#### `RetailVisitKpi` (CGC) — Actual Observed Scores
| Field | Type | Purpose |
|-------|------|---------|
| VisitId | Lookup(Visit) | Parent visit |
| AssessmentTaskId | Lookup(AssessmentTask) | Producing task |
| AssessmentIndDefinitionId | Lookup(AssessmentIndicatorDefinition) | Scoring dimension |
| Type | Picklist | `Revenue`, `ShareOfShelf`, `Facing`, `OutOfStock` (used); also Price, Inventory |
| ActualIntegerValue | Number | Surveyor-observed score (0–100) |
| TargetIntegerValue | Number | Group benchmark target score |
| Male_Population__c / Female_Population__c | Number | Gender split |
| Avg_Household_Income__c | Currency | Average HHI (₹) |
| Income_Bracket__c | Picklist | Low / Middle / Upper-Middle / High |
| Literacy_Rate__c | Percent | % literate population |
| Working_Population_Pct__c | Percent | % employed |
| Age_18_35_Pct__c | Percent | Prime retail consumer segment |
| Urban_Rural__c | Picklist | Urban / Semi-Urban / Rural |
| Data_Source__c | Text | Census / NSSO / Proprietary |
| Year__c | Number | Data vintage year |

#### `Expansion_Site__c` — Candidate Store Locations (26 fields)
| Field | Type | Purpose |
|-------|------|---------|
| Name | Text | Site identifier |
| Address__c | Text | Full street address |
| City__c / State__c / Pin_Code__c / Region__c | Text | Location |
| Latitude__c / Longitude__c | Decimal | Coordinates |
| Geolocation__c | Geolocation | SF native geo field |
| Area_Type__c | Picklist | Mall / High Street / Standalone / Transit Hub |
| Status__c | Picklist | Prospecting / Under Review / Approved / Rejected |
| Demand_Score__c | Number | 0–100 demand index |
| Competition_Level__c | Picklist | Low / Medium / High / Very High |
| Est_Monthly_Revenue__c / Est_Annual_Revenue__c | Currency | Revenue estimates |
| Setup_Cost__c | Currency | One-time setup cost |
| Payback_Period_Months__c | Number | Break-even timeline |
| Population_Density__c | Number | Local density |
| Avg_Household_Income__c | Currency | Local income level |
| Nearest_Store__c | Text | Closest existing store name |
| Distance_Nearest_Store_km__c | Number | km to nearest owned store |
| Foot_Traffic_Index__c | Number | 0–100 foot traffic score |
| Accessibility_Score__c | Number | 0–100 transport/parking score |
| Recommended__c | Checkbox | Agent-flagged recommendation |
| Notes__c | LongText | Analyst notes |
| Account__c | Lookup(Account) | Parent retail company |
| Demographic_Area__c | Lookup(Demographic_Data__c) | Linked demographic data |

#### `Competitor_Store__c` — Competitor Retail Locations (15 fields)
| Field | Type | Purpose |
|-------|------|---------|
| Name | Text | Store name |
| Brand__c | Text | DMart / Reliance / BigBazaar / etc. |
| Category__c | Picklist | Grocery / Electronics / Fashion / etc. |
| Address__c / City__c / State__c / Pin_Code__c | Text | Location |
| Latitude__c / Longitude__c / Geolocation__c | Geo | Coordinates |
| Est_Monthly_Revenue__c | Currency | Estimated revenue |
| Store_Size_Sqft__c | Number | Floor area in sq ft |
| Store_Format__c | Picklist | Hypermarket / Supermarket / Mini / Express |
| Rating__c | Number | Customer rating (1–5) |
| Nearest_Expansion_Site__c | Lookup(Expansion_Site__c) | Linked site |
| Distance_km__c | Number | Distance to linked site |

#### `Site_Score__c` — AI-Generated Scoring Breakdown (Master-Detail)
| Field | Type | Purpose |
|-------|------|---------|
| Name | AutoNumber | SS-{0000} |
| Expansion_Site__c | Master-Detail | Parent site |
| Scoring_Date__c | Date | When scored |
| Demand_Factor__c | Number | 0–25 demand sub-score |
| Demographics_Factor__c | Number | 0–25 demographic sub-score |
| Competition_Factor__c | Number | 0–25 competition sub-score |
| Accessibility_Factor__c | Number | 0–25 accessibility sub-score |
| Total_Score__c | Formula(Number) | Sum of all 4 factors |
| Scoring_Notes__c | LongText | Agent reasoning |
| Scored_By__c | Text | "Agentforce" or analyst name |

#### `Financial_Projection__c` — ROI & Payback Analysis (Master-Detail)
| Field | Type | Purpose |
|-------|------|---------|
| Name | AutoNumber | FP-{0000} |
| Expansion_Site__c | Master-Detail | Parent site |
| Projection_Date__c | Date | When projected |
| Setup_Cost__c | Currency | Capex |
| Monthly_Rent__c | Currency | Lease cost |
| Monthly_Operating__c | Currency | Opex |
| Monthly_Revenue__c | Currency | Projected revenue |
| Monthly_Profit__c | Formula(Currency) | Revenue − (Rent + Operating) |
| Payback_Months__c | Formula(Number) | Setup_Cost ÷ Monthly_Profit |
| Comparable_Store__c | Lookup(RetailStore) | Reference store for benchmarking |
| Revenue_Confidence__c | Picklist | Low / Medium / High |
| Assumptions__c | LongText | Model assumptions |

---

## 3. Security Model

### Permission Set: `Store_Expansion_Agent_Access`
- **Object permissions (custom):** Read / Create / Edit / Delete / View All / Modify All on all deployed store-expansion custom objects, including provenance/evidence objects
- **Object permissions (CGC):** Read / Create / Edit on `Contact`, `Account`, `RetailStore`, `RetailLocationGroup`, `RetailStoreGroupAssignment`, `AssessmentIndicatorDefinition`, `RetailStoreKpi`, `Visit`, `AssessmentTask`, `RetailVisitKpi`
- **Field permissions:** Read + Edit on all custom fields (formula/auto-number fields are read-only); Read + Edit on `Visit.Expansion_Site__c`
- **App visibility:** Store_Expansion_Agent Lightning App
- **Tab settings:** All 6 custom tabs set to Available
- **Assigned to:** Admin user (005ak00000WDwRx)

> **Note on CGC permission dependency chain:** `RetailStoreGroupAssignment` requires `RetailStore`; `RetailStore` requires `Account`; `Account` requires `Contact`. All four are included.

---

## 4. UI Components Deployed

| Component | Type | Details |
|-----------|------|---------|
| Store_Expansion_Agent | Lightning App | Custom app with 6 current tabs in nav bar |
| Market_Analysis__c tab | CustomTab | Telescope motif |
| Demographic_Data__c tab | CustomTab | People motif |
| Expansion_Site__c tab | CustomTab | Magnet motif |
| Competitor_Store__c tab | CustomTab | Target motif |
| Site_Score__c tab | CustomTab | Star motif |
| Financial_Projection__c tab | CustomTab | Money motif |
| 6 Page Layouts | Layout | All custom fields in logical sections |

---

## 5. Planned Apex Invocable Actions

These will be `@InvocableMethod` Apex classes that Agentforce calls as agent actions:

### `MarketAnalysisAction`
```
Input:  city (String), state (String)
Output: Market_Analysis__c summary + Demographic_Data__c stats
Use:    "What's the market potential in Bangalore?"
```

### `TopSitesAction`
```
Input:  region (String), minScore (Integer), limit (Integer)
Output: List of top Expansion_Site__c records ranked by Demand_Score__c
Use:    "Show me the top 5 sites in Maharashtra"
```

### `CompetitorIntelAction`
```
Input:  expansionSiteId (String)
Output: List of nearby Competitor_Store__c records + summary
Use:    "Who are our competitors near Site X?"
```

### `FinancialProjectionAction`
```
Input:  expansionSiteId (String)
Output: Financial_Projection__c record with ROI breakdown
Use:    "What's the payback period for Site X?"
```

### `ScoreSiteAction`
```
Input:  expansionSiteId (String)
Output: Creates/updates Site_Score__c, returns total score + breakdown
Use:    "Score this site for me"
```

---

## 6. Agentforce Agent Design

### Agent Name: Store Expansion Strategy Agent

### Topics & Instructions

| Topic | Trigger Phrases | Action Called |
|-------|----------------|---------------|
| Market Research | "analyze market", "opportunity in [city]", "demand in [region]" | MarketAnalysisAction |
| Site Recommendation | "best sites", "top expansion locations", "where should we open" | TopSitesAction |
| Competitor Analysis | "competitors near", "competition at", "who is competing" | CompetitorIntelAction |
| Financial Feasibility | "ROI for", "payback at", "financial projection for" | FinancialProjectionAction |
| Site Scoring | "score this site", "evaluate site", "rate this location" | ScoreSiteAction |

### Agent Persona
> "You are the Store Expansion Strategy Agent for [Retail Brand]. You help the leadership team identify high-potential store locations by analyzing market data, competitor presence, demographics, and financial projections. Always provide data-backed recommendations with specific numbers."

---

## 7. Reporting Plan

| Report Name | Type | Key Metrics |
|-------------|------|-------------|
| Top Expansion Sites by Score | Tabular | Site name, Total Score, City, Status, Est. Revenue |
| Competitor Density by City | Summary | City, Competitor Count, Avg Rating, Brands |
| Financial Projections Summary | Summary | Site, Setup Cost, Monthly Profit, Payback Months |
| Market TAM by Region | Summary | Region, TAM, Growth Rate, Competitor Count |
| Site Pipeline Funnel | Summary | Count by Status (Prospecting → Approved) |

---

## 8. File Structure

```
force-app/main/default/
├── objects/
│   ├── Market_Analysis__c/
│   ├── Demographic_Data__c/
│   ├── Market_Top_Site__c/
│   ├── Market_Risk__c/
│   ├── Source_Evidence__c/
│   ├── Expansion_Site__c/
│   ├── Competitor_Store__c/
│   ├── Site_Score__c/
│   └── Financial_Projection__c/
├── tabs/
│   ├── Market_Analysis__c.tab-meta.xml
│   ├── Demographic_Data__c.tab-meta.xml
│   ├── Expansion_Site__c.tab-meta.xml
│   ├── Competitor_Store__c.tab-meta.xml
│   ├── Site_Score__c.tab-meta.xml
│   └── Financial_Projection__c.tab-meta.xml
├── layouts/
│   ├── Market_Analysis__c-Market Analysis Layout.layout-meta.xml
│   ├── Demographic_Data__c-Demographic Data Layout.layout-meta.xml
│   ├── Expansion_Site__c-Expansion Site Layout.layout-meta.xml
│   ├── Competitor_Store__c-Competitor Store Layout.layout-meta.xml
│   ├── Site_Score__c-Site Score Layout.layout-meta.xml
│   └── Financial_Projection__c-Financial Projection Layout.layout-meta.xml
├── applications/
│   └── Store_Expansion_Agent.app-meta.xml
├── permissionsets/
│   └── Store_Expansion_Agent_Access.permissionset-meta.xml
└── classes/          ← (to be created)
    ├── MarketAnalysisAction.cls
    ├── TopSitesAction.cls
    ├── CompetitorIntelAction.cls
    ├── FinancialProjectionAction.cls
    └── ScoreSiteAction.cls

scripts/
├── apex/
│   ├── seed_dummy_data.apex       ← 1 record per object (done)
│   └── bulk_seed_data.apex        ← (to be created) 50-300 records
```
