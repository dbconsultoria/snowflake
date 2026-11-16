-- severity: warn
-- Linhas da fato no membro -1 (FK nula na fonte). Não falha o pipeline, só avisa.
SELECT 'customer_sk = -1' AS issue, COUNT(*) AS fact_rows
FROM GOLD.FACT_ORDERS WHERE customer_sk = -1
HAVING COUNT(*) > 0
UNION ALL
SELECT 'product_sk = -1', COUNT(*)
FROM GOLD.FACT_ORDERS WHERE product_sk = -1
HAVING COUNT(*) > 0;
