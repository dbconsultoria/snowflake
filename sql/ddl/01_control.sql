-- CONTROL: log de execução e watermarks. Idempotente.

CREATE TABLE IF NOT EXISTS CONTROL.ETL_RUN_LOG (
    log_id         VARCHAR(36)   NOT NULL,
    batch_id       VARCHAR(64)   NOT NULL,
    step           VARCHAR(30)   NOT NULL,   -- bronze | silver | gold | tests
    table_name     VARCHAR(100)  NOT NULL,   -- tabela ou script executado
    rows_affected  NUMBER(38,0),
    status         VARCHAR(10)   NOT NULL,   -- RUNNING | SUCCESS | FAILED
    started_at     TIMESTAMP_NTZ NOT NULL,
    ended_at       TIMESTAMP_NTZ,
    error_message  VARCHAR(4000),
    CONSTRAINT pk_etl_run_log PRIMARY KEY (log_id)
);

CREATE TABLE IF NOT EXISTS CONTROL.WATERMARK (
    table_name         VARCHAR(100)  NOT NULL,
    load_mode          VARCHAR(12)   NOT NULL,  -- FULL | INCREMENTAL
    watermark_column   VARCHAR(100),            -- coluna monotônica da fonte
    watermark_value    VARCHAR(100),            -- maior valor já carregado
    last_full_load_at  TIMESTAMP_NTZ,           -- _ingested_at da última carga FULL
    last_batch_id      VARCHAR(64),
    updated_at         TIMESTAMP_NTZ,
    CONSTRAINT pk_watermark PRIMARY KEY (table_name)
);

-- Seed: tudo FULL. A fonte não tem updated_at, então só tabelas append-only
-- (pedidos e itens) podem virar INCREMENTAL. Ver README.
MERGE INTO CONTROL.WATERMARK t
USING (
    SELECT column1 AS table_name, column2 AS watermark_column
    FROM VALUES
        ('TBCATEGORIES',  NULL),
        ('TBPRODUCTS',    NULL),
        ('TBCUSTOMERS',   NULL),
        ('TBORDERS',      'code'),
        ('TBORDERDETAIL', 'orders')
) s
ON t.table_name = s.table_name
WHEN NOT MATCHED THEN
    INSERT (table_name, load_mode, watermark_column, updated_at)
    VALUES (s.table_name, 'FULL', s.watermark_column, SYSDATE());
