# Requirements Document

## Introduction

Esta especificación define los requisitos técnicos para la optimización de la consulta de recuperación de pedidos recientes sobre la tabla `pedido` del sistema FoodStore en PostgreSQL. La tabla contiene aproximadamente 200.000 registros y la consulta objetivo aplica un filtro de rango temporal sobre `fecha_hora` (ventana de 30 días con `BETWEEN NOW() - INTERVAL '30 days' AND NOW()`), con ordenamiento descendente por esa misma columna. El plan de ejecución actual incurre en un Seq_Scan completo sobre los 200.000 registros seguido de un nodo Sort en memoria, lo que representa un cuello de botella de rendimiento significativo en entornos de producción. El índice existente `idx_pedido_cliente ON pedido (id_cliente)` no cubre el predicado sobre `fecha_hora` y es descartado por el Optimizador para esta consulta.

El objetivo es validar experimentalmente si un índice B-Tree sobre `fecha_hora DESC` —en sus variantes simple, compuesta con `id_cliente`, y cubriente con `INCLUDE`— elimina el Seq_Scan y el nodo Sort, y reduce el Execution Time de forma medible. La columna `fecha_hora` es de tipo `TIMESTAMPTZ`; las comparaciones con `NOW()` e `INTERVAL` son nativamente compatibles con un índice B-Tree estándar sobre ese tipo, sin necesidad de conversión de tipos explícita.

---

## Glossary

- **Optimizador**: El planificador de consultas de PostgreSQL (`pg_optimizer`) que selecciona el plan de ejecución físico para cada consulta basándose en estadísticas de tabla, factores de costo y parámetros de configuración de la sesión.
- **EXPLAIN_ANALYZE**: Instrucción de PostgreSQL que ejecuta la consulta y devuelve el plan físico real con métricas de Planning Time, Execution Time, filas estimadas y filas reales, junto con contadores de bloques de buffer cuando se usa la opción `BUFFERS`.
- **Seq_Scan**: Nodo de plan que lee la tabla completa de forma secuencial, registro a registro, sin usar ninguna estructura de índice. Para 200.000 filas representa el nodo más costoso cuando la selectividad temporal es alta.
- **Index_Scan**: Nodo de plan que recorre un índice B-Tree para acceder directamente a las filas que satisfacen el predicado, realizando una búsqueda de heap por cada puntero de fila obtenido del índice.
- **Index_Only_Scan**: Nodo de plan que resuelve la consulta íntegramente desde el índice sin acceder al heap de la tabla, posible únicamente cuando todas las columnas del `SELECT` están cubiertas por el índice (ya sea en la clave o en la cláusula `INCLUDE`).
- **Bitmap_Index_Scan**: Nodo de plan que construye un mapa de bits con los punteros de fila obtenidos del índice antes de acceder al heap en bloque, eficiente para selectividades medias donde el número de filas candidatas es demasiado grande para Index_Scan puro pero insuficiente para justificar Seq_Scan.
- **Sort**: Nodo de plan que ordena el resultado en memoria (o en disco si supera `work_mem`) para satisfacer una cláusula `ORDER BY`. Su presencia indica que el índice no satisface el ordenamiento requerido.
- **TIMESTAMPTZ**: Tipo de dato de PostgreSQL que almacena marcas de tiempo con información de zona horaria (`TIMESTAMP WITH TIME ZONE`). Las comparaciones aritméticas con `NOW()` y expresiones `INTERVAL` son directamente compatibles con índices B-Tree sobre este tipo.
- **INTERVAL**: Tipo de dato de PostgreSQL que representa un span de tiempo (ej.: `'30 days'`). Utilizado en expresiones como `NOW() - INTERVAL '30 days'` para definir límites inferiores de ventanas temporales.
- **NOW()**: Función de PostgreSQL que devuelve la marca de tiempo actual con zona horaria (`TIMESTAMPTZ`) del inicio de la transacción. Compatible de forma directa con comparaciones sobre columnas `TIMESTAMPTZ` sin conversión de tipos.
- **INCLUDE (cláusula)**: Cláusula de `CREATE INDEX` introducida en PostgreSQL 11 que permite agregar columnas adicionales al nivel hoja del índice sin incluirlas en la clave de búsqueda, habilitando Index_Only_Scan cuando el `SELECT` referencia esas columnas.
- **Selectividad_temporal**: Fracción de filas de la tabla que satisfacen el predicado de rango sobre `fecha_hora`. Una ventana de 30 días sobre 200.000 registros puede tener selectividad alta (muchas filas) si los datos están densamente distribuidos en ese rango, reduciendo el beneficio relativo del índice frente al Seq_Scan.
- **Ventana_temporal**: Intervalo de tiempo definido por un predicado `BETWEEN fecha_inicio AND fecha_fin` sobre una columna de tipo `TIMESTAMPTZ`. En esta feature, la ventana es `[NOW() - INTERVAL '30 days', NOW()]`.
- **Baseline**: Medición de referencia del plan de ejecución y las métricas de tiempo obtenida antes de aplicar cualquier cambio estructural (creación de índice), utilizada como punto de comparación para cuantificar la mejora.
- **Cobertura_de_Índice**: Propiedad de un índice de incluir todas las columnas necesarias para resolver el predicado y el `SELECT` sin acceder al heap de la tabla, condición necesaria para que el Optimizador elija Index_Only_Scan.
- **Planning_Time**: Tiempo en milisegundos que el Optimizador invierte en generar el plan de ejecución, visible en la salida de `EXPLAIN (ANALYZE)`.
- **Execution_Time**: Tiempo en milisegundos que PostgreSQL tarda en ejecutar físicamente el plan y devolver todas las filas al cliente, visible en la salida de `EXPLAIN (ANALYZE)`.

