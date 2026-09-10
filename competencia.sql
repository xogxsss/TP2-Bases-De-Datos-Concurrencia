-- SQLBook: Code
-- =============================================================================
-- HACKATHON TP3 - COMPETENCIA DE OPTIMIZACIÓN
-- Archivo de pruebas: competencia.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PASO 1: LA LÍNEA BASE (Medición Original)
-- -----------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT p.id_producto, p.nombre, p.precio_lista, p.stock
FROM producto p
JOIN categoria c ON p.id_categoria = c.id_categoria
WHERE c.nombre = 'Pizzas' 
  AND p.precio_lista BETWEEN 1500 AND 4500
  AND p.activo = TRUE
ORDER BY p.stock DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- PASO 2: PROBAR ESTRATEGIA 1 (Índice Parcial Compuesto)
-- Apunta a las columnas exactas del filtro y ordenamiento.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_comp_estrategia1 
ON producto (id_categoria, precio_lista, stock DESC) 
WHERE activo = TRUE;

-- (Volvemos a correr el EXPLAIN ANALYZE del Paso 1 para ver si mejoró)
-- Anotamos el resultado
-- Corremos: 
-- DROP INDEX idx_comp_estrategia1;

-- -----------------------------------------------------------------------------
-- PASO 3: PROBAR ESTRATEGIA 2 (Reescritura con Subconsulta)
-- Modifica la consulta para evitar el JOIN gigante. No requiere índice nuevo.
-- -----------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT id_producto, nombre, precio_lista, stock
FROM producto 
WHERE id_categoria = (SELECT id_categoria FROM categoria WHERE nombre = 'Pizzas')
  AND precio_lista BETWEEN 1500 AND 4500
  AND activo = TRUE
ORDER BY stock DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- PASO 4: PROBAR ESTRATEGIA 3 (Índice BRIN - Cuidado, puede ser trampa)
-- Usa un bloque diseñado para Big Data secuencial.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_comp_estrategia3 
ON producto USING BRIN (precio_lista, stock);

-- (Corremos EXPLAIN ANALYZE del Paso 1 para ver qué daño o mejora causó)
-- Corremos:
--  DROP INDEX idx_comp_estrategia3;

