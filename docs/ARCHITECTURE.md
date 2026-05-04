# Store Expansion Strategy Agent — Architecture
> Last updated: May 3, 2026

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          SALESFORCE ORG                                         │
│                                                                                 │
│  ┌──────────────┐     ┌─────────────────────────────────────────────────────┐  │
│  │   WhatsApp   │────▶│              AGENTFORCE AGENT                       │  │
│  │   Channel    │     │        "Store Expansion Strategy Agent"              │  │
│  └──────────────┘     │                                                     │  │
│                        │  Topics:                                            │  │
│  ┌──────────────┐     │  • Market Research                                  │  │
│  │  Lightning   │────▶│  • Site Recommendation                              │  │
│  │   App UI     │     │  • Competitor Analysis                              │  │
│  └──────────────┘     │  • Financial Feasibility                            │  │
│                        │  • Site Scoring                                     │  │
│                        │  • Field Visit Summary                              │  │
│                        └──────────────┬──────────────────────────────────────┘  │
│                                       │ calls @InvocableMethod                  │
│                         ┌─────────────▼─────────────────────────────────────┐  │
│                         │           APEX ACTION LAYER                        │  │
│                         │                                                    │  │
│                         │  ┌─────────────────┐  ┌──────────────────────┐   │  │
│                         │  │ MarketAnalysis  │  │   TopSites Action    │   │  │
│                         │  │    Action       │  │  (ranked by score)   │   │  │
│                         │  └────────┬────────┘  └──────────┬───────────┘   │  │
│                         │           │                        │               │  │
│                         │  ┌────────▼────────┐  ┌──────────▼───────────┐   │  │
│                         │  │  Competitor     │  │   Financial          │   │  │
│                         │  │  Intel Action   │  │   Projection Action  │   │  │
│                         │  └────────┬────────┘  └──────────┬───────────┘   │  │
│                         │           │                        │               │  │
│                         │  ┌────────▼────────────────────────▼───────────┐  │  │
│                         │  │        Score Site / Field Visit Action       │  │  │
│                         │  └───────────────────────────────────────────┘  │  │
│                         └──────────────┬──────────────────────────────────┘  │
│                                        │ SOQL / DML                           │
│                         ┌──────────────▼──────────────────────────────────┐  │
│                         │              DATA MODEL LAYER                    │  │
│                         │                                                  │  │
│    ┌────────────────┐   │  ┌─────────────────┐    ┌──────────────────┐   │  │
│    │  Market_       │   │  │  Expansion_      │◀───│  Demographic_    │   │  │
│    │  Analysis__c   │   │  │  Site__c         │    │  Data__c         │   │  │
│    │                │   │  │  (26 fields)     │    │  (18 fields)     │   │  │
│    │  • City/Region │   │  │  • Location/Geo  │    │  • Population    │   │  │
│    │  • TAM         │   │  │  • Scores        │    │  • Income        │   │  │
│    │  • Growth Rate │   │  │  • Revenue Est   │    │  • Age groups    │   │  │
│    │  • Comp Count  │   │  │  • Status        │    │  • Urban/Rural   │   │  │
│    │  • Source/Conf │   │  │                  │    │  • Source/Conf   │   │  │
│    └───────┬────────┘   │  └────────┬─────────┘    └─────────┬────────┘   │  │
│            │            │           │                        │             │  │
│    ┌───────▼────────┐   │           │                ┌───────▼────────┐    │  │
│    │ Market_Top_    │   │           │                │ Source_        │    │  │
│    │ Site__c        │   │           │                │ Evidence__c    │    │  │
│    └────────────────┘   │           │                └────────────────┘    │  │
│    ┌────────────────┐   │           │                                       │  │
│    │ Market_Risk__c │   │           │                                       │  │
│    └────────────────┘   │           │                                       │  │
│                         │           │ Master-Detail / Lookup                │  │
│                         │    ┌──────┴──────────────────┐                  │  │
│                         │    │                         │                   │  │
│                         │  ┌─▼──────────────┐  ┌──────▼───────────────┐  │  │
│                         │  │  Site_Score__c │  │  Financial_           │  │  │
│                         │  │  • Total Score │  │  Projection__c       │  │  │
│                         │  │    (formula)   │  │  • Monthly P&L       │  │  │
│                         │  └────────────────┘  │  • Payback (formula) │  │  │
│                         │                      └──────────────────────┘  │  │
│                         │                                                  │  │
│                         │  ┌──────────────────────────────────────────┐   │  │
│                         │  │  CGC OBJECT CHAIN (NEW)                  │   │  │
│                         │  │                                          │   │  │
│                         │  │  Account ──▶ RetailStore                 │   │  │
│                         │  │               ↕ StoreGroupAssignment     │   │  │
│                         │  │           RetailLocationGroup            │   │  │
│                         │  │                  │                       │   │  │
│                         │  │           RetailStoreKpi                 │   │  │
│                         │  │           AssessmentIndicatorDef ×6      │   │  │
│                         │  │                                          │   │  │
│                         │  │  Expansion_Site__c ──▶ Visit             │   │  │
│                         │  │                          │               │   │  │
│                         │  │               ┌──────────┴──────────┐    │   │  │
│                         │  │          AssessmentTask ×5    RetailVisitKpi ×5│  │
│                         │  │          (ConductSurveys)     (scored 82-90)   │  │
│                         │  └──────────────────────────────────────────┘   │  │
│                         └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Diagram

