# Complete Object Relationship Map
> Store Expansion Strategy Agent | 16 objects (9 custom + 7 CGC) + 21 relationships
> Last updated: April 19, 2026

---

## Object Layers

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                         LAYER 1: CRM / CGC FOUNDATION                      ║
║              Standard Salesforce + Consumer Goods Cloud objects             ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   ┌─────────────────────────────────┐                                        ║
║   │  Account (Standard)             │  ← Retail chain companies             ║
║   │  • Retail Strategy India Pvt Ltd│    (client) + competitor chains       ║
║   │  • Avenue Supermarts (DMart)    │                                        ║
║   │  • Reliance Retail Ventures     │    Fields used:                       ║
║   │  • Future Retail (Big Bazaar)   │    Name, Industry, AnnualRevenue,     ║
║   │  • Spencer's Retail Ltd         │    BillingCity, BillingState          ║
║   └────────────┬────────────────────┘                                        ║
║                │ AccountId (standard lookup)                                 ║
║                ▼                                                             ║
║   ┌────────────────────────────────────┐                                     ║
║   │  RetailStore (CGC) ✅              │  ← Benchmark stores for revenue    ║
║   │  • DMart Andheri West              │    modeling & proximity analysis   ║
║   │  • DMart Borivali East             │                                     ║
║   │  • Reliance Smart Malad West       │    Custom fields added:            ║
║   │  • DMart Goregaon West             │    Monthly_Revenue__c              ║
║   │  • Spencer's Powai                 │    Store_Format__c                 ║
║   └──────────────┬─────────────────────┘    Store_Size_Sqft__c              ║
║                  │ RetailStoreId                                             ║
║                  ▼                                                           ║
║   ┌────────────────────────────────────┐                                     ║
║   │  RetailStoreGroupAssignment (CGC)  │  ← Junction: Store ↔ Group        ║
║   │  • 2 records seeded               │    PriorityOrder, RetailStoreId,   ║
║   └──────────────┬─────────────────────┘    RetailLocationGroupId           ║
║                  │ RetailLocationGroupId                                     ║
║                  ▼                                                           ║
║   ┌────────────────────────────────────┐                                     ║
║   │  RetailLocationGroup (CGC)         │  ← Regional store clusters        ║
║   │  • "Mumbai West Region"            │    Name, Description               ║
║   └────────────────────────────────────┘                                     ║
║                                                                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                  LAYER 1B: CGC BENCHMARKING & ASSESSMENT SETUP              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   ┌──────────────────────────────────────┐   ┌────────────────────────────┐ ║
║   │  AssessmentIndicatorDefinition (CGC) │   │  RetailStoreKpi (CGC)      │ ║
║   │  6 records:                          │   │  2 records (KpiType=Rev)   │ ║
║   │  • Footfall Potential (Number)       │   │  • ₹2.1Cr/month target     │ ║
║   │  • Demographics Score (Number)       │   │  • ₹1.95Cr/month prior mo  │ ║
║   │  • Competition Density (Number)      │   │                            │ ║
║   │  • Accessibility Score (Number)      │   │  RetailStoreGroupId ───────┼▶ RetailLocationGroup
║   │  • Cannibalization Risk (Number)     │   │  AssessmentIndDefinitionId─┼▶ AID
║   │  • Monthly Revenue Performance (Dec) │   └────────────────────────────┘ ║
║   └──────────────────────────────────────┘                                   ║
║                                                                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                        LAYER 2: MARKET INTELLIGENCE                         ║
║                     Independent context objects (no parent)                 ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   ┌──────────────────────────────────┐   ┌──────────────────────────────┐   ║
║   │  Market_Analysis__c              │   │  Demographic_Data__c         │   ║
║   │  One record per city/region      │   │  One record per pin code     │   ║
║   │                                  │   │                              │   ║
║   │  City__c, State__c, Region__c    │   │  Pin_Code__c, City__c        │   ║
║   │  Primary_Source__c               │   │  Primary_Source__c           │   ║
║   │  Source_Version__c               │   │  Source_Version__c           │   ║
║   │  Confidence__c                   │   │  Confidence__c               │   ║
║   │  TAM__c, Growth_Rate__c          │   │  Total_Population__c         │   ║
║   │  Competitor_Count__c             │   │  Avg_Household_Income__c     │   ║
║   │  Blind_Spots__c (legacy summary) │   │  Literacy_Rate__c            │   ║
║   │  Top_Sites__c (legacy summary)   │   │  Income_Bracket__c           │   ║
║   │  Analysis_Date__c                │   │  Age_18_35_Pct__c            │   ║
║   │                                  │   │ Data_Source__c, Year__c      │   ║
║   └──────────────┬───────────────────┘   └──────────────┬───────────────┘   ║
║                  │                                       │                   ║
║                  ▼                                       ▼                   ║
║   ┌──────────────────────────────────┐   ┌──────────────────────────────┐   ║
║   │  Market_Top_Site__c              │   │  Source_Evidence__c          │   ║
║   │  Structured ranked site options  │   │  Source URL + type + version │   ║
║   └──────────────────────────────────┘   └──────────────────────────────┘   ║
║   ┌──────────────────────────────────┐                                   ║
║   │  Market_Risk__c                  │                                   ║
║   │  Structured blind spots / risks  │                                   ║
║   └──────────────────────────────────┘                                   ║
║                                                          │                   ║
╠══════════════════════════════════════════════════════════╪═══════════════════╣
║                       LAYER 3: SITE EVALUATION           │                  ║
║                    The core evaluation pipeline          │                  ║
╠══════════════════════════════════════════════════════════╪═══════════════════╣
║                                                          │                  ║
║   ┌──────────────────────────────────────────────────────┼──────────────┐   ║
║   │  Expansion_Site__c                                   │              │   ║
║   │  ─────────────────────────────────────────────────── │              │   ║
║   │  [Lookup] Account__c  ──────────────────────────────▶ Account       │   ║
║   │  [Lookup] Demographic_Area__c ──────────────────────▶ Demographic   │   ║
║   │  [Lookup] Nearest_Store__c ─────────────────────────▶ RetailStore   │   ║
║   │  ─────────────────────────────────────────────────────────────────  │   ║
║   │  Name, Address__c, City__c, State__c, Pin_Code__c                   │   ║
║   │  Latitude__c, Longitude__c, Geolocation__c                          │   ║
║   │  Area_Type__c, Region__c, Status__c                                 │   ║
║   │  Demand_Score__c, Competition_Level__c, Recommended__c              │   ║
║   │  Est_Monthly_Revenue__c, Est_Annual_Revenue__c (formula)            │   ║
║   │  Setup_Cost__c, Payback_Period_Months__c                            │   ║
║   │  Population_Density__c, Avg_Household_Income__c                    │   ║
║   │  Foot_Traffic_Index__c, Accessibility_Score__c                      │   ║
║   │  Distance_Nearest_Store_km__c, Notes__c                             │   ║
║   └────────────────────────────┬────────────────────────────────────────┘   ║
║                                │ Master-Detail (parent)                      ║
║             ┌──────────────────┼──────────────────┐                         ║
║             ▼                                     ▼                          ║
║   ┌──────────────────────┐         ┌────────────────────────────────────┐   ║
║   │  Site_Score__c       │         │  Financial_Projection__c           │   ║
║   │  ───────────────     │         │  ─────────────────────────────     │   ║
║   │  AutoNumber Name     │         │  AutoNumber Name                   │   ║
║   │  Scoring_Date__c     │         │  [Lookup] Comparable_Store__c ───▶ │   ║
║   │  Demand_Factor__c    │         │          (→ RetailStore)           │   ║
║   │  Demographics_Factor │         │  Projection_Date__c                │   ║
║   │  Competition_Factor  │         │  Setup_Cost__c                     │   ║
║   │  Accessibility_Factor│         │  Monthly_Rent__c                   │   ║
║   │  Total_Score__c      │         │  Monthly_Operating__c              │   ║
║   │    (formula: sum)    │         │  Monthly_Revenue__c                │   ║
║   │  Scored_By__c        │         │  Monthly_Profit__c (formula)       │   ║
║   │  Scoring_Notes__c    │         │  Payback_Months__c (formula)       │   ║
║   └──────────────────────┘         │  Revenue_Confidence__c             │   ║
║                                    │  Assumptions__c                    │   ║
║                                    └────────────────────────────────────┘   ║
║                                                                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                       LAYER 4: COMPETITOR INTELLIGENCE                      ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │  Competitor_Store__c                                                 │   ║
║   │  ─────────────────────────────────────────────────────────────────  │   ║
║   │  [Lookup] Nearest_Expansion_Site__c ──────────────▶ Expansion_Site  │   ║
║   │  ─────────────────────────────────────────────────────────────────  │   ║
║   │  Name, Brand__c, Category__c                                        │   ║
║   │  Address__c, City__c, State__c, Pin_Code__c                         │   ║
║   │  Latitude__c, Longitude__c, Geolocation__c                          │   ║
║   │  Est_Monthly_Revenue__c, Store_Size_Sqft__c                         │   ║
║   │  Store_Format__c, Rating__c, Distance_km__c                         │   ║
║   └──────────────────────────────────────────────────────────────────────┘   ║
║                                                                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                    LAYER 5: CGC FIELD VISIT & SCORING                       ║
║            Visit pipeline — wires field survey directly to site             ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │  Visit (CGC) ✅                                                      │   ║
║   │  ─────────────────────────────────────────────────────────────────  │   ║
║   │  [Lookup] Expansion_Site__c ──────────────────────▶ Expansion_Site  │ ← CUSTOM FK
║   │  [Lookup] PlaceId ────────────────────────────────▶ RetailStore     │   ║
║   │  [Lookup] AccountId ──────────────────────────────▶ Account         │   ║
║   │  ─────────────────────────────────────────────────────────────────  │   ║
║   │  VisitType, Status, VisitPriority, InstructionDescription           │   ║
║   │  PlannedVisitStartTime, PlannedVisitEndTime                         │   ║
║   └───────────────────────────────┬──────────────────────────────────────┘  ║
║                                   │ ParentId (polymorphic)                   ║
║              ┌────────────────────┴────────────────────┐                    ║
║              ▼                                         ▼                    ║
║   ┌─────────────────────────────┐    ┌──────────────────────────────────┐   ║
║   │  AssessmentTask (CGC) ✅    │    │  RetailVisitKpi (CGC) ✅         │   ║
║   │  5 records per visit        │    │  5 records per visit             │   ║
║   │                             │    │                                  │   ║
║   │  TaskType=ConductSurveys    │    │  AssessmentTaskId ─────────────▶ AssessmentTask
║   │  Status=Completed           │    │  AssessmentIndDefinitionId ────▶ AID  ║
║   │  ParentId → Visit           │    │  VisitId ──────────────────────▶ Visit
║   │  SequenceNumber (1–5)       │    │  ActualIntegerValue (0–100)      │   ║
║   │  Description, IsRequired    │    │  TargetIntegerValue              │   ║
║   │                             │    │  Type (Revenue/ShareOfShelf/etc) │   ║
║   └─────────────────────────────┘    └──────────────────────────────────┘   ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

