-- SQLBook: Code
--------------------------------------------------------------------------------
-- USO MANUAL (no ejecutar con psql -f)
-- Cada experimento se corre paso a paso en psql, dentro de una transacción:
--   BEGIN; -> baseline -> CREATE INDEX -> mismo EXPLAIN -> ROLLBACK (si corresponde)
-- Los resultados se registran en informe_mediciones.md.
--------------------------------------------------------------------------------

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
-- Índice evaluado en este experimento:
-- CREATE INDEX idx_producto_precio_stock_cubriente ON producto (precio_lista DESC, stock) INCLUDE (id_producto, nombre);

-- 0. Abrir la transacción del experimento.
-- BEGIN;

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

-- 3. Crear el índice de cobertura propuesto para productos
CREATE INDEX idx_producto_precio_stock_cubriente ON producto (precio_lista DESC, stock) INCLUDE (id_producto, nombre);

-- RESET (ejecutar solo si se desea eliminar el índice de prueba)
-- DROP INDEX IF EXISTS idx_producto_precio_stock_cubriente;

-- 4. Se vuelve a ejecutar el EXPLAIN (ANALYZE, BUFFERS) del paso 2, ahora con el índice activo.

-- 5. Cerrar el experimento: ROLLBACK elimina el índice de prueba (si corresponde).
-- ROLLBACK;

-- RESULTADO: ~41% de disminución de Exc. Time
-- Plan sugerido: Seq Scan (Nuevamente - Estamos trabajando con una tabla relativamente pequeña)
-- Tamaño: índice 3776 kB | tabla 6496 kB (el índice ocupa ~58 % de la tabla)

--------------------------------------------------------------------------------
-- ÍNDICE SIMPLE: Optimización de historial temporal de pedidos
-- Tabla: pedido (~200.000 registros)
-- Justificación: Utiliza una estructura B-Tree sobre 'fecha_hora DESC' para
-- eliminar el nodo Sort en memoria y permitir un Index Scan eficiente en rangos.
--------------------------------------------------------------------------------

-- =====================================================================
-- EXPERIMENTO DE MEDICIÓN: CONSULTA 2 (PEDIDOS)
-- =====================================================================
-- Índice evaluado en este experimento:
-- CREATE INDEX idx_pedido_fecha_hora ON pedido (fecha_hora DESC);

-- 0. Abrir la transacción del experimento.
BEGIN;

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

-- 3. Crear el índice simple propuesto para pedidos
CREATE INDEX idx_pedido_fecha_hora ON pedido (fecha_hora DESC);

-- RESET (ejecutar solo si se desea eliminar el índice de prueba)
-- DROP INDEX IF EXISTS idx_pedido_fecha_hora;

-- 4. Se vuelve a ejecutar el EXPLAIN (ANALYZE, BUFFERS) del paso 2, ahora con el índice activo.

-- 5. Cerrar el experimento: ROLLBACK elimina el índice de prueba (si corresponde).
-- ROLLBACK;

-- RESULTADO (3ª ejecución, foodstore_test, 50.000 filas; la consulta devuelve 12.487 filas, ~25 %):
-- Plan: Seq Scan + Sort (antes) -> Index Only Scan, Heap Fetches 0, sin Sort (después)
-- Execution Time (antes): 10,617 ms | Execution Time (después): 1,964 ms (~81,5 % de disminución)
-- Planning Time (antes): 0,123 ms | Planning Time (después): 0,127 ms
-- Buffers (antes): shared hit=812 | Buffers (después): shared hit=160
-- Tamaño: índice 3776 kB | tabla 6496 kB (el índice ocupa ~58 % de la tabla)

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
-- Índice evaluado en este experimento:
-- CREATE INDEX idx_cliente_nombre_cubriente ON cliente (nombre text_pattern_ops) INCLUDE (email, telefono);

-- 0. Abrir la transacción del experimento.
-- BEGIN;

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

-- 3. Crear el índice cubriente propuesto para clientes
CREATE INDEX idx_cliente_nombre_cubriente ON cliente (nombre text_pattern_ops) INCLUDE (email, telefono);

