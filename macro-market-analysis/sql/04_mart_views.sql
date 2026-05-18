-- ============================================================
-- 04_mart_views.sql
-- Macro Market Analysis — Microsoft Fabric Warehouse
-- Author: Benjamin Brady
-- Business-ready mart layer consumed by Power BI.
-- Power BI connects exclusively to the mart schema.
-- No joins or transformations occur at the BI layer.
-- ============================================================


-- ============================================================
-- mart_crisis_funding
-- US companies funded during economic crisis periods.
-- Grain: one row per company per crisis event.
-- ============================================================

CREATE OR ALTER VIEW [mart].[mart_crisis_funding] AS
SELECT
    c.name,
    c.gics_sector,
    c.market,
    c.category_list,
    c.funding_total_usd,
    c.funding_rounds,
    c.founded_year,
    c.first_funding_at,
    c.last_funding_at,
    c.country_code,
    c.status,
    YEAR(CAST(c.first_funding_at AS DATE)) AS first_funding_year,
    e.event                                AS crisis_event,
    e.description                          AS crisis_description,
    e.year                                 AS event_year
FROM [int].[int_crunchbase] c
INNER JOIN [stg_external].[economic_events_raw] e
    ON YEAR(CAST(c.first_funding_at AS DATE)) = e.year
WHERE c.country_code = 'USA';
GO


-- ============================================================
-- mart_sector_rotation
-- Annual sector performance during economic events.
-- Grain: one row per sector per event year.
-- ============================================================

CREATE OR ALTER VIEW [mart].[mart_sector_rotation] AS
SELECT
    year,
    event,
    sector,
    return_pct,
    performance_rank
FROM [stg_external].[sector_performance_raw];
GO


-- ============================================================
-- mart_funding_summary
-- Aggregated funding metrics with ROLLUP for multi-level analysis.
-- Supports grand total, sector subtotal, and detail rows.
-- row_type column indicates aggregation level for BI filtering.
-- ============================================================

CREATE OR ALTER VIEW [mart].[mart_funding_summary] AS
WITH

base AS (
    SELECT
        gics_sector,
        YEAR(CAST(first_funding_at AS DATE)) AS funding_year,
        funding_total_usd,
        funding_rounds,
        status,
        crisis_event
    FROM [mart].[mart_crisis_funding]
    WHERE funding_total_usd > 0
),

aggregated AS (
    SELECT
        COALESCE(gics_sector, 'ALL SECTORS')             AS gics_sector,
        COALESCE(CAST(funding_year AS VARCHAR), 'ALL YEARS') AS funding_year,
        COUNT(*)                                         AS company_count,
        SUM(funding_total_usd)                           AS total_funding_usd,
        AVG(funding_total_usd)                           AS avg_funding_usd,
        MAX(funding_total_usd)                           AS max_funding_usd,
        MIN(funding_total_usd)                           AS min_funding_usd,
        AVG(CAST(funding_rounds AS FLOAT))               AS avg_funding_rounds,
        SUM(CASE WHEN status = 'operating' THEN 1 ELSE 0 END) AS still_operating,
        SUM(CASE WHEN status = 'acquired'  THEN 1 ELSE 0 END) AS acquired,
        SUM(CASE WHEN status = 'closed'    THEN 1 ELSE 0 END) AS closed,
        GROUPING(gics_sector)                            AS is_sector_subtotal,
        GROUPING(funding_year)                           AS is_year_subtotal
    FROM base
    GROUP BY ROLLUP(gics_sector, funding_year)
)

SELECT
    gics_sector,
    funding_year,
    company_count,
    total_funding_usd,
    avg_funding_usd,
    max_funding_usd,
    min_funding_usd,
    avg_funding_rounds,
    still_operating,
    acquired,
    closed,
    is_sector_subtotal,
    is_year_subtotal,
    CASE
        WHEN is_sector_subtotal = 1 AND is_year_subtotal = 1 THEN 'Grand Total'
        WHEN is_year_subtotal = 1                            THEN 'Sector Subtotal'
        ELSE 'Detail'
    END AS row_type
FROM aggregated;
GO
