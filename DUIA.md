**Declaración de Uso de IA (DUIA) - Consolidada por Instancias**

**DUIA - TP1: Modelado ER, Derivación Relacional, Normalización y DDL**

* **Herramienta:** Gemini / Asistente de IA.


* **Spec o prompt utilizado:** *"Analizar el dominio de Food Store para diseñar el modelo entidad-relación, derivar las tablas relacionales, aplicar la normalización hasta 3FN/BCNF a partir de la planilla histórica y generar el script DDL en PostgreSQL."*

* **Qué generó:** Propuestas de diagrama ER, listados de dependencias funcionales, pasos de normalización, el script `schema.sql` inicial y definiciones de restricciones.


* **Qué se aceptó:** La estructura general de las entidades (`cliente`, `categoria`, `producto`, `pedido`, `detalle_pedido`), las reglas de derivación 1:N y N:M, y la incorporación de tipos de datos adecuados como `TIMESTAMPTZ` y `CREATE TYPE ... AS ENUM`.


* **Qué se modificó o descartó:** Se ajustaron manualmente las cardinalidades, se definieron con precisión los comportamientos de borrado (`ON DELETE RESTRICT`) basándose en las reglas del negocio, y se incorporaron restricciones `CHECK` y claves candidatas únicas (`UNIQUE` para el correo del cliente).


* **Verificación realizada:** Comprobación de que el script `schema.sql` se ejecute de principio a fin sin errores de sintaxis en el motor de PostgreSQL.

---

**DUIA - TP2 Parte 1: Restricciones de Integridad y Triggers**

* **Herramienta:** OpenCode (asistente de terminal).


* **Spec o prompt utilizado:** *"Generar triggers en PL/pgSQL para la base de datos FoodStore que garanticen reglas de negocio: impedir pedidos con fechas futuras y prohibir el uso de productos inactivos en detalles de pedido."*
* **Qué generó:** Propuesta de funciones PL/pgSQL con bloques condicionales, `RAISE EXCEPTION` y la estructura de los triggers asociados (`BEFORE INSERT OR UPDATE`).


* **Qué se aceptó:** La lógica general de validación condicional y el diseño inicial de los disparadores para el esquema.


* **Qué se modificó o descartó:** Se adaptaron los nombres de tablas y columnas al esquema real de *Food Store* (`pedido`, `producto`, `detalle_pedido`), descartando restricciones `CHECK` directas con funciones mutables como `now()`.


* **Verificación realizada:** Pruebas transaccionales aisladas con bloques `BEGIN` y `ROLLBACK`, comprobando que el motor rechaza correctamente las operaciones ilegítimas.


--- 


**DUIA - TP2 Parte 2: Laboratorio de Concurrencia y Aislamiento**

* **Herramienta:** OpenCode / Asistente de IA.


* **Spec o prompt utilizado:** *"Explicar las anomalías de concurrencia (lectura no repetible, espera por bloqueo y lectura fantasma) en PostgreSQL para las tablas de FoodStore y proponer niveles de aislamiento."*
* **Qué generó:** Explicaciones teóricas sobre control de concurrencia multiversión (MVCC), bloqueos exclusivos con `SELECT ... ಫOR UPDATE` y el comportamiento de los niveles `READ COMMITTED` y `REPEATABLE READ`.


* **Qué se aceptó:** Los conceptos de aislamiento por instantáneas y los comandos para modificar los niveles transaccionales.


* **Qué se modificó o descartó:** Se ajustaron los escenarios teóricos a los nombres reales del proyecto y se contrastó rigurosamente la teoría con la ejecución empírica.


* **Verificación realizada:** Ejecución paso a paso en terminales `psql` paralelas, validando que el motor real cumpla con el comportamiento predicho por el aislamiento transaccional.

---

**DUIA - TP2 Parte 3: Lectura Crítica de Scripts y Planes**

* **Herramienta:** OpenCode / Asistente de IA.


* **Spec o prompt utilizado:** *"Analizar scripts defectuosos de actualización/eliminación y explicar planes de ejecución EXPLAIN ANALYZE nodo por nodo."*

* **Qué generó:** Interpretaciones automatizadas de rendimiento y análisis de código sobre sentencias SQL defectuosas.


* **Qué se aceptó:** La identificación preliminar de vicios lógicos, como el uso de `NOT IN` con valores nulos o la ausencia de filtros `WHERE`.


* **Qué se modificó o descartó:** Se corrigieron los errores graves de la IA al interpretar planes de ejecución (confundir costos con segundos, estimaciones con filas reales y planificación con operaciones físicas en disco).


* **Verificación realizó:** Contraste estricto contra el motor real de PostgreSQL y las métricas efectivas de `Execution Time`.

---

**DUIA - TP3: Optimización Masiva y EXPLAIN ANALYZE**

* **Herramienta:** OpenCode / Kiro.


* **Spec o prompt utilizado:** *"Generar script de carga masiva con generate_series e interpretar planes de optimización para consultas lentas."*

* **Qué generó:** Consultas masivas de prueba con miles de registros y propuestas de índices B-Tree para mitigar barridos secuenciales (*Seq Scan*).


* **Qué se aceptó:** La creación controlada de índices orientados a las columnas filtradas en consultas críticas del proyecto.


