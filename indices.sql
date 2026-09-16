--------------------------------------------------------------------------------
-- ÍNDICE DE COBERTURA: Optimización de consulta de filtrado y ordenamiento de productos
-- Tabla: producto (~50.000 registros)
-- Justificación: Utiliza una estructura B-Tree compuesta con 'precio_lista DESC' 
-- para evitar el nodo Sort, incluye 'stock' para filtrar y la cláusula INCLUDE 
-- para permitir un 'Index Only Scan', minimizando accesos al heap.
--------------------------------------------------------------------------------
CREATE INDEX idx_producto_precio_stock_cubriente
ON producto (precio_lista DESC, stock)
INCLUDE (id_producto, nombre);

