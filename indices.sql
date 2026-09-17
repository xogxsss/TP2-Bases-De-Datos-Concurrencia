--------------------------------------------------------------------------------
-- ÍNDICE DE COBERTURA: Optimización de consulta de filtrado y ordenamiento de productos
-- Tabla: producto (~50.000 registros)
-- Justificación: Utiliza una estructura B-Tree compuesta con 'precio_lista DESC'
-- para evitar el nodo Sort, incluye 'stock' para filtrar y la cláusula INCLUDE
-- para permitir un 'Index Only Scan', minimizando accesos al heap.
--------------------------------------------------------------------------------

-- =====================================================================
-- EXPERIMENTO DE MEDICIÓN: CONSULTA 1 (PRODUCTOS)
-- =====================================================================
-- Índice sobre el que vamos a estar trabajando:
-- CREATE INDEX idx_producto_precio_stock_cubriente ON producto (precio_lista DESC, stock) INCLUDE (id_producto, nombre);

-- 1. Actualizar estadísticas de la tabla -> No devuelve filas de datos.
ANALYZE producto;

-- 2. MEDICIÓN DE BASELINE (Sin el índice creado)
-- Plan propuesto: Seq Scan
EXPLAIN (
    ANALYZE,
    BUFFERS,
    FORMAT TEXT
)
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

-- 3.
-- Crear el índice de cobertura propuesto para productos
CREATE INDEX idx_producto_precio_stock_cubriente ON producto (precio_lista DESC, stock) INCLUDE (id_producto, nombre);

-- RESET (ejecutar solo si se desea eliminar el índice de prueba)
-- DROP INDEX IF EXISTS idx_producto_precio_stock_cubriente;

-- El ROLLBACK limpia la base de datos eliminando el índice de prueba de forma segura.

-- 4. Volvemos a ejecutar EXPLAIN ANALYZE de las líneas 21-35

-- RESULTADO: ~41% de disminución de Exc. Time
-- Plan sugerido: Seq Scan (Nuevamente - Estamos trabajando con una tabla relativamente pequeña)

--------------------------------------------------------------------------------
-- ÍNDICE SIMPLE: Optimización de historial temporal de pedidos
-- Tabla: pedido (~200.000 registros)
-- Justificación: Utiliza una estructura B-Tree sobre 'fecha_hora DESC' para
-- eliminar el nodo Sort en memoria y permitir un Index Scan eficiente en rangos.
--------------------------------------------------------------------------------

-- =====================================================================
-- EXPERIMENTO DE MEDICIÓN: CONSULTA 2 (PEDIDOS)
-- =====================================================================
-- Índice sobre el que vamos a estar trabajando:
-- CREATE INDEX idx_pedido_fecha_hora ON pedido (fecha_hora DESC);

-- 1. Actualizar estadísticas de la tabla -> No devuelve filas de datos.
ANALYZE pedido;

-- 2. MEDICIÓN DE BASELINE (Sin el índice creado)
-- Plan propuesto: Seq Scan + Sort
EXPLAIN (
    ANALYZE,
    BUFFERS,
    FORMAT TEXT
)
SELECT
    id_pedido,
    fecha_hora,
    forma_pago,
    id_cliente
FROM pedido
ORDER BY fecha_hora DESC
LIMIT 100;

-- 3.
-- Crear el índice simple propuesto para pedidos
CREATE INDEX idx_pedido_fecha_hora ON pedido (fecha_hora DESC);

-- RESET (ejecutar solo si se desea eliminar el índice de prueba)
DROP INDEX IF EXISTS idx_pedido_fecha_hora;

-- 4. Volvemos a ejecutar EXPLAIN ANALYZE de la consulta anterior

-- RESULTADO: 
-- Plan propuesto: Index Scan (Eliminación exitosa del nodo Sort)
-- Exc. Time (antes): 0,070 ms | Exc. Time (después): 0,026 ms (~63% de disminución)
-- Planning Time (antes): 0,246 ms | Planning Time (después): 0,880 ms (~257% de aumento)
-- Total (antes): 0,026 ms | Total (después): 0,013 ms (~50% de disminución)

--------------------------------------------------------------------------------
-- ÍNDICE DE COBERTURA Y OPERADOR TEXTUAL: Optimización de búsqueda por patrón
-- Tabla: cliente (~20.000 registros)
-- Justificación: Utiliza una estructura B-Tree con 'nombre text_pattern_ops'
-- para habilitar comparaciones eficientes con operadores LIKE (prefijados)
-- independientes del collation, e incluye 'email' y 'telefono' vía INCLUDE
-- para permitir un 'Index Only Scan' y evitar el nodo Sort.
--------------------------------------------------------------------------------

-- =====================================================================
-- EXPERIMENTO DE MEDICIÓN: CONSULTA 3 (CLIENTES)
-- =====================================================================
-- Índice sobre el que vamos a estar trabajando:
-- CREATE INDEX idx_cliente_nombre_cubriente ON cliente (nombre text_pattern_ops) INCLUDE (email, telefono);

-- 1. Actualizar estadísticas de la tabla -> No devuelve filas de datos.
ANALYZE cliente;

-- 2. MEDICIÓN DE BASELINE (Sin el índice creado)
-- Plan propuesto: Seq Scan + Sort
EXPLAIN (
    ANALYZE,
    BUFFERS,
    FORMAT TEXT
)
SELECT
    id_cliente,
    nombre,
    email,
    telefono
FROM cliente
WHERE
    nombre LIKE 'Cliente de Prueba 15%'
ORDER BY nombre;

-- 3.
-- Crear el índice cubriente propuesto para clientes
CREATE INDEX idx_cliente_nombre_cubriente ON cliente (nombre text_pattern_ops) INCLUDE (email, telefono);

-- RESET (ejecutar solo si se desea eliminar el índice de prueba)
-- DROP INDEX IF EXISTS idx_cliente_nombre_cubriente;

-- 4. Volvemos a ejecutar EXPLAIN ANALYZE de la consulta anterior

-- RESULTADO: 
-- Plan propuesto: Seq Scan + Sort (Ambas ejecuciones mantuvieron el escaneo secuencial debido al bajo volumen de prueba)
-- Planning Time (antes): 0,718 ms | Planning Time (después): 1,186 ms (~65% de aumento)
-- Execution Time (antes): 0,021 ms | Execution Time (después): 0,035 ms (~66% de aumento)
-- Actual total aprox. (antes): ~0,031 ms | Actual total aprox. (después): ~0,057 ms