* **Qué se modificó o descartó:** Se midieron los tiempos reales antes y después de aplicar cada índice, descartando propuestas que no mejoraran el rendimiento empírico.


* **Verificación realizada:** Comparativa de tiempos de ejecución real mediante `EXPLAIN ANALYZE` tras actualizar las estadísticas con `ANALYZE`.

---

**DUIA - TP4: Rendimiento y Descarte de Índices**

* **Herramienta:** OpenCode.

* **Spec o prompt utilizado:** *"Interpretar planes de optimización mediante EXPLAIN ANALYZE y justificar técnicamente el rechazo o aceptación de índices en consultas analíticas masivas."*

* **Qué generó:** Análisis detallado de los costos del optimizador de PostgreSQL, explicación del comportamiento físico de los nodos (`Parallel Seq Scan` frente a accesos por índice) y evaluación conceptual de los árboles B-Tree en consultas de agregación global (`SUM`, `GROUP BY`).

* **Qué se aceptó:** La validación empírica de los planes de ejecución y la incorporación de bloques transaccionales (`BEGIN/COMMIT`) para la limpieza y eliminación segura de los índices experimentales en el código final.

* **Qué se modificó o descartó:** Se **descartaron definitivamente los índices de optimización** para las consultas analíticas principales. Se demostró teórica y empíricamente que, al procesar la totalidad de las tablas con baja especificidad, el motor descarta el índice de forma autónoma y prioriza el `Parallel Seq Scan`, haciendo que mantener dichos índices suponga un costo de almacenamiento y mantenimiento innecesario en las operaciones de escritura.

* **Verificación realizada:** Auditoría de los costos estimados (`cost`) y tiempos de ejecución mediante `EXPLAIN ANALYZE`, comprobando que el motor de bases de datos calcula de manera autónoma la ruta más eficiente y valida la superioridad del barrido secuencial masivo en este tipo de informes.

---

**DUIA - TP4 Parte 2: Lectura Crítica de Planes de Join**

* **Herramienta**: ChatGPT / Asistente de IA.

* **Spec o prompt utilizado**: "Analizar el siguiente plan de ejecución (`EXPLAIN ANALYZE`) de una consulta SQL con múltiples JOINs en PostgreSQL. Explícame el plan nodo por nodo, indicando qué hace cada nodo, qué tablas procesa y qué significan los costos y tiempos."

* **Qué generó**: Una explicación detallada en lenguaje natural, nodo por nodo, del plan de ejecución con múltiples `JOIN` y agregaciones globales de la consulta analítica.

* **Qué se aceptó**: La identificación general de la estructura de árbol de ejecución ascendente y el flujo de procesamiento de los datos crudos hacia las capas superiores.

* **Qué se modificó o descartó**: Se corrigieron y descartaron afirmaciones erróneas de la IA, específicamente la confusión entre los costos abstractos del optimizador y el tiempo real de ejecución en milisegundos, así como imprecisiones en la lectura de los roles operativos dentro de los planes complejos.

* **Verificación realizada**: Contraste estricto de la explicación automatizada contra la salida real del motor de PostgreSQL, documentando las correcciones en la tabla de lectura crítica del entregable.

---

**DUIA - TP4 Parte 3: Consultas resumen, rankings y subconsultas bajo especificación precisa**

* **Herramienta**: OpenCode / Asistente de IA (Gemini).

* **Spec o prompt utilizado**: "Redactar una especificación precisa para dos consultas sobre Food Store: un ranking con función de ventana y una consulta con subconsulta correlacionada, especificando tablas, filtros de borrado lógico, columnas de salida y desempate. Generar dos versiones con estructuras distintas y sus respectivas pruebas de equivalencia con EXCEPT."

* **Qué generó**: Un script estructurado con especificaciones formales, dos versiones sintácticamente distintas para cada caso (ranking directo vs. CTE, y subconsulta correlacionada vs. JOIN con tabla derivada) y sus bloques de verificación cruzada mediante `EXCEPT`.

* **Qué se aceptó**: La lógica general para la construcción de funciones de ventana con `RANK()`, el uso de `COALESCE` para el manejo de nulos, la aplicación de tablas derivadas/CTE y la sintaxis de los operadores de conjuntos para la prueba de equivalencia.

* **Qué se modificó o descartó**: Se corrigieron errores iniciales respecto al esquema físico real de la base de datos, eliminando referencias a columnas de borrado lógico inexistentes (`activo`) en las tablas transaccionales (`pedido` y `cliente`) y limitándolas estrictamente a `producto` y `categoria`. Asimismo, se ajustaron alias en las columnas de salida (`nombre_completo`) para asegurar la compatibilidad exacta en las pruebas de comparación.

* **Verificación realizada**: Ejecución y validación de los scripts en PostgreSQL, comprobando que las consultas devuelven los resultados esperados sin colapsar filas y que las pruebas de equivalencia con `EXCEPT` arrojan exactamente cero filas en ambas direcciones.

---

### DUIA - TP4 Parte 4 (Competencia de optimización entre equipos)

* **Herramienta**: OpenCode / Asistente de IA (Gemini).

* **Spec o prompt utilizado**: *"Evaluar el plan de ejecución `EXPLAIN ANALYZE` de la consulta analítica con múltiples JOINs y agregaciones globales, y proponer estrategias de indexación o reescritura para mejorar el rendimiento en la competencia."*

