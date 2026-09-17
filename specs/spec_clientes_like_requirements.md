# Documento de Requisitos: Optimización de Búsqueda LIKE en `cliente`

## Introducción

Esta especificación define los requisitos técnicos para optimizar la consulta de búsqueda por patrón de texto prefijado sobre la tabla `cliente` del sistema FoodStore en PostgreSQL. La tabla contiene aproximadamente 20.000 registros y la consulta objetivo aplica un filtro `LIKE 'Cliente de Prueba 15%'` (comodín al final — *left-anchored*) con ordenamiento ascendente por la columna `nombre`:

```sql
SELECT id_cliente, nombre, email, telefono
FROM cliente
WHERE nombre LIKE 'Cliente de Prueba 15%'
ORDER BY nombre;
```

El plan de ejecución actual incurre en un **Seq_Scan** completo sobre los 20.000 registros seguido de un nodo **Sort** en memoria, porque no existe ningún índice sobre `nombre` y el operador `LIKE` con comodín al final requiere consideraciones especiales de clase de operador (`text_pattern_ops`) cuando el collation de la base de datos no es `C`. El objetivo es validar experimentalmente si un índice B-Tree con la clase de operador correcta elimina ambos nodos costosos y reduce el Execution Time de forma medible.

---

## Glosario

- **Optimizador**: El planificador de consultas de PostgreSQL que selecciona el plan de ejecución físico basándose en estadísticas, factores de costo y configuración de sesión.
- **EXPLAIN_ANALYZE**: Instrucción de PostgreSQL que ejecuta la consulta y devuelve el plan físico real con métricas de Planning Time, Execution Time, filas estimadas y filas reales.
- **Seq_Scan**: Nodo de plan que lee la tabla completa de forma secuencial sin usar estructura de índice.
- **Index_Scan**: Nodo de plan que recorre un índice B-Tree para acceder directamente a las filas que satisfacen el predicado.
- **Bitmap_Index_Scan**: Nodo de plan que construye un mapa de bits con punteros de fila del índice antes de acceder al heap, eficiente para selectividades medias.
- **Index_Only_Scan**: Nodo de plan que resuelve la consulta íntegramente desde el índice sin acceder al heap, posible cuando todas las columnas del `SELECT` están en el índice (clave o `INCLUDE`).
- **Sort**: Nodo de plan que ordena el resultado en memoria (o disco si supera `work_mem`) para satisfacer `ORDER BY`.
- **LIKE prefijado** (*left-anchored*): Patrón `LIKE 'prefijo%'` donde el comodín `%` está al final. PostgreSQL puede usar un índice B-Tree para este patrón si el índice fue creado con la clase de operador adecuada.
- **text_pattern_ops**: Clase de operador de PostgreSQL para índices B-Tree sobre columnas `text` o `varchar` que permite búsquedas con `LIKE` y `~` (regex), independientemente del collation de la base de datos. Necesaria cuando el collation no es `C` (p. ej., `es_AR.UTF-8`, `en_US.UTF-8`).
- **Collation**: Configuración de orden y comparación de cadenas de texto. Con collation `C` (o `POSIX`), un índice B-Tree estándar soporta `LIKE` prefijado. Con cualquier otro collation, se requiere `text_pattern_ops`.
- **Clase de operador** (*operator class*): Define qué operadores puede soportar un índice para un tipo de dato determinado. Crucial para `LIKE` en columnas de texto.
- **INCLUDE (cláusula)**: Cláusula de `CREATE INDEX` que agrega columnas al nivel hoja del índice sin incluirlas en la clave, habilitando Index_Only_Scan.
- **Baseline**: Medición de referencia del plan y tiempos antes de aplicar el índice.
- **Cobertura de índice**: Propiedad de un índice de incluir todas las columnas necesarias para resolver el `SELECT` sin acceder al heap.
- **Planning_Time**: Tiempo en ms que el Optimizador invierte en generar el plan de ejecución.
- **Execution_Time**: Tiempo en ms que PostgreSQL tarda en ejecutar el plan y devolver todas las filas.

---

## Requisitos

### Requisito 1: Diagnóstico del cuello de botella actual

**User Story:** Como DBA del proyecto FoodStore, quiero identificar con precisión los nodos de plan costosos en la consulta de búsqueda por patrón de texto, para obtener una línea base experimental que justifique la creación de un índice especializado sobre `nombre`.

#### Criterios de Aceptación

1. IF no existe ningún índice sobre la columna `nombre` de la tabla `cliente`, THEN THE Optimizador SHALL seleccionar un nodo Seq_Scan sobre `cliente` como nodo raíz de acceso en el árbol de plan, verificable mediante `EXPLAIN` sobre la consulta objetivo:
   ```sql
   SELECT id_cliente, nombre, email, telefono
   FROM cliente
   WHERE nombre LIKE 'Cliente de Prueba 15%'
   ORDER BY nombre;
   ```

