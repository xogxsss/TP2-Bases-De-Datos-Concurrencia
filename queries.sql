-- SQLBook: Code
--------------------------------------------------------------------------------
-- TRABAJO PRÁCTICO - CATÁLOGO DE CONSULTAS (queries.sql)
-- Incluye verificación de volumen, consultas analíticas, rankings, subconsultas
-- y planes de optimización (la competencia / hackathon está en la Sección 5)
-- Esquema: Food Store (PostgreSQL)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- SECCIÓN 0: VERIFICACIÓN DE VOLUMEN CARGADO
-- Se ejecuta después de schema.sql + data.sql. Los valores esperados (comentarios)
-- corresponden a la base ya cargada masivamente, partiendo de una base nueva
-- en la que data.sql se ejecutó una sola vez.
--------------------------------------------------------------------------------
SELECT 'categoria' AS tabla, COUNT(*) AS total FROM categoria -- 9
UNION ALL
SELECT 'producto', COUNT(*) FROM producto -- 50.000
UNION ALL
SELECT 'cliente', COUNT(*) FROM cliente -- 20.000
UNION ALL
SELECT 'pedido', COUNT(*) FROM pedido -- 200.000
UNION ALL
SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido; -- 300.000

--------------------------------------------------------------------------------
-- SECCIÓN 1: RANKINGS CON FUNCIONES DE VENTANA (Semana 4 / Parte 3)
--------------------------------------------------------------------------------

-- 1.1 Versión 1: Función de ventana RANK() con JOINs y Agregación directa
SELECT
    c.nombre AS nombre_completo,
    COALESCE(
        SUM(
            dp.cantidad * dp.precio_unitario_historico
        ),
        0
    ) AS total_gastado,
    RANK() OVER (
        ORDER BY COALESCE(
                SUM(
                    dp.cantidad * dp.precio_unitario_historico
                ), 0
            ) DESC
    ) AS puesto
FROM
    cliente c
    JOIN pedido p ON c.id_cliente = p.id_cliente
    JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
GROUP BY
    c.id_cliente,
    c.nombre
ORDER BY puesto ASC, nombre_completo ASC;

-- 1.2 Versión 2: Estructura alternativa utilizando una CTE (Tabla Derivada)
WITH
    ranking_base AS (
        SELECT
            c.nombre AS nombre_completo,
            SUM(
                dp.cantidad * dp.precio_unitario_historico
            ) AS total_gastado
        FROM
            cliente c
            JOIN pedido p ON c.id_cliente = p.id_cliente
            JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
        GROUP BY
            c.id_cliente,
            c.nombre
    )
SELECT
    nombre_completo,
    total_gastado,
    RANK() OVER (
        ORDER BY total_gastado DESC
    ) AS puesto
FROM ranking_base
ORDER BY puesto ASC, nombre_completo ASC;

--------------------------------------------------------------------------------
-- SECCIÓN 2: SUBCONSULTAS CORRELACIONADAS Y DERIVADAS (Semana 4 / Parte 3)
--------------------------------------------------------------------------------

-- 2.1 Versión 1: Subconsulta Correlacionada tradicional en el WHERE
SELECT
    cat.nombre AS categoria,
    p.nombre AS producto,
    p.precio_lista AS precio
FROM producto p
    JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE
    p.activo = TRUE
    AND cat.activo = TRUE
    AND p.precio_lista > (
        SELECT AVG(p_sub.precio_lista)
        FROM producto p_sub
        WHERE
            p_sub.id_categoria = p.id_categoria
            AND p_sub.activo = TRUE
    )
ORDER BY cat.nombre ASC, p.precio_lista DESC;

-- 2.2 Versión 2: Estructura alternativa utilizando un JOIN a una tabla derivada agrupada
SELECT
    cat.nombre AS categoria,
    p.nombre AS producto,
    p.precio_lista AS precio
FROM
    producto p
    JOIN categoria cat ON p.id_categoria = cat.id_categoria
    JOIN (
        SELECT id_categoria, AVG(precio_lista) AS promedio_cat
        FROM producto
        WHERE
            activo = TRUE
        GROUP BY
            id_categoria
    ) avg_cat ON p.id_categoria = avg_cat.id_categoria
WHERE
    p.activo = TRUE
    AND cat.activo = TRUE
    AND p.precio_lista > avg_cat.promedio_cat
ORDER BY cat.nombre ASC, p.precio_lista DESC;

--------------------------------------------------------------------------------
-- SECCIÓN 3: CONSULTAS RESUMEN, AGREGACIONES Y FILTROS (Semana 3-4)
--------------------------------------------------------------------------------