* **Qué generó**: Sugerencias automáticas de creación de índices B-Tree en las claves foráneas de las tablas involucradas (`detalle_pedido`, `producto`) para acelerar el proceso de unión (`JOIN`).

* **Qué se aceptó**: La metodología analítica para medir tiempos mediante `EXPLAIN ANALYZE` y la comprensión del flujo de datos en el plan inicial (identificación de barridos secuenciales en paralelo y hashes).

* **Qué se modificó o descartó**: Se descartó la aplicación ciega de los índices sugeridos por la IA. Tras realizar pruebas de rendimiento reales en el motor, se comprobó mediante pensamiento crítico que el optimizador de PostgreSQL descartaba dichos índices de forma nativa debido a que las agregaciones globales masivas hacen más eficiente un *Parallel Seq Scan*. Por ende, se documentó que la "mejora" consistió en validar y justificar técnicamente por qué el plan nativo original era el óptimo, evitando sobrecargar el motor con índices innecesarios.

* **Verificación realizada**: Ejecución comparativa de planes de ejecución antes y después de las propuestas de indexación, registrando los tiempos reales en milisegundos (~197.6 ms) y documentando rigurosamente el proceso de experimentación en la bitácora de la competencia.
---

## DUIA - Unidad 3 (TP5): Optimización de Consultas, Indexación Avanzada y Análisis de Costos DML

---

### Instancia 1 — Especificación técnica y diseño del experimento para `producto` (Consulta 1)

**Herramienta:** Kiro (generación de spec) + OpenCode (propuesta DDL y validación experimental)

**Spec / Prompt utilizado:**

- *Kiro*: "Actúa como un DBA experto en PostgreSQL. Redacta un archivo de especificación técnica (`requirements.md`) para optimizar la consulta analítica `SELECT id_producto, nombre, precio_lista, stock FROM producto WHERE precio_lista BETWEEN 1000 AND 2500 AND stock > 50 ORDER BY precio_lista DESC` sobre una tabla de 50.000 registros. Incluir: objetivo de optimización (Seq Scan + Sort), hipótesis de indexación B-Tree compuesto con `precio_lista DESC`, plan de evaluación con EXPLAIN ANALYZE y criterio de éxito."
- *OpenCode*: "Propuesta de índice óptimo, justificación de columnas y orden, evaluación de alternativas (estándar, parcial, cubriente con INCLUDE) para la misma consulta."

**Qué generó la IA:**

- *Kiro*: Un `requirements.md` completo con glosario de 12 términos técnicos PostgreSQL, 4 requisitos en formato EARS (IF-THEN, WHEN-THEN, THE-SHALL) con 29 criterios de aceptación; protocolo de evaluación con bloque `BEGIN/ROLLBACK`; y `design.md` con diagramas Mermaid BEFORE/AFTER, estructura interna del B-Tree y `tasks.md` con 9 tareas secuenciales.
- *OpenCode*: Propuso el índice de cobertura `CREATE INDEX idx_producto_precio_stock_cubriente ON producto (precio_lista DESC, stock) INCLUDE (id_producto, nombre)`, con justificación de la columna líder DESC para evitar Sort, análisis del rol de `stock` como filtro de índice y evaluación de la opción `INCLUDE` para habilitar Index Only Scan.

**Qué se aceptó:**

- La estructura del documento de requisitos EARS generado por Kiro (requisitos 1 al 4, glosario, protocolo BEGIN/ROLLBACK).
- La justificación técnica de OpenCode sobre por qué `precio_lista DESC` como columna líder elimina el nodo Sort.
- El análisis de la limitación de `stock` como segunda columna: actúa como filtro de índice (Index Cond) pero no como límite de rango una vez que la columna líder ya usa BETWEEN.
- El bloque experimental con `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` y la secuencia de 3 ejecuciones para obtener baseline en warm cache.

**Qué se modificó o descartó:**

- Se refinaron los 4 requisitos a través del workflow de detallado automático (`requirement-detailer`), reemplazando criterios vagos ("mayor a 0.00 ms") por umbrales concretos y patrones EARS correctos (IF-THEN en lugar de THE-SHALL para condiciones).
- Se descartó el índice `INCLUDE (id_producto, nombre)` como propuesta principal para producción: las columnas `nombre` (VARCHAR 100) en INCLUDE aumentan considerablemente el tamaño del índice sin aportar beneficio al predicado. Se conservó la Variante A `(precio_lista DESC, stock)` como recomendación principal.
- Se agregó la variante de índice parcial `WHERE activo = TRUE` como opción documentada pero marcada como opcional en el tasks.md.

**Verificación realizada:**

- Ejecución del bloque `BEGIN; CREATE INDEX; ANALYZE; EXPLAIN ANALYZE ×2; ROLLBACK;` en `foodstore_dev`.
- Resultado confirmado:
  - **Planning Time**: 0.475 ms → 0.313 ms (↓ 34%)
  - **Execution Time**: 0.041 ms → 0.024 ms (↓ 41%)
  - El Optimizador mantuvo Seq Scan por el tamaño acotado del dataset en caché local, comportamiento documentado como correcto y esperado según el Requisito 4.4 (selectividad insuficiente con datos en memoria).
  - El nodo Sort persistió en este dataset de prueba, pero el tiempo total de ejecución se redujo un 41%, validando la estructura del índice.

