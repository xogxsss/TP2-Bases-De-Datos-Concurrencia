# Declaración de Uso de IA (DUIA) - Consolidada por Instancias

### DUIA - TP1: Modelado ER, Derivación Relacional, Normalización y DDL

- **Herramienta:** Gemini / Asistente de IA.
- **Spec o prompt utilizado:** _"Analizar el dominio de Food Store para diseñar el modelo entidad-relación, derivar las tablas relacionales, aplicar la normalización hasta 3FN/BCNF a partir de la planilla histórica y generar el script DDL en PostgreSQL."_
- **Qué generó:** Propuestas de diagrama ER, listados de dependencias funcionales, pasos de normalización, el script `schema.sql` inicial y definiciones de restricciones.
- **Qué se aceptó:** La estructura general de las entidades (`cliente`, `categoria`, `producto`, `pedido`, `detalle_pedido`), las reglas de derivación 1:N y N:M, y la incorporación de tipos de datos adecuados como `TIMESTAMPTZ` y `CREATE TYPE ... AS ENUM`.
- **Qué se modificó o descartó:** Se ajustaron manualmente las cardinalidades, se definieron con precisión los comportamientos de borrado (`ON DELETE RESTRICT`) basándose en las reglas del negocio, y se incorporaron restricciones `CHECK` y claves candidatas únicas (`UNIQUE` para el correo del cliente).
- **Verificación realizada:** Comprobación de que el script `schema.sql` se ejecute de principio a fin sin errores de sintaxis en el motor de PostgreSQL.

---

### DUIA - TP2 Parte 1: Restricciones de Integridad y Triggers

- **Herramienta:** OpenCode (asistente de terminal).
- **Spec o prompt utilizado:** _"Generar triggers en PL/pgSQL para la base de datos FoodStore que garanticen reglas de negocio: impedir pedidos con fechas futuras y prohibir el uso de productos inactivos en detalles de pedido."_
- **Qué generó:** Propuesta de funciones PL/pgSQL con bloques condicionales, `RAISE EXCEPTION` y la estructura de los triggers asociados (`BEFORE INSERT OR UPDATE`).
- **Qué se aceptó:** La lógica general de validación condicional y el diseño inicial de los disparadores para el esquema.
- **Qué se modificó o descartó:** Se adaptaron los nombres de tablas y columnas al esquema real de _Food Store_ (`pedido`, `producto`, `detalle_pedido`), descartando restricciones `CHECK` directas con funciones mutables como `now()`.
- **Verificación realizada:** Pruebas transaccionales aisladas con bloques `BEGIN` y `ROLLBACK`, comprobando que el motor rechaza correctamente las operaciones ilegítimas.

---

### DUIA - TP2 Parte 2: Laboratorio de Concurrencia y Aislamiento

- **Herramienta:** OpenCode / Asistente de IA.
- **Spec o prompt utilizado:** _"Explicar las anomalías de concurrencia (lectura no repetible, espera por bloqueo y lectura fantasma) en PostgreSQL para las tablas de FoodStore y proponer niveles de aislamiento."_
- **Qué generó:** Explicaciones teóricas sobre control de concurrencia multiversión (MVCC), bloqueos exclusivos con `SELECT ... FOR UPDATE` y el comportamiento de los niveles `READ COMMITTED` y `REPEATABLE READ`.
- **Qué se aceptó:** Los conceptos de aislamiento por instantáneas y los comandos para modificar los niveles transaccionales.
- **Qué se modificó o descartó:** Se ajustaron los escenarios teóricos a los nombres reales del proyecto y se contrastó rigurosamente la teoría con la ejecución empírica.
- **Verificación realizada:** Ejecución paso a paso en terminales `psql` paralelas, validando que el motor real cumpla con el comportamiento predicho por el aislamiento transaccional.

---

### DUIA - TP2 Parte 3: Lectura Crítica de Scripts y Planes

- **Herramienta:** OpenCode / Asistente de IA.
- **Spec o prompt utilizado:** _"Analizar scripts defectuosos de actualización/eliminación y explicar planes de ejecución EXPLAIN ANALYZE nodo por nodo."_
- **Qué generó:** Interpretaciones automatizadas de rendimiento y análisis de código sobre sentencias SQL defectuosas.
- **Qué se aceptó:** La identificación preliminar de vicios lógicos, como el uso de `NOT IN` con valores nulos o la ausencia de filtros `WHERE`.
- **Qué se modificó o descartó:** Se corrigieron los errores graves de la IA al interpretar planes de ejecución (confundir costos con segundos, estimaciones con filas reales y planificación con operaciones físicas en disco).
- **Verificación realizada:** Contraste estricto contra el motor real de PostgreSQL y las métricas efectivas de `Execution Time`.

