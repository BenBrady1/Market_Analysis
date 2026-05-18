-- ============================================================
-- run.sql
-- Macro Market Analysis — Microsoft Fabric Warehouse
-- Author: Benjamin Brady
--
-- DAILY / ON-DEMAND REFRESH
-- Run this file to refresh all staging data and rebuild views.
-- Does not recreate schemas or tables — run setup files first
-- on a fresh environment.
--
-- Run order for fresh environment:
--   1. 00_create_schemas.sql
--   2. 01_create_tables.sql
--   3. 02_stored_procedures.sql
--   4. 03_int_views.sql
--   5. 04_mart_views.sql
--   6. Run pl_fred pipeline in Data Factory (loads stg_fred._raw tables)
--   7. run.sql (this file)
-- ============================================================


-- ============================================================
-- STEP 1: Refresh external staging tables
-- Loads: economic_events_raw, sector_performance_raw,
--        data_sources_raw, dim_date, crunchbase
-- ============================================================

EXEC [stg_external].[usp_refresh_all_external_staging]
GO


-- ============================================================
-- STEP 2: Rebuild intermediate views
-- ============================================================

EXEC sp_refreshview '[int].[int_fred_combined]'
EXEC sp_refreshview '[int].[int_crunchbase]'
EXEC sp_refreshview '[int].[int_funded_in_events]'
GO


-- ============================================================
-- STEP 3: Rebuild mart views
-- ============================================================

EXEC sp_refreshview '[mart].[mart_crisis_funding]'
EXEC sp_refreshview '[mart].[mart_sector_rotation]'
EXEC sp_refreshview '[mart].[mart_funding_summary]'
GO


-- ============================================================
-- STEP 4: Validate pipeline log
-- ============================================================

SELECT
    table_name,
    status,
    rows_loaded,
    error_message,
    executed_at
FROM [stg_fred].[pipeline_log]
WHERE executed_at >= CAST(GETDATE() AS DATE)
ORDER BY executed_at DESC;
GO