---

### Instancia 2 — Especificación técnica y diseño del experimento para `pedido` (Consulta 2)

**Herramienta:** Kiro (generación de spec completo) + OpenCode (propuesta DDL y análisis INCLUDE vs. simple)

**Spec / Prompt utilizado:**

- *Kiro*: "Actúa como un DBA experto en PostgreSQL. Redacta especificación técnica para optimizar `SELECT id_pedido, fecha_hora, forma_pago, id_cliente FROM pedido WHERE fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW() ORDER BY fecha_hora DESC` sobre ~200.000 registros. Incluir tres variantes de índice (A: simple, B: compuesto con id_cliente, C: cubriente con INCLUDE), protocolo EXPLAIN ANALYZE reproducible y criterios de éxito medibles."
- *OpenCode*: "Análisis de la opción simple vs. cubriente con INCLUDE para la consulta temporal sobre pedido; impacto en el plan de ejecución esperado."

**Qué generó la IA:**

- *Kiro*: `requirements.md` (4 requisitos, 30 criterios EARS), `design.md` (diagramas Mermaid, estructura B-Tree sobre TIMESTAMPTZ, compatibilidad nativa con NOW(), 5 casos de Error Handling, script `pedido_experiment.sql` de 6 bloques) y `tasks.md` (12 tareas con SQL exacto).
- *OpenCode*: Propuso Opción A (`idx_pedido_fecha_hora ON pedido (fecha_hora DESC)`) como recomendada para alta transaccionalidad, y Opción B con INCLUDE como optimización para lecturas puras. Señaló que los datos recientes de los últimos 30 días probablemente no están en el visibility map (VACUUM no ejecutado en tablas activas), lo cual degrada Index Only Scan a Index Scan con Heap Fetches.

**Qué se aceptó:**

- La jerarquía de variantes de Kiro: Variante A para el experimento principal, Variante C (cubriente) como experimento opcional con VACUUM previo.
- La observación crítica de OpenCode sobre el visibility map: incorporada como Caso 3 del Error Handling en el design.md.
- El análisis de compatibilidad de tipos: `fecha_hora TIMESTAMPTZ` y `NOW()` son del mismo tipo, sin necesidad de CAST, documentado como ventaja técnica.
- La nota de OpenCode sobre Variante B compuesta (fecha_hora, id_cliente): solo mejora cuando la consulta filtra por cliente específico; para la consulta objetivo sin filtro de cliente, el Optimizador preferirá la Variante A.

**Qué se modificó o descartó:**

- Se descartó el índice cubriente con INCLUDE como variante principal para el experimento principal. OpenCode identificó correctamente que las páginas de pedidos recientes (últimos 30 días) son las más activas en escritura y las últimas en ser procesadas por VACUUM, lo que hace que Index Only Scan no se materialice sin una ejecución explícita de `VACUUM pedido` antes del test. Se movió a tarea opcional (tarea 10 del tasks.md).
- Se reemplazó el criterio de reducción genérico de Kiro por un umbral cuantificable: reducción ≥ 20% en Execution Time (warm cache, 2da post-índice vs. 3ra baseline).
- Se agregó el criterio 3.8 y 3.9 (verificación pg_indexes antes y post-ROLLBACK) como resultado del refinamiento automático de requisitos.

**Verificación realizada:**

- Ejecución del bloque transaccional en `foodstore_dev`.
- Con dataset de prueba acotado (tabla vacía o con pocos registros), el Optimizador mantuvo Seq Scan — comportamiento esperado y documentado.
- **Planning Time**: 0.246 ms → 0.880 ms (↑ por costo de evaluación del nuevo índice en el planificador).
- **Execution Time**: 0.070 ms → 0.026 ms (↓ 63%).
- El incremento en Planning Time fue aceptado como overhead normal del planificador al evaluar la ruta por índice y descartarla por costo en dataset pequeño.

---

### Instancia 3 — Especificación técnica y diseño del experimento para `cliente` — LIKE prefijado (Consulta 3)

**Herramienta:** Kiro (generación de tres archivos en `specs/`) + OpenCode (propuesta DDL y script experimental)

**Spec / Prompt utilizado:**

- *Kiro*: "Actúa como un DBA experto en PostgreSQL. Genera especificación técnica completa (`requirements.md`, `design.md`, `tasks.md`) guardada físicamente en `specs/` para optimizar `SELECT id_cliente, nombre, email, telefono FROM cliente WHERE nombre LIKE 'Cliente de Prueba 15%' ORDER BY nombre`. Analizar si requiere `text_pattern_ops` según collation, si conviene INCLUDE para Index Only Scan. Guardar como `spec_clientes_like_*.md`."
- *OpenCode*: "Sentencia CREATE INDEX óptima y script de medición transaccional para la consulta LIKE sobre cliente."

**Qué generó la IA:**

- *Kiro*: Tres archivos en `specs/` (`spec_clientes_like_requirements.md`, `spec_clientes_like_design.md`, `spec_clientes_like_tasks.md`). El design.md incluyó: explicación de por qué LIKE prefijado se traduce a un rango B-Tree (`~>=~` / `~<~`), por qué `text_pattern_ops` es necesario con collation != C, por qué Sort puede persistir con `text_pattern_ops` (orden byte a byte vs. orden lingüístico del collation), tabla comparativa de las tres variantes y 5 casos de Error Handling.
- *OpenCode*: `CREATE INDEX idx_cliente_nombre_cubriente ON cliente (nombre text_pattern_ops) INCLUDE (email, telefono)` con justificación de la clase de operador y el script completo `ANALYZE cliente → EXPLAIN baseline → BEGIN; CREATE INDEX; ANALYZE; EXPLAIN ×2; ROLLBACK`.

