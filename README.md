# FoodStore — Sistema de Gestión y Base de Datos (TP Integrador)

**Estudiante:** Agustina Micaela Guzmán  
**Asignatura:** Bases de Datos II  
**Motor de BD:** PostgreSQL 17  
**Base de datos de desarrollo (Sandbox):** foodstore_dev

---

## 1. Descripción del Proyecto

Este repositorio contiene el trabajo práctico integrador sobre la base de datos de FoodStore (PostgreSQL 17). Incluye el esquema relacional y una carga masiva de datos sintéticos; el análisis de planes de ejecución con `EXPLAIN ANALYZE`, el diseño de índices y su costo en escrituras (Parte A); vistas de reporte, con una vista segura que oculta datos personales (Parte B); una vista materializada (Parte C); triggers de integridad; y pruebas de concurrencia y aislamiento transaccional (MVCC). El uso de IA (Kiro y OpenCode) se documenta en `DUIA.md`, y las especificaciones generadas con Kiro están en `specs/`.

El proyecto abarca el ciclo completo de ingeniería sobre la base de datos: modelado DDL, cargas masivas con datos sintéticos generados con semilla, diagnósticos con `EXPLAIN ANALYZE`, control de concurrencia y aislamiento transaccional (MVCC), y configuración de seguridad por roles.

---

## 2. Estructura y Componentes del Repositorio

### Scripts SQL (.sql)

- **data.sql**: Carga masiva de datos sintéticos, con semilla fija para `random()`: 9 categorías, 50.000 productos, 20.000 clientes, 200.000 pedidos y 300.000 detalles. Al terminar actualiza las estadísticas con `ANALYZE`.
- **queries.sql**: Catálogo de consultas. Sección 0: verificación de volumen cargado. Secciones 1 a 3: rankings con funciones de ventana, subconsultas y agregaciones. Sección 4: consultas con `EXPLAIN ANALYZE`, que dan los planes de referencia antes de indexar. Sección 5: competencia de optimización (hackathon), con estrategias de indexación y reescritura probadas dentro de `BEGIN ... ROLLBACK`.
- **indices.sql**: Guion de experimentos de indexación que se ejecuta de forma manual (no con `-f`), bloque por bloque y dentro de transacciones: índices B-Tree (cobertura con `INCLUDE` y `text_pattern_ops`) y costo en escrituras.
- **informe_mediciones.md**: Diagnósticos de rendimiento con `EXPLAIN ANALYZE` (antes y después de cada índice), costo de los índices en escrituras y métricas de la vista materializada.
- **schema.sql**: Tablas base, tipos `ENUM`, claves autoincrementales `IDENTITY` y restricciones de integridad (`ON DELETE RESTRICT`).
- **views.sql**: Vistas de reporte, seguridad de datos sensibles por roles (`rol_reportes`), pruebas de equivalencia (`EXCEPT`) y vista materializada (`mv_facturacion_categoria_mes`).
- **restricciones_integridad.sql**: Triggers en PL/pgSQL para la validación preventiva de fechas de pedidos y productos inactivos.

> **Organización de los scripts:** los scripts se centralizaron en estos archivos, en lugar de uno por ejercicio, porque la estructura del proyecto no estaba definida al inicio; por eso los ejercicios de la hackathon conviven con el catálogo de consultas.

### Documentación e Informes (.md)

- **README.md**: Guía principal, mapa del repositorio y protocolo de despliegue.
- **protocolo_seguridad.md**: Normas de trabajo seguro sobre la base de desarrollo mediante transacciones (`BEGIN/ROLLBACK`) y respaldos con `pg_dump`.
- **AGENTS.md**: Directivas técnicas y restricciones del esquema diseñadas para el guiado de asistentes de IA.
- **informe_concurrencia.md**: Pruebas sobre anomalías transaccionales (Non-Repeatable Read, Lock Wait, Phantom Read) en entornos paralelos.
- **informe_mediciones.md**: Diagnósticos de rendimiento con `EXPLAIN ANALYZE`, análisis de sobrecosto en escrituras (~30%), descarte por baja cardinalidad y métricas de vistas materializadas.
- **ejercicio_lectura_critica.md**: Evaluación crítica de alucinaciones y errores conceptuales detectados en explicaciones automatizadas de la IA.
- **bitacora_competencia.md**: Comparativa técnica de estrategias de optimización (índices parciales, BRIN y reescritura de subconsultas).
- **DUIA.md**: Declaración de Uso de Inteligencia Artificial (DUIA), con la bitácora de prompts, sugerencias aceptadas y decisiones de descarte.

