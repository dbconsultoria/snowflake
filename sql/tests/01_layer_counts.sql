-- severity: error
-- Reconciliação Bronze -> Silver: snapshot vigente do Bronze = Silver + rejeitados do batch.
WITH counts AS (
    SELECT 'TBCATEGORIES' AS t,
           (SELECT COUNT(*) FROM BRONZE.V_TBCATEGORIES_LATEST)  AS bronze_rows,
           (SELECT COUNT(*) FROM SILVER.TBCATEGORIES)           AS silver_rows
    UNION ALL SELECT 'TBPRODUCTS',
           (SELECT COUNT(*) FROM BRONZE.V_TBPRODUCTS_LATEST),
           (SELECT COUNT(*) FROM SILVER.TBPRODUCTS)
    UNION ALL SELECT 'TBCUSTOMERS',
           (SELECT COUNT(*) FROM BRONZE.V_TBCUSTOMERS_LATEST),
           (SELECT COUNT(*) FROM SILVER.TBCUSTOMERS)
    UNION ALL SELECT 'TBORDERS',
           (SELECT COUNT(*) FROM BRONZE.V_TBORDERS_LATEST),
           (SELECT COUNT(*) FROM SILVER.TBORDERS)
    UNION ALL SELECT 'TBORDERDETAIL',
           (SELECT COUNT(*) FROM BRONZE.V_TBORDERDETAIL_LATEST),
           (SELECT COUNT(*) FROM SILVER.TBORDERDETAIL)
),
rejects AS (
    SELECT source_table AS t, COUNT(*) AS rejected_rows
    FROM SILVER.REJECTS
    WHERE batch_id = $batch_id
    GROUP BY source_table
)
SELECT c.t AS table_name, c.bronze_rows, c.silver_rows, COALESCE(r.rejected_rows, 0) AS rejected_rows
FROM counts c
LEFT JOIN rejects r ON r.t = c.t
WHERE c.bronze_rows <> c.silver_rows + COALESCE(r.rejected_rows, 0)
   OR c.bronze_rows = 0;