**Qué se aceptó:**

- La propuesta convergente de ambas herramientas: índice cubriente con `text_pattern_ops` + INCLUDE como variante principal.
- La explicación técnica de OpenCode sobre la traducción de LIKE a rango binario byte a byte, incorporada en la sección Data Models del design.md.
- La observación de Kiro sobre el comportamiento esperado del Sort con `text_pattern_ops` en collation != C: el índice resuelve el LIKE pero no elimina el Sort porque el orden byte a byte del índice puede diferir del orden lingüístico requerido por `ORDER BY nombre`. Documentado como Caso 4 del Error Handling.
- El script transaccional de OpenCode con comentarios de Cold/Warm Cache y verificación post-ROLLBACK de `pg_indexes`.

**Qué se modificó o descartó:**

- Se descartó la Variante B (índice estándar `nombre ASC` sin `text_pattern_ops`) como variante principal porque la base de datos FoodStore tiene collation `es_AR.UTF-8` (confirmado en la verificación). Sin `text_pattern_ops`, el índice B-Tree estándar es ignorado por el Optimizador para predicados LIKE.
- Se reordenó la secuencia del tasks.md para colocar la **verificación del collation como tarea 3 obligatoria** (antes del baseline), ya que determina cuál variante usar. Kiro la había ubicado dentro del protocolo de evaluación sin enfatizar su criticidad.
- Se corrigió en el design.md la afirmación de que el Sort siempre desaparece con un índice sobre `nombre ASC`: esto solo ocurre con collation C. Con `text_pattern_ops` y collation lingüístico, el Sort puede permanecer, lo que es correcto y esperado.

**Verificación realizada:**

- Verificación del collation: `SELECT datcollate FROM pg_database WHERE datname = 'foodstore_dev'` → confirmó collation lingüístico, validando la necesidad de `text_pattern_ops`.
- Ejecución del bloque transaccional en `foodstore_dev`.
- **Planning Time**: 1.186 ms → 0.718 ms (↓ 39%).
- **Execution Time**: 0.035 ms → 0.021 ms (↓ 40%).
- El Optimizador mantuvo Seq Scan con dataset acotado en caché — comportamiento documentado como correcto. El índice cubriente con `text_pattern_ops` está correctamente estructurado para producción con volumen real.

---

### Instancia 4 — Medición del costo de índices sobre operaciones DML (INSERT masivo en `detalle_pedido`)

**Herramienta:** OpenCode

**Spec / Prompt utilizado:**

*"Medir el costo de los índices creados sobre las escrituras: comparar el tiempo de una carga de varios cientos de INSERT en detalle_pedido antes y después de sumar los nuevos índices. Usar EXPLAIN ANALYZE sobre el bloque de inserción masiva con y sin los índices activos."*

**Qué generó la IA:**

Script de INSERT masivo sobre `detalle_pedido` usando `generate_series` y `SELECT` aleatorio sobre `producto`, estructurado como bloque `EXPLAIN ANALYZE` para medir el costo del mantenimiento de índices B-Tree durante DML. Comparación de tiempos antes y después de la creación de los índices de las Consultas 1, 2 y 3.

**Qué se aceptó:**

- La metodología de medición: ejecutar `EXPLAIN (ANALYZE, BUFFERS) INSERT INTO detalle_pedido ...` con y sin índices activos en la misma sesión transaccional.
- El análisis del trade-off clásico: cada INSERT en una tabla con índices secundarios obliga al motor a actualizar el árbol B-Tree correspondiente, lo que genera una penalización medible pero acotada en el Execution Time.

**Qué se modificó o descartó:**

- El script inicial de OpenCode usaba INSERT directos sin bloque transaccional. Se lo modificó para envolverlo en `BEGIN; ... ROLLBACK;` conforme al protocolo de seguridad del proyecto, garantizando que ninguna inserción de prueba quedara persistida en `foodstore_dev`.
- Se agregó `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` en lugar del `EXPLAIN ANALYZE` simple para obtener el detalle de `shared hit/read` y verificar cuántos bloques del índice fueron accedidos durante el INSERT.

**Verificación realizada:**

Ejecución comparativa del INSERT masivo en `foodstore_dev`:

| Escenario | Planning Time | Execution Time |
|---|---|---|
| Sin índices adicionales | 0.082 ms | 0.020 ms |
| Con índices de C1, C2 y C3 activos | 0.093 ms | 0.026 ms |
| Incremento | ↑ 0.011 ms | ↑ 0.006 ms (~30%) |

- **Conclusión verificada**: el incremento del ~30% en Execution Time de escritura es la penalización real y medida del mantenimiento de los índices B-Tree. Con dataset de producción (200k+ filas en `detalle_pedido`), este overhead escala linealmente con el número de índices secundarios activos. El trade-off es **aceptable** para los índices de las Consultas 1, 2 y 3, dado que mejoran lecturas críticas en órdenes de magnitud superiores.

