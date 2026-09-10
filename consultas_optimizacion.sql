-- SQLBook: Code
-- Consulta 1: Historial de pedidos por cliente
EXPLAIN ANALYZE
SELECT p.id_pedido, p.fecha_hora, p.forma_pago
FROM pedido p
WHERE p.id_cliente = 5000
ORDER BY p.fecha_hora DESC;

EXPLAIN ANALYZE
SELECT id_producto, nombre, precio_lista, stock
FROM producto
WHERE precio_lista BETWEEN 1000 AND 2500
  AND stock > 50
ORDER BY precio_lista DESC;

CREATE INDEX idx_producto_precio_stock ON producto(precio_lista DESC, stock);

EXPLAIN ANALYZE
SELECT id_cliente, nombre, email, telefono
FROM cliente
WHERE nombre LIKE 'Cliente de Prueba 15%'
ORDER BY nombre;

CREATE INDEX idx_cliente_nombre_pattern ON cliente(nombre varchar_pattern_ops);

EXPLAIN ANALYZE
SELECT id_pedido, fecha_hora, forma_pago, id_cliente
FROM pedido
WHERE fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
ORDER BY fecha_hora DESC;

CREATE INDEX idx_pedido_fecha_hora ON pedido(fecha_hora DESC);
