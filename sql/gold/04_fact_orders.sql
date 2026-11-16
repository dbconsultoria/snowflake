-- GOLD.FACT_ORDERS - grão: 1 linha por produto por pedido.
-- SKs resolvidas pela versão vigente na data do pedido (intervalo semiaberto
-- [valid_from, valid_to)). FK nula na fonte -> membro -1.
-- Rebuild completo (INSERT OVERWRITE): idempotente e barato neste volume; o
-- Silver sempre contém o snapshot completo, mesmo com extração incremental.

INSERT OVERWRITE INTO GOLD.FACT_ORDERS
    (order_code, customer_sk, product_sk, order_date, total_quantity, total_sales, line_count, _batch_id, _loaded_at)
WITH agg AS (
    SELECT
        o.code              AS order_code,
        o.customer          AS customer_code,
        o.orderdate         AS order_date,
        d.product           AS product_code,
        SUM(d.quantity)                        AS total_quantity,
        ROUND(SUM(d.quantity * d.salesvalue), 2) AS total_sales,
        COUNT(*)                               AS line_count
    FROM SILVER.TBORDERDETAIL d
    JOIN SILVER.TBORDERS      o ON o.code = d.orders
    GROUP BY o.code, o.customer, o.orderdate, d.product
)
SELECT
    a.order_code,
    COALESCE(c.customer_sk, -1),
    COALESCE(p.product_sk,  -1),
    a.order_date,
    a.total_quantity,
    a.total_sales,
    a.line_count,
    $batch_id,
    $run_ts
FROM agg a
LEFT JOIN GOLD.DIM_CUSTOMERS c
       ON c.customer_code = a.customer_code
      AND a.order_date >= c.valid_from AND a.order_date < c.valid_to
LEFT JOIN GOLD.DIM_PRODUCTS p
       ON p.product_code = a.product_code
      AND a.order_date >= p.valid_from AND a.order_date < p.valid_to;