## All Relationships (21 total)

| # | From Object | Field | To Object | Type | Purpose |
|---|-------------|-------|-----------|------|---------|
| 1 | `RetailStore` | `AccountId` | `Account` | CGC Standard Lookup | Links benchmark store to parent retail chain |
| 2 | `RetailStoreGroupAssignment` | `RetailStoreId` | `RetailStore` | CGC Standard Lookup | Which store is in the group |
| 3 | `RetailStoreGroupAssignment` | `RetailLocationGroupId` | `RetailLocationGroup` | CGC Standard Lookup | Which group the store belongs to |
| 4 | `RetailStoreKpi` | `RetailStoreGroupId` | `RetailLocationGroup` | CGC Standard Lookup | Revenue benchmark for group |
| 5 | `RetailStoreKpi` | `AssessmentIndDefinitionId` | `AssessmentIndicatorDefinition` | CGC Standard Lookup | Which KPI definition applies |
| 6 | `Expansion_Site__c` | `Account__c` | `Account` | Custom Lookup | Links expansion site to client company |
| 7 | `Expansion_Site__c` | `Demographic_Area__c` | `Demographic_Data__c` | Custom Lookup | Pulls pin-code demographics for site |
| 8 | `Expansion_Site__c` | `Nearest_Store__c` | `RetailStore` | Custom Lookup | Nearest existing comparable store |
| 9 | `Site_Score__c` | `Expansion_Site__c` | `Expansion_Site__c` | **Master-Detail** | Score child of site (ControlledByParent) |
| 10 | `Financial_Projection__c` | `Expansion_Site__c` | `Expansion_Site__c` | **Master-Detail** | Projection child of site (ControlledByParent) |
| 11 | `Financial_Projection__c` | `Comparable_Store__c` | `RetailStore` | Custom Lookup | Revenue benchmark: "model projections like this store" |
| 12 | `Competitor_Store__c` | `Nearest_Expansion_Site__c` | `Expansion_Site__c` | Custom Lookup | Which site is this competitor nearest to? |
| 13 | `Visit` | `Expansion_Site__c` | `Expansion_Site__c` | **Custom Lookup** (new) | Wires field visit directly to candidate site |
| 14 | `Visit` | `PlaceId` | `RetailStore` | CGC Standard Lookup | Nearest benchmark store as reference |
| 15 | `Visit` | `AccountId` | `Account` | CGC Standard Lookup | Executing account for the visit |
| 16 | `AssessmentTask` | `ParentId` | `Visit` | CGC Polymorphic | Checklist task belongs to visit |
| 17 | `RetailVisitKpi` | `VisitId` | `Visit` | CGC Standard Lookup | KPI observation belongs to visit |
| 18 | `Market_Top_Site__c` | `Market_Analysis__c` | `Market_Analysis__c` | **Master-Detail** | Structured top site recommendations |
| 19 | `Market_Risk__c` | `Market_Analysis__c` | `Market_Analysis__c` | **Master-Detail** | Structured blind spots / risk factors |
| 20 | `Source_Evidence__c` | `Demographic_Data__c` | `Demographic_Data__c` | Custom Lookup | Stores provenance for demographic records |
| 21 | `Source_Evidence__c` | `Market_Analysis__c` | `Market_Analysis__c` | Custom Lookup | Stores provenance for market analysis records |

