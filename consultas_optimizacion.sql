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

