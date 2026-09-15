-- SQLBook: Code
--------------------------------------------------------------------------------
-- Trabajo Práctico - Semana 4 - Unidad 2: Optimización de Consultas
-- Parte 4: Competencia de optimización entre equipos
-- Esquema: Food Store
--------------------------------------------------------------------------------
-- Descripción:
-- Este script contiene la consulta analítica oficial de la competencia de 
-- optimización (cruce masivo de 4 tablas con agregación y filtros de borrado 
-- lógico). Se documenta el plan de ejecución inicial, la evaluación de 
-- estrategias propuestas por la IA (como índices B-Tree) y el resultado 
-- del benchmarking mediante EXPLAIN ANALYZE.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 1. CONSULTA ANALÍTICA DE LA COMPETENCIA (Medición Inicial)
--------------------------------------------------------------------------------
-- Métrica de referencia obtenida (Execution Time): ~197.59 ms
-- Plan seleccionado por PostgreSQL: Parallel Seq Scan con Hash Joins y Parallel Hash Aggregate.

EXPLAIN ANALYZE
SELECT 
    c.nombre AS categoria,
    COUNT(p.id_pedido) AS total_pedidos,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS facturacion_total
FROM categoria c
JOIN producto pr ON pr.id_categoria = c.id_categoria
JOIN detalle_pedido dp ON dp.id_producto = pr.id_producto
JOIN pedido p ON p.id_pedido = dp.id_pedido
WHERE c.activo = TRUE 
    AND pr.activo = TRUE
GROUP BY c.nombre;