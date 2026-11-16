-- severity: error
-- Exatamente uma versão is_current por chave de negócio.
SELECT 'DIM_CATEGORIES' AS dim, category_code AS business_key, COUNT_IF(is_current) AS current_versions
FROM GOLD.DIM_CATEGORIES GROUP BY category_code HAVING COUNT_IF(is_current) <> 1
UNION ALL
SELECT 'DIM_PRODUCTS', product_code, COUNT_IF(is_current)
FROM GOLD.DIM_PRODUCTS GROUP BY product_code HAVING COUNT_IF(is_current) <> 1
UNION ALL
SELECT 'DIM_CUSTOMERS', customer_code, COUNT_IF(is_current)
FROM GOLD.DIM_CUSTOMERS GROUP BY customer_code HAVING COUNT_IF(is_current) <> 1;
