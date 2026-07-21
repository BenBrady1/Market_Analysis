-- ============================================================
-- 02_stored_procedures.sql
-- Macro Market Analysis — Microsoft Fabric Warehouse
-- Author: Benjamin Brady
-- Creates all stored procedures for external staging refresh.
-- FRED series are loaded via the Data Factory pipeline (pl_fred).
-- ============================================================


-- ============================================================
-- BASE PROCEDURE: Parameterized CSV loader
-- Accepts a table name and OneLake file path.
-- Truncates and reloads the target table.
-- Logs result to stg_fred.pipeline_log.
-- ============================================================

CREATE OR ALTER PROCEDURE [stg_external].[usp_refresh_external_staging]
    @table_name NVARCHAR(128),
    @file_path  NVARCHAR(MAX)
AS
BEGIN
    DECLARE @sql          NVARCHAR(MAX)
    DECLARE @rows         INT
    DECLARE @status       VARCHAR(50)
    DECLARE @error        VARCHAR(MAX)

    SET @status = 'SUCCESS'

    BEGIN TRY
        SET @sql = '
            TRUNCATE TABLE [stg_external].[' + @table_name + ']

            INSERT INTO [stg_external].[' + @table_name + ']
            SELECT *
            FROM OPENROWSET(
                BULK ''' + @file_path + ''',
                FORMAT = ''CSV'',
                HEADER_ROW = TRUE
            ) AS data'

        EXEC sp_executesql @sql

        SET @rows = @@ROWCOUNT

    END TRY
    BEGIN CATCH
        SET @status = 'FAILED'
        SET @error  = ERROR_MESSAGE()
        SET @rows   = 0
    END CATCH

    INSERT INTO [stg_fred].[pipeline_log]
        (procedure_name, table_name, status, error_message, rows_loaded, executed_at)
    VALUES
        ('usp_refresh_external_staging', @table_name, @status, @error, @rows, GETDATE())
END
GO


-- ============================================================
-- MASTER PROCEDURE: Refresh all external staging tables
-- Calls the base procedure for CSV tables.
-- Handles dim_date and crunchbase with custom logic.
-- ============================================================

CREATE OR ALTER PROCEDURE [stg_external].[usp_refresh_all_external_staging]
AS
BEGIN
    DECLARE @rows  INT
    DECLARE @error VARCHAR(MAX)

    -- Generic CSV loads via base procedure
    EXEC [stg_external].[usp_refresh_external_staging]
        'economic_events_raw',
        'https://onelake.dfs.fabric.microsoft.com/8143cf61-40ef-40f2-b6b9-8de0b03d4744/a7e595a3-0f06-4103-99a3-875dfa5bbc36/Files/economic_events.csv'

    EXEC [stg_external].[usp_refresh_external_staging]
        'sector_performance_raw',
        'https://onelake.dfs.fabric.microsoft.com/8143cf61-40ef-40f2-b6b9-8de0b03d4744/a7e595a3-0f06-4103-99a3-875dfa5bbc36/Files/sector_performance_chart.csv'

    EXEC [stg_external].[usp_refresh_external_staging]
        'data_sources_raw',
        'https://onelake.dfs.fabric.microsoft.com/8143cf61-40ef-40f2-b6b9-8de0b03d4744/a7e595a3-0f06-4103-99a3-875dfa5bbc36/Files/data_sources.csv'
    EXEC [stg_external].[usp_refresh_external_staging]
        'data_sources_raw',
        'https://onelake.dfs.fabric.microsoft.com/8143cf61-40ef-40f2-b6b9-8de0b03d4744/a7e595a3-0f06-4103-99a3-875dfa5bbc36/Files/market_gcis.csv'

    -- dim_date: custom transformation on load (month truncation)
    BEGIN TRY
        TRUNCATE TABLE [stg_external].[dim_date]

        INSERT INTO [stg_external].[dim_date]
        SELECT DISTINCT
            DATEFROMPARTS(
                YEAR(CAST([Observation Date] AS DATE)),
                MONTH(CAST([Observation Date] AS DATE)),
                1
            )
        FROM OPENROWSET(
            BULK 'https://onelake.dfs.fabric.microsoft.com/8143cf61-40ef-40f2-b6b9-8de0b03d4744/a7e595a3-0f06-4103-99a3-875dfa5bbc36/Files/DateTable.csv',
            FORMAT = 'CSV',
            HEADER_ROW = TRUE
        ) AS data

        SET @rows = @@ROWCOUNT

        INSERT INTO [stg_fred].[pipeline_log]
            (procedure_name, table_name, status, error_message, rows_loaded, executed_at)
        VALUES
            ('usp_refresh_all_external_staging', 'dim_date', 'SUCCESS', NULL, @rows, GETDATE())
    END TRY
    BEGIN CATCH
        SET @error = ERROR_MESSAGE()
        INSERT INTO [stg_fred].[pipeline_log]
            (procedure_name, table_name, status, error_message, rows_loaded, executed_at)
        VALUES
            ('usp_refresh_all_external_staging', 'dim_date', 'FAILED', @error, 0, GETDATE())
    END CATCH

    -- crunchbase: loaded from Dataflow Gen2 via Fabric Lakehouse
    BEGIN TRY
        TRUNCATE TABLE [stg_external].[crunchbase]

        INSERT INTO [stg_external].[crunchbase]
        SELECT * FROM [market_analysis_data_lakehouse].[dbo].[crunchbase_raw]

        SET @rows = @@ROWCOUNT

        INSERT INTO [stg_fred].[pipeline_log]
            (procedure_name, table_name, status, error_message, rows_loaded, executed_at)
        VALUES
            ('usp_refresh_all_external_staging', 'crunchbase', 'SUCCESS', NULL, @rows, GETDATE())
    END TRY
    BEGIN CATCH
        SET @error = ERROR_MESSAGE()
        INSERT INTO [stg_fred].[pipeline_log]
            (procedure_name, table_name, status, error_message, rows_loaded, executed_at)
        VALUES
            ('usp_refresh_all_external_staging', 'crunchbase', 'FAILED', @error, 0, GETDATE())
    END CATCH
END

-- ============================================================
-- Purpose: Merges gics_sector onto [stg_external].[crunchbase]
-- from the staged [stg_external].[market_gics] lookup table.
--
-- Must run AFTER both usp_refresh_external_staging calls that
-- load 'crunchbase' and 'market_gics' — this procedure does not
-- refresh either source itself, it only joins them.
-- ============================================================

CREATE OR ALTER PROCEDURE [stg_external].[usp_apply_gics_sector]
AS
BEGIN
    DECLARE @rows   INT
    DECLARE @status VARCHAR(50)
    DECLARE @error  VARCHAR(MAX)

    SET @status = 'SUCCESS'

    BEGIN TRY
        UPDATE c
        SET c.gics_sector = m.gics_sector
        FROM [stg_external].[crunchbase] c
        JOIN [stg_external].[market_gics] m
            ON m.market = TRIM(c.market)

        SET @rows = @@ROWCOUNT
    END TRY
    BEGIN CATCH
        SET @status = 'FAILED'
        SET @error  = ERROR_MESSAGE()
        SET @rows   = 0
    END CATCH

    INSERT INTO [stg_fred].[pipeline_log]
        (procedure_name, table_name, status, error_message, rows_loaded, executed_at)
    VALUES
        ('usp_apply_gics_sector', 'crunchbase', @status, @error, @rows, GETDATE())
END
GO
