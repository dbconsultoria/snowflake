-- BRONZE: cópia crua das tabelas TiDB, tipos da fonte preservados, append-only.
-- Mapeamento MySQL -> Snowflake: int -> NUMBER(10,0), varchar(n) -> VARCHAR(n),
-- decimal(18,2) -> NUMBER(18,2), datetime/timestamp -> TIMESTAMP_NTZ (UTC).

CREATE TABLE IF NOT EXISTS BRONZE.TBCATEGORIES (
    code          NUMBER(10,0) NOT NULL,
    description   VARCHAR(150),
    _ingested_at  TIMESTAMP_NTZ NOT NULL,
    _batch_id     VARCHAR(64)   NOT NULL
);

CREATE TABLE IF NOT EXISTS BRONZE.TBPRODUCTS (
    code          NUMBER(10,0) NOT NULL,
    description   VARCHAR(150),
    salevalue     NUMBER(18,2),
    active        NUMBER(10,0),
    category      NUMBER(10,0),
    _ingested_at  TIMESTAMP_NTZ NOT NULL,
    _batch_id     VARCHAR(64)   NOT NULL
);

CREATE TABLE IF NOT EXISTS BRONZE.TBCUSTOMERS (
    code          NUMBER(10,0) NOT NULL,
    name          VARCHAR(100),
    address       VARCHAR(250),
    phone         VARCHAR(25),
    email         VARCHAR(100),
    birthdate     TIMESTAMP_NTZ,
    _ingested_at  TIMESTAMP_NTZ NOT NULL,
    _batch_id     VARCHAR(64)   NOT NULL
);

CREATE TABLE IF NOT EXISTS BRONZE.TBORDERS (
    code          NUMBER(10,0) NOT NULL,
    customer      NUMBER(10,0),
    orderdate     TIMESTAMP_NTZ NOT NULL,
    _ingested_at  TIMESTAMP_NTZ NOT NULL,
    _batch_id     VARCHAR(64)   NOT NULL
);

CREATE TABLE IF NOT EXISTS BRONZE.TBORDERDETAIL (
    product       NUMBER(10,0),
    orders        NUMBER(10,0),
    quantity      NUMBER(10,0),
    salesvalue    NUMBER(18,2),
    _ingested_at  TIMESTAMP_NTZ NOT NULL,
    _batch_id     VARCHAR(64)   NOT NULL
);

-- -----------------------------------------------------------------------------
-- Views de snapshot vigente: o que a fonte "é" segundo o Bronze.
--   * considera só o que chegou desde a última carga FULL (deleções na fonte
--     somem do snapshot) + cargas incrementais posteriores;
--   * tabelas com PK: última versão de cada code;
--   * tborderdetail (sem PK): linhas do batch mais recente de cada pedido,
--     SEM deduplicar (linhas idênticas são legítimas).
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW BRONZE.V_TBCATEGORIES_LATEST AS
SELECT * FROM BRONZE.TBCATEGORIES
WHERE _ingested_at >= (SELECT COALESCE(MAX(last_full_load_at), '1900-01-01'::TIMESTAMP_NTZ)
                       FROM CONTROL.WATERMARK WHERE table_name = 'TBCATEGORIES')
QUALIFY ROW_NUMBER() OVER (PARTITION BY code ORDER BY _ingested_at DESC, _batch_id DESC) = 1;

CREATE OR REPLACE VIEW BRONZE.V_TBPRODUCTS_LATEST AS
SELECT * FROM BRONZE.TBPRODUCTS
WHERE _ingested_at >= (SELECT COALESCE(MAX(last_full_load_at), '1900-01-01'::TIMESTAMP_NTZ)
                       FROM CONTROL.WATERMARK WHERE table_name = 'TBPRODUCTS')
QUALIFY ROW_NUMBER() OVER (PARTITION BY code ORDER BY _ingested_at DESC, _batch_id DESC) = 1;

CREATE OR REPLACE VIEW BRONZE.V_TBCUSTOMERS_LATEST AS
SELECT * FROM BRONZE.TBCUSTOMERS
WHERE _ingested_at >= (SELECT COALESCE(MAX(last_full_load_at), '1900-01-01'::TIMESTAMP_NTZ)
                       FROM CONTROL.WATERMARK WHERE table_name = 'TBCUSTOMERS')
QUALIFY ROW_NUMBER() OVER (PARTITION BY code ORDER BY _ingested_at DESC, _batch_id DESC) = 1;

CREATE OR REPLACE VIEW BRONZE.V_TBORDERS_LATEST AS
SELECT * FROM BRONZE.TBORDERS
WHERE _ingested_at >= (SELECT COALESCE(MAX(last_full_load_at), '1900-01-01'::TIMESTAMP_NTZ)
                       FROM CONTROL.WATERMARK WHERE table_name = 'TBORDERS')
QUALIFY ROW_NUMBER() OVER (PARTITION BY code ORDER BY _ingested_at DESC, _batch_id DESC) = 1;

CREATE OR REPLACE VIEW BRONZE.V_TBORDERDETAIL_LATEST AS
SELECT * FROM BRONZE.TBORDERDETAIL
WHERE _ingested_at >= (SELECT COALESCE(MAX(last_full_load_at), '1900-01-01'::TIMESTAMP_NTZ)
                       FROM CONTROL.WATERMARK WHERE table_name = 'TBORDERDETAIL')
QUALIFY _ingested_at = MAX(_ingested_at) OVER (PARTITION BY orders);
