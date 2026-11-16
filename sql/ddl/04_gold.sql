-- GOLD: star schema. SCD2 nas dimensões; -1 = membro desconhecido.

CREATE SEQUENCE IF NOT EXISTS GOLD.SEQ_CATEGORY_SK START = 1 INCREMENT = 1;
CREATE SEQUENCE IF NOT EXISTS GOLD.SEQ_PRODUCT_SK  START = 1 INCREMENT = 1;
CREATE SEQUENCE IF NOT EXISTS GOLD.SEQ_CUSTOMER_SK START = 1 INCREMENT = 1;

CREATE TABLE IF NOT EXISTS GOLD.DIM_CATEGORIES (
    category_sk           NUMBER(38,0)  NOT NULL DEFAULT GOLD.SEQ_CATEGORY_SK.NEXTVAL,
    category_code         NUMBER(10,0)  NOT NULL,
    category_description  VARCHAR(150),
    attr_hash             VARCHAR(64)   NOT NULL,
    valid_from            TIMESTAMP_NTZ NOT NULL,
    valid_to              TIMESTAMP_NTZ NOT NULL,
    is_current            BOOLEAN       NOT NULL,
    _batch_id             VARCHAR(64)   NOT NULL,
    _updated_at           TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_dim_categories PRIMARY KEY (category_sk) RELY
);

CREATE TABLE IF NOT EXISTS GOLD.DIM_PRODUCTS (
    product_sk            NUMBER(38,0)  NOT NULL DEFAULT GOLD.SEQ_PRODUCT_SK.NEXTVAL,
    product_code          NUMBER(10,0)  NOT NULL,
    product_description   VARCHAR(150),
    sale_value            NUMBER(18,2),
    is_active             BOOLEAN,
    category_code         NUMBER(10,0),
    attr_hash             VARCHAR(64)   NOT NULL,
    valid_from            TIMESTAMP_NTZ NOT NULL,
    valid_to              TIMESTAMP_NTZ NOT NULL,
    is_current            BOOLEAN       NOT NULL,
    _batch_id             VARCHAR(64)   NOT NULL,
    _updated_at           TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_dim_products PRIMARY KEY (product_sk) RELY
);

CREATE TABLE IF NOT EXISTS GOLD.DIM_CUSTOMERS (
    customer_sk           NUMBER(38,0)  NOT NULL DEFAULT GOLD.SEQ_CUSTOMER_SK.NEXTVAL,
    customer_code         NUMBER(10,0)  NOT NULL,
    customer_name         VARCHAR(100),
    address               VARCHAR(250),
    phone                 VARCHAR(25),
    email                 VARCHAR(100),
    birth_date            DATE,
    attr_hash             VARCHAR(64)   NOT NULL,
    valid_from            TIMESTAMP_NTZ NOT NULL,
    valid_to              TIMESTAMP_NTZ NOT NULL,
    is_current            BOOLEAN       NOT NULL,
    _batch_id             VARCHAR(64)   NOT NULL,
    _updated_at           TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_dim_customers PRIMARY KEY (customer_sk) RELY
);

CREATE TABLE IF NOT EXISTS GOLD.FACT_ORDERS (
    order_code            NUMBER(10,0)  NOT NULL,   -- dimensão degenerada
    customer_sk           NUMBER(38,0)  NOT NULL,
    product_sk            NUMBER(38,0)  NOT NULL,
    order_date            TIMESTAMP_NTZ NOT NULL,   -- UTC
    total_quantity        NUMBER(38,0)  NOT NULL,
    total_sales           NUMBER(18,2)  NOT NULL,
    line_count            NUMBER(38,0)  NOT NULL,
    _batch_id             VARCHAR(64)   NOT NULL,
    _loaded_at            TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_fact_orders PRIMARY KEY (order_code, product_sk) RELY,
    CONSTRAINT fk_fact_customer FOREIGN KEY (customer_sk) REFERENCES GOLD.DIM_CUSTOMERS (customer_sk) RELY,
    CONSTRAINT fk_fact_product  FOREIGN KEY (product_sk)  REFERENCES GOLD.DIM_PRODUCTS  (product_sk)  RELY
);

-- Membros desconhecidos (FK nula na fonte -> -1).
MERGE INTO GOLD.DIM_CATEGORIES t USING (SELECT -1 AS sk) s ON t.category_sk = s.sk
WHEN NOT MATCHED THEN INSERT
    (category_sk, category_code, category_description, attr_hash, valid_from, valid_to, is_current, _batch_id, _updated_at)
VALUES (-1, -1, 'Desconhecido', 'UNKNOWN', '1900-01-01', '9999-12-31', TRUE, 'SEED', SYSDATE());

MERGE INTO GOLD.DIM_PRODUCTS t USING (SELECT -1 AS sk) s ON t.product_sk = s.sk
WHEN NOT MATCHED THEN INSERT
    (product_sk, product_code, product_description, sale_value, is_active, category_code, attr_hash,
     valid_from, valid_to, is_current, _batch_id, _updated_at)
VALUES (-1, -1, 'Desconhecido', NULL, NULL, NULL, 'UNKNOWN', '1900-01-01', '9999-12-31', TRUE, 'SEED', SYSDATE());

MERGE INTO GOLD.DIM_CUSTOMERS t USING (SELECT -1 AS sk) s ON t.customer_sk = s.sk
WHEN NOT MATCHED THEN INSERT
    (customer_sk, customer_code, customer_name, address, phone, email, birth_date, attr_hash,
     valid_from, valid_to, is_current, _batch_id, _updated_at)
VALUES (-1, -1, 'Desconhecido', NULL, NULL, NULL, NULL, 'UNKNOWN', '1900-01-01', '9999-12-31', TRUE, 'SEED', SYSDATE());
