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
    LEFT JOIN [stg_fred].[dsg10_raw]    dsg ON CAST(dsg.[observations.date] AS DATE) = d.month_date
    LEFT JOIN [stg_fred].[sp500_raw]    s   ON CAST(s.[observations.date]   AS DATE) = d.month_date
    LEFT JOIN [stg_fred].[gold]         g   ON g.observation_date                    = d.month_date
    LEFT JOIN [stg_fred].[nasdaq_raw]   n   ON CAST(n.[observations.date]   AS DATE) = d.month_date
    LEFT JOIN [stg_fred].[gfdegdq_raw]  gfd ON CAST(gfd.[observations.date] AS DATE) = d.month_date
    LEFT JOIN [stg_fred].[dtwexbgs_raw] dx  ON CAST(dx.[observations.date]  AS DATE) = d.month_date
    LEFT JOIN [stg_fred].[cpi_raw]      c   ON CAST(c.[observations.date]   AS DATE) = d.month_date
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
    gics_sector
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