2. IF no existe un índice con `nombre` como columna líder en dirección `ASC`, THEN THE Optimizador SHALL incluir un nodo Sort en el plan de ejecución para satisfacer la cláusula `ORDER BY nombre`, verificable como un nodo `Sort` explícito en la salida de `EXPLAIN`.

3. WHEN se ejecuta `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` sobre la consulta objetivo en 3 ejecuciones consecutivas dentro de la misma sesión `psql`, THE EXPLAIN_ANALYZE SHALL reportar un `Execution Time` mayor a 0.50 ms en cada ejecución, registrándose el valor de la tercera ejecución como referencia de baseline.

4. WHEN el plan contiene un nodo Seq_Scan sobre `cliente`, THE Optimizador SHALL reportar el campo `rows` con un valor estimado entre 18.000 y 22.000, confirmando que no se aplica ningún filtro de índice previo.

5. WHEN se va a ejecutar cualquier medición con `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)`, THE Procedimiento_de_Evaluación SHALL verificar previamente las precondiciones ejecutando `SHOW enable_indexscan; SHOW enable_seqscan;` y confirmando que ambos retornan `on`.

6. THE Procedimiento_de_Evaluación SHALL verificar que no existe índice previo sobre `nombre` ejecutando:
   ```sql
   SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'cliente';
   ```
   Y SHALL proceder únicamente si ninguna entrada muestra `nombre` en `indexdef`.

---

### Requisito 2: Hipótesis de indexación para LIKE prefijado con ORDER BY

**User Story:** Como DBA del proyecto FoodStore, quiero proponer y justificar la estructura exacta del índice B-Tree sobre `nombre`, incluyendo la clase de operador correcta para `LIKE` prefijado y la cláusula `INCLUDE` para evitar accesos al heap.

#### Criterios de Aceptación

1. THE Sistema_de_Indexación SHALL soportar la creación de la **Variante A — Índice con text_pattern_ops** (recomendada para collation != C):
   ```sql
   CREATE INDEX idx_cliente_nombre_pattern
   ON cliente (nombre text_pattern_ops);
   ```
   Esta variante habilita el operador `LIKE` prefijado independientemente del collation de la base de datos, pero **no** satisface `ORDER BY nombre` con el collation normal (requiere dos índices o la Variante C).

2. THE Sistema_de_Indexación SHALL soportar la creación de la **Variante B — Índice estándar ASC** (para collation C o POSIX):
   ```sql
   CREATE INDEX idx_cliente_nombre_asc
   ON cliente (nombre ASC);
   ```
   Con collation `C`, un índice B-Tree estándar soporta nativamente `LIKE` prefijado Y satisface `ORDER BY nombre ASC` sin nodo Sort.

3. THE Sistema_de_Indexación SHALL soportar la creación de la **Variante C — Índice cubriente con INCLUDE** (cobertura completa del SELECT):
   ```sql
   CREATE INDEX idx_cliente_nombre_cubriente
   ON cliente (nombre text_pattern_ops)
   INCLUDE (email, telefono);
   ```
   Las columnas `id_cliente`, `nombre`, `email` y `telefono` del `SELECT` quedan cubiertas: `nombre` en la clave, `email` y `telefono` en `INCLUDE`, `id_cliente` (PK BIGINT) implícita en el nivel hoja del B-Tree. Habilita Index_Only_Scan sin accesos al heap.

4. WHEN el índice `idx_cliente_nombre_pattern` (Variante A) existe y la consulta filtra `nombre LIKE 'Cliente de Prueba 15%'`, THE plan de ejecución reportado por EXPLAIN_ANALYZE SHALL mostrar un nodo Index_Scan o Bitmap_Index_Scan referenciando dicho índice, sin un nodo Seq_Scan.

5. WHEN el índice `idx_cliente_nombre_asc` (Variante B, collation C) existe, THE plan SHALL mostrar Index_Scan o Bitmap_Index_Scan Y SHALL no contener nodo Sort, dado que el índice B-Tree estándar ya entrega las filas en orden `nombre ASC`.

6. WHEN el índice `idx_cliente_nombre_cubriente` (Variante C) existe y se ejecutó `VACUUM cliente` previamente, THE Optimizador SHALL seleccionar Index_Only_Scan con `Heap Fetches: 0` en la salida de EXPLAIN_ANALYZE.

7. IF la base de datos tiene collation distinto de `C` (p. ej., `es_AR.UTF-8`), THEN THE Sistema_de_Indexación SHALL requerir la clase de operador `text_pattern_ops` para que el Optimizador pueda usar el índice con el operador `LIKE`. Sin `text_pattern_ops`, el índice B-Tree estándar no es seleccionado por el Optimizador para predicados `LIKE` con collation != C.

8. WHEN se crea cualquier variante de índice, THE Sistema_de_Indexación SHALL ejecutar `ANALYZE cliente` inmediatamente después para actualizar las estadísticas antes de ejecutar EXPLAIN_ANALYZE.

---

### Requisito 3: Plan de evaluación experimental reproducible

**User Story:** Como DBA del proyecto FoodStore, quiero un procedimiento de evaluación reproducible con EXPLAIN ANALYZE, para comparar el plan de ejecución antes y después de crear el índice propuesto sobre `nombre`.

