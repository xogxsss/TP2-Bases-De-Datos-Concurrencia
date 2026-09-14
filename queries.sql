-- SQLBook: Code
-- Facturación por categoría y mes
-- Tablas utilizadas: categoria, producto, detalle_pedido y pedido
/*
    * categoria: otorga el nombre del conjunto de productos.
    * producto: vinculamos con la categoría para agrupar.
    * detalle_pedido: Datos de venta (cantidad y precio histórico)
    a través del producto.
    * pedido: aporta la fecha de transacción y filtro de borrado lógico (soft delete)
*/
EXPLAIN ANALYZE
SELECT 
    c.nombre AS categoria,
    TO_CHAR(p.fecha_hora, 'YYYY-MM') AS anio_mes,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS facturacion_total
FROM categoria c
JOIN producto pr ON pr.id_categoria = c.id_categoria
JOIN detalle_pedido dp ON dp.id_producto = pr.id_producto
JOIN pedido p ON p.id_pedido = dp.id_pedido
WHERE c.activo = TRUE 
    AND pr.activo = TRUE
GROUP BY c.nombre, TO_CHAR(p.fecha_hora, 'YYYY-MM')
ORDER BY anio_mes DESC, facturacion_total DESC;

-- Ranking de usuarios por gasto
-- Tablas utilizadas: cliente, pedido y detalle_pedido
/*
    * cliente: aporta la identidad y datos del usuario (nombre, email).
    * pedido: vincula al cliente con sus transacciones realizadas y aplica el filtro de borrado lógico.
    * detalle_pedido: contiene los montos de cada línea de compra para calcular el gasto total.
*/
EXPLAIN ANALYZE
SELECT 
    cl.id_cliente,
    cl.nombre AS cliente,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS gasto_total
FROM cliente cl
JOIN pedido p ON p.id_cliente = cl.id_cliente
JOIN detalle_pedido dp ON dp.id_pedido = p.id_pedido
GROUP BY cl.id_cliente, cl.nombre
ORDER BY gasto_total DESC;

-- =============================================================================
-- OPTIMIZACIÓN DE CONSULTAS ANALÍTICAS - PRUEBA DE ÍNDICES ESTRATÉGICOS
-- Archivo: optimizaciones.sql
-- =============================================================================

/*
    JUSTIFICACIÓN TÉCNICA (Basada en los Nodos de Join):
    En los planes iniciales, el motor recurrió a 'Seq Scan' (barridos secuenciales) 
    sobre todas las tablas porque no existían rutas de acceso directo para las 
    claves foráneas involucradas en los 'Hash Joins'. 
*/

-- -----------------------------------------------------------------------------
-- LIMPIEZA TRANSACCIONAL DE ÍNDICES DE PRUEBA
-- -----------------------------------------------------------------------------
BEGIN;
    DROP INDEX IF EXISTS idx_opt_producto_categoria;
    DROP INDEX IF EXISTS idx_opt_detalle_producto;
    DROP INDEX IF EXISTS idx_opt_pedido_fecha;
    DROP INDEX IF EXISTS idx_opt_pedido_cliente;
    DROP INDEX IF EXISTS idx_opt_detalle_pedido;
COMMIT;

/*
    VEREDICTO EXPERIMENTAL:
    Los índices fueron creados para la experimentación pero finalmente se rechazan 
    y eliminan, dado que las consultas analíticas masivas priorizan 'Parallel Seq Scan' 
    para procesar agregaciones globales, volviendo inútiles los índices B-Tree en este escenario.
    [Detalle completo en DUIA.md]
*/