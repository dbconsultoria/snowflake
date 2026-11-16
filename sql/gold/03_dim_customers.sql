-- GOLD.DIM_CUSTOMERS - SCD tipo 2 (ver técnica em 01_dim_categories.sql).
-- Atributos versionados: nome, endereço, telefone, email, data de nascimento.
-- Datas no hash com formato fixo (independe de DATE_OUTPUT_FORMAT da sessão).

MERGE INTO GOLD.DIM_CUSTOMERS t
USING (
    WITH src AS (
        SELECT
            code      AS customer_code,
            name      AS customer_name,
            address,
            phone,
            email,
            birthdate AS birth_date,
            SHA2(CONCAT_WS('|',
                COALESCE(name, '~'),
                COALESCE(address, '~'),
                COALESCE(phone, '~'),
                COALESCE(email, '~'),
                COALESCE(TO_CHAR(birthdate, 'YYYY-MM-DD'), '~')), 256) AS attr_hash
        FROM SILVER.TBCUSTOMERS
    ),
    changes AS (
        SELECT s.*, (d.customer_sk IS NULL) AS is_new
        FROM src s
        LEFT JOIN GOLD.DIM_CUSTOMERS d
               ON d.customer_code = s.customer_code AND d.is_current
        WHERE d.customer_sk IS NULL OR d.attr_hash <> s.attr_hash
    )
    SELECT customer_code AS merge_key, * FROM changes WHERE NOT is_new
    UNION ALL
    SELECT NULL          AS merge_key, * FROM changes
) s
ON t.customer_code = s.merge_key AND t.is_current
WHEN MATCHED THEN UPDATE SET
    valid_to      = $run_ts,
    is_current    = FALSE,
    _batch_id     = $batch_id,
    _updated_at   = $run_ts
WHEN NOT MATCHED THEN INSERT
    (customer_code, customer_name, address, phone, email, birth_date, attr_hash,
     valid_from, valid_to, is_current, _batch_id, _updated_at)
VALUES
    (s.customer_code, s.customer_name, s.address, s.phone, s.email, s.birth_date, s.attr_hash,
     IFF(s.is_new, '1900-01-01'::TIMESTAMP_NTZ, $run_ts),
     '9999-12-31'::TIMESTAMP_NTZ, TRUE, $batch_id, $run_ts);
