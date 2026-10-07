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

### DUIA - Unidad 4 (TP6) 

## Parte 1: Normalización Avanzada (FNBC) en `control_lote_almacen`

* **Herramienta:** Kiro (generación de especificación en `specs/tp_fnbc_control_lote.md` y script `tp_fnbc_control_lote.sql`).
* **Prompt / Requisito:** Generar el DDL `tp_fnbc_control_lote.sql` para la base `foodstore_dev` que detecte y corrija una violación de la FNBC en la tabla `control_lote_almacen(lote_id, deposito_id, responsable_control_id)`, aplicando el **Teorema de Heath** para descomponerla en dos relaciones en FNBC, con vista de compatibilidad y prueba de equivalencia mediante `EXCEPT` bidireccional.
* **Qué se generó:** El DDL en 6 pasos que incluye dominios reutilizables (`codigo_producto_dom`, `dni_arg_dom`), tablas maestras, esquema defectuoso original, descomposición en FNBC ($R_1$: `responsable_deposito` y $R_2$: `control_lote_responsable`), vista de compatibilidad `vw_control_lote_almacen_compatibilidad`, migración de datos y prueba *lossless-join*.
* **Qué se aceptó:**
* Descomposición por Teorema de Heath.
* Clave foránea de $R_2$ apuntando a `responsable_deposito` para garantizar la reunión sin pérdida.
* Uso de `SELECT DISTINCT` en la migración a $R_1$ para colapsar filas redundantes.
* Dominios de PostgreSQL para centralizar reglas de validación.


* **Qué se modificó o descartó:**
* **Codificación de encabezado:** Se eliminaron símbolos Unicode del encabezado del script que causaban un error de conversión en `psql` bajo codificación `WIN1252/UTF-8` al iniciar la transacción (`BEGIN`).
* **Tipo de dato `fecha_vencimiento`:** Se rechazó `TIMESTAMPTZ` y se mantuvo `DATE` para reflejar la caducidad como fecha calendario pura.
* **Fechas de prueba:** Se actualizaron las fechas de los datos de prueba a 2027 para superar la restricción `CHECK (fecha_vencimiento >= CURRENT_DATE)`.
* **Trigger redundante:** Se descartó el trigger `fn_check_deposito_consistencia` al quedar garantizada la consistencia por el orden de migración de los datos.


* **Verificación realizada:** Ejecución mediante `psql` en `foodstore_dev`. Las pruebas de equivalencia de conjuntos con `EXCEPT` bidireccional entre la vista de compatibilidad y la tabla original devolvieron `(0 rows)`, demostrando la propiedad *lossless-join*.

---

## Parte 1 (Actualización): Carga de Datos de Prueba e Idempotencia

* **Herramienta:** Kiro (generación y corrección de `data.sql`).
* **Prompt / Requisito:** Actualizar `data.sql` para incorporar 3.000 pedidos del día actual (`CURRENT_DATE`) y registros FNBC adicionales, manteniendo idempotencia con `ON CONFLICT DO NOTHING` y `generate_series`.
* **Qué se generó:** Un bloque adicional en `data.sql` con 3.000 pedidos diarios con *offsets* numéricos en la clave compuesta de `detalle_pedido` y 5 registros adicionales para tablas maestras y de control de lote.
* **Qué se aceptó:** Estrategia de *offsets* para asegurar unicidad en `(id_pedido, id_producto)` y rangos de ID independientes para evitar colisiones.
* **Qué se modificó o descartó:**
* **Cláusula `ON CONFLICT`:** Se agregó a las inserciones de `producto` y `cliente` para prevenir errores de unicidad en reejecuciones.
* **Tablas temporales:** Se incorporó `DROP TABLE IF EXISTS` antes de cada `CREATE TEMP TABLE` para evitar colisiones en sesiones abiertas.
* **Corrección de errores de sintaxis y FK:** Se corrigió un comentario desordenado que impedía la ejecución del bloque de depósitos, envolviendo todas las inserciones en un único bloque transaccional `BEGIN...COMMIT`.
* **Centralización de DROPs:** Se trasladaron las sentencias de limpieza al final del archivo.


* **Verificación realizada:** Ejecución exitosa de `data.sql` en `foodstore_dev` (`\i data.sql`), insertando o procesando sin errores el histórico completo y los datos del día actual.

---

## Parte 2: Análisis de Rendimiento con `EXPLAIN ANALYZE` (Consulta Top 5 Categorías)

