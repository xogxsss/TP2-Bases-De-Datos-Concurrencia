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