---

## Requirements

### Requisito 1: Diagnóstico del cuello de botella actual

**User Story:** Como DBA del proyecto FoodStore, quiero identificar con precisión los nodos de plan costosos en la consulta de pedidos recientes, para obtener una línea base experimental que justifique la intervención de indexación sobre `fecha_hora`.

#### Criterios de Aceptación

1. IF no existe ningún índice cuyas columnas cubran el predicado `fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()`, THEN THE Optimizador SHALL seleccionar un nodo Seq_Scan sobre la tabla `pedido` como nodo raíz de acceso a dicha tabla en el árbol de plan, verificable mediante `EXPLAIN` sobre la consulta objetivo:
   ```sql
   SELECT id_pedido, fecha_hora, forma_pago, id_cliente
   FROM pedido
   WHERE fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
   ORDER BY fecha_hora DESC;
   ```

2. IF no existe un índice con `fecha_hora` definido en dirección `DESC` como columna líder, THEN THE Optimizador SHALL incluir un nodo Sort en el plan de ejecución para satisfacer la cláusula `ORDER BY fecha_hora DESC`, verificable como un nodo `Sort` explícito en la salida de `EXPLAIN`.

3. IF el índice existente `idx_pedido_cliente ON pedido (id_cliente)` no incluye la columna `fecha_hora` en su definición, THEN THE Optimizador SHALL ignorar dicho índice para la consulta objetivo y el plan reportado por `EXPLAIN` SHALL mostrar Seq_Scan como nodo de acceso a `pedido`, sin ningún nodo Index_Scan ni Bitmap_Index_Scan referenciando `idx_pedido_cliente`.

4. WHEN se ejecuta `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` sobre la consulta objetivo en 3 ejecuciones consecutivas dentro de la misma sesión `psql` sin cerrar la conexión entre ejecuciones, THE EXPLAIN_ANALYZE SHALL reportar un `Execution Time` mayor a 1.00 ms en cada una de las 3 ejecuciones, registrándose el valor obtenido en la tercera ejecución como la referencia de baseline para las comparaciones del Requisito 4.

5. WHEN el plan de ejecución contiene un nodo Seq_Scan sobre `pedido`, THE Optimizador SHALL reportar en la salida de `EXPLAIN` el campo `rows` con un valor estimado de filas entre 180.000 y 220.000, confirmando que el planificador no aplica ningún filtro de índice previo a la evaluación del predicado.

6. WHEN se va a ejecutar cualquier medición con `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` sobre la consulta objetivo, THE Procedimiento_de_Evaluación SHALL verificar previamente las precondiciones de la sesión ejecutando `SHOW enable_indexscan; SHOW enable_seqscan;` y confirmando que ambos parámetros retornan `on`, garantizando que el Optimizador selecciona el plan por costo real y no por restricción artificial de parámetros de sesión.