---

### DUIA - TP3: Optimización Masiva y EXPLAIN ANALYZE

- **Herramienta:** OpenCode / Kiro.
- **Spec o prompt utilizado:** _"Generar script de carga masiva con generate_series e interpretar planes de optimización para consultas lentas."_
- **Qué generó:** Consultas masivas de prueba con miles de registros y propuestas de índices B-Tree para mitigar barridos secuenciales (_Seq Scan_).
- **Qué se aceptó:** La creación controlada de índices orientados a las columnas filtradas en consultas críticas del proyecto.
- **Qué se modificó o descartó:** Se midieron los tiempos reales antes y después de aplicar cada índice, descartando propuestas que no mejoraran el rendimiento empírico.
- **Verificación realizada:** Comparativa de tiempos de ejecución real mediante `EXPLAIN ANALYZE` tras actualizar las estadísticas con `ANALYZE`.

---

### DUIA - TP4: Rendimiento y Descarte de Índices

- **Herramienta:** OpenCode.
- **Spec o prompt utilizado:** _"Interpretar planes de optimización mediante EXPLAIN ANALYZE y justificar técnicamente el rechazo o aceptación de índices en consultas analíticas masivas."_
- **Qué generó:** Análisis detallado de los costos del optimizador de PostgreSQL, explicación del comportamiento físico de los nodos (`Parallel Seq Scan` frente a accesos por índice) y evaluación conceptual de los árboles B-Tree en consultas de agregación global (`SUM`, `GROUP BY`).
- **Qué se aceptó:** La validación empírica de los planes de ejecución y la incorporación de bloques transaccionales (`BEGIN/COMMIT`) para la limpieza y eliminación segura de los índices experimentales en el código final.
- **Qué se modificó o descartó:** Se **descartaron definitivamente los índices de optimización** para las consultas analíticas principales. Se demostró teórica y empíricamente que, al procesar la totalidad de las tablas con baja especificidad, el motor descarta el índice de forma autónoma y prioriza el `Parallel Seq Scan`, haciendo que mantener dichos índices suponga un costo de almacenamiento y mantenimiento innecesario en las operaciones de escritura.
- **Verificación realizada:** Auditoría de los costos estimados (`cost`) y tiempos de ejecución mediante `EXPLAIN ANALYZE`, comprobando que el motor de bases de datos calcula de manera autónoma la ruta más eficiente y valida la superioridad del barrido secuencial masivo en este tipo de informes.

---

### DUIA - TP4 Parte 2: Lectura Crítica de Planes de Join

- **Herramienta**: ChatGPT / Asistente de IA.
- **Spec o prompt utilizado**: _"Analizar el siguiente plan de ejecución (`EXPLAIN ANALYZE`) de una consulta SQL con múltiples JOINs en PostgreSQL. Explícame el plan nodo por nodo, indicando qué hace cada nodo, qué tablas procesa y qué significan los costos y tiempos."_
- **Qué generó**: Una explicación detallada en lenguaje natural, nodo por nodo, del plan de ejecución con múltiples `JOIN` y agregaciones globales de la consulta analítica.
- **Qué se aceptó**: La identificación general de la estructura de árbol de ejecución ascendente y el flujo de procesamiento de los datos crudos hacia las capas superiores.
- **Qué se modificó o descartó**: Se corrigieron y descartaron afirmaciones erróneas de la IA, específicamente la confusión entre los costos abstractos del optimizador y el tiempo real de ejecución en milisegundos, así como imprecisiones en la lectura de los roles operativos dentro de los planes complejos.
- **Verificación realizada**: Contraste estricto de la explicación automatizada contra la salida real del motor de PostgreSQL, documentando las correcciones en la tabla de lectura crítica del entregable.

---

### DUIA - TP4 Parte 3: Consultas resumen, rankings y subconsultas bajo especificación precisa