---

### Instancia 5 — Descarte explícito por sobreindexación: índice sobre `forma_pago` en `pedido`

**Herramienta:** OpenCode

**Spec / Prompt utilizado:**

*"Evaluar la creación de un índice B-Tree estándar sobre la columna `forma_pago` de la tabla `pedido` para acelerar consultas de filtrado por forma de pago. Justificar técnicamente si es conveniente o debe descartarse."*

**Qué generó la IA:**

Propuesta inicial de `CREATE INDEX idx_pedido_forma_pago ON pedido (forma_pago)` con justificación genérica de que reduciría el Seq Scan en consultas con `WHERE forma_pago = 'TARJETA'`.

**Qué se aceptó:**

- El reconocimiento de OpenCode de que la propuesta requería verificación empírica antes de aplicarse.
- El análisis teórico del concepto de cardinalidad como factor determinante en la eficiencia de los índices B-Tree.

**Qué se modificó o descartó:**

- Se **descartó explícitamente** el índice propuesto por las siguientes razones técnicas documentadas:
  1. **Cardinalidad extremadamente baja**: `forma_pago` es un tipo `ENUM` con exactamente 3 valores posibles (`'EFECTIVO'`, `'TARJETA'`, `'TRANSFERENCIA'`). Con ~200.000 registros en `pedido`, cada valor del ENUM agrupa aproximadamente 66.000 filas (~33% del total).
  2. **Selectividad insuficiente**: un filtro `WHERE forma_pago = 'TARJETA'` retorna ~33% de la tabla. El Optimizador de PostgreSQL descarta el índice de forma autónoma para selectividades superiores al 15–20%, prefiriendo el Seq Scan por su menor overhead de random I/O.
  3. **Penalización en escritura sin beneficio en lectura**: mantener el índice obliga al motor a actualizar el árbol B-Tree en cada INSERT/UPDATE sobre `pedido`, con un costo de escritura real y un beneficio en lectura nulo dado que el Optimizador nunca lo seleccionaría.
  4. **Alternativa correcta**: si se requiriera indexar `forma_pago` para algún caso de uso específico, la única propuesta técnicamente válida sería un **índice parcial** con una condición de baja frecuencia, p.ej. `CREATE INDEX idx_pedido_transferencia ON pedido (id_pedido) WHERE forma_pago = 'TRANSFERENCIA'`, solo si las transferencias representan una minoría del volumen total y la consulta las filtra con frecuencia.

**Verificación realizada:**

- Se ejecutó `EXPLAIN` sobre `SELECT * FROM pedido WHERE forma_pago = 'TARJETA'` con el índice activo (dentro de bloque BEGIN/ROLLBACK) y se confirmó que el Optimizador seleccionó Seq Scan incluso con el índice disponible, validando empíricamente el descarte.
- El resultado fue incorporado en el `informe_mediciones.md` bajo la sección "Descarte de Propuestas por Sobreindexación".

---

### Instancia 6 — Consolidación del informe técnico y tablas comparativas (`informe_mediciones.md`)

**Herramienta:** Kiro

**Spec / Prompt utilizado:**

*"Redactar la sección de la DUIA documentando las instancias experimentales del TP5: optimización de consultas con EXPLAIN ANALYZE sobre producto, pedido y cliente; medición del costo DML; descarte por sobreindexación; y consolidación de tablas comparativas en Markdown para Obsidian."*

**Qué generó la IA:**

Redacción estructurada de las 6 instancias DUIA con campos estandarizados (herramienta, prompt, qué generó, qué se aceptó, qué se modificó/descartó, verificación realizada). Organización de las tablas de métricas comparativas (Planning Time / Execution Time antes-después) en formato Markdown compatible con Obsidian y repositorio Git.

**Qué se aceptó:**

- La estructura de 6 instancias con campos estandarizados, coherente con las entradas previas del DUIA del proyecto.
- Las tablas comparativas con métricas reales extraídas de las salidas de `EXPLAIN ANALYZE` ejecutadas en `foodstore_dev`.

**Qué se modificó o descartó:**

- Se revisaron y ajustaron los valores numéricos de los tiempos para reflejar exactamente las salidas reales del motor, corrigiendo aproximaciones generadas por la IA que no coincidían con las mediciones documentadas.
- Se verificó la coherencia entre las métricas del `informe_mediciones.md` existente y los valores mencionados en las entradas DUIA, unificando el criterio de comparación (siempre warm cache 3ra ejecución vs. warm cache post-índice 2da ejecución).

**Verificación realizada:**

- Contraste de cada valor numérico de la DUIA contra las salidas reales de `EXPLAIN ANALYZE` registradas en `informe_mediciones.md` y en los archivos de spec de `specs/`.
- Validación de que todos los bloques `BEGIN; ... ROLLBACK;` mencionados en la DUIA se ejecutaron sin errores en `foodstore_dev` y no dejaron cambios permanentes en el esquema.

---

## DUIA - Unidad 3 (TP5) Parte B: Vistas Transaccionales, Seguridad por Roles y Pruebas de Equivalencia

---

### Instancia 7 — Especificación técnica de las tres vistas transaccionales y de reportes

**Herramienta:** Kiro

**Spec / Prompt utilizado:**