---

## Simplified View (for presentations)

```
Account ─────────────────────────── RetailStore (CGC)
  │ (owns)                      ↕ RetailStoreGroupAssignment ↕
  │                         RetailLocationGroup (CGC)
  │                              │
  │                         RetailStoreKpi (benchmark targets)
  │                              │
  └──────▶ Expansion_Site__c ◀───┘
               │         │         └──▶ Demographic_Data__c
               │         └──────────────────────────────┐
          ┌────┴─────────┐                              │
          ▼              ▼                              ▼
    Site_Score__c   Financial_Projection__c          Visit (CGC)
                          │                        ┌───┴───────┐
                          └──▶ RetailStore      AssessmentTask RetailVisitKpi
                               (comparable)    (×5 tasks)     (×5 scores)
                                               │               │
                                               └───────────────┘
                                               (linked via AID definition)

Market_Analysis__c  (standalone, queried by city/region)
     ├──▶ Market_Top_Site__c
     ├──▶ Market_Risk__c
     └──▶ Source_Evidence__c
Demographic_Data__c ──▶ Source_Evidence__c
Competitor_Store__c ──▶ Expansion_Site__c
```

---

## Scoring Lineage

```
Demographic_Data__c
  • Total_Population__c
  • Avg_Household_Income__c
  • Literacy_Rate__c
       │
       ├──▶ Expansion_Site__c.Demand_Score__c / Avg_Household_Income__c / Population_Density__c
       │
Competitor_Store__c.Distance_km__c / count by catchment
       ├──▶ Site_Score__c.Competition_Factor__c
       │
Visit + RetailVisitKpi
  • Footfall / accessibility / field observations
       ├──▶ Site_Score__c.Accessibility_Factor__c and scoring notes
       │
Site_Score__c.Total_Score__c
  = Demand_Factor__c + Demographics_Factor__c + Competition_Factor__c + Accessibility_Factor__c
       │
       └──▶ Expansion_Site__c.Recommended__c + Financial_Projection__c
```