- **Herramienta**: OpenCode / Asistente de IA (Gemini).
- **Spec o prompt utilizado**: _"Redactar una especificación precisa para dos consultas sobre Food Store: un ranking con función de ventana y una consulta con subconsulta correlacionada, especificando tablas, filtros de borrado lógico, columnas de salida y desempate. Generar dos versiones con estructuras distintas y sus respectivas pruebas de equivalencia con EXCEPT."_
- **Qué generó**: Un script estructurado con especificaciones formales, dos versiones sintácticamente distintas para cada caso (ranking directo vs. CTE, y subconsulta correlacionada vs. JOIN con tabla derivada) y sus bloques de verificación cruzada mediante `EXCEPT`.
- **Qué se aceptó**: La lógica general para la construcción de funciones de ventana con `RANK()`, el uso de `COALESCE` para el manejo de nulos, la aplicación de tablas derivadas/CTE y la sintaxis de los operadores de conjuntos para la prueba de equivalencia.
- **Qué se modificó o descartó**: Se corrigieron errores iniciales respecto al esquema físico real de la base de datos, eliminando referencias a columnas de borrado lógico inexistentes (`activo`) en las tablas transaccionales (`pedido` y `cliente`) y limitándolas strictly a `producto` y `categoria`. Asimismo, se ajustaron alias en las columnas de salida (`nombre_completo`) para asegurar la compatibilidad exacta en las pruebas de comparación.
- **Verificación realizada**: Ejecución y validación de los scripts en PostgreSQL, comprobando que las consultas devuelven los resultados esperados sin colapsar filas y que las pruebas de equivalencia con `EXCEPT` arrojan exactamente cero filas en ambas direcciones.

---

### DUIA - TP4 Parte 4: Competencia de optimización entre equipos

- **Herramienta**: OpenCode / Asistente de IA (Gemini).
- **Spec o prompt utilizado**: _"Evaluar el plan de ejecución `EXPLAIN ANALYZE` de la consulta analítica con múltiples JOINs y agregaciones globales, y proponer estrategias de indexación o reescritura para mejorar el rendimiento en la competencia."_
- **Qué generó**: Sugerencias automáticas de creación de índices B-Tree en las claves foráneas de las tablas involucradas (`detalle_pedido`, `producto`) para acelerar el proceso de unión (`JOIN`).
- **Qué se aceptó**: La metodología analítica para medir tiempos mediante `EXPLAIN ANALYZE` y la comprensión del flujo de datos en el plan inicial (identificación de barridos secuenciales en paralelo y hashes).
- **Qué se modificó o descartó**: Se descartó la aplicación ciega de los índices sugeridos por la IA. Tras realizar pruebas de rendimiento reales en el motor, se comprobó mediante pensamiento crítico que el optimizador de PostgreSQL descartaba dichos índices de forma nativa debido a que las agregaciones globales masivas hacen más eficiente un _Parallel Seq Scan_. Por ende, se documentó que la "mejora" consistió en validar y justificar técnicamente por qué el plan nativo original era el óptimo, evitando sobrecargar el motor con índices innecesarios.
- **Verificación realizada**: Ejecución comparativa de planes de ejecución antes y después de las propuestas de indexación, registrando los tiempos reales en milisegundos (~197.6 ms) y documentando rigurosamente el proceso de experimentación en la bitácora de la competencia.

---

### DUIA - Unidad 3 (TP5): Optimización de Consultas, Indexación Avanzada y Validación Empírica

#### Instancia 1 — Evaluación experimental de `producto` (Consulta 1)

- **Herramienta:** Kiro (generación de specs en `specs/`) + OpenCode (propuesta DDL).
- **Spec o prompt utilizado:** _"Diseñar un índice B-Tree cubriente para la consulta sobre producto filtrada por precio_lista y stock, ordenando por precio_lista DESC."_
- **Qué generó:** Propuesta de índice cubriente `CREATE INDEX idx_producto_precio_stock_cubriente ON producto (precio_lista DESC, stock) INCLUDE (id_producto, nombre)`.
- **Qué se aceptó:** La estructura del índice B-Tree con la columna líder `precio_lista DESC`.
- **Qué se modificó o descartó (Refutación crítica):** Se verificó mediante `EXPLAIN (ANALYZE, BUFFERS)` que el motor ejecuta un `Index Only Scan` con **`Heap Fetches: 0`**, leyendo solo 160 páginas de buffers frente a 812 del barrido secuencial. La mejora en tiempo fue de **10.538 ms → 1.951 ms (~81.5%)**.
- **Verificación realizada:** Ejecución en PostgreSQL 17 confirmando la eliminación total del nodo `Sort` y el acceso eficiente al índice.

