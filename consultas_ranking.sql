-- Active: 1789077630437@@127.0.0.1@5432@foodstore_dev
-- SQLBook: Code
--------------------------------------------------------------------------------
-- Trabajo Práctico - Semana 4 - Unidad 2: Optimización de Consultas
-- Parte 3: Consultas resumen, rankings y subconsultas bajo especificación precisa
-- Esquema: Food Store
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- PARTE A: RANKING CON FUNCIÓN DE VENTANA
--------------------------------------------------------------------------------
-- Especificación:
-- «Genera una consulta SQL sobre el esquema de Food Store que devuelva, para cada 
-- cliente con al menos un pedido registrado, su nombre completo, el total 
-- gastado (suma de detalle_pedido.cantidad * precio_unitario_historico en los pedidos) 
-- y su puesto en un ranking de mayor a menor gasto, sin colapsar filas. En caso de empate, 
-- deben compartir el mismo puesto. No uses SELECT *.»

-- Versión 1: Función de ventana RANK() con JOINs y Agregación directa
-- Cost: 178ms
SELECT 
    c.nombre AS nombre_completo,
    COALESCE(SUM(dp.cantidad * dp.precio_unitario_historico), 0) AS total_gastado,
    RANK() OVER (ORDER BY COALESCE(SUM(dp.cantidad * dp.precio_unitario_historico), 0) DESC) AS puesto
FROM cliente c
JOIN pedido p ON c.id_cliente = p.id_cliente
JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
GROUP BY c.id_cliente, c.nombre
ORDER BY puesto ASC, nombre_completo ASC;

-- Versión 2: Estructura alternativa utilizando una CTE (Tabla Derivada)
-- Cost: 178ms
WITH ranking_base AS (
    SELECT 
        c.nombre AS nombre_completo,
        SUM(dp.cantidad * dp.precio_unitario_historico) AS total_gastado
    FROM cliente c
    JOIN pedido p ON c.id_cliente = p.id_cliente
    JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
    GROUP BY c.id_cliente, c.nombre
)
SELECT 
    nombre_completo,
    total_gastado,
    RANK() OVER (ORDER BY total_gastado DESC) AS puesto
FROM ranking_base
ORDER BY puesto ASC, nombre_completo ASC;

-- Verificación de equivalencia (Debe retornar 0 filas en ambas direcciones)
-- Cost: 504ms

(
    SELECT c.nombre AS nombre_completo, COALESCE(SUM(dp.cantidad * dp.precio_unitario_historico), 0) AS total_gastado, 
           RANK() OVER (ORDER BY COALESCE(SUM(dp.cantidad * dp.precio_unitario_historico), 0) DESC)
    FROM cliente c 
    JOIN pedido p ON c.id_cliente = p.id_cliente
    JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
    GROUP BY c.id_cliente, c.nombre
)
EXCEPT
(
    WITH ranking_base AS (
        SELECT c.nombre AS nombre_completo, SUM(dp.cantidad * dp.precio_unitario_historico) AS total_gastado
        FROM cliente c 
        JOIN pedido p ON c.id_cliente = p.id_cliente
        JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
        GROUP BY c.id_cliente, c.nombre
    )
    SELECT nombre_completo, total_gastado, RANK() OVER (ORDER BY total_gastado DESC) FROM ranking_base
);

-- Cost: 700ms
(
    WITH ranking_base AS (
        SELECT c.nombre AS nombre_completo, SUM(dp.cantidad * dp.precio_unitario_historico) AS total_gastado
        FROM cliente c 
        JOIN pedido p ON c.id_cliente = p.id_cliente
        JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
        GROUP BY c.id_cliente, c.nombre
    )
    SELECT nombre_completo, total_gastado, RANK() OVER (ORDER BY total_gastado DESC) FROM ranking_base
)
EXCEPT
(
    SELECT c.nombre AS nombre_completo, COALESCE(SUM(dp.cantidad * dp.precio_unitario_historico), 0) AS total_gastado, 
           RANK() OVER (ORDER BY COALESCE(SUM(dp.cantidad * dp.precio_unitario_historico), 0) DESC)
    FROM cliente c 
    JOIN pedido p ON c.id_cliente = p.id_cliente
    JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
    GROUP BY c.id_cliente, c.nombre
);


