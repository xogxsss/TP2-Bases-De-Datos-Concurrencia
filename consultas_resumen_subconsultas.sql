-- SQLBook: Code
-- =============================================================================
-- TRABAJO PRÁCTICO N° 3 - BASES DE DATOS
-- Parte 4: Consultas resumen y subconsultas bajo especificación precisa
-- Database: foodstore_dev (PostgreSQL)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- CONSULTA 1: Resumen (Agregación con GROUP BY y HAVING)
-- Spec: Categorías con ventas totales superiores a $100.000 en el último año.
-- -----------------------------------------------------------------------------

-- Versión A: JOIN explícito tradicional con GROUP BY y HAVING
SELECT 
    c.nombre AS categoria,
    SUM(dp.cantidad) AS total_unidades,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS monto_total
FROM categoria c
JOIN producto p ON c.id_categoria = p.id_categoria
JOIN detalle_pedido dp ON p.id_producto = dp.id_producto
JOIN pedido ped ON dp.id_pedido = ped.id_pedido
WHERE ped.fecha_hora >= NOW() - INTERVAL '1 year'
GROUP BY c.id_categoria, c.nombre
HAVING SUM(dp.cantidad * dp.precio_unitario_historico) > 100000
ORDER BY monto_total DESC;

-- Versión B: Uso de CTE (Common Table Expression) para pre-agregar detalles
WITH ventas_filtradas AS (
    SELECT 
        p.id_categoria,
        SUM(dp.cantidad) AS total_unidades,
        SUM(dp.cantidad * dp.precio_unitario_historico) AS monto_total
    FROM pedido ped
    JOIN detalle_pedido dp ON ped.id_pedido = dp.id_pedido
    JOIN producto p ON dp.id_producto = p.id_producto
    WHERE ped.fecha_hora >= NOW() - INTERVAL '1 year'
    GROUP BY p.id_categoria
    HAVING SUM(dp.cantidad * dp.precio_unitario_historico) > 100000
)
SELECT 
    c.nombre AS categoria,
    vf.total_unidades,
    vf.monto_total
FROM ventas_filtradas vf
JOIN categoria c ON vf.id_categoria = c.id_categoria
ORDER BY vf.monto_total DESC;

-- Prueba de Equivalencia (Si devuelve 0 filas, las versiones A y B son 100% equivalentes)
(
    SELECT c.nombre AS categoria, SUM(dp.cantidad) AS total_unidades, SUM(dp.cantidad * dp.precio_unitario_historico) AS monto_total
    FROM categoria c JOIN producto p ON c.id_categoria = p.id_categoria JOIN detalle_pedido dp ON p.id_producto = dp.id_producto JOIN pedido ped ON dp.id_pedido = ped.id_pedido
    WHERE ped.fecha_hora >= NOW() - INTERVAL '1 year'
    GROUP BY c.id_categoria, c.nombre HAVING SUM(dp.cantidad * dp.precio_unitario_historico) > 100000
)
EXCEPT
(
    WITH ventas_filtradas AS (
        SELECT p.id_categoria, SUM(dp.cantidad) AS total_unidades, SUM(dp.cantidad * dp.precio_unitario_historico) AS monto_total
        FROM pedido ped JOIN detalle_pedido dp ON ped.id_pedido = dp.id_pedido JOIN producto p ON dp.id_producto = p.id_producto
        WHERE ped.fecha_hora >= NOW() - INTERVAL '1 year'
        GROUP BY p.id_categoria HAVING SUM(dp.cantidad * dp.precio_unitario_historico) > 100000
    )
    SELECT c.nombre AS categoria, vf.total_unidades, vf.monto_total
    FROM ventas_filtradas vf JOIN categoria c ON vf.id_categoria = c.id_categoria
);


-- -----------------------------------------------------------------------------
-- CONSULTA 2: Subconsulta (Top 10 clientes por encima del promedio global)
-- Spec: Clientes con gasto acumulado superior al promedio global de gasto.
-- -----------------------------------------------------------------------------

-- Versión A: Subconsulta dentro de la cláusula HAVING
SELECT 
    c.id_cliente,
    c.nombre,
    c.email,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS total_gastado
FROM cliente c
JOIN pedido p ON c.id_cliente = p.id_cliente
JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
GROUP BY c.id_cliente, c.nombre, c.email
HAVING SUM(dp.cantidad * dp.precio_unitario_historico) > (
    -- Subconsulta: Promedio de gasto por cliente
    SELECT AVG(sub.gasto_cliente)
    FROM (
        SELECT SUM(dp2.cantidad * dp2.precio_unitario_historico) AS gasto_cliente
        FROM pedido p2
        JOIN detalle_pedido dp2 ON p2.id_pedido = dp2.id_pedido
        GROUP BY p2.id_cliente
    ) sub
)
ORDER BY total_gastado DESC
LIMIT 10;

-- Versión B: Pre-calculando el gasto por cliente y el promedio mediante CTE
WITH gasto_por_cliente AS (
    SELECT 
        p.id_cliente,
        SUM(dp.cantidad * dp.precio_unitario_historico) AS total_gastado
    FROM pedido p
    JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
    GROUP BY p.id_cliente
),
promedio_global AS (
    SELECT AVG(total_gastado) AS promedio FROM gasto_por_cliente
)
SELECT 
    c.id_cliente,
    c.nombre,
    c.email,
    g.total_gastado
FROM gasto_por_cliente g
JOIN cliente c ON g.id_cliente = c.id_cliente
CROSS JOIN promedio_global pg
WHERE g.total_gastado > pg.promedio
ORDER BY g.total_gastado DESC
LIMIT 10;

-- Prueba de Equivalencia (Si devuelve 0 filas, las versiones A y B son 100% equivalentes)
(
    SELECT c.id_cliente, c.nombre, c.email, SUM(dp.cantidad * dp.precio_unitario_historico) AS total_gastado
    FROM cliente c JOIN pedido p ON c.id_cliente = p.id_cliente JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
    GROUP BY c.id_cliente, c.nombre, c.email
    HAVING SUM(dp.cantidad * dp.precio_unitario_historico) > (
        SELECT AVG(sub.gasto_cliente) FROM (
            SELECT SUM(dp2.cantidad * dp2.precio_unitario_historico) AS gasto_cliente FROM pedido p2 JOIN detalle_pedido dp2 ON p2.id_pedido = dp2.id_pedido GROUP BY p2.id_cliente
        ) sub
    )
    ORDER BY total_gastado DESC LIMIT 10
)
EXCEPT
(
    WITH gasto_por_cliente AS (
        SELECT p.id_cliente, SUM(dp.cantidad * dp.precio_unitario_historico) AS total_gastado FROM pedido p JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido GROUP BY p.id_cliente
    ), promedio_global AS (
        SELECT AVG(total_gastado) AS promedio FROM gasto_por_cliente
    )
    SELECT c.id_cliente, c.nombre, c.email, g.total_gastado
    FROM gasto_por_cliente g JOIN cliente c ON g.id_cliente = c.id_cliente CROSS JOIN promedio_global pg
    WHERE g.total_gastado > pg.promedio
    ORDER BY g.total_gastado DESC LIMIT 10
);