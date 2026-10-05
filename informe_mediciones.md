# Informe de Rendimiento y Costos de Indexación - Sistema FoodStore

### 1. Introducción y Metodología
El presente informe documenta las métricas experimentales obtenidas mediante la ejecución de planes de ejecución (`EXPLAIN (ANALYZE, BUFFERS)`) sobre el motor PostgreSQL 17 para el sandbox `foodstore_test`. 

Se evalúan tres consultas críticas del sistema comparando la línea base (sin índices) contra las estrategias de indexación B-Tree propuestas en las especificaciones de `specs/`.

---

### 2. Resumen Comparativo de Mediciones Reales

| Consulta / Tabla | Estrategia de Índice Aplicada | Plan Real (Antes → Después) | Shared Buffers Hit (Antes → Después) | Execution Time (Antes → Después) | Impacto y Veredicto Técnico |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **C1: Productos** <br>(`producto` - 50k filas) | `idx_producto_precio_stock_cubriente` <br>`(precio_lista DESC, stock)` `INCLUDE (id_producto, nombre)` | `Seq Scan + Sort` → <br>**`Index Only Scan`** | 812 → **160** <br>(↓ 80.3%) | 10.538 ms → **1.951 ms** | **~81.5% de reducción** en tiempo. Eliminación total del `Sort` y acceso $0$ a páginas del Heap (`Heap Fetches: 0`). |
| **C2: Pedidos** <br>(`pedido` - 200k filas) | `idx_pedido_fecha_hora` <br>`(fecha_hora DESC)` | `Seq Scan + Disk Sort` → <br>**`Index Scan`** | 1.471 → **62.367** <br>(↑ por baja correlación) | 52.522 ms → **20.084 ms** | **~61.7% de reducción** en tiempo. Elimina el ordenamiento temporal en disco (`external merge Disk: 2568kB`). |
| **C3: Clientes** <br>(`cliente` - 20k filas) | `idx_cliente_nombre_cubriente` <br>`(nombre text_pattern_ops)` `INCLUDE (email, telefono)` | `Seq Scan + Sort` → <br>**`Bitmap Index Scan + Sort`** | 364 → **41** <br>(↓ 88.7%) | 6.289 ms → **5.091 ms** | **~19.0% de reducción**. El I/O se reduce drásticamente, pero el nodo `Sort` persiste por diferencia entre `text_pattern_ops` y la collation lingüística. |

---

### 3. Análisis Detallado por Consulta

#### Consulta 1 — Filtrado de Productos por Rango de Precio y Stock
* **Comportamiento sin índice:** El motor realizó un `Seq Scan` leyendo 812 páginas de 8 kB (6.496 kB, la totalidad de la tabla), aplicando el filtro sobre 50.000 filas y ordenando 12.487 filas resultantes en RAM mediante `quicksort` (1.165 kB).
* **Comportamiento con índice:** Al aplicar `idx_producto_precio_stock_cubriente`, el planificador seleccionó un `Index Only Scan`. Leyó solo 160 páginas (~1.280 kB, un tercio de la estructura del índice de 3.776 kB) gracias a la restricción de rango sobre la columna líder `precio_lista`.
* **Resultado:** Eliminación total de lecturas sobre la tabla base (`Heap Fetches: 0`).

#### Consulta 2 — Historial Reciente de Pedidos (Últimos 30 días)
* **Comportamiento sin índice:** La consulta filtraba 62.237 filas. Al no caber el ordenamiento en memoria `work_mem`, el motor recurrió a un ordenamiento externo en disco (`external merge Disk: 2568kB`), elevando el tiempo a 52.522 ms.
* **Comportamiento con índice:** Con `idx_pedido_fecha_hora`, el motor optó por un `Index Scan` que lee las filas en el orden exacto requerido por `ORDER BY fecha_hora DESC`, eliminando completamente el `Sort`.
* **Análisis de Buffers (Trade-off de I/O):** El índice requirió 62.367 shared hits frente a los 1.471 del `Seq Scan`. Esto responde a la correlación física prácticamente nula de la tabla (`-0.0026`): las filas ordenadas temporalmente están dispersas físicamente por toda la tabla. A pesar del alto conteo de buffers, la consulta gana un 61.7% en tiempo porque la RAM absorbió los saltos y se evitó la escritura/lectura en disco.