--------------------------------------------------------------------------------
-- PARTE B: SUBCONSULTA CORRELACIONADA
--------------------------------------------------------------------------------
-- Especificación:
-- «Genera una consulta SQL sobre el esquema de Food Store que devuelva los productos 
-- vigentes de categorías vigentes cuyo precio unitario sea mayor al precio promedio 
-- de los productos activos dentro de su propia categoría. Muestra categoría, producto 
-- y precio de lista, ordenados por categoría y precio descendente. No uses SELECT *.»

-- Versión 1: Subconsulta Correlacionada tradicional en el WHERE
-- Cost: 2m 31.6s

SELECT 
    cat.nombre AS categoria,
    p.nombre AS producto,
    p.precio_lista AS precio
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE p.activo = TRUE 
    AND cat.activo = TRUE
    AND p.precio_lista > (
        SELECT AVG(p_sub.precio_lista)
        FROM producto p_sub
        WHERE p_sub.id_categoria = p.id_categoria
            AND p_sub.activo = TRUE
    )
ORDER BY cat.nombre ASC, p.precio_lista DESC;

-- Versión 2: Estructura alternativa utilizando un JOIN a una tabla derivada agrupada
-- Cost: 2m 18.4s

SELECT 
    cat.nombre AS categoria,
    p.nombre AS producto,
    p.precio_lista AS precio
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
JOIN (
    SELECT id_categoria, AVG(precio_lista) AS promedio_cat
    FROM producto
    WHERE activo = TRUE
    GROUP BY id_categoria
) avg_cat ON p.id_categoria = avg_cat.id_categoria
WHERE p.activo = TRUE 
    AND cat.activo = TRUE
    AND p.precio_lista > avg_cat.promedio_cat
ORDER BY cat.nombre ASC, p.precio_lista DESC;

-- Verificación de equivalencia (Debe retornar 0 filas en ambas direcciones)
-- Cost: 2m 30.2s

(
    SELECT cat.nombre, p.nombre, p.precio_lista
    FROM producto p
    JOIN categoria cat ON p.id_categoria = cat.id_categoria
    WHERE p.activo = TRUE AND cat.activo = TRUE
        AND p.precio_lista > (
            SELECT AVG(p_sub.precio_lista) 
            FROM producto p_sub 
            WHERE p_sub.id_categoria = p.id_categoria AND p_sub.activo = TRUE
        )
)
EXCEPT
(
    SELECT cat.nombre, p.nombre, p.precio_lista
    FROM producto p
    JOIN categoria cat ON p.id_categoria = cat.id_categoria
    JOIN (
        SELECT id_categoria, AVG(precio_lista) AS promedio_cat 
        FROM producto 
        WHERE activo = TRUE 
        GROUP BY id_categoria
    ) avg_cat ON p.id_categoria = avg_cat.id_categoria
    WHERE p.activo = TRUE AND cat.activo = TRUE 
        AND p.precio_lista > avg_cat.promedio_cat
);


-- Cost: 2m 29.7s
(
    SELECT cat.nombre, p.nombre, p.precio_lista
    FROM producto p
    JOIN categoria cat ON p.id_categoria = cat.id_categoria
    JOIN (
        SELECT id_categoria, AVG(precio_lista) AS promedio_cat 
        FROM producto 
        WHERE activo = TRUE 
        GROUP BY id_categoria
    ) avg_cat ON p.id_categoria = avg_cat.id_categoria
    WHERE p.activo = TRUE AND cat.activo = TRUE 
        AND p.precio_lista > avg_cat.promedio_cat
)
EXCEPT
(
    SELECT cat.nombre, p.nombre, p.precio_lista
    FROM producto p
    JOIN categoria cat ON p.id_categoria = cat.id_categoria
    WHERE p.activo = TRUE AND cat.activo = TRUE
        AND p.precio_lista > (
            SELECT AVG(p_sub.precio_lista) 
            FROM producto p_sub 
            WHERE p_sub.id_categoria = p.id_categoria AND p_sub.activo = TRUE
        )
);