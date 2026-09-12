-- SQLBook: Code
-- =============================================================================
-- SCRIPT DE INSERCIÓN MASIVA DE DATOS DE PRUEBA - FOOD STORE
-- Archivo: insertar_datos_masivos.sql
-- Motor: PostgreSQL
-- =============================================================================

BEGIN; -- Tratamos todas las transacciones a continuación como una sola.

-- 1. Crear tabla temporal para categorías
CREATE TEMP TABLE temp_cats AS 
SELECT id_categoria, (row_number() OVER (ORDER BY id_categoria)) - 1 AS rn
FROM categoria;
-- rn -> Contador auxiliar para posicionar 'algo'; en este caso, las categorías

-- Verificar que hay al menos una categoría para evitar divisiones por cero
DO $$
BEGIN
    IF (SELECT count(*) FROM temp_cats) = 0 THEN
        RAISE EXCEPTION 'No hay categorías en la base de datos para asociar los productos. Por favor inserta al menos una categoría en "categoria" antes de ejecutar este script.';
    END IF;
END $$;

-- 2. Inserción masiva de 50.000 productos (con sufijo aleatorio para evitar colisiones UNIQUE)
INSERT INTO producto (nombre, descripcion, precio_lista, stock, activo, id_categoria)
SELECT 
    'Producto Masivo ' || s || '_' || floor(random() * 1000000)::text AS nombre,
    'Descripción del producto masivo ' || s AS descripcion,
    (500.00 + (random() * 4500.00))::NUMERIC(10, 2) AS precio_lista,
    floor(random() * 201)::INT AS stock,
    TRUE AS activo,
    tc.id_categoria
FROM generate_series(1, 50000) AS s
JOIN temp_cats tc ON tc.rn = (s % (SELECT count(*) FROM temp_cats));

-- 3. Inserción masiva de 20.000 clientes (con prefijo temporal para evitar colisiones UNIQUE en email)
INSERT INTO cliente (email, nombre, telefono, direccion)
SELECT 
    'cliente_masivo_' || floor(extract(epoch from now()))::text || '_' || s || '@foodstore.com' AS email,
    'Cliente de Prueba ' || s AS nombre,
    '+54911' || lpad((s % 100000000)::text, 8, '0') AS telefono,
    'Dirección de Prueba ' || s AS direccion
FROM generate_series(1, 20000) AS s;

-- 4. Crear tabla temporal para clientes recién creados
CREATE TEMP TABLE temp_clis AS 
SELECT id_cliente, (row_number() OVER (ORDER BY id_cliente)) - 1 AS rn
FROM cliente;

-- 5. Inserción masiva de 200.000 pedidos capturando sus IDs de manera segura
CREATE TEMP TABLE temp_peds AS
WITH inserted_pedidos AS (
    INSERT INTO pedido (fecha_hora, forma_pago, id_cliente)
    SELECT 
        now() - (random() * interval '90 days') AS fecha_hora,
        (ARRAY['EFECTIVO', 'TARJETA', 'TRANSFERENCIA'::forma_pago_enum])[1 + floor(random() * 3)] AS forma_pago,
        tc.id_cliente
    FROM generate_series(1, 200000) AS s
    JOIN temp_clis tc ON tc.rn = (s % (SELECT count(*) FROM temp_clis))
    RETURNING id_pedido
)
SELECT id_pedido, (row_number() OVER (ORDER BY id_pedido)) - 1 AS rn FROM inserted_pedidos;

-- 6. Obtener los productos activos para los detalles de pedido
CREATE TEMP TABLE temp_prods_activos AS
SELECT id_producto, precio_lista, (row_number() OVER (ORDER BY id_producto)) - 1 AS rn
FROM producto
WHERE activo = TRUE;

-- 7. Insertar el primer detalle para cada uno de los 200000 pedidos (1 por pedido)
-- Esto garantiza que todo pedido tenga al menos un detalle de producto.
-- El id_producto se asocia de forma determinista y balanceada usando el residuo.
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico)
SELECT 
    tp.id_pedido,
    tpa.id_producto,
    1 + floor(random() * 5)::INT AS cantidad,
    tpa.precio_lista AS precio_unitario_historico
FROM temp_peds tp
JOIN temp_prods_activos tpa ON tpa.rn = (tp.rn % (SELECT count(*) FROM temp_prods_activos));

-- 8. Insertar un segundo detalle para el 50% de los pedidos (los pares)
-- El uso de (tp.rn + 1) garantiza matemáticamente que el id_producto sea diferente del primer detalle,
-- evitando violar la restricción de clave primaria compuesta (id_pedido, id_producto) de forma segura y eficiente.
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico)
SELECT 
    tp.id_pedido,
    tpa.id_producto,
    1 + floor(random() * 3)::INT AS cantidad,
    tpa.precio_lista AS precio_unitario_historico
FROM temp_peds tp
JOIN temp_prods_activos tpa ON tpa.rn = ((tp.rn + 1) % (SELECT count(*) FROM temp_prods_activos))
WHERE tp.rn % 2 = 0;

-- Limpieza de tablas temporales
DROP TABLE temp_cats;
DROP TABLE temp_clis;
DROP TABLE temp_peds;
DROP TABLE temp_prods_activos;

COMMIT; -- Si hay errores antes del commit, la transacción puede cancelarse.

-- Actualizar estadísticas del optimizador para las tablas afectadas
ANALYZE producto;
ANALYZE cliente;
ANALYZE pedido;
ANALYZE detalle_pedido;
