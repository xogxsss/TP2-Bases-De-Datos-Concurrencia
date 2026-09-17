# Documento de Requisitos: Vistas Transaccionales y de Reportes — FoodStore

## Introducción

Esta especificación define los requisitos técnicos para la creación de tres vistas SQL sobre el esquema FoodStore en PostgreSQL. Las vistas encapsulan consultas reutilizables que sirven como capa de abstracción entre la lógica de presentación y las tablas base, ofreciendo control de exposición de columnas, simplificación de JOINs complejos y una interfaz segura para otorgar permisos de lectura sin exponer el esquema interno.

Las tres vistas a implementar son:

1. **`vw_productos_vigentes`** — Productos activos con su categoría, filtrando `activo = TRUE` en ambas tablas.
2. **`vw_pedidos_cliente_segura`** — Pedidos con datos del cliente, omitiendo la columna `direccion` (dato sensible en el esquema actual) para permitir `GRANT SELECT` seguro.
3. **`vw_detalle_pedido_completo`** — Detalle de pedido con nombre del producto, cantidad, precio histórico y subtotal calculado.

**Nota de esquema:** La tabla `cliente` en el esquema actual de FoodStore no incluye columna de contraseña o password. La columna de dato sensible a omitir es `direccion` (VARCHAR 200), que constituye información personal del cliente. Esta decisión de diseño se documenta explícitamente para cualquier auditoría futura.

---

## Glossary

- **Vista (VIEW)**: Objeto de base de datos que almacena una consulta SELECT con nombre. No materializa datos; ejecuta la consulta subyacente cada vez que se la referencia.
- **Columna sensible**: Columna cuyo contenido no debe exponerse a todos los roles de la base de datos. En el esquema FoodStore, `cliente.direccion` es la columna de dato personal que se omite en la vista de seguridad.
- **EXCEPT**: Operador de conjuntos SQL que devuelve las filas del primer SELECT que no están presentes en el segundo. Usado para pruebas de equivalencia: si `SELECT ... FROM vista EXCEPT SELECT ... FROM tabla_base` devuelve cero filas, ambos resultados son idénticos.
- **Prueba de equivalencia**: Técnica de validación que verifica mediante `EXCEPT` bidireccional que una vista devuelve exactamente las mismas filas que la consulta nativa equivalente.
- **Subtotal calculado**: Columna derivada `cantidad * precio_unitario_historico AS subtotal` en `vw_detalle_pedido_completo`. No se almacena en ninguna tabla base.
- **activo = TRUE (filtro de vigencia)**: Criterio institucional que determina qué productos y categorías están disponibles para operaciones de negocio. Una categoría inactiva excluye todos sus productos de la vista, incluso si el producto tiene `activo = TRUE`.
- **GRANT SELECT**: Instrucción DDL que otorga permiso de lectura sobre una vista o tabla a un rol específico. Al hacerlo sobre una vista en lugar de la tabla base, el receptor no puede acceder a columnas no incluidas en la vista.
- **Column-level security**: Patrón de seguridad donde el acceso a columnas específicas se controla a través de vistas, sin necesidad de columnas virtuales ni row-level security.
- **JOIN INNER**: Devuelve solo las filas que tienen correspondencia en ambas tablas. Usado en las tres vistas para garantizar consistencia referencial.
- **Columna implícita (PK en hoja B-Tree)**: Concepto de índice; no aplica directamente a vistas.
- **CREATE OR REPLACE VIEW**: Instrucción DDL que crea la vista si no existe, o reemplaza su definición si ya existe, sin necesidad de `DROP VIEW` previo.

---

## Requirements

### Requisito 1: Vista `vw_productos_vigentes`

**User Story:** Como desarrollador de consultas del sistema FoodStore, quiero una vista que exponga únicamente los productos activos con su categoría activa, para poder construir listados del menú sin reescribir los filtros de vigencia en cada consulta.

#### Criterios de Aceptación

1. THE Sistema_de_Vistas SHALL crear la vista `vw_productos_vigentes` con la siguiente instrucción o equivalente funcional:
   ```sql
   CREATE OR REPLACE VIEW vw_productos_vigentes AS
   SELECT
       p.id_producto,
       p.nombre          AS nombre_producto,
       p.descripcion,
       p.precio_lista,
       p.stock,
       c.id_categoria,
       c.nombre          AS nombre_categoria
   FROM producto p
   INNER JOIN categoria c ON p.id_categoria = c.id_categoria
   WHERE p.activo = TRUE
     AND c.activo = TRUE;
   ```

2. WHEN se consulta `SELECT * FROM vw_productos_vigentes`, THE Vista SHALL retornar exactamente las columnas: `id_producto`, `nombre_producto`, `descripcion`, `precio_lista`, `stock`, `id_categoria`, `nombre_categoria`, sin incluir las columnas `activo` de ninguna de las dos tablas base.

