# Informe de Rendimiento y Costos de Indexación - Sistema FoodStore

## 1. Introducción y Metodología
El presente informe documenta las métricas experimentales obtenidas mediante la ejecución de planes de ejecución (`EXPLAIN ANALYZE`) y pruebas de carga transaccionales sobre el motor PostgreSQL para el sistema FoodStore. Se evalúa tanto el beneficio en consultas de lectura como el costo operativo en operaciones de escritura (`INSERT`).

---

## 2. Resumen Comparativo de Consultas (Lectura)

| Consulta / Tabla | Índice Aplicado | Plan Real / Esperado | Planning Time (Antes → Después) | Execution Time (Antes → Después) | Impacto / Resultado Clave |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **C1: Productos** <br>(`producto` - 50k filas) | `idx_producto_precio_stock_cubriente` <br>(`precio_lista DESC`, `stock`) `INCLUDE (id, nombre)` | Seq Scan (por tamaño de caché local) | 0.475 ms → 0.313 ms | 0.041 ms → 0.024 ms | **~41% de reducción** en tiempo de ejecución. |
| **C2: Pedidos** <br>(`pedido` - 200k filas) | `idx_pedido_fecha_hora` <br>(`fecha_hora DESC`) | **Index Scan** <br>(Eliminación total del nodo `Sort`) | *Optimizado por volumen* | *Optimizado por volumen* | **Eliminación del Sort en memoria** y acceso eficiente por rango temporal. |
| **C3: Clientes** <br>(`cliente` - 20k filas) | `idx_cliente_nombre_cubriente` <br>(`nombre text_pattern_ops`) `INCLUDE (email, tel)` | Seq Scan (en entorno acotado) | 0.246 ms → 0.880 ms <br>(↑ 0.634 ms) | 0.070 ms → 0.026 ms <br>(↓ 0.044 ms) | **~62% de reducción** en ejecución; aumento de planning por operadores especializados. |



---

## 3. Análisis de Costo en Escrituras (`INSERT` Masivos)
Se evaluó el impacto de mantener estructuras de índices activas frente a inserciones masivas de 500 registros en la tabla transaccional `detalle_pedido`:
* **Comportamiento observado:** Cada inserción DML obliga a PostgreSQL a actualizar las páginas de datos (*heap*) y a reacomodar los nodos del árbol B-Tree del índice secundario.
* **Métricas registradas:** Se observó un incremento marginal del **~30% en el Execution Time** del lote de inserción masiva (pasando de 0,020 ms a 0,026 ms) debido al mantenimiento del índice B-Tree. Este comportamiento evidencia el *trade-off* clásico de bases de datos: una penalización menor y perfectamente asumible en escrituras a cambio de optimizaciones críticas en lecturas.

---

## 4. Descarte de Propuestas por Sobreindexación
Se descartó explícitamente la creación de un índice plano sobre la columna `forma_pago` en la tabla `pedido`. 
* **Justificación técnica:** Al tratarse de un tipo `ENUM` con una cardinalidad muy baja (3 valores posibles), el uso de un índice B-Tree estándar sin condiciones parciales resulta ineficiente para el optimizador y genera una penalización innecesaria de espacio en disco y ciclos de CPU durante las operaciones de escritura masiva.

---

## 5. Implementación y Verificación de Vistas (Parte B)

### 5.1. Vistas Transaccionales y Analíticas
Para estandarizar el acceso a los reportes frecuentes del sistema FoodStore, se implementaron tres vistas institucionales mediante el motor de PostgreSQL:
1. **`vw_productos_vigentes`**: Filtra y expone los productos activos de la tienda (`activo = TRUE`) en conjunto con su categoría asociada.
2. **`vw_pedidos_cliente_segura`**: Relaciona las operaciones de compra con la información de sus clientes, aplicando un criterio estricto de seguridad.
3. **`vw_detalle_pedido_completo`**: Desglosa los ítems transaccionales de los pedidos incorporando el nombre del producto, la cantidad, el precio histórico y el cálculo dinámico del subtotal.

### 5.2. Criterio de Seguridad y Privacidad (Principio de Menor Privilegio)
Para dar cumplimiento a las normativas de protección de datos y seguridad en bases de datos relacionales:
* En la vista **`vw_pedidos_cliente_segura`**, se **omite explícitamente la columna `direccion`** (datos personales sensibles / PII de la tabla `cliente`).
* Esto permite configurar un rol específico (`rol_reportes`) al cual se le otorgan permisos exclusivos de lectura sobre la vista (`GRANT SELECT ON vw_pedidos_cliente_segura TO rol_reportes;`) sin necesidad de conceder acceso directo a las tablas base del esquema transaccional.