### Especificaciones Técnicas (specs/)

- **specs/**: Carpeta que implementa el enfoque Spec-Driven Development (Kiro), organizando cada requerimiento de optimización en documentos de requisitos (sintaxis EARS), arquitectura y planes de ejecución secuenciales.

---

## 3. Guía de Reproducción del Entorno

### Paso 1: Creación de la base de desarrollo (Sandbox)

De acuerdo con el protocolo de seguridad del proyecto, las ejecuciones de prueba se aíslan en la base de datos de desarrollo:

```bash
createdb -U postgres foodstore_dev

```

### Paso 2: Carga del esquema e inserción de datos

Ejecutar los scripts en secuencia para construir la estructura e insertar el dataset sintético:

```bash
# Crear estructura DDL
psql -U postgres -d foodstore_dev -f schema.sql

# Poblar masa de datos masiva
psql -U postgres -d foodstore_dev -f data.sql

```

> **Determinismo y repetibilidad de la carga:** `data.sql` ejecuta `SELECT setseed(0.5);` al inicio de la transacción, fijando la semilla del generador pseudoaleatorio. Esto garantiza determinismo total sobre las columnas numéricas e inmutables: en cargas consecutivas sobre una base limpia, la sumatoria de `precio_lista` ($137.332.979,93$) y `stock` ($4.985.554$) en la tabla `producto` es idéntica.
> _Excepciones no deterministas:_ Las columnas `fecha_hora` en `pedido` y `email` en `cliente` varían en cada ejecución porque ambas derivan de la función mutable `now()` (marcas de tiempo de ejecución). Sin embargo, la distribución probabilística de los datos y el volumen de filas se mantienen constantes.

### Paso 3: Verificación de la carga

Antes de medir, comprobar que la carga masiva se aplicó completa. Este comando ejecuta la misma consulta de la Sección 0 de `queries.sql`:

```bash
psql -U postgres -d foodstore_dev -c "SELECT 'categoria' AS tabla, COUNT(*) AS total FROM categoria UNION ALL SELECT 'producto', COUNT(*) FROM producto UNION ALL SELECT 'cliente', COUNT(*) FROM cliente UNION ALL SELECT 'pedido', COUNT(*) FROM pedido UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido;"

```

Valores esperados, con `data.sql` ejecutado una sola vez sobre una base nueva:

| Tabla          | Filas   |
| -------------- | ------- |
| categoria      | 9       |
| producto       | 50.000  |
| cliente        | 20.000  |
| pedido         | 200.000 |
| detalle_pedido | 300.000 |

Si los valores no coinciden, repetir el Paso 2: `schema.sql` empieza eliminando las tablas existentes (`DROP TABLE ... CASCADE`), por lo que la carga parte de cero. Esto también elimina los índices, las vistas y los triggers que dependían de esas tablas, que deben volver a crearse en los pasos siguientes. El rol `rol_reportes` y las funciones PL/pgSQL no se eliminan.

### Paso 4: Medición de referencia (antes de la indexación)

Ejecutar `queries.sql` antes de `indices.sql`, para registrar los planes de ejecución iniciales:

```bash
psql -U postgres -d foodstore_dev -f queries.sql -o salida_queries.txt

```

La salida es extensa (los rankings de las Secciones 1 a 3 devuelven miles de filas), por eso se redirige a un archivo. Los planes de la Sección 4 son los de referencia "antes" de la Parte A. Los experimentos con índices de la Sección 5 se ejecutan dentro de `BEGIN ... ROLLBACK`, por lo que no dejan índices en la base.

### Paso 5: Parte A — Índices (ejecución manual)

`indices.sql` **no se ejecuta completo** con `-f`: es un guion de experimentos que se corre bloque por bloque en una sesión de `psql`.

```bash
psql -U postgres -d foodstore_dev

```

Para cada experimento (productos, pedidos, clientes y costo de escritura), seguir los mismos pasos que figuran en el archivo:

- **Paso 0:** abrir una transacción con `BEGIN;`.
- **Paso 1:** actualizar las estadísticas de la tabla con `ANALYZE`.
- **Paso 2:** ejecutar el `EXPLAIN (ANALYZE, BUFFERS)` de referencia, sin índice.
- **Paso 3:** crear el índice indicado en el bloque.
- **Paso 4:** volver a ejecutar el mismo `EXPLAIN (ANALYZE, BUFFERS)` del Paso 2.
- **Paso 5:** cerrar la transacción con `ROLLBACK;` solo cuando corresponda:
- **Medición de escritura:** siempre, porque `EXPLAIN ANALYZE` ejecuta realmente el `INSERT` y, sin `ROLLBACK`, las filas de prueba quedarían en la tabla.
- **Índices de lectura:** si el índice es solo de prueba y no se quiere conservar. Si se decide conservarlo, confirmar con `COMMIT;` y tener en cuenta que los experimentos siguientes ya no parten de una base sin ese índice.

Los resultados de cada experimento se registran y analizan en `informe_mediciones.md`.

### Paso 6: Partes B y C — Vistas y vista materializada

```bash
psql -U postgres -d foodstore_dev -f views.sql

```

`views.sql` crea las vistas `vw_productos_vigentes`, `vw_pedidos_cliente_segura` y `vw_detalle_pedido_completo`, ejecuta las verificaciones de equivalencia con `EXCEPT`, crea el rol `rol_reportes` y la vista materializada `mv_facturacion_categoria_mes`.

- **Equivalencia:** cada una de las dos direcciones de comparación `EXCEPT` debe devolver `(0 rows)`.
- **Seguridad:** `rol_reportes` solo tiene acceso a la vista segura. Se puede comprobar en `psql`:

```sql
SET ROLE rol_reportes;
SELECT * FROM vw_pedidos_cliente_segura LIMIT 1;  -- funciona
SELECT * FROM cliente LIMIT 1;                    -- ERROR: permission denied
RESET ROLE;

```

> _Nota sobre permisos:_ Si el rol `rol_reportes` ya fue creado previamente en la instancia de PostgreSQL, el script notificará `ERROR: el rol «rol_reportes» ya existe`. Esto es un comportamiento normal del motor al ser los roles globales para todo el servidor; los permisos (`GRANT`) y las vistas se crean sin inconvenientes.

- **Actualización de la vista materializada:**

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;

```

Requiere el índice único `idx_mv_facturacion_uk`, que crea el propio script. La comparación de rendimiento de la vista materializada está en `informe_mediciones.md`.

### Paso 7: Restricciones de integridad

```bash
psql -U postgres -d foodstore_dev -f restricciones_integridad.sql

```

Define los triggers en PL/pgSQL que validan las fechas de los pedidos y los productos inactivos. Se aplican después de la carga masiva para que la validación no se ejecute fila por fila durante la inserción de los 200.000 pedidos.

Al final del script hay dos pruebas, cada una dentro de `BEGIN ... ROLLBACK`, que provocan un `ERROR` a propósito: un pedido con fecha futura y un detalle con un producto inactivo. Ese error es el resultado esperado, porque demuestra que el trigger rechazó la operación; no indica un fallo en la ejecución. Ambas pruebas se revierten, por lo que no dejan datos en la base.

### Paso 8: Pruebas de concurrencia

`informe_concurrencia.md` documenta las pruebas de anomalías transaccionales (Non-Repeatable Read, Lock Wait y Phantom Read). Para reproducirlas, abrir dos terminales con `psql` conectadas a `foodstore_dev` (Sesión A y Sesión B) y ejecutar los pasos del informe de forma intercalada, en el orden indicado.

---

## 4. Protocolo de Seguridad Operativa

Toda modificación manual o experimental sobre el esquema o los datos debe ejecutarse dentro de un bloque transaccional, para verificar los efectos colaterales antes de confirmar los cambios:

```sql
BEGIN;
-- Consulta o sentencia DML/DDL de prueba
ROLLBACK;

```
