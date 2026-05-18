-- ============================================================
-- 01_create_tables.sql
-- Macro Market Analysis — Microsoft Fabric Warehouse
-- Author: Benjamin Brady
-- Creates all staging tables and the pipeline log.
-- Note: stg_fred._raw tables are auto-created by the
--       Data Factory pipeline on first run.
-- ============================================================


-- ============================================================
-- EXTERNAL STAGING TABLES
-- ============================================================

CREATE TABLE [stg_external].[crunchbase]
(
    permalink           VARCHAR(MAX),
    name                VARCHAR(MAX),
    homepage_url        VARCHAR(MAX),
    category_list       VARCHAR(MAX),
    market              VARCHAR(MAX),
    funding_total_usd   BIGINT,
    status              VARCHAR(MAX),
    country_code        VARCHAR(MAX),
    state_code          VARCHAR(MAX),
    region              VARCHAR(MAX),
    city                VARCHAR(MAX),
    funding_rounds      INT,
    founded_at          VARCHAR(MAX),
    founded_month       VARCHAR(MAX),
    founded_quarter     VARCHAR(MAX),
    founded_year        INT,
    first_funding_at    VARCHAR(MAX),
    last_funding_at     VARCHAR(MAX)
);

CREATE TABLE [stg_external].[economic_events_raw]
(
    year        INT,
    event       VARCHAR(MAX),
    description VARCHAR(MAX)
);

CREATE TABLE [stg_external].[data_sources_raw]
(
    source_table VARCHAR(MAX),
    source       VARCHAR(MAX),
    description  VARCHAR(MAX)
);

CREATE TABLE [stg_external].[sector_performance_raw]
(
    year             INT,
    event            VARCHAR(MAX),
    sector           VARCHAR(MAX),
    return_pct       VARCHAR(MAX),
    performance_rank VARCHAR(MAX)
);

CREATE TABLE [stg_external].[dim_date]
(
    month_date DATE
);


-- ============================================================
-- PIPELINE LOG
-- Tracks all ingestion runs across FRED and external staging.
-- ============================================================

CREATE TABLE [stg_fred].[pipeline_log]
(
    log_id         BIGINT IDENTITY,
    procedure_name VARCHAR(200),
    table_name     VARCHAR(200),
    status         VARCHAR(50),
    error_message  VARCHAR(MAX),
    rows_loaded    INT,
    executed_at    DATETIME2(0)
);
