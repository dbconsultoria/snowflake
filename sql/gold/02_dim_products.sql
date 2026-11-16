-- GOLD.DIM_PRODUCTS - SCD tipo 2 (ver técnica em 01_dim_categories.sql).
-- Atributos versionados: descrição, preço, ativação e categoria.

MERGE INTO GOLD.DIM_PRODUCTS t
USING (
    WITH src AS (
        SELECT
            code        AS product_code,
            description AS product_description,
            salevalue   AS sale_value,
            active      AS is_active,
            category    AS category_code,
            SHA2(CONCAT_WS('|',
                COALESCE(description, '~'),
                COALESCE(TO_VARCHAR(salevalue), '~'),
                COALESCE(TO_VARCHAR(active), '~'),
                COALESCE(TO_VARCHAR(category), '~')), 256) AS attr_hash
        FROM SILVER.TBPRODUCTS
    ),
    changes AS (
        SELECT s.*, (d.product_sk IS NULL) AS is_new
        FROM src s
        LEFT JOIN GOLD.DIM_PRODUCTS d
               ON d.product_code = s.product_code AND d.is_current
        WHERE d.product_sk IS NULL OR d.attr_hash <> s.attr_hash
    )
    SELECT product_code AS merge_key, * FROM changes WHERE NOT is_new
    UNION ALL
    SELECT NULL         AS merge_key, * FROM changes
) s
ON t.product_code = s.merge_key AND t.is_current
WHEN MATCHED THEN UPDATE SET
    valid_to      = $run_ts,
    is_current    = FALSE,
    _batch_id     = $batch_id,
    _updated_at   = $run_ts
WHEN NOT MATCHED THEN INSERT
    (product_code, product_description, sale_value, is_active, category_code, attr_hash,
     valid_from, valid_to, is_current, _batch_id, _updated_at)
VALUES
    (s.product_code, s.product_description, s.sale_value, s.is_active, s.category_code, s.attr_hash,
     IFF(s.is_new, '1900-01-01'::TIMESTAMP_NTZ, $run_ts),
     '9999-12-31'::TIMESTAMP_NTZ, TRUE, $batch_id, $run_ts);
