-- SILVER.TBPRODUCTS
-- Nulos: active NULL -> TRUE (default da fonte é 1). category NULL é válido
-- (FK ON DELETE SET NULL) e vira membro -1 no Gold. Só FK órfã é rejeitada.

CREATE OR REPLACE TEMPORARY TABLE SILVER.STG_TBPRODUCTS AS
SELECT
    b.code,
    NULLIF(TRIM(REGEXP_REPLACE(b.description, '\\s+', ' ')), '') AS description,
    b.salevalue,
    COALESCE(b.active, 1) <> 0                                    AS active,
    b.category,
    CASE
        WHEN b.code IS NULL THEN 'chave nula (code)'
        WHEN b.category IS NOT NULL AND c.code IS NULL
            THEN 'FK órfã: category=' || b.category || ' inexistente em tbcategories'
        WHEN b.salevalue < 0 THEN 'salevalue negativo'
    END                                                           AS reject_reason,
    b.record
FROM (SELECT *, OBJECT_CONSTRUCT_KEEP_NULL(*) AS record FROM BRONZE.V_TBPRODUCTS_LATEST) b
LEFT JOIN SILVER.TBCATEGORIES c ON c.code = b.category;

DELETE FROM SILVER.REJECTS WHERE batch_id = $batch_id AND source_table = 'TBPRODUCTS';

INSERT INTO SILVER.REJECTS (batch_id, source_table, record_key, reason, record, rejected_at)
SELECT $batch_id, 'TBPRODUCTS', 'code=' || COALESCE(code::VARCHAR, 'NULL'), reject_reason, record, $run_ts
FROM SILVER.STG_TBPRODUCTS
WHERE reject_reason IS NOT NULL;

INSERT OVERWRITE INTO SILVER.TBPRODUCTS (code, description, salevalue, active, category, _batch_id, _processed_at)
SELECT code, description, salevalue, active, category, $batch_id, $run_ts
FROM SILVER.STG_TBPRODUCTS
WHERE reject_reason IS NULL;
