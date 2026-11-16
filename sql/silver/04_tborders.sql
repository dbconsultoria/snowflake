-- SILVER.TBORDERS
-- customer NULL é válido (FK ON DELETE SET NULL) -> membro -1 no Gold.
-- customer apontando para cliente inexistente = FK órfã -> REJECTS.

CREATE OR REPLACE TEMPORARY TABLE SILVER.STG_TBORDERS AS
SELECT
    b.code,
    b.customer,
    b.orderdate,
    CASE
        WHEN b.code IS NULL      THEN 'chave nula (code)'
        WHEN b.orderdate IS NULL THEN 'orderdate nulo'
        WHEN b.customer IS NOT NULL AND c.code IS NULL
            THEN 'FK órfã: customer=' || b.customer || ' inexistente em tbcustomers'
    END                             AS reject_reason,
    b.record
FROM (SELECT *, OBJECT_CONSTRUCT_KEEP_NULL(*) AS record FROM BRONZE.V_TBORDERS_LATEST) b
LEFT JOIN SILVER.TBCUSTOMERS c ON c.code = b.customer;

DELETE FROM SILVER.REJECTS WHERE batch_id = $batch_id AND source_table = 'TBORDERS';

INSERT INTO SILVER.REJECTS (batch_id, source_table, record_key, reason, record, rejected_at)
SELECT $batch_id, 'TBORDERS', 'code=' || COALESCE(code::VARCHAR, 'NULL'), reject_reason, record, $run_ts
FROM SILVER.STG_TBORDERS
WHERE reject_reason IS NOT NULL;

INSERT OVERWRITE INTO SILVER.TBORDERS (code, customer, orderdate, _batch_id, _processed_at)
SELECT code, customer, orderdate, $batch_id, $run_ts
FROM SILVER.STG_TBORDERS
WHERE reject_reason IS NULL;