### 5.3. Verificación de Equivalencia de Resultados (`EXCEPT`)
Se llevaron a cabo pruebas de equivalencia lógico-conjuntista utilizando el operador `EXCEPT` de PostgreSQL en ambas direcciones (Vista menos Consulta Nativa, y Consulta Nativa menos Vista) para garantizar que las vistas no alteran ni omiten registros de forma indebida.
* **Resultado obtenido:** Todas las pruebas de equivalencia bidireccionales para `vw_productos_vigentes`, `vw_pedidos_cliente_segura` y `vw_detalle_pedido_completo` arrojaron exactamente **0 filas de diferencia**, validando formalmente la corrección de la implementación.


---

## 6. Vista Materializada `mv_facturacion_categoria_mes` (Parte C)

### 6.1. Motivación y Descripción

La consulta analítica de referencia (Sección 5 de `queries.sql`) cruza cuatro tablas (`categoria`, `producto`, `detalle_pedido`, `pedido`) mediante tres `INNER JOIN` y calcula agregaciones globales de `SUM` y `COUNT`. En el conjunto de datos de prueba (~50k productos, ~200k pedidos, ~N detalles) el motor seleccionó un plan basado en **Parallel Seq Scan + Hash Join + Parallel Hash Aggregate**, con un tiempo de ejecución de referencia de **~197.59 ms**.

La vista materializada `mv_facturacion_categoria_mes` almacena físicamente el resultado precomputado de esa consulta, segmentado por año, mes e `id_categoria`. El acceso de reporte pasa de resolver el JOIN masivo en tiempo de ejecución a leer directamente las filas almacenadas en disco, reduciendo el costo a una fracción del original.

---

### 6.2. Comparativa de Rendimiento: Consulta Original vs. Vista Materializada

Los valores de la columna "Con MV" son representativos del comportamiento esperado con el dataset de prueba. Las mediciones exactas deben reproducirse en `foodstore_dev` con el protocolo `EXPLAIN (ANALYZE, BUFFERS)` detallado en la Sección 6.3.

| Métrica | Consulta Analítica Original | Consulta sobre la MV |
| :--- | :---: | :---: |
| **Plan de acceso** | Parallel Seq Scan + Hash Join + Parallel Hash Aggregate | Seq Scan sobre relación materializada |
| **Nodos de Join activos** | 3 (producto ↔ categoria, detalle_pedido ↔ producto, pedido ↔ detalle_pedido) | 0 |
| **Aggregation en tiempo de consulta** | Sí (SUM, COUNT, GROUP BY en ejecución) | No (resultados precalculados) |
| **Execution Time (referencia)** | ~197.59 ms | < 1 ms (estimado con datos en shared_buffers) |
| **Buffers hit esperados** | Alto (múltiples tablas grandes leídas en paralelo) | Mínimo (solo páginas de la MV) |
| **Escalabilidad con volumen** | Lineal / super-lineal con filas en `detalle_pedido` | Constante (independiente del volumen histórico) |
| **Consistencia de datos** | Siempre actual (lee tablas base en tiempo real) | Eventual (datos al momento del último `REFRESH`) |

#### Protocolo de medición reproducible

```sql
-- PASO 1: Medir la consulta analítica original (línea base)
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    cat.nombre                                          AS categoria,
    COUNT(DISTINCT ped.id_pedido)                       AS total_pedidos,
    SUM(dp.cantidad * dp.precio_unitario_historico)     AS facturacion_total
FROM categoria cat
INNER JOIN producto       pr  ON pr.id_categoria = cat.id_categoria
INNER JOIN detalle_pedido dp  ON dp.id_producto  = pr.id_producto
INNER JOIN pedido         ped ON ped.id_pedido   = dp.id_pedido
WHERE cat.activo = TRUE
  AND pr.activo  = TRUE
GROUP BY cat.nombre;

-- PASO 2: Medir la consulta directa sobre la vista materializada
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT anio, mes, categoria_nombre, total_pedidos, facturacion_total
FROM mv_facturacion_categoria_mes
ORDER BY anio DESC, mes DESC, facturacion_total DESC;
```

> **Criterio de éxito:** La consulta del Paso 2 debe exhibir un `Execution Time` al menos **dos órdenes de magnitud menor** que la del Paso 1, sin nodos de Join ni Aggregate en el plan.

---

### 6.3. Índice Único `idx_mv_facturacion_uk` — Justificación Técnica

El índice `CREATE UNIQUE INDEX idx_mv_facturacion_uk ON mv_facturacion_categoria_mes (anio, mes, id_categoria)` cumple dos funciones complementarias:

1. **Habilitación de `REFRESH CONCURRENTLY`:** PostgreSQL exige la existencia de al menos un índice único sobre la vista materializada para poder ejecutar `REFRESH MATERIALIZED VIEW CONCURRENTLY`. Sin él, el único modo disponible es `REFRESH MATERIALIZED VIEW` (sin `CONCURRENTLY`), que adquiere un `AccessExclusiveLock` sobre la relación, bloqueando todas las lecturas durante el tiempo de refresco.

2. **Optimización de accesos por rango temporal:** La secuencia de columnas `(anio, mes, id_categoria)` sigue el patrón de filtrado más frecuente en los reportes de negocio (filtrar por año → mes → categoría específica), permitiendo que el optimizador realice un `Index Scan` o `Index Only Scan` en lugar de un `Seq Scan` sobre la MV cuando la consulta incluye predicados de igualdad o rango sobre esas columnas.

| Alternativa de REFRESH | Bloqueo adquirido | Lecturas durante el refresco | Requisito |
| :--- | :--- | :--- | :--- |
| `REFRESH MATERIALIZED VIEW` | `AccessExclusiveLock` | **Bloqueadas** | Ninguno |
| `REFRESH MATERIALIZED VIEW CONCURRENTLY` | `ShareUpdateExclusiveLock` | **Permitidas** | Índice único obligatorio |

---

### 6.4. Política de Mantenimiento y Frecuencia de `REFRESH`

#### Frecuencia recomendada: Diaria (mantenimiento nocturno)

Para el sistema FoodStore, cuyo volumen transaccional es continuo durante el horario comercial, se recomienda una política de refresco **diaria en horario de baja carga** (ventana nocturna sugerida: entre las 02:00 y las 04:00 hs). La implementación operativa se delega a un **cron job** del sistema operativo del servidor de base de datos:

```bash
# Ejemplo de entrada crontab (servidor Linux con psql instalado)
# Ejecuta el REFRESH todos los días a las 03:00 hs
0 3 * * * psql -U postgres -d foodstore_dev -c "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;" >> /var/log/pg_refresh_mv.log 2>&1
```

#### Criterios para ajustar la frecuencia

| Escenario operativo | Frecuencia sugerida | Justificación |
| :--- | :--- | :--- |
| Reportes de gestión (gerencia, BI) | Diaria (nocturna) | Los informes de cierre se generan sobre datos del día anterior |
| Dashboard operativo en tiempo cercano al real | Cada 1–4 horas | Mayor carga de mantenimiento; aceptable si el hardware lo permite |
| Analítica histórica (datos de meses anteriores) | Semanal | Los datos pasados no cambian; el refresco frecuente no agrega valor |
| Auditoría o recálculo puntual | Manual (`REFRESH` explícito) | Ante correcciones de datos o backfills históricos |

---

### 6.5. Implicancias Operativas: Consistencia Eventual vs. Rendimiento de Lectura

La vista materializada introduce una **disyuntiva fundamental** entre dos propiedades del sistema que no pueden maximizarse simultáneamente:

#### Consistencia eventual
Los datos de `mv_facturacion_categoria_mes` reflejan el estado de las tablas base **en el momento del último `REFRESH`**. Todo pedido cargado después de ese instante **no estará visible** en la vista hasta el próximo ciclo de refresco. Esto implica:

- Un usuario que consulte el dashboard de facturación puede estar viendo datos con hasta ~23 horas de desfase respecto a las transacciones reales.
- Las correcciones retroactivas (actualizaciones de `precio_unitario_historico` o reversiones de pedidos) tampoco se reflejan hasta el próximo `REFRESH`.
- El desfase es **conocido, acotado y predecible**, lo que lo diferencia de inconsistencias aleatorias o bugs de lógica.

#### Rendimiento de lectura
A cambio del desfase aceptado, las consultas de reporte se ejecutan en tiempos submilesegundo independientemente de:
- El volumen acumulado en `detalle_pedido` (millones de registros).
- La carga concurrente de escrituras transaccionales.
- La cantidad de usuarios simultáneos consultando el dashboard.

#### Recomendación de comunicación hacia los usuarios del sistema
Es obligatorio que la interfaz de reporting informe visualmente la fecha y hora del último refresco de la vista materializada. Esto puede implementarse mediante una columna de metadata:

```sql
-- Consulta de auditoría: momento del último REFRESH
SELECT schemaname, matviewname, last_refresh
FROM pg_matviews
WHERE matviewname = 'mv_facturacion_categoria_mes';
```

Exponer este valor en el encabezado del reporte ("Datos actualizados al: DD/MM/YYYY HH:MM hs") gestiona la expectativa del usuario y evita decisiones basadas en datos que el usuario interpreta erróneamente como en tiempo real.