---

### Requisito 2: Hipótesis de indexación con B-Tree sobre fecha_hora DESC

**User Story:** Como DBA del proyecto FoodStore, quiero proponer y justificar tres variantes de índice B-Tree sobre `fecha_hora`, para que el Optimizador pueda satisfacer el predicado temporal y el ordenamiento de la consulta objetivo sin nodos Seq_Scan ni Sort, y potencialmente sin acceso al heap mediante Index_Only_Scan.

#### Criterios de Aceptación

1. THE Sistema_de_Indexación SHALL soportar la creación de la **Variante A — Índice simple** sobre `fecha_hora DESC` mediante la siguiente instrucción, que permite al Optimizador recorrer el índice en dirección descendente satisfaciendo `ORDER BY fecha_hora DESC` sin nodo Sort:
   ```sql
   CREATE INDEX idx_pedido_fecha_hora
   ON pedido (fecha_hora DESC);
   ```

2. WHEN el índice `idx_pedido_fecha_hora` existe y la consulta filtra `fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()`, THE plan de ejecución reportado por EXPLAIN_ANALYZE SHALL mostrar un nodo Index_Scan o Bitmap_Index_Scan referenciando `idx_pedido_fecha_hora` como método de acceso a `pedido`, sin un nodo Seq_Scan.

3. WHEN el índice está definido con `fecha_hora DESC` como columna líder, THE plan de ejecución reportado por EXPLAIN_ANALYZE SHALL no contener ningún nodo Sort, dado que el recorrido del índice en dirección descendente produce las filas ordenadas por `fecha_hora DESC` sin reordenamiento adicional en memoria.

4. THE Sistema_de_Indexación SHALL soportar la creación de la **Variante B — Índice compuesto con id_cliente** mediante la siguiente instrucción, útil cuando la consulta incluye un filtro adicional `AND id_cliente = ?`:
   ```sql
   CREATE INDEX idx_pedido_fecha_cliente
   ON pedido (fecha_hora DESC, id_cliente);
   ```
   Para la consulta objetivo sin filtro de cliente, el Optimizador puede preferir la Variante A por menor tamaño de índice; la Variante B es más eficiente únicamente cuando el predicado incluye `AND id_cliente = <valor>`.

5. THE Sistema_de_Indexación SHALL soportar la creación de la **Variante C — Índice cubriente con INCLUDE** mediante la siguiente instrucción, que permite Index_Only_Scan al cubrir todas las columnas del `SELECT`:
   ```sql
   CREATE INDEX idx_pedido_fecha_cubriente
   ON pedido (fecha_hora DESC)
   INCLUDE (forma_pago, id_cliente);
   ```
   Las columnas `id_pedido`, `fecha_hora`, `forma_pago` e `id_cliente` requeridas por el `SELECT` quedan cubiertas: `fecha_hora` en la clave, `forma_pago` e `id_cliente` en la cláusula `INCLUDE`, e `id_pedido` (PK) implícitamente almacenado en el nivel hoja, verificable en la salida de EXPLAIN_ANALYZE como un nodo Index_Only_Scan sin accesos al heap cuando `Heap Fetches = 0`.

6. WHEN el índice `idx_pedido_fecha_cubriente` existe y se ejecuta `VACUUM pedido` previamente para actualizar la visibility map, THE Optimizador SHALL seleccionar un nodo Index_Only_Scan que resuelva la consulta completa sin acceder al heap de `pedido`, verificable por `Heap Fetches: 0` en la salida de EXPLAIN_ANALYZE.

7. IF la selectividad temporal de la ventana de 30 días retorna más de ~30.000 filas (más del 15% de 200.000), THEN THE Optimizador PUEDE legítimamente preferir Seq_Scan sobre Index_Scan por razones de costo, lo cual constituye un comportamiento aceptable del planificador y no un defecto del índice, conforme a los criterios del Requisito 4.

8. WHEN se crea cualquiera de las tres variantes de índice, THE Sistema_de_Indexación SHALL ejecutar `ANALYZE pedido` inmediatamente después para actualizar las estadísticas de la tabla antes de ejecutar cualquier medición de EXPLAIN_ANALYZE, garantizando que el Optimizador tome decisiones basadas en histogramas y estadísticas de `fecha_hora` actualizados.

---

