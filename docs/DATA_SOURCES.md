# Data Sources & Verification Guide

> **Purpose:** This document lists every data source, API, and reference link used to build the CSVs
> loaded into Salesforce custom objects for the Store Expansion Strategy Agent.
> All sources are free, public-domain, or open-government. Judges and reviewers can open
> each link below to cross-verify the values in the CSV files.

---

## How to Use This Document

1. Open the source link for the field you want to verify.
2. Find the district or pin code from the CSV row.
3. Match the source value to the CSV.
   - Population rows are neighbourhood estimates: district total × `pop_scale_pct`.
   - Literacy, worker share, density and age share come from the district baseline.

### Quick Notes for Object 1 — `Demographic_Data__c`

| Item | Current project position |
|------|--------------------------|
| Dataset type | Estimated demo/seed data for hackathon evaluation |
| Official baseline | Census of India 2011 district-level demographic tables |
| Recent locality adjustment | Municipal ward population reports used to derive `pop_scale_pct` |
| Live API usage | `api.postalpincode.in` for district/state lookup, but currently blocked in this environment |
| Confidence | `Medium` — official baseline, but locality values are modeled rather than live official ward counts |
| Best judge-safe description | Public-source baseline demographics with modeled locality estimates |

---

## Object 1 — `Demographic_Data__c`

**CSV file:** `data/demographics/demographic_data.csv`  
**Script:** `scripts/python/fetch_demographics.py`  
**Total rows:** 48 pin codes across 10 states

**New provenance fields in CSV / object**

| Field | Meaning |
|------|---------|
| `Primary_Source__c` | Main official source backing the row |
| `Source_Version__c` | Baseline/version used to generate the record |
| `Confidence__c` | Judge-safe trust indicator for the row |

---

### Source 1 — Pin Code → District/State Lookup

| Item | Detail |
|------|--------|
| **API** | api.postalpincode.in |
| **Cost** | Free, no registration, no API key |
| **Returns** | District name, State name, Post Office list for any Indian pin code |
| **Status in project** | Blocked by corporate firewall — script falls back to bundled Census data automatically |

#### Verification links (paste in browser to see raw JSON response)

**Mumbai**
| Pin Code | Neighbourhood | Verification URL |
|----------|--------------|-----------------|
| 400064 | Malad West | https://api.postalpincode.in/pincode/400064 |
| 400058 | Kandivali West | https://api.postalpincode.in/pincode/400058 |
| 400069 | Goregaon West | https://api.postalpincode.in/pincode/400069 |
| 400053 | Andheri East | https://api.postalpincode.in/pincode/400053 |
| 400047 | Powai | https://api.postalpincode.in/pincode/400047 |
| 400062 | Dahisar West | https://api.postalpincode.in/pincode/400062 |
| 400097 | Borivali West | https://api.postalpincode.in/pincode/400097 |
| 400091 | Ghatkopar East | https://api.postalpincode.in/pincode/400091 |
| 400028 | Bandra West | https://api.postalpincode.in/pincode/400028 |
| 400050 | Bandra East | https://api.postalpincode.in/pincode/400050 |
| 400037 | Chembur | https://api.postalpincode.in/pincode/400037 |
| 400022 | Sion | https://api.postalpincode.in/pincode/400022 |

**Pune**
| Pin Code | Neighbourhood | Verification URL |
|----------|--------------|-----------------|
| 411001 | Pune Cantonment | https://api.postalpincode.in/pincode/411001 |
| 411045 | Baner | https://api.postalpincode.in/pincode/411045 |
| 411007 | Kothrud | https://api.postalpincode.in/pincode/411007 |
| 411038 | Hadapsar | https://api.postalpincode.in/pincode/411038 |

**Bangalore**
| Pin Code | Neighbourhood | Verification URL |
|----------|--------------|-----------------|
| 560001 | Bangalore City | https://api.postalpincode.in/pincode/560001 |
| 560038 | Indiranagar | https://api.postalpincode.in/pincode/560038 |

**Hyderabad**
| Pin Code | Neighbourhood | Verification URL |
|----------|--------------|-----------------|
| 500001 | Hyderabad City | https://api.postalpincode.in/pincode/500001 |
| 500081 | Kondapur | https://api.postalpincode.in/pincode/500081 |

**Delhi**
| Pin Code | Neighbourhood | Verification URL |
|----------|--------------|-----------------|
| 110001 | Connaught Place | https://api.postalpincode.in/pincode/110001 |
| 110024 | Lajpat Nagar | https://api.postalpincode.in/pincode/110024 |

**Chennai**
| Pin Code | Neighbourhood | Verification URL |
|----------|--------------|-----------------|
| 600001 | Chennai City | https://api.postalpincode.in/pincode/600001 |
| 600093 | Velachery | https://api.postalpincode.in/pincode/600093 |

