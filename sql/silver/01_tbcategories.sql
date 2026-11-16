-- SILVER.TBCATEGORIES
-- Padrão de todos os scripts Silver:
--   1. STG temporária com valores tratados + motivo de rejeição (NULL = válido)
--   2. rejeitados -> SILVER.REJECTS (idempotente por batch/tabela)
--   3. INSERT OVERWRITE dos válidos (último DML do arquivo = linhas logadas)

CREATE OR REPLACE TEMPORARY TABLE SILVER.STG_TBCATEGORIES AS
SELECT
    code,
    NULLIF(TRIM(REGEXP_REPLACE(description, '\\s+', ' ')), '') AS description,
    CASE
        WHEN code IS NULL THEN 'chave nula (code)'
    END                                                         AS reject_reason,
    OBJECT_CONSTRUCT_KEEP_NULL(*)                               AS record
FROM BRONZE.V_TBCATEGORIES_LATEST;

DELETE FROM SILVER.REJECTS WHERE batch_id = $batch_id AND source_table = 'TBCATEGORIES';

INSERT INTO SILVER.REJECTS (batch_id, source_table, record_key, reason, record, rejected_at)
SELECT $batch_id, 'TBCATEGORIES', 'code=' || COALESCE(code::VARCHAR, 'NULL'), reject_reason, record, $run_ts
FROM SILVER.STG_TBCATEGORIES
WHERE reject_reason IS NOT NULL;

INSERT OVERWRITE INTO SILVER.TBCATEGORIES (code, description, _batch_id, _processed_at)
SELECT code, description, $batch_id, $run_ts
FROM SILVER.STG_TBCATEGORIES
WHERE reject_reason IS NULL;
