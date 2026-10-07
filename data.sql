-- =============================================================================
-- SCRIPT DE INSERCIÓN MASIVA DE DATOS DE PRUEBA - FOOD STORE
-- Archivo: data.sql
-- Motor: PostgreSQL
-- =============================================================================

BEGIN;

INSERT INTO
    categoria (nombre, activo)
VALUES ('Bebidas y Refrescos', TRUE),
    ('Comidas Rápidas', TRUE),
    ('Almacén General', TRUE),
    ('Snacks y Golosinas', TRUE),
    (
        'Panificados y Repostería',
        TRUE
    ),
    ('Lácteos y Fiambrería', TRUE),
    ('Frutas y Verduras', TRUE),
    ('Carnicería y Granja', TRUE),
    ('Congelados', TRUE)
ON CONFLICT (nombre) DO NOTHING;

COMMIT;

BEGIN;
-- Tratamos todas las transacciones a continuación como una sola.
SELECT setseed(0.5);
/*
Se fija la semilla de `random()` para que los valores generados función
(precio_lista, stock, cantidades y sufijos de nombre) tiendan a repetirse entre
cargas, con el objetivo de facilitar la comparación de mediciones.

No es una reproducibilidad exacta: fecha_hora y el email dependen de `now()`, por
lo que cambian en cada carga. Además, el orden en que se evalúa `random()` puede variar
según el plan de ejecución.
*/

-- 1. Crear tabla temporal para categorías
DROP TABLE IF EXISTS temp_cats;
CREATE TEMP TABLE temp_cats AS
SELECT id_categoria, (
        row_number() OVER (
            ORDER BY id_categoria
        )
    ) - 1 AS rn
FROM categoria;
-- rn -> Índice numérico base 0 (ROW_NUMBER() - 1) utilizado para asociar registros
-- mediante el operador módulo (%) y lograr una distribución equitativa de claves foráneas.

-- Verificar que hay al menos una categoría para evitar divisiones por cero
DO $$
BEGIN
    IF (SELECT count(*) FROM temp_cats) = 0 THEN
        RAISE EXCEPTION 'No hay categorías en la base de datos para asociar los productos. Por favor inserta al menos una categoría en "categoria" antes de ejecutar este script.';
    END IF;
END $$;

-- 2. Inserción masiva de 50.000 productos (con sufijo aleatorio para evitar colisiones UNIQUE)
INSERT INTO
    producto (
        nombre,
        descripcion,
        precio_lista,
        stock,
        activo,
        id_categoria
    )
SELECT
    'Producto Masivo ' || s || '_' || floor(random() * 1000000)::text AS nombre,
    'Descripción del producto masivo ' || s AS descripcion,
    (500.00 + (random() * 4500.00))::NUMERIC(10, 2) AS precio_lista,
    floor(random() * 201)::INT AS stock,
    TRUE AS activo,
    tc.id_categoria
FROM generate_series(1, 50000) AS s
    JOIN temp_cats tc ON tc.rn = (
        s % (
            SELECT count(*)
            FROM temp_cats
        )
    )
ON CONFLICT (nombre) DO NOTHING;

-- 3. Inserción masiva de 20.000 clientes (con prefijo temporal para evitar colisiones UNIQUE en email)
INSERT INTO
    cliente (
        email,
        nombre,
        telefono,
        direccion
    )
SELECT
    'cliente_masivo_' || floor(
        extract(
            epoch
            from now()
        )
    )::text || '_' || s || '@foodstore.com' AS email,
    'Cliente de Prueba ' || s AS nombre,
    '+54911' || lpad((s % 100000000)::text, 8, '0') AS telefono,
    'Dirección de Prueba ' || s AS direccion
FROM generate_series(1, 20000) AS s
ON CONFLICT (email) DO NOTHING;

-- 4. Crear tabla temporal para clientes recién creados
DROP TABLE IF EXISTS temp_clis;
CREATE TEMP TABLE temp_clis AS
SELECT id_cliente, (
        row_number() OVER (
            ORDER BY id_cliente
        )
    ) - 1 AS rn
FROM cliente;

-- 5. Inserción masiva de 200.000 pedidos capturando sus IDs de manera segura
DROP TABLE IF EXISTS temp_peds;
CREATE TEMP TABLE temp_peds AS
WITH
    inserted_pedidos AS (
        INSERT INTO
            pedido (
                fecha_hora,
                forma_pago,
                id_cliente
            )
        SELECT now() - (random() * interval '90 days') AS fecha_hora, (
                ARRAY[
                    'EFECTIVO', 'TARJETA', 'TRANSFERENCIA'::forma_pago_enum
                ]
            ) [1 + floor(random() * 3)] AS forma_pago, tc.id_cliente
        FROM generate_series(1, 200000) AS s
            JOIN temp_clis tc ON tc.rn = (
                s % (
                    SELECT count(*)
                    FROM temp_clis
                )
            )
        RETURNING
            id_pedido
    )