-- 3.1 Categorías con ventas totales superiores a $100.000 en el último año (JOIN + HAVING)
SELECT
    c.nombre AS categoria,
    SUM(dp.cantidad) AS total_unidades,
    SUM(
        dp.cantidad * dp.precio_unitario_historico
    ) AS monto_total
FROM
    categoria c
    JOIN producto p ON c.id_categoria = p.id_categoria
    JOIN detalle_pedido dp ON p.id_producto = dp.id_producto
    JOIN pedido ped ON dp.id_pedido = ped.id_pedido
WHERE
    ped.fecha_hora >= NOW() - INTERVAL '1 year'
GROUP BY
    c.id_categoria,
    c.nombre
HAVING
    SUM(
        dp.cantidad * dp.precio_unitario_historico
    ) > 100000
ORDER BY monto_total DESC;

-- 3.2 Top 10 clientes por encima del promedio global de gasto
SELECT c.id_cliente, c.nombre, c.email, SUM(
        dp.cantidad * dp.precio_unitario_historico
    ) AS total_gastado
FROM
    cliente c
    JOIN pedido p ON c.id_cliente = p.id_cliente
    JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
GROUP BY
    c.id_cliente,
    c.nombre,
    c.email
HAVING
    SUM(
        dp.cantidad * dp.precio_unitario_historico
    ) > (
        SELECT AVG(sub.gasto_cliente)
        FROM (
                SELECT SUM(
                        dp2.cantidad * dp2.precio_unitario_historico
                    ) AS gasto_cliente
                FROM pedido p2
                    JOIN detalle_pedido dp2 ON p2.id_pedido = dp2.id_pedido
                GROUP BY
                    p2.id_cliente
            ) sub
    )
ORDER BY total_gastado DESC
LIMIT 10;

--------------------------------------------------------------------------------
-- SECCIÓN 4: CONSULTAS FRECUENTES PARA PLANES DE EJECUCIÓN (EXPLAIN ANALYZE)
--------------------------------------------------------------------------------

-- 4.1 Historial de pedidos por cliente específico
EXPLAIN
ANALYZE
SELECT p.id_pedido, p.fecha_hora, p.forma_pago
FROM pedido p
WHERE
    p.id_cliente = 5000
ORDER BY p.fecha_hora DESC;

-- 4.2 Filtrado de productos por rango de precio y stock
EXPLAIN
ANALYZE
SELECT
    id_producto,
    nombre,
    precio_lista,
    stock
FROM producto
WHERE
    precio_lista BETWEEN 1000 AND 2500
    AND stock > 50
ORDER BY precio_lista DESC;

-- 4.3 Búsqueda de clientes por coincidencia de patrón de texto
EXPLAIN
ANALYZE
SELECT
    id_cliente,
    nombre,
    email,
    telefono
FROM cliente
WHERE
    nombre LIKE 'Cliente de Prueba 15%'
ORDER BY nombre;

-- 4.4 Historial temporal de pedidos en los últimos 30 días
EXPLAIN
ANALYZE
SELECT
    id_pedido,
    fecha_hora,
    forma_pago,
    id_cliente
FROM pedido
WHERE
    fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
ORDER BY fecha_hora DESC;

--------------------------------------------------------------------------------
-- SECCIÓN 5: CONSULTAS ANALÍTICAS Y COMPETENCIA DE OPTIMIZACIÓN (HACKATHON)
--------------------------------------------------------------------------------
-- Trabajo Práctico - Semana 4 - Unidad 2: Optimización de Consultas
-- Parte 4: Competencia de optimización entre equipos (Hackathon TP3)
-- Esquema: Food Store
--
-- Descripción:
-- Esta sección contiene la consulta analítica oficial de la competencia de
-- optimización (cruce masivo de 4 tablas con agregación y filtros de borrado
-- lógico) y los pasos de prueba de estrategias de indexación y reescritura.
-- Se documenta el plan de ejecución inicial, la evaluación de estrategias
-- propuestas por la IA (como índices B-Tree) y el resultado del benchmarking
-- mediante EXPLAIN ANALYZE.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 5.1 CONSULTA ANALÍTICA DE LA COMPETENCIA (Medición Inicial)
--------------------------------------------------------------------------------
-- Métrica de referencia obtenida (Execution Time): ~197.59 ms
-- Plan seleccionado por PostgreSQL: Parallel Seq Scan con Hash Joins y Parallel Hash Aggregate.

EXPLAIN
ANALYZE
SELECT
    c.nombre AS categoria,
    COUNT(p.id_pedido) AS total_pedidos,
    SUM(
        dp.cantidad * dp.precio_unitario_historico
    ) AS facturacion_total