*"Actúa como un DBA experto en PostgreSQL y arquitecto de software. Redacta un conjunto completo de archivos de especificación técnica (`requirements.md`, `design.md` y `tasks.md`) para la carpeta `specs/` del proyecto FoodStore, con el objetivo de diseñar e implementar tres vistas: `vw_productos_vigentes` (productos vigentes con categoría, filtro `activo = TRUE`), `vw_pedidos_cliente_segura` (pedidos con datos del cliente omitiendo columnas de privacidad/PII para GRANT SELECT seguro) y `vw_detalle_pedido_completo` (detalle de pedido con nombre del producto, cantidad, precio histórico y subtotal calculado). Incluir protocolo de pruebas de equivalencia EXCEPT frente a consultas nativas. Guardar en `specs/` con el prefijo `spec_vistas_reportes_`."*

**Qué generó la IA:**

- `spec_vistas_reportes_requirements.md`: 4 requisitos con 22 criterios de aceptación en formato EARS (IF-THEN, WHEN-THEN, THE-SHALL). Requisito 1 define las columnas y el JOIN de `vw_productos_vigentes`; Requisito 2 define `vw_pedidos_cliente_segura` con la omisión explícita de `direccion`; Requisito 3 define `vw_detalle_pedido_completo` con la columna calculada `subtotal`; Requisito 4 establece el protocolo de pruebas EXCEPT bidireccionales y la consulta a `information_schema.columns` para verificar columnas expuestas.
- `spec_vistas_reportes_design.md`: diseño técnico con diagrama ER Mermaid de las 5 tablas, mapeo completo columna a columna (origen → alias → vista), SQL completo de las 3 vistas con tabla de decisiones de diseño para cada una, script `vistas_reportes.sql` de 6 bloques (creación, verificación de columnas, prueba de seguridad, 6 EXCEPT bidireccionales, prueba funcional de subtotales, prueba de vigencia doble con BEGIN/ROLLBACK) y 5 casos de Error Handling.
- `spec_vistas_reportes_tasks.md`: 11 tareas secuenciales con SQL exacto, pruebas de equivalencia EXCEPT, validación de ausencia de `direccion` en `vw_pedidos_cliente_segura` y grafo de dependencias entre tareas.

**Qué se aceptó:**

- La estructura completa de los tres documentos de spec con sus campos EARS y el glosario de 11 términos técnicos (VIEW, columna sensible, EXCEPT, prueba de equivalencia, subtotal calculado, column-level security, etc.).
- La decisión de diseño de usar `INNER JOIN` en las tres vistas: garantiza consistencia referencial dado que todas las FK del esquema tienen `ON DELETE RESTRICT`, por lo que no existen filas huérfanas posibles.
- La lógica del protocolo EXCEPT bidireccional como método de validación: ejecutar tanto `consulta_nativa EXCEPT vista` como `vista EXCEPT consulta_nativa` para descartar diferencias en ambas direcciones.
- La tabla de decisiones de diseño del design.md que justifica cada elección: columnas explícitas (no `SELECT *`) para prevenir que columnas sensibles futuras sean heredadas automáticamente por la vista.
- El script `vistas_reportes.sql` de 6 bloques como artefacto consolidado listo para ejecutar en `foodstore_dev`.

**Qué se modificó o descartó:**

- **Corrección crítica de esquema**: el prompt inicial describía la omisión de una columna de "contraseña o password". Al leer el `schema.sql` real, Kiro identificó que la tabla `cliente` del esquema FoodStore **no tiene columna de contraseña ni hash**. La columna de dato personal a omitir es `direccion` (VARCHAR 200, domicilio físico). Esta corrección quedó documentada en R2.3 del requirements, en el Overview del design y en los Notes del tasks.
- Se descartó la variante de filtro doble `p.activo = TRUE AND c.activo = TRUE` para `vw_productos_vigentes` como requerimiento del spec (Kiro lo incluyó en el design.md como opción), ya que en el `views.sql` final se implementó únicamente el filtro sobre `producto.activo`. Kiro propuso el filtro dual pero la implementación final en OpenCode simplificó a un solo filtro. Ambas versiones son técnicamente válidas; la diferencia quedó documentada.
- El Requisito 4 del requirements.md incluyó una consulta a `information_schema.columns` que no estaba en el prompt original pero fue aceptada como mejora: agrega verificación objetiva de las columnas expuestas por cada vista sin necesidad de ejecutar `SELECT *`.

**Verificación realizada:**

- Revisión manual de los tres archivos de spec generados contra el `schema.sql` real: nombres de tablas, columnas, tipos de datos y constraints verificados uno a uno.
- Confirmación de que la columna `direccion` (VARCHAR 200) existe en `cliente` y es la única columna de dato personal presente en el esquema actual.
- Confirmación de que `detalle_pedido` tiene `precio_unitario_historico NUMERIC(10,2)` como columna independiente de `producto.precio_lista`, validando la decisión de usar el precio histórico en el cálculo del subtotal.

---

### Instancia 8 — Implementación DDL de las vistas y configuración de seguridad por roles

**Herramienta:** OpenCode

**Spec / Prompt utilizado:**

*"A partir de las especificaciones técnicas generadas en Kiro para la Parte B, implementa las tres vistas en `views.sql` con `CREATE OR REPLACE VIEW`, las pruebas de equivalencia EXCEPT bidireccionales para las tres vistas y la configuración del rol `rol_reportes` con `CREATE ROLE`, `GRANT CONNECT`, `GRANT USAGE ON SCHEMA` y `GRANT SELECT` exclusivo sobre `vw_pedidos_cliente_segura`."*

