-- severity: error
-- Fato sem chave órfã: toda SK existe na dimensão e o grão é único.
SELECT 'customer_sk órfã' AS issue, f.order_code, f.customer_sk AS sk
FROM GOLD.FACT_ORDERS f
LEFT JOIN GOLD.DIM_CUSTOMERS c ON c.customer_sk = f.customer_sk
WHERE c.customer_sk IS NULL
UNION ALL
SELECT 'product_sk órfã', f.order_code, f.product_sk
FROM GOLD.FACT_ORDERS f
LEFT JOIN GOLD.DIM_PRODUCTS p ON p.product_sk = f.product_sk
WHERE p.product_sk IS NULL
UNION ALL
SELECT 'grão duplicado (order_code, product_sk)', order_code, product_sk
FROM GOLD.FACT_ORDERS
GROUP BY order_code, product_sk
HAVING COUNT(*) > 1;