FROM
    categoria c
    JOIN producto pr ON pr.id_categoria = c.id_categoria
    JOIN detalle_pedido dp ON dp.id_producto = pr.id_producto
    JOIN pedido p ON p.id_pedido = dp.id_pedido
WHERE
    c.activo = TRUE
    AND pr.activo = TRUE
GROUP BY
    c.nombre;

--------------------------------------------------------------------------------
-- 5.2 HACKATHON TP3 - ESTRATEGIAS SOBRE LA CONSULTA DE PRODUCTOS POR CATEGORÍA
--------------------------------------------------------------------------------
-- Nota: el enunciado original filtraba por la categoría 'Pizzas', que no existe
-- en el dataset de data.sql. Se usa 'Comidas Rápidas', que sí está cargada.
--
-- Cada estrategia que crea un índice se ejecuta dentro de BEGIN ... ROLLBACK,
-- según el protocolo de seguridad del proyecto, para no dejar índices de prueba
-- en la base de desarrollo.

-- -----------------------------------------------------------------------------
-- PASO 1: LA LÍNEA BASE (Medición Original)
-- -----------------------------------------------------------------------------
EXPLAIN
ANALYZE
SELECT p.id_producto, p.nombre, p.precio_lista, p.stock
FROM producto p
    JOIN categoria c ON p.id_categoria = c.id_categoria
WHERE
    c.nombre = 'Comidas Rápidas'
    AND p.precio_lista BETWEEN 1500 AND 4500
    AND p.activo = TRUE
ORDER BY p.stock DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- PASO 2: PROBAR ESTRATEGIA 1 (Índice Parcial Compuesto)
-- Apunta a las columnas del filtro y del ordenamiento.
-- -----------------------------------------------------------------------------
BEGIN;

CREATE INDEX idx_comp_estrategia1 ON producto (
    id_categoria,
    precio_lista,
    stock DESC
)
WHERE
    activo = TRUE;

ANALYZE producto;

-- Se vuelve a medir la misma consulta del Paso 1, ahora con el índice presente.
EXPLAIN
ANALYZE
SELECT p.id_producto, p.nombre, p.precio_lista, p.stock
FROM producto p
    JOIN categoria c ON p.id_categoria = c.id_categoria
WHERE
    c.nombre = 'Comidas Rápidas'
    AND p.precio_lista BETWEEN 1500 AND 4500
    AND p.activo = TRUE
ORDER BY p.stock DESC
LIMIT 20;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- PASO 3: PROBAR ESTRATEGIA 2 (Reescritura con Subconsulta)
-- Modifica la consulta para evitar el JOIN. No requiere índice nuevo.
-- -----------------------------------------------------------------------------
EXPLAIN
ANALYZE
SELECT
    id_producto,
    nombre,
    precio_lista,
    stock
FROM producto
WHERE
    id_categoria = (
        SELECT id_categoria
        FROM categoria
        WHERE
            nombre = 'Comidas Rápidas'
    )
    AND precio_lista BETWEEN 1500 AND 4500
    AND activo = TRUE
ORDER BY stock DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- PASO 4: PROBAR ESTRATEGIA 3 (Índice BRIN)
-- Índice pensado para datos grandes con correlación física con el orden de la
-- tabla; en este dataset se evalúa para comprobar si aporta o perjudica.
-- -----------------------------------------------------------------------------
BEGIN;

CREATE INDEX idx_comp_estrategia3 ON producto USING BRIN (precio_lista, stock);

ANALYZE producto;

-- Se vuelve a medir la misma consulta del Paso 1, ahora con el índice BRIN.
EXPLAIN
ANALYZE
SELECT p.id_producto, p.nombre, p.precio_lista, p.stock
FROM producto p
    JOIN categoria c ON p.id_categoria = c.id_categoria
WHERE
    c.nombre = 'Comidas Rápidas'
    AND p.precio_lista BETWEEN 1500 AND 4500
    AND p.activo = TRUE
ORDER BY p.stock DESC
LIMIT 20;

ROLLBACK;

--------------------------------------------------------------------------------
-- JUSTIFICACIÓN TÉCNICA Y VEREDICTO DE ÍNDICES ANALÍTICOS
--------------------------------------------------------------------------------
/*
JUSTIFICACIÓN TÉCNICA (Basada en los Nodos de Join):
En los planes iniciales, el motor recurrió a 'Seq Scan' (barridos secuenciales) 
sobre todas las tablas porque no existían rutas de acceso directo para las 
claves foráneas involucradas en los 'Hash Joins'. 
*/

-- Limpieza de índices de pruebas anteriores (si existieran en la base)
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