3. IF un producto tiene `activo = TRUE` pero su categoría tiene `activo = FALSE`, THEN THE Vista SHALL excluir dicho producto del resultado, ya que el filtro de vigencia institucional aplica a ambas tablas de forma conjunta.

4. IF una categoría tiene `activo = FALSE`, THEN THE Vista SHALL excluir todos los productos de esa categoría independientemente del valor de `activo` en la tabla `producto`.

5. WHEN se ejecuta la prueba de equivalencia:
   ```sql
   SELECT id_producto, nombre, descripcion, precio_lista, stock, p.id_categoria, c.nombre
   FROM producto p INNER JOIN categoria c ON p.id_categoria = c.id_categoria
   WHERE p.activo = TRUE AND c.activo = TRUE
   EXCEPT
   SELECT id_producto, nombre_producto, descripcion, precio_lista, stock, id_categoria, nombre_categoria
   FROM vw_productos_vigentes;
   ```
   THE Procedimiento_de_Prueba SHALL confirmar que el resultado devuelve **cero filas**, validando la equivalencia total entre la vista y la consulta nativa.

6. THE Vista SHALL resolverse mediante un `INNER JOIN` entre `producto` y `categoria` usando la clave foránea `producto.id_categoria = categoria.id_categoria`, garantizando que no aparezcan productos sin categoría registrada.

---

### Requisito 2: Vista `vw_pedidos_cliente_segura`

**User Story:** Como administrador de base de datos del sistema FoodStore, quiero una vista que exponga los pedidos con los datos identificatorios del cliente, omitiendo la columna `direccion` de la tabla `cliente`, para poder otorgar `GRANT SELECT` sobre la vista a roles analíticos sin exponer datos personales de domicilio.

#### Criterios de Aceptación

1. THE Sistema_de_Vistas SHALL crear la vista `vw_pedidos_cliente_segura` con la siguiente instrucción o equivalente funcional:
   ```sql
   CREATE OR REPLACE VIEW vw_pedidos_cliente_segura AS
   SELECT
       p.id_pedido,
       p.fecha_hora,
       p.forma_pago,
       c.id_cliente,
       c.nombre          AS nombre_cliente,
       c.email,
       c.telefono
   FROM pedido p
   INNER JOIN cliente c ON p.id_cliente = c.id_cliente;
   ```

2. WHEN se consulta `SELECT * FROM vw_pedidos_cliente_segura`, THE Vista SHALL retornar exactamente las columnas: `id_pedido`, `fecha_hora`, `forma_pago`, `id_cliente`, `nombre_cliente`, `email`, `telefono`, sin incluir en ningún caso la columna `direccion` de la tabla `cliente`.

3. THE Vista SHALL omitir de forma explícita la columna `cliente.direccion` (VARCHAR 200, dato personal de domicilio) para implementar column-level security mediante la capa de vista, conforme al principio de mínimo privilegio.

4. WHEN se ejecuta `GRANT SELECT ON vw_pedidos_cliente_segura TO <rol_analitico>`, THE Sistema_de_Permisos SHALL permitir que el rol consulte los pedidos con datos del cliente sin tener acceso directo a la tabla `cliente` ni a la columna `direccion`.

5. WHEN se ejecuta la prueba de equivalencia:
   ```sql
   SELECT p.id_pedido, p.fecha_hora, p.forma_pago, c.id_cliente, c.nombre, c.email, c.telefono
   FROM pedido p INNER JOIN cliente c ON p.id_cliente = c.id_cliente
   EXCEPT
   SELECT id_pedido, fecha_hora, forma_pago, id_cliente, nombre_cliente, email, telefono
   FROM vw_pedidos_cliente_segura;
   ```
   THE Procedimiento_de_Prueba SHALL confirmar que el resultado devuelve **cero filas**.

6. THE Vista SHALL incluir la columna `forma_pago` (tipo `forma_pago_enum`) sin conversión de tipo, permitiendo que los consumidores de la vista filtren por `WHERE forma_pago = 'TARJETA'` usando los literales del ENUM directamente.

7. IF se agrega en el futuro una columna de contraseña o hash a la tabla `cliente`, THEN THE Vista SHALL requerir una revisión explícita de su definición para confirmar que la nueva columna sensible no quede incluida en el `SELECT *` implícito — razón por la cual la vista usa `SELECT` con columnas explícitas y nunca `SELECT *` sobre las tablas base.

---

### Requisito 3: Vista `vw_detalle_pedido_completo`

