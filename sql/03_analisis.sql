-- =============================================================
-- 03_analisis.sql
-- Análisis de entregas: planificado (fecha estimada) vs. ejecutado (fecha real).
-- Cada consulta responde una pregunta de negocio.
-- =============================================================

USE olist_entregas;

-- -------------------------------------------------------------
-- Vista base: un registro por pedido entregado, con los desvíos ya calculados.
--   dias_desvio > 0  -> llegó tarde (días después de lo prometido)
--   dias_desvio <= 0 -> llegó a tiempo o antes
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW v_entregas AS
SELECT
    o.order_id,
    c.customer_state                                                   AS estado_cliente,
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')                   AS mes_compra,
    DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)       AS dias_entrega_real,
    DATEDIFF(o.order_estimated_delivery_date, o.order_purchase_timestamp)       AS dias_entrega_prometida,
    DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date)  AS dias_desvio,
    CASE WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date)
         THEN 1 ELSE 0 END                                             AS llego_tarde,
    DATEDIFF(o.order_approved_at, o.order_purchase_timestamp)                   AS dias_aprobacion,
    DATEDIFF(o.order_delivered_carrier_date, o.order_approved_at)              AS dias_despacho_vendedor,
    DATEDIFF(o.order_delivered_customer_date, o.order_delivered_carrier_date)  AS dias_transporte
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;


-- -------------------------------------------------------------
-- P1. ¿Cómo es el nivel de servicio general?
-- -------------------------------------------------------------
SELECT
    COUNT(*)                                        AS pedidos_entregados,
    SUM(llego_tarde)                                AS pedidos_tarde,
    ROUND(100 * AVG(llego_tarde), 1)                AS pct_tarde,
    ROUND(AVG(dias_entrega_real), 1)                AS prom_dias_entrega_real,
    ROUND(AVG(dias_entrega_prometida), 1)           AS prom_dias_entrega_prometida,
    ROUND(AVG(CASE WHEN llego_tarde = 1 THEN dias_desvio END), 1) AS prom_dias_atraso_si_tarde
FROM v_entregas;


-- -------------------------------------------------------------
-- P2. ¿En qué zonas (estados) se concentran los atrasos?
--     Se filtran estados con al menos 500 pedidos para que el porcentaje sea representativo.
-- -------------------------------------------------------------
SELECT
    estado_cliente,
    COUNT(*)                                AS pedidos,
    ROUND(100 * AVG(llego_tarde), 1)        AS pct_tarde,
    ROUND(AVG(dias_entrega_real), 1)        AS prom_dias_entrega_real,
    ROUND(AVG(dias_entrega_prometida), 1)   AS prom_dias_prometidos
FROM v_entregas
GROUP BY estado_cliente
HAVING COUNT(*) >= 500
ORDER BY pct_tarde DESC;


-- -------------------------------------------------------------
-- P3. ¿Cómo evoluciona el porcentaje de atrasos mes a mes?
--     Se excluyen meses con menos de 500 pedidos (inicio y fin del dataset).
-- -------------------------------------------------------------
SELECT
    mes_compra,
    COUNT(*)                            AS pedidos,
    SUM(llego_tarde)                    AS pedidos_tarde,
    ROUND(100 * AVG(llego_tarde), 1)    AS pct_tarde
FROM v_entregas
GROUP BY mes_compra
HAVING COUNT(*) >= 500
ORDER BY mes_compra;


-- -------------------------------------------------------------
-- P4. ¿Dónde está el cuello de botella? Tiempo promedio de cada etapa,
--     comparando pedidos a tiempo vs. pedidos tarde.
-- -------------------------------------------------------------
SELECT
    CASE WHEN llego_tarde = 1 THEN 'Tarde' ELSE 'A tiempo' END AS resultado,
    COUNT(*)                                AS pedidos,
    ROUND(AVG(dias_aprobacion), 1)          AS prom_dias_aprobacion,
    ROUND(AVG(dias_despacho_vendedor), 1)   AS prom_dias_despacho_vendedor,
    ROUND(AVG(dias_transporte), 1)          AS prom_dias_transporte
