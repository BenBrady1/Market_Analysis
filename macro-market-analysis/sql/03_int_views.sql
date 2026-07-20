-- ============================================================
-- 03_int_views.sql
-- Macro Market Analysis — Microsoft Fabric Warehouse
-- Author: Benjamin Brady
-- Intermediate transformation layer.
-- Responsibilities:
--   - Cast raw VARCHAR types to FLOAT and DATE
--   - Forward-fill sparse FRED series using LAST_VALUE
--   - Align quarterly/annual series to monthly grain
--   - Map 80+ Crunchbase market categories to GICS sectors
--   - Join Crunchbase to economic events by funding year
-- ============================================================


-- ============================================================
-- int_fred_combined
-- Joins all FRED series to the date spine.
-- Two CTEs: raw_joined (join + cast) and forward_filled (fill nulls).
--
-- Note: dsg10_raw may be empty if the FRED API is unstable.
--       The pipeline falls back to the static stg_fred.dsg10 table.
--       When dsg10_raw populates reliably, swap the commented JOIN.
-- ============================================================

CREATE OR ALTER VIEW [int].[int_fred_combined] AS
WITH

raw_joined AS (
    -- Join all FRED series to the monthly date spine and cast types
    SELECT
        d.month_date,
        TRY_CAST(c.[observations.value]   AS FLOAT) AS cpi_raw,
        TRY_CAST(dsg.[observations.value] AS FLOAT) AS interest_rate_raw,
        TRY_CAST(s.[observations.value]   AS FLOAT) AS sp500_raw,
        TRY_CAST(g.gold                   AS FLOAT) AS gold_raw,
        TRY_CAST(n.[observations.value]   AS FLOAT) AS nasdaq_raw,
        TRY_CAST(gfd.[observations.value] AS FLOAT) AS debt_to_gdp_raw,
        TRY_CAST(dx.[observations.value]  AS FLOAT) AS dollar_index_raw,
        TRY_CAST(f.[observations.value]   AS FLOAT) AS federal_interest_raw
    FROM [stg_external].[dim_date] d
    -- DSG10 is finicky on FREDS side it is not always avaialble from the API. When unavaiable go to the site and download it manually. Swap between these 2 accordingly. 
    -- LEFT JOIN [stg_fred].[cpi_raw]      c   ON CAST(c.[observations.date]   AS DATE) = d.month_date --Manual upload: https://fred.stlouisfed.org/series/DGS10
    LEFT JOIN [stg_fred].[dsg10_raw] dsg ON CAST(dsg.[observations.date] AS DATE) = d.month_date -- API Call
    LEFT JOIN [stg_fred].[dsg10_raw]    dsg ON CAST(dsg.[observations.date] AS DATE) = d.month_date
    LEFT JOIN [stg_fred].[sp500_raw]    s   ON CAST(s.[observations.date]   AS DATE) = d.month_date
    LEFT JOIN [stg_fred].[gold]         g   ON g.observation_date                    = d.month_date
    LEFT JOIN [stg_fred].[nasdaq_raw]   n   ON CAST(n.[observations.date]   AS DATE) = d.month_date
    LEFT JOIN [stg_fred].[gfdegdq_raw]  gfd ON CAST(gfd.[observations.date] AS DATE) = d.month_date
    LEFT JOIN [stg_fred].[dtwexbgs_raw] dx  ON CAST(dx.[observations.date]  AS DATE) = d.month_date
    LEFT JOIN [stg_fred].[foyint_raw]   f   ON YEAR(CAST(f.[observations.date] AS DATE))             = YEAR(d.month_date)
                                           AND DATEPART(QUARTER, CAST(f.[observations.date] AS DATE)) = DATEPART(QUARTER, d.month_date)
),