**User Story:** Como analista de datos del sistema FoodStore, quiero una vista que exponga cada línea de detalle de pedido con el nombre del producto, la cantidad, el precio unitario histórico y el subtotal calculado, para poder construir reportes de ventas sin replicar la lógica de cálculo en cada consulta.

#### Criterios de Aceptación

1. THE Sistema_de_Vistas SHALL crear la vista `vw_detalle_pedido_completo` con la siguiente instrucción o equivalente funcional:
   ```sql
   CREATE OR REPLACE VIEW vw_detalle_pedido_completo AS
   SELECT
       dp.id_pedido,
       dp.id_producto,
       pr.nombre                                         AS nombre_producto,
       dp.cantidad,
       dp.precio_unitario_historico,
       (dp.cantidad * dp.precio_unitario_historico)      AS subtotal
   FROM detalle_pedido dp
   INNER JOIN producto pr ON dp.id_producto = pr.id_producto;
   ```

2. WHEN se consulta `SELECT * FROM vw_detalle_pedido_completo`, THE Vista SHALL retornar exactamente las columnas: `id_pedido`, `id_producto`, `nombre_producto`, `cantidad`, `precio_unitario_historico`, `subtotal`, donde `subtotal` es una columna calculada y no está almacenada en ninguna tabla base.

3. THE Vista SHALL calcular `subtotal` como `cantidad * precio_unitario_historico`, usando los valores históricos almacenados en `detalle_pedido.precio_unitario_historico` y no el precio actual de la tabla `producto`, para preservar la integridad del historial de ventas ante cambios de precio posteriores.

4. WHEN se ejecuta la prueba de equivalencia:
   ```sql
   SELECT dp.id_pedido, dp.id_producto, pr.nombre, dp.cantidad,
          dp.precio_unitario_historico, (dp.cantidad * dp.precio_unitario_historico)
   FROM detalle_pedido dp INNER JOIN producto pr ON dp.id_producto = pr.id_producto
   EXCEPT
   SELECT id_pedido, id_producto, nombre_producto, cantidad,
          precio_unitario_historico, subtotal
   FROM vw_detalle_pedido_completo;
   ```
   THE Procedimiento_de_Prueba SHALL confirmar que el resultado devuelve **cero filas**.

5. THE Vista SHALL usar `INNER JOIN` entre `detalle_pedido` y `producto` sobre `id_producto`, garantizando que cada línea de detalle tenga un producto registrado. No se incluyen líneas huérfanas.

6. IF se necesita calcular el total de un pedido completo usando la vista, THEN la consulta `SELECT id_pedido, SUM(subtotal) AS total FROM vw_detalle_pedido_completo GROUP BY id_pedido` SHALL producir resultados equivalentes a calcular la suma directamente desde las tablas base.

---

### Requisito 4: Protocolo de pruebas de equivalencia y validación

**User Story:** Como DBA del proyecto FoodStore, quiero un protocolo estandarizado de pruebas `EXCEPT` para validar que las tres vistas son equivalentes a sus consultas nativas, de modo que cualquier modificación futura al esquema que rompa una vista sea detectada inmediatamente.

#### Criterios de Aceptación

1. THE Procedimiento_de_Prueba SHALL ejecutar la prueba de equivalencia **bidireccional** para cada vista: tanto `consulta_nativa EXCEPT vista` como `vista EXCEPT consulta_nativa`, confirmando que ambas devuelven cero filas y descartando diferencias en cualquier dirección.

2. WHEN alguna de las pruebas `EXCEPT` devuelve al menos una fila, THE Procedimiento_de_Prueba SHALL identificar la fila discrepante e interpretar el resultado como una diferencia en el predicado, las columnas expuestas o el tipo de JOIN entre la vista y la consulta nativa.

3. THE Procedimiento_de_Prueba SHALL ejecutar las pruebas de equivalencia dentro de un bloque `BEGIN; ... ROLLBACK;` cuando incluyan datos de prueba insertados, garantizando que la base de datos `foodstore_dev` quede en estado limpio tras cada ejecución.

4. WHEN se ejecutan las pruebas sobre una base de datos con cero registros en las tablas base, THE Procedimiento_de_Prueba SHALL reportar cero filas en las pruebas `EXCEPT` — resultado válido pero no concluyente — y SHALL documentar que la prueba debe repetirse con datos reales cargados desde `data.sql`.

5. THE Procedimiento_de_Prueba SHALL verificar el conteo de columnas expuestas por cada vista ejecutando:
   ```sql
   SELECT column_name, data_type
   FROM information_schema.columns
   WHERE table_name IN ('vw_productos_vigentes', 'vw_pedidos_cliente_segura', 'vw_detalle_pedido_completo')
   ORDER BY table_name, ordinal_position;
   ```
   Y SHALL confirmar que `vw_pedidos_cliente_segura` no expone la columna `direccion` en el resultado.