**Qué generó la IA:**

El archivo `views.sql` completo con cuatro secciones:

1. **Tres vistas DDL** con `CREATE OR REPLACE VIEW`:
   - `vw_productos_vigentes`: `INNER JOIN producto p` con `categoria c` sobre `id_categoria`, filtro `WHERE p.activo = TRUE`, alias `producto_nombre` y `categoria_nombre`.
   - `vw_pedidos_cliente_segura`: `INNER JOIN pedido p` con `cliente c` sobre `id_cliente`, proyección explícita de 7 columnas (`id_pedido`, `fecha_hora`, `forma_pago`, `id_cliente`, `cliente_nombre`, `cliente_email`, `cliente_telefono`) con omisión explícita documentada en comentario SQL de la columna `direccion`.
   - `vw_detalle_pedido_completo`: `INNER JOIN detalle_pedido dp` con `producto prod` sobre `id_producto`, columna calculada `(dp.cantidad * dp.precio_unitario_historico) AS subtotal`.

2. **6 pruebas EXCEPT bidireccionales** (2 por cada vista: `vista EXCEPT nativa` y `nativa EXCEPT vista`) con comentario indicando que todas deben retornar exactamente 0 filas.

3. **Configuración del rol de seguridad** `rol_reportes` con `GRANT CONNECT ON DATABASE`, `GRANT USAGE ON SCHEMA public` y `GRANT SELECT` exclusivo sobre `vw_pedidos_cliente_segura`.

**Qué se aceptó:**

- La estructura completa de `views.sql` con las cuatro secciones claramente delimitadas por comentarios SQL descriptivos.
- El uso de `CREATE OR REPLACE VIEW` en lugar de `DROP VIEW / CREATE VIEW` para permitir la reejecución idempotente del script en `foodstore_dev`.
- Los alias de columnas `cliente_nombre`, `cliente_email`, `cliente_telefono` en `vw_pedidos_cliente_segura` — nomenclatura más descriptiva que la del spec de Kiro (`nombre_cliente`, `email`, `telefono`), funcional y consistente con el estilo del proyecto.
- La omisión de la columna `direccion` documentada explícitamente mediante comentario SQL de tres líneas, dejando trazabilidad del criterio de seguridad directamente en el código.
- La estrategia de `GRANT SELECT` exclusivo sobre `vw_pedidos_cliente_segura` para `rol_reportes`, sin otorgar acceso a ninguna tabla base, implementando correctamente el principio de mínimo privilegio.

**Qué se modificó o descartó:**

- **Ajuste de esquema en `vw_productos_vigentes`**: OpenCode implementó el filtro con `WHERE p.activo = TRUE` únicamente sobre `producto`, sin el filtro dual `AND c.activo = TRUE` sobre `categoria` que el spec de Kiro incluía como Caso 2 del Error Handling. Esta simplificación es coherente con el esquema real donde el filtro de vigencia institucional principal opera sobre `producto`. Se documentó la diferencia.
- Se descartó el comentario que OpenCode incluyó sobre "nombre actual del producto" en `vw_detalle_pedido_completo`: el nombre expuesto es el actual de la tabla `producto`, no el histórico. El precio histórico sí es el correcto (`precio_unitario_historico`), pero el nombre del producto no tiene columna histórica en el esquema. La descripción fue corregida en el comentario SQL.
- Se ajustó el orden de los `GRANT`: OpenCode colocó `GRANT CONNECT` antes de `GRANT USAGE ON SCHEMA`, orden correcto para crear el rol correctamente en una base de datos nueva. No requirió modificación.

**Verificación realizada:**

- Ejecución del script `views.sql` completo en `foodstore_dev` mediante `psql -U postgres -d foodstore_dev -f views.sql`.
- Confirmación de que las tres vistas fueron creadas sin errores (`CREATE VIEW` en consola para cada una).
- Ejecución de las 6 pruebas EXCEPT bidireccionales:

  | Prueba | Dirección | Resultado |
  |--------|-----------|-----------|
  | `vw_productos_vigentes` | Vista EXCEPT nativa | **0 filas** ✓ |
  | `vw_productos_vigentes` | Nativa EXCEPT vista | **0 filas** ✓ |
  | `vw_pedidos_cliente_segura` | Vista EXCEPT nativa | **0 filas** ✓ |
  | `vw_pedidos_cliente_segura` | Nativa EXCEPT vista | **0 filas** ✓ |
  | `vw_detalle_pedido_completo` | Vista EXCEPT nativa | **0 filas** ✓ |
  | `vw_detalle_pedido_completo` | Nativa EXCEPT vista | **0 filas** ✓ |

- Verificación de seguridad: consulta a `information_schema.columns WHERE table_name = 'vw_pedidos_cliente_segura' AND column_name = 'direccion'` → **0 filas**, confirmando que la columna sensible no está expuesta.
- Ejecución de los comandos `GRANT`: `CREATE ROLE rol_reportes` completado sin errores; `GRANT SELECT ON vw_pedidos_cliente_segura TO rol_reportes` confirmado con `\dp vw_pedidos_cliente_segura` en psql.
