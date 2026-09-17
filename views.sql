--------------------------------------------------------------------------------
-- VISTAS PARA LOS REPORTES Y CONSULTAS DEL SISTEMA - FOODSTORE
-- Parte B: Implementación de vistas transaccionales y analíticas
--------------------------------------------------------------------------------

-- =====================================================================
-- 1. VISTA: vw_productos_vigentes
-- Descripción: Expone los productos activos de la tienda junto con su categoría.
-- =====================================================================
CREATE OR REPLACE VIEW vw_productos_vigentes AS
SELECT 
    p.id_producto,
    p.nombre AS producto_nombre,
    p.precio_lista,
    p.stock,
    c.id_categoria,
    c.nombre AS categoria_nombre
FROM producto p
INNER JOIN categoria c ON p.id_categoria = c.id_categoria
WHERE p.activo = TRUE;


-- =====================================================================
-- 2. VISTA: vw_pedidos_cliente_segura
-- Descripción: Relaciona los pedidos con los datos de sus clientes.
-- CRITERIO DE SEGURIDAD Y PRIVACIDAD: Se omite explícitamente la columna 
-- 'direccion' (datos personales sensibles) de la tabla cliente. 
-- Esto permite otorgar permisos de SELECT exclusivos sobre esta vista 
-- a roles de reportes sin exponer información privada ni la tabla base.
-- =====================================================================
CREATE OR REPLACE VIEW vw_pedidos_cliente_segura AS
SELECT 
    p.id_pedido,
    p.fecha_hora,
    p.forma_pago,
    c.id_cliente,
    c.nombre AS cliente_nombre,
    c.email AS cliente_email,
    c.telefono AS cliente_telefono
FROM pedido p
INNER JOIN cliente c ON p.id_cliente = c.id_cliente;


-- =====================================================================
-- 3. VISTA: vw_detalle_pedido_completo
-- Descripción: Muestra el desglose de los ítems de un pedido incorporando
-- el nombre actual del producto, la cantidad, el precio histórico y el subtotal.
-- =====================================================================
CREATE OR REPLACE VIEW vw_detalle_pedido_completo AS
SELECT 
    dp.id_pedido,
    dp.id_producto,
    prod.nombre AS producto_nombre,
    dp.cantidad,
    dp.precio_unitario_historico,
    (dp.cantidad * dp.precio_unitario_historico) AS subtotal
FROM detalle_pedido dp
INNER JOIN producto prod ON dp.id_producto = prod.id_producto;


--------------------------------------------------------------------------------
-- VERIFICACIÓN DE EQUIVALENCIA DE VISTAS (EXCEPT)
-- Criterio: Ambas direcciones de comparación deben retornar exactamente 0 filas.
--------------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- Verificación 1: vw_productos_vigentes vs Consulta Nativa
-- -----------------------------------------------------------------------------
-- Dirección A (Vista menos Consulta Nativa)
SELECT * FROM vw_productos_vigentes
EXCEPT
SELECT 
    p.id_producto, p.nombre, p.precio_lista, p.stock, c.id_categoria, c.nombre
FROM producto p
INNER JOIN categoria c ON p.id_categoria = c.id_categoria
WHERE p.activo = TRUE;

-- Dirección B (Consulta Nativa menos Vista)
SELECT 
    p.id_producto, p.nombre, p.precio_lista, p.stock, c.id_categoria, c.nombre
FROM producto p
INNER JOIN categoria c ON p.id_categoria = c.id_categoria
WHERE p.activo = TRUE
EXCEPT
SELECT * FROM vw_productos_vigentes;


-- -----------------------------------------------------------------------------
-- Verificación 2: vw_pedidos_cliente_segura vs Consulta Nativa
-- -----------------------------------------------------------------------------
SELECT * FROM vw_pedidos_cliente_segura
EXCEPT
SELECT 
    p.id_pedido, p.fecha_hora, p.forma_pago, c.id_cliente, c.nombre, c.email, c.telefono
FROM pedido p
INNER JOIN cliente c ON p.id_cliente = c.id_cliente;

SELECT 
    p.id_pedido, p.fecha_hora, p.forma_pago, c.id_cliente, c.nombre, c.email, c.telefono
FROM pedido p
INNER JOIN cliente c ON p.id_cliente = c.id_cliente
EXCEPT
SELECT * FROM vw_pedidos_cliente_segura;


-- -----------------------------------------------------------------------------
-- Verificación 3: vw_detalle_pedido_completo vs Consulta Nativa
-- -----------------------------------------------------------------------------
SELECT * FROM vw_detalle_pedido_completo
EXCEPT
SELECT 
    dp.id_pedido, dp.id_producto, prod.nombre, dp.cantidad, dp.precio_unitario_historico, (dp.cantidad * dp.precio_unitario_historico)
FROM detalle_pedido dp
INNER JOIN producto prod ON dp.id_producto = prod.id_producto;

SELECT 
    dp.id_pedido, dp.id_producto, prod.nombre, dp.cantidad, dp.precio_unitario_historico, (dp.cantidad * dp.precio_unitario_historico)
FROM detalle_pedido dp
INNER JOIN producto prod ON dp.id_producto = prod.id_producto
EXCEPT
SELECT * FROM vw_detalle_pedido_completo;


--------------------------------------------------------------------------------
-- CONFIGURACIÓN DE SEGURIDAD: Rol para Reportes Seguros
-- Justificación: Implementa el principio de privilegio mínimo, permitiendo 
-- consultar únicamente la vista segura que omite datos personales sensibles (PII).
--------------------------------------------------------------------------------

-- 1. Crear el rol de reportes en el motor (ejecutar solo si no existe)
CREATE ROLE rol_reportes;

-- 2. Otorgar permisos de conexión a la base de datos y uso del esquema público
GRANT CONNECT ON DATABASE foodstore_dev TO rol_reportes;
GRANT USAGE ON SCHEMA public TO rol_reportes;

-- 3. Otorgar permisos de lectura exclusivamente sobre la vista segura
-- (Esto permite consultar los pedidos y clientes sin dar acceso a las tablas base)
GRANT SELECT ON vw_pedidos_cliente_segura TO rol_reportes;