```
USER QUERY (via WhatsApp / Lightning UI)
         │
         ▼
┌─────────────────────────────────┐
│      Agentforce Agent           │
│  Classifies intent → Topic      │
└──────────────┬──────────────────┘
               │
    ┌──────────▼───────────┐
    │  Which topic?        │
    └──┬───┬────┬───┬──────┘
       │   │    │   │
  Market  Top  Comp Fin
  Research Sites Intel Proj
       │   │    │   │
       ▼   ▼    ▼   ▼
  ┌─────────────────────┐
  │   Apex Invocable    │
  │     Action          │
  │  - Build SOQL query │
  │  - Query objects    │
  │  - Format response  │
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │   Salesforce DB     │
  │  Custom + CGC Objs  │
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │  Structured Result  │
  │  returned to Agent  │
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │ Agent formats into  │
  │ natural language    │
  │ response for user   │
  └─────────────────────┘
```

### CGC Field Visit Data Flow

```
Field Surveyor arrives at candidate site
         │
         ▼
  Visit record created (CGC)
  • PlaceId → nearest RetailStore
  • Expansion_Site__c → candidate site     ← CUSTOM FK (new)
  • AccountId → client company
         │
         ▼
  5 × AssessmentTask created (CGC)
  • TaskType = ConductInStoreSurveys
  • Footfall / Demographics / Competition / Accessibility / Cannibalization
         │
         ▼ (after observation)
  5 × RetailVisitKpi created (CGC)
  • Actual scores: 82, 75, 68, 90, 85
  • Linked to AssessmentTask + AssessmentIndicatorDefinition
  • Types: Revenue, Revenue, ShareOfShelf, Facing, OutOfStock
         │
         ▼
  Site_Score__c.Total_Score formula auto-computes from
  stored score fields → agent can report final 80/100 rating
```

### Recommendation Score Lineage

```
Demographic_Data__c baseline + Competitor_Store__c proximity + Visit / RetailVisitKpi observations
            │
            ▼
Site_Score__c
   Total_Score__c = Demand_Factor__c + Demographics_Factor__c + Competition_Factor__c + Accessibility_Factor__c
            │
            ▼
Expansion_Site__c.Recommended__c + Financial_Projection__c.Payback_Months__c
```

This keeps the recommendation explainable for judges: every final site recommendation can be traced back to demographic baselines, competitor density, and field validation.

---

## Build Phases & Status