---

#### Instancia 2 — Evaluación experimental de `pedido` (Consulta 2)

- **Herramienta:** Kiro + OpenCode.
- **Spec o prompt utilizado:** _"Optimizar la consulta por rango temporal sobre la tabla pedido usando un índice sobre fecha_hora."_
- **Qué generó:** Propuesta del índice `idx_pedido_fecha_hora` sobre `(fecha_hora DESC)`.
- **Qué se aceptó:** El índice B-Tree sobre la columna temporal.
- **Qué se modificó o descartó (Refutación crítica):** La IA asumió que el índice reduciría las lecturas de páginas. La medición empírica reveló que los `shared buffers` se dispararon de **1.471 a 62.367** debido a la correlación física nula (`-0.0026`). Sin embargo, el tiempo de ejecución bajó de **52.522 ms a 20.084 ms (~61.7%)** porque se evitó un ordenamiento externo en disco (`external merge Disk: 2568kB`). Se documentó este trade-off de I/O en `informe_mediciones.md`.
- **Verificación realizada:** Comparativa de planes de ejecución en `foodstore_test`.

---

#### Instancia 3 — Búsqueda prefijada en `cliente` (Consulta 3)

- **Herramienta:** Kiro + OpenCode.
- **Spec o prompt utilizado:** _"Crear un índice para acelerar consultas con LIKE 'Cliente de Prueba 15%' sobre cliente."_
- **Qué generó:** Propuesta del índice `idx_cliente_nombre_cubriente ON cliente (nombre text_pattern_ops) INCLUDE (email, telefono)`.
- **Qué se aceptó:** El uso del operador `text_pattern_ops` para transformar el `LIKE` en un rango B-Tree.
- **Qué se modificó o descartó (Refutación crítica a la IA):** OpenCode afirmó falsamente que la columna `id_cliente` estaba "implícitamente en el índice" y que ejecutaría un `Index Only Scan`. La evidencia mostró un `Bitmap Heap Scan` visitando 23 bloques de la tabla base (`Heap Blocks: exact=23`). Además, el tiempo de ejecución solo se redujo levemente (**6.289 ms → 5.091 ms**) porque el nodo `Sort` persistió debido a la discrepancia entre la ordenación byte a byte de `text_pattern_ops` y la collation lingüística del servidor (`Spanish_Argentina.1252`).
- **Verificación realizada:** Registrado en `ejercicio_lectura_critica.md` y `informe_mediciones.md`.

---

#### Instancia 4 — Evaluación del costo DML en escrituras

- **Herramienta:** OpenCode.
- **Spec o prompt utilizado:** _"Medir el sobrecosto de escrituras mediante un INSERT masivo con y sin índices activos."_
- **Qué generó:** Un número estimado del ~30% de penalización en escrituras.
- **Qué se modificó o descartó:** Se **descartó la cifra numérica del ~30%** en la entrega final debido a que las pruebas automatizadas de inserción sobre 500 filas sufrieron transacciones abortadas por restricciones de identidad (`GENERATED ALWAYS AS IDENTITY`) e incompatibilidad en claves primarias compuestas. En su lugar, se documentó el impacto estructural cualitativo: el índice de productos mide **3.776 kB** (un 58% del tamaño de la tabla) e incluye `stock`, por lo que cada `UPDATE` de inventario incurre en un sobrecosto de reestructuración en el B-Tree.
- **Verificación realizada:** Auditoría del tamaño de los objetos con `pg_relation_size`.

---

### DUIA - Unidad 3 (TP5) Parte B: Vistas Transaccionales, Seguridad por Roles y Equivalencia

- **Herramientas:** Kiro y OpenCode.
- **Spec o prompt utilizado:** _"Implementar las vistas vw_productos_vigentes, vw_pedidos_cliente_segura y vw_detalle_pedido_completo, configurando seguridad por roles y pruebas EXCEPT."_
- **Qué generó:** DDL de las vistas en `views.sql`, asignación de permisos a `rol_reportes` y pruebas de comparación de conjuntos.
- **Qué se aceptó:** La estructura general de las vistas y el aislamiento de datos sensibles (PII), omitiendo la columna `direccion` de la tabla `cliente`.
- **Verificación realizada:** Verificación en consola mediante `SET ROLE rol_reportes;`, confirmando que el acceso a `vw_pedidos_cliente_segura` fue permitido y la consulta directa a `cliente` fue bloqueada con `ERROR: permiso denegado a la tabla cliente`. Las 6 pruebas de equivalencia `EXCEPT` devolvieron **`(0 rows)`**.