FROM v_entregas
WHERE dias_aprobacion IS NOT NULL
  AND dias_despacho_vendedor IS NOT NULL
  AND dias_transporte IS NOT NULL
GROUP BY resultado;


-- -------------------------------------------------------------
-- P5. ¿Los vendedores que despachan tarde generan entregas tarde?
--     Se compara la fecha en que el vendedor entregó al transporte
--     con su fecha límite de despacho (shipping_limit_date).
-- -------------------------------------------------------------
WITH despacho AS (
    SELECT
        oi.order_id,
        MAX(CASE WHEN o.order_delivered_carrier_date > oi.shipping_limit_date
                 THEN 1 ELSE 0 END) AS despacho_tarde
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_delivered_carrier_date IS NOT NULL
    GROUP BY oi.order_id
)
SELECT
    CASE WHEN d.despacho_tarde = 1 THEN 'Vendedor despachó tarde'
         ELSE 'Vendedor despachó a tiempo' END   AS despacho,
    COUNT(*)                                     AS pedidos,
    ROUND(100 * AVG(e.llego_tarde), 1)           AS pct_entrega_tarde
FROM v_entregas e
JOIN despacho d ON d.order_id = e.order_id
GROUP BY despacho;


-- -------------------------------------------------------------
-- P6. ¿Influye que vendedor y cliente estén en distinto estado?
-- -------------------------------------------------------------
WITH ruta AS (
    SELECT
        oi.order_id,
        MAX(CASE WHEN s.seller_state <> c.customer_state THEN 1 ELSE 0 END) AS interestatal
    FROM order_items oi
    JOIN sellers s   ON s.seller_id = oi.seller_id
    JOIN orders o    ON o.order_id = oi.order_id
    JOIN customers c ON c.customer_id = o.customer_id
    GROUP BY oi.order_id
)
SELECT
    CASE WHEN r.interestatal = 1 THEN 'Distinto estado' ELSE 'Mismo estado' END AS tipo_ruta,
    COUNT(*)                             AS pedidos,
    ROUND(AVG(e.dias_entrega_real), 1)   AS prom_dias_entrega_real,
    ROUND(100 * AVG(e.llego_tarde), 1)   AS pct_tarde
FROM v_entregas e
JOIN ruta r ON r.order_id = e.order_id
GROUP BY tipo_ruta;


-- -------------------------------------------------------------
-- P7. ¿Cuánto impacta el atraso en la satisfacción del cliente?
-- -------------------------------------------------------------
SELECT
    CASE WHEN e.dias_desvio <= 0 THEN '1. A tiempo o antes'
         WHEN e.dias_desvio <= 3 THEN '2. 1 a 3 días tarde'
         WHEN e.dias_desvio <= 7 THEN '3. 4 a 7 días tarde'
         ELSE '4. Más de 7 días tarde' END   AS rango_desvio,
    COUNT(*)                                 AS pedidos_con_resena,
    ROUND(AVG(r.review_score), 2)            AS puntaje_promedio,
    ROUND(100 * AVG(r.review_score <= 2), 1) AS pct_resenas_negativas
FROM v_entregas e
JOIN order_reviews r ON r.order_id = e.order_id
GROUP BY rango_desvio
ORDER BY rango_desvio;


-- -------------------------------------------------------------
-- P8. ¿La fecha prometida es demasiado conservadora?
--     Distribución de cuántos días antes de lo prometido llegan los pedidos.
-- -------------------------------------------------------------
SELECT
    CASE WHEN dias_desvio > 0    THEN '1. Tarde'
         WHEN dias_desvio >= -7  THEN '2. Entre 0 y 7 días antes'
         WHEN dias_desvio >= -14 THEN '3. Entre 8 y 14 días antes'
         ELSE '4. Más de 14 días antes' END AS llegada,
    COUNT(*)                                AS pedidos,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_pedidos
FROM v_entregas
GROUP BY llegada
ORDER BY llegada;
