-- SILVER.TBORDERDETAIL
-- Sem PK na fonte: NÃO deduplica (linhas idênticas são legítimas; a fato
-- agrega e expõe line_count).
-- Item sem pedido não tem como entrar na fato -> rejeitado.
-- product NULL é válido (FK ON DELETE SET NULL) -> membro -1 no Gold.
-- Pedidos/produtos rejeitados não estão no Silver, então seus itens também
-- caem como FK órfã (rejeição em cascata).

CREATE OR REPLACE TEMPORARY TABLE SILVER.STG_TBORDERDETAIL AS
SELECT
    b.orders,
    b.product,
    b.quantity,
    b.salesvalue,
    CASE
        WHEN b.orders IS NULL THEN 'item sem pedido (orders nulo)'
        WHEN o.code IS NULL
            THEN 'FK órfã: orders=' || b.orders || ' inexistente ou rejeitado em tborders'
        WHEN b.product IS NOT NULL AND p.code IS NULL
            THEN 'FK órfã: product=' || b.product || ' inexistente ou rejeitado em tbproducts'
        WHEN b.quantity IS NULL OR b.quantity <= 0     THEN 'quantity nula ou <= 0'
        WHEN b.salesvalue IS NULL OR b.salesvalue < 0  THEN 'salesvalue nulo ou negativo'
    END                             AS reject_reason,
    b.record
FROM (SELECT *, OBJECT_CONSTRUCT_KEEP_NULL(*) AS record FROM BRONZE.V_TBORDERDETAIL_LATEST) b
LEFT JOIN SILVER.TBORDERS   o ON o.code = b.orders
LEFT JOIN SILVER.TBPRODUCTS p ON p.code = b.product;

DELETE FROM SILVER.REJECTS WHERE batch_id = $batch_id AND source_table = 'TBORDERDETAIL';

INSERT INTO SILVER.REJECTS (batch_id, source_table, record_key, reason, record, rejected_at)
SELECT $batch_id, 'TBORDERDETAIL',
       'orders=' || COALESCE(orders::VARCHAR, 'NULL') || '|product=' || COALESCE(product::VARCHAR, 'NULL'),
       reject_reason, record, $run_ts
FROM SILVER.STG_TBORDERDETAIL
WHERE reject_reason IS NOT NULL;

INSERT OVERWRITE INTO SILVER.TBORDERDETAIL (orders, product, quantity, salesvalue, _batch_id, _processed_at)
SELECT orders, product, quantity, salesvalue, $batch_id, $run_ts
FROM SILVER.STG_TBORDERDETAIL
WHERE reject_reason IS NULL;