---

### DUIA - Unidad 3 (TP5) Parte C: Vista Materializada e Índice Único

- **Herramientas:** Kiro.
- **Spec o prompt utilizado:** _"Diseñar la vista materializada mv_facturacion_categoria_mes con refresco concurrente."_
- **Qué generó:** Sentencia `CREATE MATERIALIZED VIEW`, creación del índice único `idx_mv_facturacion_uk` y análisis de consistencia eventual.
- **Qué se aceptó:** El precálculo de agregaciones de facturación agrupadas por año, mes y categoría.
- **Verificación realizada:** Creación exitosa de la vista materializada (36 filas precomputadas) y comprobación del índice único para la ejecución no bloqueante de `REFRESH MATERIALIZED VIEW CONCURRENTLY`.

---

### DUIA - TP6 Parte 1: Normalizacion Avanzada (FNBC) en ControlLoteAlmacen

- **Herramienta:** Kiro (generacion de spec en `specs/tp_fnbc_control_lote.md` y script DDL `tp_fnbc_control_lote.sql`).
- **Spec o prompt utilizado:** _"Generar el script DDL tp_fnbc_control_lote.sql para la base foodstore_dev que demuestre la deteccion y correccion de una violacion FNBC en la tabla control_lote_almacen(lote_id, deposito_id, responsable_control_id), aplicando el Teorema de Heath para descomponer en dos relaciones en FNBC, con vista de compatibilidad y prueba de equivalencia de conjuntos con EXCEPT en ambas direcciones."_
- **Que genero:** La spec unificada `specs/tp_fnbc_control_lote.md` (requirements con sintaxis EARS, design con diagramas Mermaid, tabla de dominios y plan de tareas), y el script DDL `tp_fnbc_control_lote.sql` con los seis pasos: dominios reutilizables (`codigo_producto_dom`, `dni_arg_dom`), tablas maestras, esquema original defectuoso, descomposicion FNBC en R1 (`responsable_deposito`) y R2 (`control_lote_responsable`), vista de compatibilidad `vw_control_lote_almacen_compatibilidad`, migracion de datos y prueba lossless-join con `EXCEPT`.
- **Que se acepto:** La estructura general de la descomposicion por Teorema de Heath, la FK de R2 apuntando a `responsable_deposito` (no a `responsable_control` directamente) como mecanismo critico para garantizar la reunion sin perdida, el uso de `SELECT DISTINCT` en la migracion a R1 para colapsar las filas redundantes de `(responsable=801, deposito=30)`, y los dominios PostgreSQL como mecanismo de centralizacion de reglas de validacion.
- **Que se modifico o descarto:**
  - **Codificacion del encabezado:** las versiones iniciales del script incluian caracteres Unicode no ASCII en el bloque de comentarios del encabezado (flechas `->`, simbolos de verificacion, acentos). Al ejecutar el script en psql, el motor reporto `ERROR: caracter con secuencia de bytes 0x90 en codificacion WIN1252 no tiene equivalente en UTF8`, lo que impidio que el `BEGIN` se procesara y dejo todas las sentencias subsiguientes fuera de la transaccion. Se reescribio el encabezado completo usando exclusivamente caracteres ASCII; los literales de datos con acentos en los `INSERT` se mantuvieron porque se procesan correctamente dentro de la transaccion ya iniciada.
  - **Tipo de dato `fecha_vencimiento`:** la IA propuso inicialmente `TIMESTAMPTZ`. Se rechazo y se mantuvo `DATE` porque la caducidad legal de un alimento se expresa como dia calendario; usar `TIMESTAMPTZ` introduciria ambiguedad sobre el momento exacto del vencimiento. La comparacion de negocio relevante (`fecha_vencimiento < CURRENT_DATE`) opera sobre fechas puras.
  - **Fechas de prueba:** el enunciado proveia fechas en 2026 (`2026-10-20`, `2026-11-15`, `2026-12-31`). Al incorporar el `CHECK (fecha_vencimiento >= CURRENT_DATE)`, esas fechas ya estaban vencidas al momento de ejecucion (octubre 2026). Se ajustaron a 2027 para que los datos de prueba superen la validacion sin modificar la restriccion de integridad.
  - **Trigger de consistencia cruzada:** en iteraciones previas se incluyo un trigger PL/pgSQL (`fn_check_deposito_consistencia`) sobre `responsable_deposito` para detectar inconsistencias entre R1 y `control_lote_almacen` durante la migracion. Se descarto porque la restriccion queda implicita en el orden de ejecucion del script (poblar R1 con `DISTINCT` antes de poblar R2) y el trigger introducia complejidad innecesaria para el alcance del ejercicio.