```
Phase 1: Data Model          ████████████████████ 100% ✅
Phase 2: Security & Access   ████████████████████ 100% ✅
Phase 3: UI / Navigation     ████████████████████ 100% ✅
Phase 4: Seed Data (full)    ████████████████████ 100% ✅  ← CGC objects added
Phase 5: Bulk Data           ░░░░░░░░░░░░░░░░░░░░   0% ⏳
Phase 6: Apex Actions        ░░░░░░░░░░░░░░░░░░░░   0% ⏳
Phase 7: Agentforce Config   ░░░░░░░░░░░░░░░░░░░░   0% ⏳
Phase 8: Reports/Dashboard   ░░░░░░░░░░░░░░░░░░░░   0% ⏳
Phase 9: WhatsApp Channel    ░░░░░░░░░░░░░░░░░░░░   0% ⏳

Overall: ████████████░░░░░░░░ ~60%
```

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Platform | Salesforce (Developer Org) |
| AI Agent | Agentforce (Einstein Agent) |
| Backend Logic | Apex (`@InvocableMethod`) |
| Data Storage | 9 Custom Objects + 7 CGC Objects |
| CGC Package | Consumer Goods Cloud (RetailStore, Visit, AssessmentTask, etc.) |
| UI | Lightning App + Standard Record Pages |
| Messaging | WhatsApp via Salesforce Messaging Channel |
| CLI / Deploy | Salesforce CLI (sf) v66.0 |
| Source Control | Git (SFDX project) |

---

## Object Relationship Summary

```
Account (standard)
    │
    ├─[lookup]──► RetailStore (CGC) ◄─[junction]──► RetailLocationGroup (CGC)
    │                   │                                     │
    │             RetailStoreKpi (CGC)           AssessmentIndicatorDefinition (CGC)
    │
    └─[Lookup]──► Expansion_Site__c ◄─[Lookup]── Demographic_Data__c
                        │   ▲
                        │   └──[Custom Lookup]── Visit (CGC)
                        │                              │
                        │                   ┌──────────┴──────────┐
                        │              AssessmentTask ×5    RetailVisitKpi ×5
                        │
                        ├─[Master-Detail]──► Site_Score__c
                        │                         └── Total_Score (formula)
                        │
                        ├─[Master-Detail]──► Financial_Projection__c
                        │                         ├── Monthly_Profit (formula)
                        │                         └── Payback_Months (formula)
                        │
                        └─[Lookup]◄── Competitor_Store__c

Market_Analysis__c  (standalone — city/region level, no parent)
   ├─[Master-Detail]──► Market_Top_Site__c
   ├─[Master-Detail]──► Market_Risk__c
   └─[Lookup]─────────► Source_Evidence__c

Demographic_Data__c
   └─[Lookup]─────────► Source_Evidence__c
```

---

## Next Steps (Immediate Priority Order)

```
1. ▶ Bulk Seed Data
   └── 50+ Expansion Sites (Indian cities: Mumbai, Delhi, Bangalore, Pune, Hyderabad...)
   └── 100+ Competitor Stores (DMart, Reliance Smart, BigBazaar, Star Bazaar...)
   └── 30+ Demographic Data records (pin code level)
   └── 20+ Market Analysis records (city level)
   └── Auto-generate Site Scores + Financial Projections

2. ▶ Apex Invocable Actions (5 classes)
   └── MarketAnalysisAction.cls
   └── TopSitesAction.cls
   └── CompetitorIntelAction.cls
   └── FinancialProjectionAction.cls
   └── ScoreSiteAction.cls  ← can now read RetailVisitKpi averages

3. ▶ Agentforce Agent Setup (in Setup UI)
```
USER QUERY (via WhatsApp / Lightning UI)
         │
         ▼
