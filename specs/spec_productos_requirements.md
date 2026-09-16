# Requirements Document

## Introduction

Esta especificación define los requisitos técnicos para la optimización de la consulta de filtrado y ordenamiento sobre la tabla `producto` del sistema FoodStore en PostgreSQL. La tabla contiene aproximadamente 50.000 registros y la consulta objetivo aplica filtros de rango sobre `precio_lista` y `stock`, con ordenamiento descendente por `precio_lista`. El plan de ejecución actual incurre en un Seq Scan completo seguido de un nodo Sort en memoria, lo que representa un cuello de botella de rendimiento en entornos de producción. El objetivo es validar experimentalmente si un índice B-Tree compuesto elimina ambos nodos costosos y reduce el Execution Time de forma medible.

---

## Glossary

- **Optimizador**: El planificador de consultas de PostgreSQL (`pg_optimizer`) que selecciona el plan de ejecución físico para cada consulta.
- **EXPLAIN_ANALYZE**: Instrucción de PostgreSQL que ejecuta la consulta y devuelve el plan físico real con métricas de Planning Time, Execution Time, filas estimadas y filas reales.
- **Seq_Scan**: Nodo de plan que lee la tabla completa de forma secuencial, registro a registro, sin usar ninguna estructura de índice.
- **Index_Scan**: Nodo de plan que recorre un índice B-Tree para acceder directamente a las filas que satisfacen el predicado, evitando el barrido completo de la tabla.
- **Bitmap_Index_Scan**: Nodo de plan que construye un mapa de bits con los punteros de fila obtenidos del índice antes de acceder al heap, eficiente para selectividades medias.
- **Sort**: Nodo de plan que ordena el resultado en memoria (o en disco si supera `work_mem`) para satisfacer una cláusula `ORDER BY`.
- **Planning_Time**: Tiempo, en milisegundos, que el Optimizador invierte en generar el plan de ejecución.
- **Execution_Time**: Tiempo, en milisegundos, que PostgreSQL tarda en ejecutar físicamente el plan y devolver todas las filas.
- **Índice_B-Tree_Compuesto**: Estructura de árbol B sobre dos o más columnas. El orden de las columnas y la dirección de ordenamiento (`ASC`/`DESC`) determinan qué predicados y cláusulas `ORDER BY` puede satisfacer directamente.
- **Índice_Parcial**: Índice que incluye únicamente las filas que cumplen una condición `WHERE` definida en la cláusula `CREATE INDEX ... WHERE`, reduciendo su tamaño y mantenimiento.
- **Baseline**: Medición de referencia del plan de ejecución y las métricas de tiempo obtenida antes de aplicar cualquier cambio estructural (creación de índice).
- **Cobertura_de_Índice**: Propiedad de un índice de incluir todas las columnas necesarias para resolver el predicado sin acceder al heap de la tabla.

---

## Requirements

### Requisito 1: Diagnóstico del cuello de botella actual

**User Story:** Como DBA del proyecto FoodStore, quiero identificar con precisión el nodo de plan costoso en la consulta de filtrado de productos, para tener una línea base experimental que justifique la intervención de indexación.

#### Criterios de Aceptación

1. IF no existe ningún índice cuyas columnas cubran el predicado `precio_lista BETWEEN 1000 AND 2500 AND stock > 50`, THEN THE Optimizador SHALL seleccionar un nodo Seq_Scan sobre la tabla `producto` como método de acceso principal, verificable mediante `EXPLAIN` sobre la consulta objetivo: `SELECT id_producto, nombre, precio_lista, stock FROM producto WHERE precio_lista BETWEEN 1000 AND 2500 AND stock > 50 ORDER BY precio_lista DESC`.

2. IF no existe un índice con `precio_lista` definido en dirección `DESC` como columna líder, THEN THE Optimizador SHALL incluir un nodo Sort en el plan de ejecución para satisfacer la cláusula `ORDER BY precio_lista DESC`, verificable como un nodo `Sort` explícito en la salida de `EXPLAIN`.

3. WHEN se ejecuta `EXPLAIN (ANALYZE, BUFFERS)` sobre la consulta objetivo sin el índice propuesto en al menos 3 ejecuciones consecutivas, THE EXPLAIN_ANALYZE SHALL reportar un Execution_Time mayor a 0.00 ms en cada ejecución, registrándose el valor de la tercera ejecución (post-cache) como la referencia de baseline.

4. WHEN el plan de ejecución contiene un nodo Seq_Scan, THE Optimizador SHALL mostrar en la salida de `EXPLAIN` un campo `cost` de inicio mayor a `0.00`, comparación que se realiza deshabilitando temporalmente el Seq_Scan con `SET enable_seqscan = off` y ejecutando `EXPLAIN` nuevamente para obtener el costo del plan alternativo con Index_Scan.