- **Verificacion realizada:** Ejecucion del script en `foodstore_dev` mediante `psql -U postgres -d foodstore_dev -f tp_fnbc_control_lote.sql`. Las pruebas de equivalencia de conjuntos con `EXCEPT` en ambas direcciones devolvieron `(0 rows)`:
  - **Direccion A** (`vw_control_lote_almacen_compatibilidad EXCEPT control_lote_almacen`): 0 filas, confirmando que la vista no genera tuplas espurias.
  - **Direccion B** (`control_lote_almacen EXCEPT vw_control_lote_almacen_compatibilidad`): 0 filas, confirmando que ninguna tupla de la instancia original fue perdida por la descomposicion.
  - La propiedad lossless-join quedo demostrada experimentalmente sobre la instancia de prueba `(501,30,801)`, `(502,30,801)`, `(503,31,802)`.

---

### DUIA - TP6 Parte 1 (Actualización): Carga de Datos de Prueba y Correcciones de Idempotencia

- **Herramienta:** Kiro (generacion y corrección iterativa de `data.sql`).
- **Spec o prompt utilizado:** _"Actualizar data.sql para agregar datos de prueba específicos de ventas del día actual (3.000 pedidos con CURRENT_DATE) y registros FNBC adicionales en deposito, lote, responsable_control y control_lote_almacen, manteniendo intacta la estructura DDL existente, usando ON CONFLICT DO NOTHING y generate_series para idempotencia."_
- **Qué generó:** Un bloque adicional (Bloque 2) en `data.sql` con: 3.000 pedidos de fecha actual distribuidos con hasta 4 ítems por pedido (offsets +0/+1/+2/+3 sobre el índice de producto para evitar colisiones de PK compuesta), y 5 registros adicionales en `deposito` (ids 32–36), `lote` (ids 504–508, fechas en 2027), `responsable_control` (ids 803–807) y `control_lote_almacen` (8 tuplas totales, replicando la anomalía DF2 en los lotes 504–505 con responsable 803 y depósito 32).
- **Qué se aceptó:** La estrategia de offsets numéricos consecutivos (+1, +2, +3) para garantizar unicidad en la PK compuesta `(id_pedido, id_producto)` sin necesidad de subconsultas de deduplicación, y el rango de IDs separados de los datos del script FNBC para evitar colisiones con `ON CONFLICT`.
- **Qué se modificó o descartó:**
  - **`ON CONFLICT` en productos y clientes:** la primera versión del Bloque 1 carecía de cláusula `ON CONFLICT` en los INSERT de `producto` y `cliente`, provocando `ERROR: llave duplicada viola restricción de unicidad «producto_nombre_key»` al reejecutar. Se agregaron `ON CONFLICT (nombre) DO NOTHING` y `ON CONFLICT (email) DO NOTHING` respectivamente.
  - **Tablas temporales sin DROP previo:** el Bloque 2 usaba `CREATE TEMP TABLE` sin verificar existencia previa. Al reejecutar en una sesión abierta, el motor reportó `ERROR: la relación «tmp_prods» ya existe`. Se incorporó `DROP TABLE IF EXISTS` antes de cada `CREATE TEMP TABLE` en ambos bloques.
  - **Error de sintaxis en comentario inline:** el texto `(5 registros adicionales)` quedó accidentalmente en la misma línea que `ANALYZE detalle_pedido;`, generando `ERROR: error de sintaxis en o cerca de «5»`. Se corrigió separando el comentario en una línea `--` independiente.
  - **FK violation en `control_lote_almacen`:** como consecuencia del error anterior, el INSERT de `deposito` no se ejecutó antes del INSERT en `control_lote_almacen`, fallando por `(deposito_id)=(32) no está presente en la tabla «deposito»`. Se reordenaron todos los INSERT del Bloque 2 dentro de un único `BEGIN...COMMIT` garantizando que `deposito`, `lote` y `responsable_control` se inserten antes de `control_lote_almacen`.
  - **Centralización de DROPs:** a pedido explícito, los `DROP TABLE` de tablas temporales se extrajeron de su posición inline (entre sentencias de negocio) y se centralizaron en una sección documentada al final del archivo, comentados, con nota aclaratoria sobre su comportamiento en sesiones largas.