-- RESET (ejecutar solo si se desea eliminar el índice de prueba)
-- DROP INDEX IF EXISTS idx_cliente_nombre_cubriente;

-- 4. Se vuelve a ejecutar el EXPLAIN (ANALYZE, BUFFERS) del paso 2, ahora con el índice activo.

-- 5. Cerrar el experimento: ROLLBACK elimina el índice de prueba (si corresponde).
-- ROLLBACK;

-- RESULTADO (3ª ejecución, foodstore_test, 200.000 filas; la consulta devuelve ~62.200 filas, ~31 %):
-- Plan: Seq Scan + Sort externo en disco (antes) -> Index Scan sin Sort (después)
-- Execution Time (antes): 52,522 ms | Execution Time (después): 20,084 ms (~61,8 % de disminución)
-- Buffers (antes): shared hit=1471 + temp read=321 written=322 | Buffers (después): shared hit=62367
-- Tamaño: índice 4408 kB | tabla 11 MB (~40 % de la tabla)
-- Correlación de fecha_hora: -0,0026 (filas desordenadas respecto del orden físico)

--------------------------------------------------------------------------------
-- EXPERIMENTO DE COSTO EN ESCRITURAS: Inserciones masivas en detalle_pedido
-- Tabla: detalle_pedido (~300.000 registros)
-- Justificación: Evaluar el impacto en el Execution Time de un INSERT masivo 
-- (500 registros) al tener que mantener los índices B-Tree actualizados.
--------------------------------------------------------------------------------

-- =====================================================================
-- EXPERIMENTO DE MEDICIÓN: COSTO DE ESCRITURAS (INSERT MASIVOS)
-- =====================================================================
-- Índice evaluado en este experimento:
-- CREATE INDEX idx_detalle_pedido_temp ON detalle_pedido (id_pedido, id_producto);

-- 0. Abrir la transacción del experimento (siempre: EXPLAIN ANALYZE ejecuta el INSERT).
-- BEGIN;

-- 1. Actualizar estadísticas de la tabla -> No devuelve filas de datos.
ANALYZE detalle_pedido;

-- 2. MEDICIÓN DE BASELINE (Sin el índice creado)
-- Plan de ejecución y tiempo de inserción masiva pura sin overhead de índices adicionales.
EXPLAIN (
    ANALYZE,
    BUFFERS,
    FORMAT TEXT
)
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico)
SELECT 
    1 AS id_pedido,
    p.id_producto,
    2 AS cantidad,
    p.precio_lista
FROM producto p
LIMIT 500;

-- 3. Crear el índice de prueba para evaluar la penalización en escrituras (DML)
CREATE INDEX idx_detalle_pedido_temp ON detalle_pedido (id_pedido, id_producto);

-- RESET (ejecutar solo si se desea eliminar el índice de prueba)
-- DROP INDEX IF EXISTS idx_detalle_pedido_temp;

-- 4. Se vuelve a ejecutar el EXPLAIN (ANALYZE, BUFFERS) del INSERT del paso 2, ahora con el índice activo.

-- 5. Cerrar el experimento: ROLLBACK elimina el índice temporal y revierte la inserción de prueba.
-- ROLLBACK;

-- Justificación: Utiliza una estructura B-Tree con 'nombre text_pattern_ops' para
-- habilitar búsquedas LIKE con prefijo independientemente del collation de la base
-- (compara byte a byte), e incluye 'email' y 'telefono' vía INCLUDE para reducir
-- accesos a la tabla.

-- RESULTADO (3ª ejecución, foodstore_test, 20.000 filas; la consulta devuelve 1.111 filas, ~5,6 %):
-- Plan: Seq Scan + Sort (antes) -> Bitmap Index Scan + Bitmap Heap Scan + Sort (después)
-- El Sort se mantiene: el índice text_pattern_ops ordena byte a byte y la base usa Spanish_Argentina.1252.
-- No hay Index Only Scan: id_cliente no está en el índice, por lo que se accede a la tabla.
-- Execution Time (antes): 6,289 ms | Execution Time (después): 5,091 ms (~19 % de disminución)
-- Buffers (antes): shared hit=364 | Buffers (después): shared hit=41