**Gujarat**
| Pin Code | Neighbourhood | Verification URL |
|----------|--------------|-----------------|
| 380001 | Ahmedabad Old City | https://api.postalpincode.in/pincode/380001 |
| 380015 | Satellite | https://api.postalpincode.in/pincode/380015 |
| 382010 | Gandhinagar Sector | https://api.postalpincode.in/pincode/382010 |
| 395001 | Surat City Centre | https://api.postalpincode.in/pincode/395001 |
| 395007 | Adajan | https://api.postalpincode.in/pincode/395007 |
| 390001 | Sayajigunj (Vadodara) | https://api.postalpincode.in/pincode/390001 |

**Madhya Pradesh**
| Pin Code | Neighbourhood | Verification URL |
|----------|--------------|-----------------|
| 462001 | MP Nagar Bhopal | https://api.postalpincode.in/pincode/462001 |
| 462016 | Arera Colony | https://api.postalpincode.in/pincode/462016 |
| 452001 | Indore Old Palasia | https://api.postalpincode.in/pincode/452001 |
| 452010 | Vijay Nagar | https://api.postalpincode.in/pincode/452010 |
| 474001 | Gwalior City | https://api.postalpincode.in/pincode/474001 |
| 482001 | Jabalpur City | https://api.postalpincode.in/pincode/482001 |

**Uttar Pradesh**
| Pin Code | Neighbourhood | Verification URL |
|----------|--------------|-----------------|
| 226001 | Hazratganj (Lucknow) | https://api.postalpincode.in/pincode/226001 |
| 226010 | Gomti Nagar | https://api.postalpincode.in/pincode/226010 |
| 208001 | Kanpur Civil Lines | https://api.postalpincode.in/pincode/208001 |
| 282001 | Agra City | https://api.postalpincode.in/pincode/282001 |
| 221001 | Varanasi Godowlia | https://api.postalpincode.in/pincode/221001 |
| 201301 | Noida Sector 18 | https://api.postalpincode.in/pincode/201301 |
| 201304 | Noida Sector 62 | https://api.postalpincode.in/pincode/201304 |

**Rajasthan**
| Pin Code | Neighbourhood | Verification URL |
|----------|--------------|-----------------|
| 302001 | Jaipur Pink City | https://api.postalpincode.in/pincode/302001 |
| 302020 | Malviya Nagar | https://api.postalpincode.in/pincode/302020 |
| 342001 | Jodhpur City | https://api.postalpincode.in/pincode/342001 |
| 313001 | Udaipur City | https://api.postalpincode.in/pincode/313001 |
| 324001 | Kota City | https://api.postalpincode.in/pincode/324001 |

> **What to check in the JSON response:**
> - `PostOffice[0].District` → district used for Census lookup
> - `PostOffice[0].State` → maps to `State__c` in the CSV
> - `Status` must be `"Success"`

---

### Source 2 — Census of India 2011 (Primary Census Abstract)

All population, density, literacy, worker %, and age % values come from here.

| Item | Detail |
|------|--------|
| **Publisher** | Office of the Registrar General & Census Commissioner, India |
| **License** | Public Domain (Government of India Open Data) |
| **Year** | Census 2011 (decennial — next full census pending as of 2026) |

#### Main portal
https://censusindia.gov.in

#### Primary Census Abstract (district-level tables — direct data used)
https://censusindia.gov.in/census.website/data/census-tables

#### District Census Handbooks (state-wise PDFs with ward/taluka detail)
https://censusindia.gov.in/census.website/data/DCHB

#### Age-group data used for `Age_18_35_Pct__c` (Table C-13)
https://censusindia.gov.in/census.website/data/census-tables

#### Field-by-field mapping to Census tables

| CSV Field | Census Table | Metric |
|-----------|-------------|--------|
| `Total_Population__c` | Primary Census Abstract — Table A-1 | Total population, district level |
| `Male_Population__c` | Primary Census Abstract — Table A-1 | Male population, district level |
| `Female_Population__c` | Primary Census Abstract — Table A-1 | Female population, district level |
| `Population_Density__c` | Primary Census Abstract — Table A-1 | Persons per sq km |
| `Literacy_Rate__c` | Primary Census Abstract — Table A-4 | Literacy rate %, age 7+ |
| `Working_Population_Pct__c` | Primary Census Abstract — Table B-1 | Main + marginal workers % |
| `Age_18_35_Pct__c` | Census Table C-13 | Age group 15–34 as % of total (proxied to 18–35) |

#### District-level data quick reference (data.gov.in mirror — searchable)
https://data.gov.in/catalog/primary-census-abstract-data-tables-india-level

> **How to verify a specific district:**
> 1. Open the link above → search for the district (e.g. "Mumbai", "Ahmedabad")
> 2. Download the CSV/Excel for that state
> 3. Find the district row — the population, density and literacy figures will match the script's `DISTRICT_CENSUS` dict exactly