5. IF el índice `idx_producto_categoria_activo` está presente pero no incluye las columnas `precio_lista` ni `stock` en su definición, THEN THE Optimizador SHALL ignorar ese índice para la consulta objetivo y el plan reportado por `EXPLAIN` SHALL mostrar Seq_Scan como nodo de acceso a `producto`, sin ningún nodo Index_Scan ni Bitmap_Index_Scan referenciando `idx_producto_categoria_activo`.

---

### Requisito 2: Hipótesis de indexación con B-Tree compuesto

**User Story:** Como DBA del proyecto FoodStore, quiero proponer y justificar un índice B-Tree compuesto sobre `(precio_lista DESC, stock)`, para que el Optimizador pueda satisfacer el predicado y el ordenamiento de la consulta objetivo sin nodos Seq_Scan ni Sort.

#### Criterios de Aceptación

1. THE Sistema_de_Indexación SHALL permitir la creación de un índice B-Tree compuesto sobre las columnas `(precio_lista DESC, stock)` de la tabla `producto` mediante la siguiente instrucción:
   ```sql
   CREATE INDEX idx_producto_precio_stock
   ON producto (precio_lista DESC, stock);
   ```

2. WHEN el índice `idx_producto_precio_stock` existe y la consulta filtra `precio_lista BETWEEN 1000 AND 2500`, THE plan de ejecución reportado por EXPLAIN_ANALYZE SHALL mostrar un nodo Index_Scan o Bitmap_Index_Scan referenciando `idx_producto_precio_stock` como método de acceso a la tabla `producto`, sin un nodo Seq_Scan.

3. WHEN el índice está definido con `precio_lista DESC` como primera columna, THE plan de ejecución reportado por EXPLAIN_ANALYZE SHALL no contener ningún nodo Sort, dado que el orden del índice satisface directamente la cláusula `ORDER BY precio_lista DESC` sin reordenamiento adicional en memoria.

4. WHEN `stock` es la segunda columna del índice compuesto, THE plan de ejecución reportado por EXPLAIN_ANALYZE SHALL mostrar el predicado `stock > 50` como una condición de índice (`Index Cond`) o filtro aplicado durante el recorrido del índice, reduciendo el número de heap tuple fetches visible en el contador `rows` del nodo de acceso respecto al total de filas de la tabla.

5. IF la selectividad combinada de los predicados `precio_lista BETWEEN 1000 AND 2500 AND stock > 50` descarta menos del 85% de las 50.000 filas (es decir, retorna más de ~7.500 filas), THEN THE Optimizador PUEDE legítimamente preferir Seq_Scan sobre Index_Scan por razones de costo, lo cual constituye un comportamiento aceptable del planificador y no un defecto del índice, conforme a lo establecido en el Requisito 4.

6. WHERE se requiera limitar el tamaño del índice a filas activas únicamente, THE Sistema_de_Indexación SHALL soportar la variante de índice parcial:
   ```sql
   CREATE INDEX idx_producto_precio_stock_activo
   ON producto (precio_lista DESC, stock)
   WHERE activo = TRUE;
   ```
   En ese caso, la consulta optimizada deberá incluir el predicado `AND activo = TRUE` para que el Optimizador pueda elegir el índice parcial.

7. WHEN se crea el índice `idx_producto_precio_stock` o su variante parcial, THE Sistema_de_Indexación SHALL ejecutar `ANALYZE producto` inmediatamente después para actualizar las estadísticas de la tabla antes de ejecutar cualquier medición de EXPLAIN_ANALYZE, garantizando que el Optimizador tome decisiones basadas en estadísticas actualizadas.

---

### Requisito 3: Plan de evaluación experimental (EXPLAIN ANALYZE)

**User Story:** Como DBA del proyecto FoodStore, quiero un procedimiento de evaluación reproducible con EXPLAIN ANALYZE, para comparar el plan de ejecución y las métricas de tiempo antes y después de crear el índice propuesto.

#### Criterios de Aceptación

1. WHEN el procedimiento de evaluación se inicia, THE Procedimiento_de_Evaluación SHALL ejecutar el siguiente bloque como medición de baseline antes de crear el índice:
   ```sql
   EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
   SELECT id_producto, nombre, precio_lista, stock
   FROM producto
   WHERE precio_lista BETWEEN 1000 AND 2500
     AND stock > 50
   ORDER BY precio_lista DESC;
   ```