SELECT id_pedido, (
        row_number() OVER (
            ORDER BY id_pedido
        )
    ) - 1 AS rn
FROM inserted_pedidos;

-- 6. Obtener los productos activos para los detalles de pedido
DROP TABLE IF EXISTS temp_prods_activos;
CREATE TEMP TABLE temp_prods_activos AS
SELECT id_producto, precio_lista, (
        row_number() OVER (
            ORDER BY id_producto
        )
    ) - 1 AS rn
FROM producto
WHERE
    activo = TRUE;

-- 7. Insertar el primer detalle para cada uno de los 200000 pedidos (1 por pedido)
-- Esto garantiza que todo pedido tenga al menos un detalle de producto.
-- El id_producto se asocia de forma determinista y balanceada usando el residuo.
INSERT INTO
    detalle_pedido (
        id_pedido,
        id_producto,
        cantidad,
        precio_unitario_historico
    )
SELECT
    tp.id_pedido,
    tpa.id_producto,
    1 + floor(random() * 5)::INT AS cantidad,
    tpa.precio_lista AS precio_unitario_historico
FROM
    temp_peds tp
    JOIN temp_prods_activos tpa ON tpa.rn = (
        tp.rn % (
            SELECT count(*)
            FROM temp_prods_activos
        )
    );

-- 8. Insertar un segundo detalle para el 50% de los pedidos (los pares)
-- El uso de (tp.rn + 1) garantiza matemáticamente que el id_producto sea diferente del primer detalle,
-- evitando violar la restricción de clave primaria compuesta (id_pedido, id_producto) de forma segura y eficiente.
INSERT INTO
    detalle_pedido (
        id_pedido,
        id_producto,
        cantidad,
        precio_unitario_historico
    )
SELECT
    tp.id_pedido,
    tpa.id_producto,
    1 + floor(random() * 3)::INT AS cantidad,
    tpa.precio_lista AS precio_unitario_historico
FROM
    temp_peds tp
    JOIN temp_prods_activos tpa ON tpa.rn = (
        (tp.rn + 1) % (
            SELECT count(*)
            FROM temp_prods_activos
        )
    )
WHERE
    tp.rn % 2 = 0;

-- Si hay errores antes del commit, la transacción puede cancelarse.
COMMIT;

-- Actualizar estadísticas del optimizador para las tablas afectadas
ANALYZE producto;
ANALYZE cliente;
ANALYZE pedido;
ANALYZE detalle_pedido;

-- =============================================================================
-- BLOQUE 2: DATOS DE PRUEBA ADICIONALES
-- Pedidos del dia actual (para EXPLAIN ANALYZE Top 5 categorias)
-- + registros FNBC (deposito, lote, responsable_control, control_lote_almacen)
-- =============================================================================

BEGIN;

SELECT setseed(0.7);

-- Tablas temporales de apoyo: DROP previo garantiza idempotencia
DROP TABLE IF EXISTS tmp_prods;
CREATE TEMP TABLE tmp_prods AS
SELECT id_producto, precio_lista,
       (row_number() OVER (ORDER BY id_producto)) - 1 AS rn
FROM producto WHERE activo = TRUE;

DROP TABLE IF EXISTS tmp_clis;
CREATE TEMP TABLE tmp_clis AS
SELECT id_cliente,
       (row_number() OVER (ORDER BY id_cliente)) - 1 AS rn
FROM cliente;

-- 3.000 pedidos con fecha_hora = hoy (necesarios para el Top 5)
DROP TABLE IF EXISTS tmp_peds_hoy;
CREATE TEMP TABLE tmp_peds_hoy AS
WITH ins AS (
    INSERT INTO pedido (fecha_hora, forma_pago, id_cliente)
    SELECT
        CURRENT_DATE + (random() * interval '23 hours 59 minutes') AS fecha_hora,
        (ARRAY['EFECTIVO','TARJETA','TRANSFERENCIA']::forma_pago_enum[])
            [1 + (s % 3)] AS forma_pago,
        tc.id_cliente
    FROM generate_series(1, 3000) AS s
    JOIN tmp_clis tc ON tc.rn = (s % (SELECT count(*) FROM tmp_clis))
    RETURNING id_pedido
)
SELECT id_pedido,
       (row_number() OVER (ORDER BY id_pedido)) - 1 AS rn
FROM ins;

