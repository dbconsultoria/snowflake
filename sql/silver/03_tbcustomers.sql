-- SILVER.TBCUSTOMERS
-- Padronização: trim + espaços colapsados; email minúsculo (inválido -> NULL);
-- telefone só com dígitos; birthdate -> DATE (fora de 1900..hoje -> NULL).
-- Atributos inválidos são anulados, não rejeitam o cliente (preserva pedidos).

CREATE OR REPLACE TEMPORARY TABLE SILVER.STG_TBCUSTOMERS AS
WITH cleaned AS (
    SELECT
        code,
        NULLIF(TRIM(REGEXP_REPLACE(name,    '\\s+', ' ')), '') AS name,
        NULLIF(TRIM(REGEXP_REPLACE(address, '\\s+', ' ')), '') AS address,
        NULLIF(REGEXP_REPLACE(phone, '[^0-9]', ''), '')        AS phone,
        NULLIF(LOWER(TRIM(email)), '')                         AS email_raw,
        birthdate::DATE                                        AS birthdate_raw,
        OBJECT_CONSTRUCT_KEEP_NULL(*)                          AS record
    FROM BRONZE.V_TBCUSTOMERS_LATEST
)
SELECT
    code,
    name,
    address,
    phone,
    IFF(REGEXP_LIKE(email_raw, '^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$'), email_raw, NULL) AS email,
    IFF(birthdate_raw BETWEEN '1900-01-01'::DATE AND CURRENT_DATE(), birthdate_raw, NULL)  AS birthdate,
    CASE
        WHEN code IS NULL THEN 'chave nula (code)'
    END AS reject_reason,
    record
FROM cleaned;

DELETE FROM SILVER.REJECTS WHERE batch_id = $batch_id AND source_table = 'TBCUSTOMERS';

INSERT INTO SILVER.REJECTS (batch_id, source_table, record_key, reason, record, rejected_at)
SELECT $batch_id, 'TBCUSTOMERS', 'code=' || COALESCE(code::VARCHAR, 'NULL'), reject_reason, record, $run_ts
FROM SILVER.STG_TBCUSTOMERS
WHERE reject_reason IS NOT NULL;

INSERT OVERWRITE INTO SILVER.TBCUSTOMERS (code, name, address, phone, email, birthdate, _batch_id, _processed_at)
SELECT code, name, address, phone, email, birthdate, $batch_id, $run_ts
FROM SILVER.STG_TBCUSTOMERS
WHERE reject_reason IS NULL;