* **Herramienta:** Kiro (adaptación de consulta y análisis de plan de ejecución).
* **Prompt / Requisito:** Adaptar la consulta del Top 5 de categorías por ventas del día al esquema real de la base de datos (`pedido.fecha_hora`) y diagnosticar los cuellos de botella con `EXPLAIN ANALYZE`.
* **Qué se generó:** Consulta adaptada utilizando `DATE(ped.fecha_hora) = CURRENT_DATE` y diagnóstico del plan de ejecución identificando la lectura secuencial paralela sobre la tabla de pedidos.
* **Qué se aceptó:** Diagnóstico del nodo `Parallel Seq Scan` como cuello de botella dominante debido al uso de la función `DATE()` sobre una columna sin índice funcional.
* **Qué se modificó o descartó:** Se removieron referencias a columnas inexistentes en el esquema físico (`pedido.fecha` y campos `eliminado`).
* **Verificación realizada:** Medición con `EXPLAIN ANALYZE`:

| Métrica / Operación | Sin Pedidos del Día | Con Pedidos del Día | Observación Técnica |
| --- | --- | --- | --- |
| **Tiempo de Ejecución** | 25.21 ms | 132.42 ms | Incremento por procesamiento de transacciones del día. |
| **Filas Retornadas** | 0 filas | 5 filas | Top 5 calculado con importes reales. |
| **Lectura de `pedido**` | 200.000 descartadas | 199.391 descartadas / 7.218 de hoy | `Parallel Seq Scan` evaluando la función `DATE()`. |
| **Lectura de `detalle_pedido**` | 0 filas | 15.238 filas procesadas | Lectura de ítems para cálculo de subtotal. |
| **Workers Paralelos** | 1 worker | 2 workers | Paralelización para el procesamiento de datos. |
| **Ordenamiento** | `quicksort` | `top-N heapsort` | Algoritmo optimizado para retención del Top 5. |

---

## Parte 2: Desnormalización Controlada (Top 5 Categorías por Ventas del Día)

* **Herramienta:** Kiro (generación del script `tp_desnormalizacion_top_categorias.sql`, análisis de plan de ejecución y tabla comparativa).
* **Prompt / Requisito:** Implementar una estrategia de desnormalización controlada mediante una vista materializada (`mv_ventas_categoria_diario`), un índice único compuesto sobre `(fecha, categoria)` y una función PL/pgSQL (`fn_refrescar_top5_categorias()`) para sincronización concurrente.
* **Qué se generó:** El script `tp_desnormalizacion_top_categorias.sql` con los tres objetos DDL, comentarios técnicos ASCII, sentencias idempotentes (`DROP ... IF EXISTS CASCADE`) y documentación para invocación programada (`pg_cron` / `crontab`).
* **Qué se aceptó:**
* Agrupamiento por `DATE(ped.fecha_hora)` y `c.nombre` para preservar el histórico en la vista materializada y eludir la restricción de PostgreSQL sobre funciones volátiles (`CURRENT_DATE`) en DDL.
* Índice único compuesto `(fecha, categoria)` para permitir `REFRESH MATERIALIZED VIEW CONCURRENTLY` y optimizar la lectura directa.
* Uso de `precio_unitario_historico` de `detalle_pedido` para garantizar la exactitud contable transaccional.


* **Qué se modificó o descartó:**
* **Filtro dinámico en DDL:** Se descartó incluir `WHERE DATE(ped.fecha_hora) = CURRENT_DATE` en el DDL de la vista por restricción del motor ante funciones volátiles.
* **Índice simple:** Se descartó el índice sobre `(categoria)` al no ser único en la vista materializada, impidiendo el refresco concurrente.


* **Verificación realizada:**
* Ejecución exitosa e idempotente del script en `foodstore_dev` y `foodstore_test`.
* **Medición de rendimiento (`EXPLAIN ANALYZE`):**



| Métrica / Aspecto | Antes (Tablas 3FN) | Después (Vista Materializada) |
| --- | --- | --- |
| **Consulta SQL** | 4 JOINs + GROUP BY + filtro `DATE()` en tiempo real | Lectura directa sobre la MV con `WHERE fecha = CURRENT_DATE` |
| **Tiempo de Ejecución** | 132.42 ms | **0.070 ms** |
| **Reducción de Tiempo** | — | **99.94% más rápida (~1.890x de ganancia)** |
| **Nodo Dominante** | `Parallel Seq Scan` sobre `pedido` (200.000+ filas) | `Bitmap Index Scan` sobre `idx_mv_ventas_fecha_cat` |
| **Filas Procesadas** | 200.000+ pedidos + 15.238 detalles | **14 filas preagregadas** (`Heap Blocks: exact=1`) |
| **Workers / JOINs** | 2 workers / 4 JOINs | 0 workers / 0 JOINs |
| **Lectura de Disco** | Múltiples *buffers* sobre 4 tablas | **1 bloque** en disco (`Heap Blocks: exact=1`) |

* **Auditoría de consistencia:** La comparación mediante `EXCEPT` bidireccional entre las tablas operativas y la vista materializada devolvió `(0 rows)`, confirmando la ausencia de desincronización o inconsistencia de datos.
* **Versionado:** Commit registrado en Git (`feat: creacion del script tp_desnormalizacion_top_categorias.sql para desnormalizacion controlada`).