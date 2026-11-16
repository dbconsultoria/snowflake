-- SILVER: mesmas 5 tabelas, tratadas. Recarregadas por INSERT OVERWRITE.

CREATE TABLE IF NOT EXISTS SILVER.TBCATEGORIES (
    code          NUMBER(10,0)  NOT NULL,
    description   VARCHAR(150),
    _batch_id     VARCHAR(64)   NOT NULL,
    _processed_at TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_silver_tbcategories PRIMARY KEY (code)
);

CREATE TABLE IF NOT EXISTS SILVER.TBPRODUCTS (
    code          NUMBER(10,0)  NOT NULL,
    description   VARCHAR(150),
    salevalue     NUMBER(18,2),
    active        BOOLEAN       NOT NULL,
    category      NUMBER(10,0),
    _batch_id     VARCHAR(64)   NOT NULL,
    _processed_at TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_silver_tbproducts PRIMARY KEY (code)
);

CREATE TABLE IF NOT EXISTS SILVER.TBCUSTOMERS (
    code          NUMBER(10,0)  NOT NULL,
    name          VARCHAR(100),
    address       VARCHAR(250),
    phone         VARCHAR(25),     -- só dígitos
    email         VARCHAR(100),    -- minúsculo; NULL se inválido
    birthdate     DATE,
    _batch_id     VARCHAR(64)   NOT NULL,
    _processed_at TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_silver_tbcustomers PRIMARY KEY (code)
);

CREATE TABLE IF NOT EXISTS SILVER.TBORDERS (
    code          NUMBER(10,0)  NOT NULL,
    customer      NUMBER(10,0),
    orderdate     TIMESTAMP_NTZ NOT NULL,
    _batch_id     VARCHAR(64)   NOT NULL,
    _processed_at TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_silver_tborders PRIMARY KEY (code)
);

CREATE TABLE IF NOT EXISTS SILVER.TBORDERDETAIL (
    orders        NUMBER(10,0)  NOT NULL,
    product       NUMBER(10,0),
    quantity      NUMBER(10,0)  NOT NULL,
    salesvalue    NUMBER(18,2)  NOT NULL,
    _batch_id     VARCHAR(64)   NOT NULL,
    _processed_at TIMESTAMP_NTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS SILVER.REJECTS (
    batch_id      VARCHAR(64)   NOT NULL,
    source_table  VARCHAR(100)  NOT NULL,
    record_key    VARCHAR(200),
    reason        VARCHAR(500)  NOT NULL,
    record        VARIANT,                 -- linha completa como veio do Bronze
    rejected_at   TIMESTAMP_NTZ NOT NULL
);