forward_filled AS (
    -- Carry last known value forward to fill gaps in sparse series
    SELECT
        month_date AS observation_date,
        LAST_VALUE(cpi_raw)              IGNORE NULLS OVER (ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cpi,
        LAST_VALUE(interest_rate_raw)    IGNORE NULLS OVER (ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS interest_rate_10yr,
        LAST_VALUE(sp500_raw)            IGNORE NULLS OVER (ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS sp500,
        LAST_VALUE(gold_raw)             IGNORE NULLS OVER (ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS gold,
        LAST_VALUE(nasdaq_raw)           IGNORE NULLS OVER (ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS nasdaq,
        LAST_VALUE(debt_to_gdp_raw)      IGNORE NULLS OVER (ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS debt_to_gdp,
        LAST_VALUE(dollar_index_raw)     IGNORE NULLS OVER (ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS dollar_index,
        LAST_VALUE(federal_interest_raw) IGNORE NULLS OVER (ORDER BY month_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS federal_interest_payments
    FROM raw_joined
)

SELECT * FROM forward_filled;
GO


-- ============================================================
-- int_crunchbase
-- Cleans and classifies Crunchbase startup data.
-- Maps 80+ market categories to 11 GICS sectors via CASE WHEN.
-- ============================================================

CREATE OR ALTER VIEW [int].[int_crunchbase] AS
SELECT
    permalink,
    name,
    homepage_url,
    category_list,
    TRIM(market)      AS market,
    funding_total_usd,
    status,
    country_code,
    state_code,
    region,
    city,
    funding_rounds,
    founded_at,
    founded_month,
    founded_quarter,
    founded_year,
    first_funding_at,
    last_funding_at,
    CASE TRIM(market)
        WHEN 'Software'                         THEN 'Information Technology'
        WHEN 'Enterprise Software'              THEN 'Information Technology'
        WHEN 'SaaS'                             THEN 'Information Technology'
        WHEN 'Mobile'                           THEN 'Information Technology'
        WHEN 'Analytics'                        THEN 'Information Technology'
        WHEN 'Big Data'                         THEN 'Information Technology'
        WHEN 'Big Data Analytics'               THEN 'Information Technology'
        WHEN 'Business Intelligence'            THEN 'Information Technology'
        WHEN 'Cloud Computing'                  THEN 'Information Technology'
        WHEN 'Cloud Data Services'              THEN 'Information Technology'
        WHEN 'Cloud Infrastructure'             THEN 'Information Technology'
        WHEN 'Cloud Management'                 THEN 'Information Technology'
        WHEN 'Cloud Security'                   THEN 'Information Technology'
        WHEN 'Computer Vision'                  THEN 'Information Technology'
        WHEN 'Computers'                        THEN 'Information Technology'
        WHEN 'Consumer Electronics'             THEN 'Information Technology'
        WHEN 'CRM'                              THEN 'Information Technology'
        WHEN 'Cyber Security'                   THEN 'Information Technology'
        WHEN 'Cyber'                            THEN 'Information Technology'
        WHEN 'IT and Cybersecurity'             THEN 'Information Technology'
        WHEN 'Data Centers'                     THEN 'Information Technology'
        WHEN 'Data Center Infrastructure'       THEN 'Information Technology'
        WHEN 'Data Center Automation'           THEN 'Information Technology'
        WHEN 'Data Integration'                 THEN 'Information Technology'
        WHEN 'Data Mining'                      THEN 'Information Technology'
        WHEN 'Data Security'                    THEN 'Information Technology'
        WHEN 'Data Visualization'               THEN 'Information Technology'
        WHEN 'Databases'                        THEN 'Information Technology'
        WHEN 'Developer APIs'                   THEN 'Information Technology'
        WHEN 'Developer Tools'                  THEN 'Information Technology'
        WHEN 'Development Platforms'            THEN 'Information Technology'
        WHEN 'Electronics'                      THEN 'Information Technology'
        WHEN 'Embedded Hardware and Software'   THEN 'Information Technology'
        WHEN 'Enterprise Resource Planning'     THEN 'Information Technology'
        WHEN 'Enterprise Search'                THEN 'Information Technology'
        WHEN 'Enterprise Security'              THEN 'Information Technology'
        WHEN 'Enterprise Application'           THEN 'Information Technology'
        WHEN 'Enterprise Hardware'              THEN 'Information Technology'
        WHEN 'Hardware'                         THEN 'Information Technology'
        WHEN 'Hardware + Software'              THEN 'Information Technology'
        WHEN 'IaaS'                             THEN 'Information Technology'
        WHEN 'Information Technology'           THEN 'Information Technology'
        WHEN 'Internet'                         THEN 'Information Technology'
        WHEN 'Internet Infrastructure'          THEN 'Information Technology'
        WHEN 'Internet of Things'               THEN 'Information Technology'
        WHEN 'Internet Technology'              THEN 'Information Technology'
        WHEN 'Machine Learning'                 THEN 'Information Technology'
        WHEN 'Artificial Intelligence'          THEN 'Information Technology'
        WHEN 'Natural Language Processing'      THEN 'Information Technology'
        WHEN 'Network Security'                 THEN 'Information Technology'
        WHEN 'Networking'                       THEN 'Information Technology'
        WHEN 'Open Source'                      THEN 'Information Technology'
        WHEN 'PaaS'                             THEN 'Information Technology'
        WHEN 'Predictive Analytics'             THEN 'Information Technology'
        WHEN 'Productivity Software'            THEN 'Information Technology'
        WHEN 'Robotics'                         THEN 'Information Technology'
        WHEN 'Semiconductors'                   THEN 'Information Technology'
        WHEN 'Biotechnology and Semiconductor'  THEN 'Information Technology'
        WHEN 'Semiconductor Manufacturing Equipment' THEN 'Information Technology'
        WHEN 'Sensors'                          THEN 'Information Technology'
        WHEN 'Storage'                          THEN 'Information Technology'
        WHEN 'Flash Storage'                    THEN 'Information Technology'
        WHEN 'Technology'                       THEN 'Information Technology'
        WHEN 'Text Analytics'                   THEN 'Information Technology'
        WHEN 'Virtualization'                   THEN 'Information Technology'
        WHEN 'Web Development'                  THEN 'Information Technology'
        WHEN 'Web Hosting'                      THEN 'Information Technology'
        WHEN 'Web Tools'                        THEN 'Information Technology'
        WHEN 'Social Media'                     THEN 'Communication Services'
        WHEN 'Social Network Media'             THEN 'Communication Services'
        WHEN 'Social Media Marketing'           THEN 'Communication Services'
        WHEN 'Messaging'                        THEN 'Communication Services'
        WHEN 'Video'                            THEN 'Communication Services'
        WHEN 'Video Streaming'                  THEN 'Communication Services'
        WHEN 'Games'                            THEN 'Communication Services'
        WHEN 'Video Games'                      THEN 'Communication Services'
        WHEN 'Broadcasting'                     THEN 'Communication Services'
        WHEN 'Music'                            THEN 'Communication Services'
        WHEN 'Publishing'                       THEN 'Communication Services'
        WHEN 'Media'                            THEN 'Communication Services'
        WHEN 'Advertising'                      THEN 'Communication Services'
        WHEN 'E-Commerce'                       THEN 'Consumer Discretionary'
        WHEN 'Retail'                           THEN 'Consumer Discretionary'
        WHEN 'Fashion'                          THEN 'Consumer Discretionary'
        WHEN 'Automotive'                       THEN 'Consumer Discretionary'
        WHEN 'Travel'                           THEN 'Consumer Discretionary'
        WHEN 'Restaurants'                      THEN 'Consumer Discretionary'
        WHEN 'Sports'                           THEN 'Consumer Discretionary'
        WHEN 'Consumer Goods'                   THEN 'Consumer Staples'
        WHEN 'Agriculture'                      THEN 'Consumer Staples'
        WHEN 'Biotechnology'                    THEN 'Health Care'
        WHEN 'Health Care'                      THEN 'Health Care'
        WHEN 'Medical'                          THEN 'Health Care'
        WHEN 'Pharmaceuticals'                  THEN 'Health Care'
        WHEN 'Finance'                          THEN 'Financials'
        WHEN 'Financial Services'               THEN 'Financials'
        WHEN 'Banking'                          THEN 'Financials'
        WHEN 'Insurance'                        THEN 'Financials'
        WHEN 'Manufacturing'                    THEN 'Industrials'
        WHEN 'Logistics'                        THEN 'Industrials'
        WHEN 'Transportation'                   THEN 'Industrials'
        WHEN 'Energy'                           THEN 'Energy'
        WHEN 'Solar'                            THEN 'Energy'
        WHEN 'Oil & Gas'                        THEN 'Energy'
        WHEN 'Real Estate'                      THEN 'Real Estate'
        WHEN 'Utilities'                        THEN 'Utilities'
        ELSE 'Other'
    END AS gics_sector
FROM [stg_external].[crunchbase];
GO


-- ============================================================
-- int_funded_in_events
-- Joins Crunchbase companies to economic events by funding year.
-- ============================================================

CREATE OR ALTER VIEW [int].[int_funded_in_events] AS
SELECT
    c.*,
    e.event,
    e.description
FROM [stg_external].[crunchbase] c
LEFT JOIN [stg_external].[economic_events_raw] e
    ON YEAR(CAST(c.[first_funding_at] AS DATE)) = e.[year];
GO