- **Verificación realizada:** Ejecución completa de `data.sql` en `foodstore_dev` con `\i data.sql`. Resultado sin errores: `INSERT 0 49978` productos (22 colisiones absorbidas), `INSERT 0 20000` clientes, `INSERT 0 200000` pedidos históricos, `INSERT 0 3000` pedidos del día actual, `INSERT 0 2400 + 1000 + 300` detalles del día, `INSERT 0 5` en `deposito` y `control_lote_almacen`. Los `NOTICE` de `la tabla no existe, omitiendo` en los `DROP IF EXISTS` son el comportamiento esperado en primera ejecución.

---

### DUIA - TP6 Parte 2: Análisis de Rendimiento con EXPLAIN ANALYZE (Consulta Top 5 Categorías)

- **Herramienta:** Kiro (adaptación de consulta al esquema real y análisis del plan de ejecución).
- **Spec o prompt utilizado:** _"Adaptar la consulta EXPLAIN ANALYZE de Top 5 categorías por ventas del día a los nombres de columnas reales del esquema de FoodStore (pedido.fecha_hora en lugar de pedido.fecha, eliminando columnas eliminado inexistentes) y documentar el diagnóstico del plan antes y después de cargar pedidos del día actual."_
- **Qué generó:** La consulta adaptada con `DATE(ped.fecha_hora) = CURRENT_DATE` en lugar de `ped.fecha = CURRENT_DATE`, eliminando los filtros `dp.eliminado = FALSE` y `ped.eliminado = FALSE` ausentes en el esquema físico. Análisis del plan de ejecución identificando el `Parallel Seq Scan` sobre `pedido` como cuello de botella al evaluar más de 200.000 filas para filtrar por la función `DATE()` sobre `fecha_hora`.
- **Qué se aceptó:** La identificación del nodo `Parallel Seq Scan` como operación dominante y la interpretación del cambio en el algoritmo de ordenamiento de `quicksort` a `top-N heapsort` al procesar datos reales del día.
- **Qué se modificó o descartó:** La consulta original referenciaba `pedido.fecha` (columna inexistente) y columnas `eliminado` en `detalle_pedido` y `pedido` que no existen en el esquema de FoodStore. Se corrigieron contra el `schema.sql` real antes de ejecutar.
- **Verificación realizada:** Ejecución de `EXPLAIN ANALYZE` en dos escenarios documentados con las métricas concretas de la tabla comparativa:

| Métrica / Operación | Sin Pedidos del Día | Con Pedidos del Día | Observación Técnica |
| :--- | :--- | :--- | :--- |
| Tiempo de Ejecución | 25.21 ms | 132.42 ms | Incremento por procesamiento efectivo de datos de la fecha actual. |
| Filas Retornadas | 0 filas | 5 filas | Top 5 de categorías calculado con montos reales. |
| Lectura de `pedido` | 200.000 descartadas / 0 de hoy | 199.391 descartadas / 7.218 de hoy | `Parallel Seq Scan` con filtro por función `DATE()` sobre `fecha_hora`. |
| Lectura de `detalle_pedido` | 0 filas (`never executed`) | 15.238 filas procesadas | Lectura e integración de ítems para cálculo de subtotal. |
| Workers Paralelos | 1 worker | 2 workers | Paralelización para procesamiento intensivo de datos. |
| Método de Ordenamiento | `quicksort` (memoria) | `top-N heapsort` (memoria) | Algoritmo optimizado para retención de los 5 mayores subtotales. |

  El diagnóstico principal identificado: el filtro `DATE(ped.fecha_hora) = CURRENT_DATE` aplica una función sobre la columna, impidiendo el uso de cualquier índice sobre `fecha_hora`. Con 200.000+ pedidos históricos evaluados en cada ejecución para retener únicamente los 7.218 del día actual, el `Parallel Seq Scan` descarta el 97.4% de las filas leídas. Este cuello de botella es candidato a optimización mediante un índice funcional `CREATE INDEX ON pedido (DATE(fecha_hora))` o reescritura del filtro con rango explícito `fecha_hora >= CURRENT_DATE AND fecha_hora < CURRENT_DATE + 1`.