---

## Data Seeded (Current State)

| Object | Type | Records | Notes |
|--------|------|---------|-------|
| `Account` | Standard | 5 | Retail Strategy India, DMart, Reliance, Future Group, Spencer's |
| `RetailStore` | CGC | 5 | Benchmark stores in Mumbai — real revenue figures |
| `RetailLocationGroup` | CGC | 1 | "Mumbai West Region" |
| `RetailStoreGroupAssignment` | CGC | 2 | DMart Andheri + Reliance Malad → Mumbai West Region |
| `AssessmentIndicatorDefinition` | CGC | 6 | 5 scoring factors + 1 revenue AID |
| `RetailStoreKpi` | CGC | 2 | Revenue benchmarks: ₹2.1Cr + ₹1.95Cr/month |
| `Visit` | CGC | 1 | Apr 17 field eval — Expansion_Site__c wired ✅ |
| `AssessmentTask` | CGC | 5 | One per scoring factor — all Completed |
| `RetailVisitKpi` | CGC | 5 | Actual scores: 82, 75, 68, 90, 85 → avg 80/100 |
| `Market_Analysis__c` | Custom | 24 | 23 cities — Mumbai, Pune, Bangalore, Hyderabad, Delhi, Chennai, Ahmedabad, Bhopal, Indore, Lucknow, Jaipur, Jodhpur, Kota, Kolkata, Surat, Nagpur, Patna, Chandigarh, Kochi, Coimbatore, Visakhapatnam, Bhubaneswar, Ranchi (bulk CSV upsert) |
| `Demographic_Data__c` | Custom | 49 | 48 cities/pin codes across India (bulk-loaded via CSV upsert) |
| `Expansion_Site__c` | Custom | 11 | 10 expansion sites across 10 cities (bulk CSV upsert) |
| `Market_Top_Site__c` | Custom (M-D) | 29 | 1–2 top sites per city, linked to Market_Analysis__c (bulk CSV import) |
| `Market_Risk__c` | Custom (M-D) | 14 | 1 risk per city, 2 for Mumbai (bulk CSV import) |
| `Competitor_Store__c` | Custom | 13 | 12 competitor stores — DMart, Reliance Smart, Big Bazaar, Spencer's across cities (bulk CSV upsert) |
| `Site_Score__c` | Custom (M-D) | 9 | 8 baseline scores for each Expansion_Site, agent-scored by "Agentforce Store Expansion Agent" (bulk CSV import) |
| `Financial_Projection__c` | Custom (M-D) | 9 | 8 baseline projections for each Expansion_Site (bulk CSV import) |

**Total: 187 records across 15 object types. All static data loaded.**

---

## What's NOT Yet Connected (intentional gaps)

| Gap | Reason | Plan |
|-----|--------|------|
| `Market_Analysis__c` has no FK to `Expansion_Site__c` | Intentional — Market Analysis is city-level (1:many sites possible). Agents query by matching `City__c` | No change needed |
| `Competitor_Store__c` has no link to `Account` | Could be added: Brand__c could lookup Account | Low priority — string Brand__c is sufficient for Agentforce |
| `Demographic_Data__c` has no FK to `Market_Analysis__c` | Pin code ↔ city link via City__c matching | No change needed |