### Requisito 3: Plan de evaluación experimental reproducible (EXPLAIN ANALYZE)

**User Story:** Como DBA del proyecto FoodStore, quiero un procedimiento de evaluación reproducible con EXPLAIN ANALYZE, para comparar el plan de ejecución y las métricas de tiempo antes y después de crear el índice propuesto sobre `fecha_hora`.

#### Criterios de Aceptación

1. WHEN el procedimiento de evaluación se inicia, THE Procedimiento_de_Evaluación SHALL obtener una medición de baseline ejecutando tres veces consecutivas la siguiente instrucción sin índice sobre `fecha_hora`, registrando los valores de la tercera ejecución como referencia:
   ```sql
   EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
   SELECT id_pedido, fecha_hora, forma_pago, id_cliente
   FROM pedido
   WHERE fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
   ORDER BY fecha_hora DESC;
   ```

2. WHEN se obtiene la medición de baseline, THE Procedimiento_de_Evaluación SHALL registrar los siguientes valores como referencia comparativa antes de cualquier creación de índice sobre `fecha_hora`, con las tres ejecuciones completadas y sin modificaciones a los parámetros del planificador en la sesión activa:
   - Nodo de acceso a la tabla (Seq Scan, Index Scan, Index Only Scan o Bitmap Index Scan).
   - Presencia o ausencia del nodo Sort en el plan.
   - Planning Time en milisegundos, con precisión de dos decimales.
   - Execution Time en milisegundos, con precisión de dos decimales (valor de la 3.ª ejecución).
   - Cantidad de `shared hit` y `shared read` reportados por la opción `BUFFERS`.
   - Cantidad de heap blocks leídos según el contador de buffers del nodo de acceso a `pedido`.

3. WHILE la evaluación experimental está en curso, THE Procedimiento_de_Evaluación SHALL contener la creación del índice y la ejecución de EXPLAIN ANALYZE dentro de un bloque transaccional con `ROLLBACK`, siguiendo el protocolo de seguridad del proyecto:
   ```sql
   BEGIN;
       CREATE INDEX idx_pedido_fecha_hora
       ON pedido (fecha_hora DESC);
       ANALYZE pedido;
       -- Primera ejecución (cold cache post-índice):
       EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
       SELECT id_pedido, fecha_hora, forma_pago, id_cliente
       FROM pedido
       WHERE fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
       ORDER BY fecha_hora DESC;
       -- Segunda ejecución (warm cache post-índice):
       EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
       SELECT id_pedido, fecha_hora, forma_pago, id_cliente
       FROM pedido
       WHERE fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
       ORDER BY fecha_hora DESC;
   ROLLBACK;
   ```

4. THE Procedimiento_de_Evaluación SHALL ejecutar EXPLAIN ANALYZE exactamente dos veces consecutivas e inmediatas dentro del bloque transaccional, sin instrucciones intermedias entre ambas ejecuciones, registrando el Execution Time de la primera ejecución como medición en frío (cold cache post-índice) y el de la segunda como medición en caliente (warm cache post-índice), ambos con precisión de dos decimales en milisegundos.

5. WHEN se ejecutan las mediciones post-índice, THE Procedimiento_de_Evaluación SHALL no modificar los parámetros del planificador `enable_seqscan`, `enable_indexscan`, `enable_bitmapscan` ni `work_mem` respecto a sus valores de sesión al momento de la medición de baseline, garantizando que la comparación refleje el comportamiento real del Optimizador ante el nuevo índice.

6. THE Procedimiento_de_Evaluación SHALL verificar la selectividad real de la ventana temporal ejecutando la siguiente consulta antes del bloque transaccional de creación del índice, registrando el conteo resultante y calculando el porcentaje que representa sobre el total de 200.000 registros de la tabla `pedido`:
   ```sql
   SELECT COUNT(*) FROM pedido
   WHERE fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW();
   ```
   IF el porcentaje de filas seleccionadas supera el 20% del total de registros, THEN THE Procedimiento_de_Evaluación SHALL documentar que el Optimizador puede mantener el Seq Scan como plan elegido incluso con el índice disponible, y que ese resultado es correcto y esperado.

