-- severity: error
-- Todo código NÃO nulo precisa resolver uma versão de dimensão vigente na data
-- do pedido. Se falhar, a fato teria caído indevidamente no membro -1.
SELECT 'cliente sem versão vigente na data' AS issue, o.code AS order_code, o.customer AS business_key, o.orderdate
FROM SILVER.TBORDERS o
WHERE o.customer IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM GOLD.DIM_CUSTOMERS c
      WHERE c.customer_code = o.customer
        AND o.orderdate >= c.valid_from AND o.orderdate < c.valid_to)
UNION ALL
SELECT 'produto sem versão vigente na data', o.code, d.product, o.orderdate
FROM SILVER.TBORDERDETAIL d
JOIN SILVER.TBORDERS o ON o.code = d.orders
WHERE d.product IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM GOLD.DIM_PRODUCTS p
      WHERE p.product_code = d.product
        AND o.orderdate >= p.valid_from AND o.orderdate < p.valid_to);
