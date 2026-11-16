-- severity: error
-- Vigências contíguas, sem sobreposição nem buraco; a vigente termina em 9999-12-31.
WITH versions AS (
    SELECT 'DIM_CATEGORIES' AS dim, category_code AS business_key, valid_from, valid_to, is_current
    FROM GOLD.DIM_CATEGORIES
    UNION ALL
    SELECT 'DIM_PRODUCTS', product_code, valid_from, valid_to, is_current FROM GOLD.DIM_PRODUCTS
    UNION ALL
    SELECT 'DIM_CUSTOMERS', customer_code, valid_from, valid_to, is_current FROM GOLD.DIM_CUSTOMERS
),
ordered AS (
    SELECT *, LEAD(valid_from) OVER (PARTITION BY dim, business_key ORDER BY valid_from) AS next_from
    FROM versions
)
SELECT dim, business_key, valid_from, valid_to, is_current, next_from
FROM ordered
WHERE valid_from >= valid_to
   OR (next_from IS NOT NULL AND (valid_to <> next_from OR is_current))
   OR (next_from IS NULL AND (NOT is_current OR valid_to <> '9999-12-31'::TIMESTAMP_NTZ));
