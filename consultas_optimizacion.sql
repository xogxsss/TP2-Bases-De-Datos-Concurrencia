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

-- Creamos `idx_producto_precio_stock` 
-- para acelerar los rangos de precios y existencias.
-- Pedimos el rango de precios y stock en forma descendente para evitar usar `SORT`
-- posteriormente.
CREATE INDEX idx_producto_precio_stock ON producto(precio_lista DESC, stock);

EXPLAIN ANALYZE
SELECT id_cliente, nombre, email, telefono
FROM cliente
WHERE nombre LIKE 'Cliente de Prueba 15%'
ORDER BY nombre;

-- Creamos `idx_cliente_nombre_pattern`
-- para acelerar consultas con patrones `LIKE`
-- `varchar_pattern_ops` -> Operador de clase
-- Optimiza búsquedas de texto mediante patrones prefijados.
-- Garantiza que el optimizador use Index Scan en lugar de un Seq Scan
CREATE INDEX idx_cliente_nombre_pattern ON cliente(nombre varchar_pattern_ops);


-- `EXPLAIN`
/*
  La cláusula explain sirve para generar un plan estimado y costos
  teóricos calculados por el planificador de PostgreSQL, no ejecuta la consulta.
*/

-- `EXPLAIN ANALYZE`
/*
  Combinado con `ANALYZE`, ejecutamos la consulta y contrastamos costo
  estimativo vs. costo real.

  Se utilizan en índices para:
  * Evaluación del plan
  * Medir mejoras
*/
EXPLAIN ANALYZE
SELECT id_pedido, fecha_hora, forma_pago, id_cliente
FROM pedido
WHERE fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
ORDER BY fecha_hora DESC;

-- Creamos `idx_pedido_fecha_hora`
-- para optimizar consultas e historiales ordenados por marcas de tiempo recientes.
-- Acelera la recuperación de historiales de pedidos ordenados por fecha de forma
-- cronológica inversa (más recientes a menos) para reducir el costo E/S
-- y tiempo de ejecución
CREATE INDEX idx_pedido_fecha_hora ON pedido(fecha_hora DESC);
