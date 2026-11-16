-- GOLD.DIM_CATEGORIES - SCD tipo 2 via MERGE.
-- Técnica: cada chave alterada aparece 2x na origem do MERGE:
--   merge_key = código -> casa com a versão vigente e a FECHA;
--   merge_key = NULL   -> nunca casa e INSERE a nova versão.
-- A primeira versão de qualquer chave começa em 1900-01-01, para que pedidos
-- históricos resolvam a versão vigente na data do pedido.

MERGE INTO GOLD.DIM_CATEGORIES t
USING (
    WITH src AS (
        SELECT
            code        AS category_code,
            description AS category_description,
            SHA2(CONCAT_WS('|', COALESCE(description, '~')), 256) AS attr_hash
        FROM SILVER.TBCATEGORIES
    ),
    changes AS (
        SELECT s.*, (d.category_sk IS NULL) AS is_new
        FROM src s
        LEFT JOIN GOLD.DIM_CATEGORIES d
               ON d.category_code = s.category_code AND d.is_current
        WHERE d.category_sk IS NULL OR d.attr_hash <> s.attr_hash
    )
    SELECT category_code AS merge_key, * FROM changes WHERE NOT is_new
    UNION ALL
    SELECT NULL          AS merge_key, * FROM changes
) s
ON t.category_code = s.merge_key AND t.is_current
WHEN MATCHED THEN UPDATE SET
    valid_to      = $run_ts,
    is_current    = FALSE,
    _batch_id     = $batch_id,
    _updated_at   = $run_ts
WHEN NOT MATCHED THEN INSERT
    (category_code, category_description, attr_hash, valid_from, valid_to, is_current, _batch_id, _updated_at)
VALUES
    (s.category_code, s.category_description, s.attr_hash,
     IFF(s.is_new, '1900-01-01'::TIMESTAMP_NTZ, $run_ts),
     '9999-12-31'::TIMESTAMP_NTZ, TRUE, $batch_id, $run_ts);