#### Criterios de Aceptación

1. WHEN el procedimiento se inicia, THE Procedimiento_de_Evaluación SHALL obtener el baseline ejecutando tres veces consecutivas:
   ```sql
   EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
   SELECT id_cliente, nombre, email, telefono
   FROM cliente
   WHERE nombre LIKE 'Cliente de Prueba 15%'
   ORDER BY nombre;
   ```
   Registrando los valores de la tercera ejecución (warm cache).

2. WHEN se obtiene el baseline, THE Procedimiento_de_Evaluación SHALL registrar:
   - Nodo de acceso (Seq_Scan, Index_Scan, Bitmap_Index_Scan o Index_Only_Scan).
   - Presencia o ausencia del nodo Sort.
   - Planning Time (ms, dos decimales).
   - Execution Time (ms, dos decimales) — referencia R4.
   - `shared hit` y `shared read` (BUFFERS).
   - Heap blocks leídos.

3. WHILE la evaluación está en curso, THE Procedimiento_de_Evaluación SHALL contener la creación del índice dentro de un bloque `BEGIN; ... ROLLBACK;`:
   ```sql
   BEGIN;
       CREATE INDEX idx_cliente_nombre_cubriente
       ON cliente (nombre text_pattern_ops)
       INCLUDE (email, telefono);
       ANALYZE cliente;
       -- Cold cache (1ra post-índice):
       EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
       SELECT id_cliente, nombre, email, telefono
       FROM cliente
       WHERE nombre LIKE 'Cliente de Prueba 15%'
       ORDER BY nombre;
       -- Warm cache (2da post-índice):
       EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
       SELECT id_cliente, nombre, email, telefono
       FROM cliente
       WHERE nombre LIKE 'Cliente de Prueba 15%'
       ORDER BY nombre;
   ROLLBACK;
   ```

4. THE Procedimiento_de_Evaluación SHALL verificar el collation de la base de datos ejecutando:
   ```sql
   SELECT datname, datcollate, datctype FROM pg_database WHERE datname = current_database();
   ```
   IF el collation no es `C` ni `POSIX`, THEN THE Procedimiento_de_Evaluación SHALL usar `text_pattern_ops` en el índice.

5. WHEN se ejecutan las mediciones post-índice, THE Procedimiento_de_Evaluación SHALL no modificar `enable_seqscan`, `enable_indexscan`, `enable_bitmapscan` ni `work_mem` respecto a sus valores del baseline.

6. WHEN la evaluación concluye con ROLLBACK, THE Procedimiento_de_Evaluación SHALL confirmar que el índice ya no existe en `pg_indexes` antes de considerar los resultados como válidos.

---

### Requisito 4: Criterio de éxito y validación del resultado

**User Story:** Como DBA del proyecto FoodStore, quiero definir criterios de éxito objetivos y verificables para determinar si el índice sobre `nombre` produce la mejora esperada.

#### Criterios de Aceptación

1. IF el índice sobre `nombre` con `text_pattern_ops` está activo y `ANALYZE cliente` fue ejecutado, THEN THE Optimizador SHALL reemplazar el nodo Seq_Scan por un nodo Index_Scan, Index_Only_Scan o Bitmap_Index_Scan referenciando el nuevo índice.

2. WHEN el índice está definido con `nombre ASC` (o `text_pattern_ops` que internamente ordena ASC), THE Optimizador SHALL eliminar el nodo Sort del plan, dado que el recorrido natural del índice ya entrega las filas en orden `nombre ASC` requerido por `ORDER BY nombre`.

3. WHEN se comparan las mediciones de baseline y post-índice, THE Procedimiento_de_Evaluación SHALL constatar una reducción de al menos 20% en Execution Time, tomando la segunda ejecución post-índice (warm cache) como medición válida comparada contra la tercera del baseline.

4. THE Procedimiento_de_Evaluación SHALL verificar con `BUFFERS` que `shared hit` del índice sea mayor a cero Y que los heap blocks leídos post-índice sean estrictamente menores que en el baseline.

5. IF el Optimizador mantiene Seq_Scan después de crear el índice, THEN THE Procedimiento_de_Evaluación SHALL verificar el collation con la consulta del Requisito 3.4 y SHALL documentar si el índice fue creado sin `text_pattern_ops` siendo necesario, sin considerar el resultado como error del índice.

6. WHEN la validación confirma Seq_Scan reemplazado Y Sort eliminado, THE Procedimiento_de_Evaluación SHALL incluir ambas salidas completas de EXPLAIN_ANALYZE (baseline y post-índice warm cache) como evidencia en el informe del TP2.

7. IF se decide promover el índice a producción, THEN THE Sistema_de_Indexación SHALL ejecutar:
   ```sql
   CREATE INDEX CONCURRENTLY idx_cliente_nombre_cubriente
   ON cliente (nombre text_pattern_ops)
   INCLUDE (email, telefono);
   ```
   Fuera de cualquier bloque transaccional.
