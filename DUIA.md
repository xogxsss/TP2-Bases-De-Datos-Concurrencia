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