---

### Source 3 — NSSO 76th Round (Household Consumption Expenditure Survey 2017-18)

Used for `Avg_Household_Income__c` estimates, adjusted to 2024 price levels.

| Item | Detail |
|------|--------|
| **Publisher** | Ministry of Statistics & Programme Implementation (MoSPI), Govt of India |
| **License** | Public Domain |
| **Adjustment** | CPI inflation ~6% CAGR from 2017–18 to 2024 applied to MPCE figures, then converted to monthly HHI |

#### Report download (MoSPI)
https://mospi.gov.in/web/mospi/reports-notes

#### data.gov.in dataset page
https://data.gov.in/catalog/household-consumer-expenditure-survey

---

### Source 4 — Municipal Corporation Ward Population Estimates

Used for `pop_scale_pct` — the percentage of district population attributed to each neighbourhood pin code.

These portals are reference evidence, not runtime fetches in the script. They support the locality scaling percentages used to convert district totals into pin-code-level estimates.

| City | Body | Official Portal |
|------|------|----------------|
| Mumbai | MCGM / BMC | https://mcgm.gov.in |
| Pune | PMC | https://pmc.gov.in |
| Bangalore | BBMP | https://bbmp.gov.in |
| Hyderabad | GHMC | https://ghmc.gov.in |
| Delhi | MCD | https://mcd.gov.in |
| Chennai | GCC | https://chennaicorporation.gov.in |
| Ahmedabad | AMC | https://ahmedabadcity.gov.in |
| Gandhinagar | Gandhinagar Municipal Corporation | https://gandhinagar-municipality.org.in |
| Surat | SMC | https://suratmunicipal.gov.in |
| Vadodara | VMC | https://vmc.gov.in |
| Bhopal | BMC | https://bhopalmunicipalcorporation.org |
| Indore | IMC | https://imc.gov.in |
| Gwalior | GMC | https://gwaliorcorporation.com |
| Jabalpur | JMC | https://jbpmunicipalcorporation.org |
| Lucknow | LMC | https://lmc.up.nic.in |
| Kanpur | KNN | https://kanpurnagarnigam.in |
| Agra | ANN | https://agranagarnigam.com |
| Varanasi | VNN | https://varanasi.nic.in |
| Noida | Noida Authority | https://noidaauthority.in |
| Jaipur | JMC | https://jmc.gov.in |
| Jodhpur | JMC | https://jodhpurmc.org |
| Udaipur | UIT | https://urbanudaipur.rajasthan.gov.in |
| Kota | KMC | https://kotamunicipal.rajasthan.gov.in |

---

### Source 5 — data.gov.in API (Optional enrichment — not active by default)

Can be enabled by setting `DATA_GOV_IN_KEY` environment variable.

| Item | Detail |
|------|--------|
| **Portal** | https://data.gov.in |
| **Registration** | Free at https://data.gov.in/user/register |
| **Dataset used** | Primary Census Abstract — Total Population (District level) |
| **Resource ID** | `9ef84268-d588-465a-a308-a864a43d0070` |
| **API endpoint** | `https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070` |

#### Sample API call (replace `YOUR_KEY`)
```
https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070?api-key=YOUR_KEY&format=json&filters[District_Name]=Mumbai
```

---

## Future Objects (Data Sources to Be Added)

As the pipeline expands to additional Salesforce custom objects, their source documentation will be appended here in the same format.

| # | Object | Dataset | Planned Source |
|---|--------|---------|---------------|
| 2 | `Market_Analysis__c` | City-level TAM, retail market size | IBEF Industry Reports, Planning Commission data |
| 2A | `Market_Top_Site__c` | Ranked site candidates per market | Derived from `Expansion_Site__c`, `Site_Score__c`, and `Financial_Projection__c` |
| 2B | `Market_Risk__c` | Structured blind spots and constraints | Analyst summaries grounded in competitor, demographics, and infrastructure evidence |
| 2C | `Source_Evidence__c` | Provenance links and source notes | Official URLs, API endpoints, reports, and internal methodology notes |
| 3 | `Zoning_Data__c` | Land use, FSI, commercial zones | State RERA portals, District Town Planning offices |
| 4 | `Infrastructure_Score__c` | Metro, highway, airport proximity | OpenStreetMap Overpass API (free), NHAI data |
| 5 | `Competitor_Store__c` | Competitor universe by city | Google Places API, Open Data Commons |
| 6 | `Real_Estate_Data__c` | Commercial rent per sq ft | MagicBricks / 99acres data APIs, PropEquity |
| 7 | `Site_Attributes__c` | Footfall, parking, visibility scores | Field survey + Foursquare Places API |

> This file is maintained by the Store Expansion Agent pipeline.
> Last updated: April 2026