7. IF la columna `fecha_hora` es de tipo `TIMESTAMPTZ` y la expresión `NOW() - INTERVAL '30 days'` devuelve también un valor `TIMESTAMPTZ`, THEN THE Procedimiento_de_Evaluación SHALL confirmar que no se requiere ninguna función de conversión de tipos (como `CAST` o `::DATE`) en el predicado, evitando la pérdida del beneficio del índice por incompatibilidad de tipos.

8. WHEN el procedimiento de evaluación se inicia, THE Procedimiento_de_Evaluación SHALL verificar que no exista ningún índice previo sobre `fecha_hora` ejecutando:
   ```sql
   SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'pedido';
   ```
   Y SHALL proceder únicamente si el resultado no retorna ningún índice sobre `fecha_hora`.

9. WHEN la evaluación concluye con el `ROLLBACK` del bloque transaccional, THE Procedimiento_de_Evaluación SHALL confirmar que el índice `idx_pedido_fecha_hora` ya no existe en `pg_indexes` usando la misma consulta del criterio 8, antes de considerar el procedimiento como completado y sus resultados como válidos.

---

### Requisito 4: Criterio de éxito y validación del resultado

**User Story:** Como DBA del proyecto FoodStore, quiero definir criterios de éxito objetivos y verificables, para determinar con certeza si el índice propuesto sobre `fecha_hora` produce la mejora esperada en el plan de ejecución y en las métricas de rendimiento de la tabla `pedido`.

#### Criterios de Aceptación

1. IF el índice sobre `fecha_hora DESC` está activo y `ANALYZE pedido` fue ejecutado después de su creación, THEN THE Optimizador SHALL reemplazar el nodo Seq_Scan por un nodo Index_Scan, Index_Only_Scan o Bitmap_Index_Scan referenciando el nuevo índice en el plan de ejecución reportado por EXPLAIN_ANALYZE.

2. WHEN el índice está definido con `fecha_hora DESC` como columna líder, THE Optimizador SHALL eliminar cualquier nodo Sort de la salida de EXPLAIN_ANALYZE, dado que el recorrido del índice en dirección descendente satisface directamente la cláusula `ORDER BY fecha_hora DESC` sin reordenamiento en memoria.

3. WHEN se comparan las mediciones de baseline y post-índice, THE Procedimiento_de_Evaluación SHALL constatar una reducción de al menos 20% en el valor de Execution_Time, tomando como medición válida la segunda ejecución post-índice (warm cache, `shared read = 0` en el nodo de acceso al heap) comparada contra la tercera ejecución del baseline (warm cache), garantizando condiciones de cache equivalentes en ambas mediciones.

4. THE Procedimiento_de_Evaluación SHALL utilizar la opción `BUFFERS` en EXPLAIN_ANALYZE para verificar que el valor de `shared hit` sobre las páginas del índice sea mayor a cero Y que la cantidad de heap blocks leídos en la medición post-índice sea estrictamente menor que la registrada en el baseline, confirmando que el camino de acceso efectivamente utilizó el índice y redujo los accesos al heap.

5. IF el Optimizador mantiene el nodo Seq_Scan después de crear el índice y `ANALYZE pedido` fue ejecutado, THEN THE Procedimiento_de_Evaluación SHALL ejecutar `SELECT COUNT(*) FROM pedido WHERE fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()` para verificar la selectividad, y SHALL documentar el resultado como evidencia de que la ventana de 30 días abarca más del 20% de las 200.000 filas, sin considerar dicho resultado como un error del índice ni de la implementación.

6. WHEN la validación confirma que el nodo Seq_Scan fue reemplazado por un nodo Index_Scan, Index_Only_Scan o Bitmap_Index_Scan, Y que el nodo Sort desapareció del plan, THE Procedimiento_de_Evaluación SHALL considerar el experimento exitoso e incluir ambas salidas completas de EXPLAIN_ANALYZE con la opción `BUFFERS` activa (baseline warm cache y post-índice warm cache) como evidencia en el informe final del TP2.

7. IF se decide promover el índice a producción tras la validación experimental, THEN THE Sistema_de_Indexación SHALL crear el índice de forma permanente fuera de un bloque transaccional usando `CREATE INDEX CONCURRENTLY` para evitar bloqueos de escritura sobre `pedido`:
   ```sql
   CREATE INDEX CONCURRENTLY idx_pedido_fecha_hora
   ON pedido (fecha_hora DESC);
   ```
