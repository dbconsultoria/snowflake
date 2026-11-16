-- severity: error
-- Silver -> Gold: itens, quantidade e valor da fato batem com o Silver.
WITH silver AS (
    SELECT COUNT(*)                            AS lines,
           SUM(d.quantity)                     AS qty,
           ROUND(SUM(d.quantity * d.salesvalue), 2) AS sales
    FROM SILVER.TBORDERDETAIL d
    JOIN SILVER.TBORDERS o ON o.code = d.orders
),
gold AS (
    SELECT SUM(line_count) AS lines, SUM(total_quantity) AS qty, SUM(total_sales) AS sales
    FROM GOLD.FACT_ORDERS
)
SELECT s.lines AS silver_lines, g.lines AS fact_lines,
       s.qty   AS silver_qty,   g.qty   AS fact_qty,
       s.sales AS silver_sales, g.sales AS fact_sales
FROM silver s CROSS JOIN gold g
WHERE NOT (EQUAL_NULL(s.lines, g.lines) AND EQUAL_NULL(s.qty, g.qty) AND EQUAL_NULL(s.sales, g.sales));