┌─────────────────────────────────┐
│      Agentforce Agent           │
│  Classifies intent → Topic      │
└──────────────┬──────────────────┘
               │
    ┌──────────▼───────────┐
    │  Which topic?        │
    └──┬───┬────┬───┬──────┘
       │   │    │   │
  Market  Top  Comp Fin
  Research Sites Intel Proj
       │   │    │   │
       ▼   ▼    ▼   ▼
  ┌─────────────────────┐
  │   Apex Invocable    │
  │     Action          │
  │  - Build SOQL query │
  │  - Query objects    │
  │  - Format response  │
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │   Salesforce DB     │
  │  Custom Objects     │
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │  Structured Result  │
  │  returned to Agent  │
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │ Agent formats into  │
  │ natural language    │
  │ response for user   │
  └─────────────────────┘
```

---

## Build Phases & Status

```
Phase 1: Data Model          ████████████████████ 100% ✅
Phase 2: Security & Access   ████████████████████ 100% ✅
Phase 3: UI / Navigation     ████████████████████ 100% ✅
Phase 4: Seed Data (basic)   ████████████████████ 100% ✅
Phase 5: Bulk Data           ░░░░░░░░░░░░░░░░░░░░   0% ⏳
Phase 6: Apex Actions        ░░░░░░░░░░░░░░░░░░░░   0% ⏳
Phase 7: Agentforce Config   ░░░░░░░░░░░░░░░░░░░░   0% ⏳
Phase 8: Reports/Dashboard   ░░░░░░░░░░░░░░░░░░░░   0% ⏳
Phase 9: WhatsApp Channel    ░░░░░░░░░░░░░░░░░░░░   0% ⏳

Overall: ████████████░░░░░░░░ ~60%
```

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Platform | Salesforce (Developer Org) |
| AI Agent | Agentforce (Einstein Agent) |
| Backend Logic | Apex (`@InvocableMethod`) |
| Data Storage | Custom Objects (9) |
| UI | Lightning App + Standard Record Pages |
| Messaging | WhatsApp via Salesforce Messaging Channel |
| CLI / Deploy | Salesforce CLI (sf) v66.0 |
| Source Control | Git (SFDX project) |

---

## Object Relationship Summary

```
Account (standard)
    │
    └─[Lookup]──► Expansion_Site__c ◄─[Lookup]── Demographic_Data__c
                        │
                        ├─[Master-Detail]──► Site_Score__c
                        │                         └── Total_Score (formula)
                        │
                        ├─[Master-Detail]──► Financial_Projection__c
                        │                         ├── Monthly_Profit (formula)
                        │                         └── Payback_Months (formula)
                        │
                        └─[Lookup]◄── Competitor_Store__c
                                      (Nearest_Expansion_Site__c)

Market_Analysis__c  (standalone — city/region level, no parent)
   ├─[Master-Detail]──► Market_Top_Site__c
   ├─[Master-Detail]──► Market_Risk__c
   └─[Lookup]─────────► Source_Evidence__c

Demographic_Data__c
   └─[Lookup]─────────► Source_Evidence__c
```

---

## Next Steps (Immediate Priority Order)

```
1. ▶ Bulk Seed Data
   └── 50+ Expansion Sites (Indian cities: Mumbai, Delhi, Bangalore, Pune, Hyderabad...)
   └── 100+ Competitor Stores (DMart, Reliance Smart, BigBazaar, Star Bazaar...)
   └── 30+ Demographic Data records (pin code level)
   └── 20+ Market Analysis records (city level)
   └── Auto-generate Site Scores + Financial Projections

2. ▶ Apex Invocable Actions (5 classes)
   └── MarketAnalysisAction.cls
   └── TopSitesAction.cls
   └── CompetitorIntelAction.cls
   └── FinancialProjectionAction.cls
   └── ScoreSiteAction.cls

3. ▶ Agentforce Agent Setup (in Setup UI)
   └── Create Agent
   └── Define 5 Topics
   └── Attach Actions to Topics
   └── Write system instructions / persona

4. ▶ Reports & Dashboard
   └── 5 reports
   └── 1 executive dashboard

5. ▶ WhatsApp Channel
   └── Connect messaging channel
   └── Route to agent
   └── End-to-end test
```