2. WHEN se obtiene la medición de baseline, THE Procedimiento_de_Evaluación SHALL registrar los siguientes valores como referencia:
   - Nodo de acceso a la tabla (Seq_Scan, Index_Scan o Bitmap_Index_Scan).
   - Presencia o ausencia del nodo Sort.
   - Planning_Time (ms).
   - Execution_Time (ms).
   - Filas estimadas vs. filas reales reportadas por EXPLAIN_ANALYZE.

3. WHEN se crea el índice propuesto, THE Procedimiento_de_Evaluación SHALL ejecutar la misma instrucción `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` sobre la consulta objetivo sin modificar los parámetros del planificador `enable_seqscan`, `enable_indexscan`, `enable_bitmapscan` ni `work_mem` respecto a sus valores de sesión al momento de la medición de baseline.

4. THE Procedimiento_de_Evaluación SHALL ejecutar la consulta de EXPLAIN_ANALYZE al menos dos veces consecutivas e inmediatas (sin consultas intermedias sobre `producto`) después de crear el índice, registrando el Execution_Time de la primera ejecución como medición en frío (cold cache) y el de la segunda como medición en caliente (warm cache).

5. IF se desea probar si el Optimizador elige el nuevo índice en lugar del Seq_Scan, THEN THE Procedimiento_de_Evaluación SHALL verificar que los parámetros `enable_indexscan` y `enable_seqscan` estén ambos en `on` ejecutando `SHOW enable_indexscan; SHOW enable_seqscan;` y confirmando que ambos retornan `on` antes de ejecutar las mediciones.

6. WHILE la evaluación experimental está en curso, THE Procedimiento_de_Evaluación SHALL contener la creación y eliminación del índice dentro de un bloque transaccional con `ROLLBACK` para pruebas no destructivas, siguiendo el protocolo de seguridad del proyecto:
   ```sql
   BEGIN;
       CREATE INDEX idx_producto_precio_stock
       ON producto (precio_lista DESC, stock);
       -- Ejecutar aquí el EXPLAIN ANALYZE de comparación
   ROLLBACK;
   ```

---

### Requisito 4: Criterio de éxito y validación del resultado

**User Story:** Como DBA del proyecto FoodStore, quiero definir criterios de éxito objetivos y verificables, para determinar con certeza si el índice propuesto produce la mejora esperada en el plan de ejecución y en las métricas de rendimiento.

#### Criterios de Aceptación

1. WHEN el índice `idx_producto_precio_stock` está activo, THE Optimizador SHALL reemplazar el nodo Seq_Scan por un nodo Index_Scan o Bitmap_Index_Scan sobre dicho índice en el plan de ejecución reportado por EXPLAIN_ANALYZE.

2. WHEN el índice está definido con `precio_lista DESC` como columna líder, THE Optimizador SHALL eliminar el nodo Sort del plan de ejecución, dado que el orden del índice satisface directamente la cláusula `ORDER BY precio_lista DESC`.

3. WHEN se comparan las mediciones de baseline y post-índice, THE Procedimiento_de_Evaluación SHALL constatar una reducción de al menos 20% en el valor de `Execution Time` reportado por EXPLAIN_ANALYZE, tomando como medición válida el resultado de la tercera ejecución consecutiva de la consulta en la misma sesión de psql, a fin de garantizar que el cache de buffers compartidos se encuentre caliente al momento de la medición.

4. IF el Optimizador sigue eligiendo el Seq_Scan después de crear el índice, THEN THE Procedimiento_de_Evaluación SHALL interpretar ese resultado como evidencia de que la selectividad de los predicados no es suficiente para que el índice sea más económico que el barrido completo, documentando el hallazgo sin considerarlo un error del índice.

5. THE Procedimiento_de_Evaluación SHALL utilizar la opción `BUFFERS` en EXPLAIN_ANALYZE para verificar que el valor de `shared hit` sobre las páginas del índice sea mayor a cero y que el número de bloques leídos del heap sea estrictamente menor que el registrado en la medición de baseline, confirmando que el camino de acceso efectivamente utilizó el índice.

6. WHEN la validación confirma que el nodo Seq_Scan fue reemplazado por un nodo Index_Scan o Bitmap_Index_Scan Y que el nodo Sort desapareció del plan, THE Procedimiento_de_Evaluación SHALL considerar el experimento exitoso e incluir ambas salidas completas de EXPLAIN_ANALYZE con la opción BUFFERS activa (baseline y post-índice) como evidencia en el informe final del TP2.

7. IF se decide promover el índice a producción tras la validación experimental, THEN THE Sistema_de_Indexación SHALL crear el índice de forma permanente fuera de un bloque transaccional, usando la instrucción `CREATE INDEX CONCURRENTLY` para evitar bloqueos de escritura sobre la tabla `producto` durante la construcción del índice.
