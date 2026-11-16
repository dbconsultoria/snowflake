-- severity: warn
-- Resumo das rejeições do batch (aviso, não erro).
SELECT source_table, reason, COUNT(*) AS rejected_rows
FROM SILVER.REJECTS
WHERE batch_id = $batch_id
GROUP BY source_table, reason
ORDER BY source_table, rejected_rows DESC;