#### Consulta 3 — Búsqueda Prefijada de Clientes (`LIKE 'Cliente de Prueba 15%'`)
* **Comportamiento sin índice:** `Seq Scan` sobre 20.000 filas con filtrado en texto y `quicksort` en RAM.
* **Comportamiento con índice:** El índice con `text_pattern_ops` transformó el predicado `LIKE` en un rango B-Tree (`~>=~` y `~<~`). Redujo la lectura física de 364 a 41 buffers (Bitmap Heap Scan sobre 23 páginas).
* **Persistencia del nodo Sort:** El tiempo no cayó drásticamente (~19%) porque el `ORDER BY` requiere ordenación lingüística según la Collation del sistema (`Spanish_Argentina.1252`), mientras que `text_pattern_ops` ordena estrictamente byte a byte. Por lo tanto, el motor debió mantener un nodo `quicksort` explícito al final.
* **Refutación a la IA:** Se comprobó empíricamente la falsedad de la afirmación de que `id_cliente` estaba "implícitamente incluido" para permitir un `Index Only Scan`. Al no incluir `id_cliente` en el índice, el motor se vio obligado a realizar un `Bitmap Heap Scan` visitando 23 bloques de la tabla.

---

### 4. Evaluación del Costo de Mantenimiento en Escrituras (DML)

No se registró una métrica cuantitativa directa de inserción en el reporte final debido a que las pruebas automatizadas de `INSERT` fueron descartadas por inconsistencias en la generación de claves primarias compuestas y transacciones abortadas. 

Sin embargo, el análisis del tamaño de los objetos revela la penalización estructural implícita:
1. El índice cubriente `idx_producto_precio_stock_cubriente` ocupa **3.776 kB** (más del 58% del tamaño total de la tabla `producto` de 6.496 kB).
2. Dado que `stock` forma parte de la clave del índice B-Tree, **cualquier actualización de inventario (`UPDATE producto SET stock = ...`) exige modificar tanto el Heap como la estructura del índice**, incrementando la contención de bloqueos en escenarios de alta concurrencia.

---

### 5. Implementación y Verificación de Vistas (Parte B)

#### 5.1. Vistas Transaccionales y Analíticas
Se implementaron tres vistas institucionales en `views.sql`:
1. `vw_productos_vigentes`: Productos activos (`activo = TRUE`) con su categoría.
2. `vw_pedidos_cliente_segura`: Relación de pedidos y clientes con **omisión explícita de la columna `direccion` (PII)**.
3. `vw_detalle_pedido_completo`: Desglose de detalle transaccional con cálculo dinámico de subtotal.

#### 5.2. Verificación de Equivalencia de Resultados (`EXCEPT`)
Se ejecutaron 6 pruebas de comparación conjuntista bidireccionales (`Vista EXCEPT Consulta Nativa` y viceversa). En las 6 pruebas el resultado fue estrictamente **`0 rows`**, probando la fidelidad absoluta de las vistas respecto a las tablas base.

#### 5.3. Control de Acceso por Roles (`rol_reportes`)
Se validó en consola la aplicación del Principio de Menor Privilegio:
* `SET ROLE rol_reportes; SELECT * FROM vw_pedidos_cliente_segura LIMIT 1;` → **Exitoso** (devuelve 1 fila omitiendo domicilio).
* `SET ROLE rol_reportes; SELECT * FROM cliente LIMIT 1;` → **Rechazado** (`ERROR: permiso denegado a la tabla cliente`).

---

### 6. Vista Materializada `mv_facturacion_categoria_mes` (Parte C)

* **Rendimiento:** Precalcula la consulta analítica de 4 `JOIN`s y agregaciones masivas sobre 36 filas agrupadas por año, mes y categoría.
* **Índice Único y Concurrencia:** Se creó el índice único `idx_mv_facturacion_uk` sobre `(anio, mes, id_categoria)`, garantizando la ejecución exitosa de `REFRESH MATERIALIZED VIEW CONCURRENTLY` sin bloquear las lecturas de los usuarios durante la actualización.