-- Detalle: 1 item garantizado por pedido
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico)
SELECT
    tp.id_pedido,
    tpa.id_producto,
    1 + floor(random() * 4)::INT,
    tpa.precio_lista
FROM tmp_peds_hoy tp
JOIN tmp_prods tpa ON tpa.rn = (tp.rn % (SELECT count(*) FROM tmp_prods));

-- Detalle: 2do item para el 60% de los pedidos (offset +1 evita PK duplicada)
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico)
SELECT
    tp.id_pedido,
    tpa.id_producto,
    1 + floor(random() * 3)::INT,
    tpa.precio_lista
FROM tmp_peds_hoy tp
JOIN tmp_prods tpa ON tpa.rn = ((tp.rn + 1) % (SELECT count(*) FROM tmp_prods))
WHERE tp.rn % 5 != 0;

-- Detalle: 3er item para el 30% de los pedidos (offset +2)
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico)
SELECT
    tp.id_pedido,
    tpa.id_producto,
    1 + floor(random() * 2)::INT,
    tpa.precio_lista
FROM tmp_peds_hoy tp
JOIN tmp_prods tpa ON tpa.rn = ((tp.rn + 2) % (SELECT count(*) FROM tmp_prods))
WHERE tp.rn % 3 = 0;

-- Detalle: 4to item para el 10% de los pedidos (offset +3)
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico)
SELECT
    tp.id_pedido,
    tpa.id_producto,
    1,
    tpa.precio_lista
FROM tmp_peds_hoy tp
JOIN tmp_prods tpa ON tpa.rn = ((tp.rn + 3) % (SELECT count(*) FROM tmp_prods))
WHERE tp.rn % 10 = 0;

-- FNBC: deposito, ids 32-36
INSERT INTO deposito (id, nombre, ubicacion, capacidad)
VALUES
    (32, 'Deposito Norte',      'Las Heras',   8000),
    (33, 'Deposito Este',       'Guaymallen',  6000),
    (34, 'Deposito Oeste',      'Lujan',       4500),
    (35, 'Deposito Mayorista',  'Maipu',      12000),
    (36, 'Deposito Frigorifico','Godoy Cruz',  3000)
ON CONFLICT (id) DO NOTHING;

-- FNBC: lote, ids 504-508, fechas en 2027
INSERT INTO lote (id, codigo_producto, fecha_vencimiento)
VALUES
    (504, 'PROD-04', '2027-08-15'),
    (505, 'PROD-05', '2027-09-01'),
    (506, 'PROD-06', '2027-06-30'),
    (507, 'PROD-07', '2027-03-20'),
    (508, 'PROD-08', '2027-11-28')
ON CONFLICT (id) DO NOTHING;

-- FNBC: responsable_control, ids 803-807
INSERT INTO responsable_control (id, dni, mail, nombre_completo)
VALUES
    (803, '28500111', 'lucia@foodstore.com',   'Lucia Martinez'),
    (804, '31200222', 'pedro@foodstore.com',   'Pedro Sanchez'),
    (805, '25700333', 'sofia@foodstore.com',   'Sofia Romero'),
    (806, '33100444', 'matias@foodstore.com',  'Matias Torres'),
    (807, '29900555', 'valeria@foodstore.com', 'Valeria Diaz')
ON CONFLICT (id) DO NOTHING;

-- FNBC: control_lote_almacen
-- DF2 visible: responsable 803 aparece en lotes 504 y 505 con mismo
-- deposito 32, replicando la anomalia de actualizacion del enunciado.
INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
VALUES
    (504, 32, 803),
    (505, 32, 803),
    (506, 33, 804),
    (507, 34, 805),
    (508, 35, 806)
ON CONFLICT DO NOTHING;

COMMIT;

-- Actualizar estadisticas para que el optimizador vea los nuevos datos
ANALYZE pedido;
ANALYZE detalle_pedido;

-- =============================================================================
-- LIMPIEZA DE TABLAS TEMPORALES
-- Se agregan DROP IF EXISTS antes de cada CREATE TEMP TABLE para garantizar
-- idempotencia en reejecutar. Los DROP al final son referencia documentada;
-- las tablas TEMP se eliminan solas al cerrar la sesion de psql.
-- =============================================================================

-- Bloque 1
-- DROP TABLE IF EXISTS temp_cats;
-- DROP TABLE IF EXISTS temp_clis;
-- DROP TABLE IF EXISTS temp_peds;
-- DROP TABLE IF EXISTS temp_prods_activos;

-- Bloque 2
-- DROP TABLE IF EXISTS tmp_prods;
-- DROP TABLE IF EXISTS tmp_clis;
-- DROP TABLE IF EXISTS tmp_peds_hoy;
