# Plan de Implementación: Vistas Transaccionales y de Reportes — FoodStore

## Overview

Este plan implementa las tres vistas SQL sobre `foodstore_dev` y ejecuta el protocolo completo de pruebas de equivalencia. El flujo es estrictamente secuencial: primero se crea el script consolidado, luego se crean las vistas, se verifica la estructura de columnas, se valida la seguridad de la vista V2 y finalmente se ejecutan las seis pruebas EXCEPT bidireccionales.

Todas las pruebas que involucran modificaciones de datos (Paso 7 del diseño) se ejecutan dentro de bloques `BEGIN; ... ROLLBACK;` conforme al protocolo de seguridad del proyecto.

El archivo a crear en la raíz del proyecto es `vistas_reportes.sql`.

---

## Tasks

- [ ] 1. Verificar que las tablas base tienen datos antes de comenzar
  - Ejecutar en `psql -U postgres -d foodstore_dev`:
    ```sql
    SELECT 'producto'       AS tabla, COUNT(*) FROM producto       UNION ALL
    SELECT 'categoria',              COUNT(*) FROM categoria       UNION ALL
    SELECT 'pedido',                 COUNT(*) FROM pedido          UNION ALL
    SELECT 'cliente',                COUNT(*) FROM cliente         UNION ALL
    SELECT 'detalle_pedido',         COUNT(*) FROM detalle_pedido;
    ```
  - Si alguna tabla retorna `0`, ejecutar `data.sql` primero: `psql -U postgres -d foodstore_dev -f data.sql`
  - Las pruebas de equivalencia con tablas vacías son válidas técnicamente pero no concluyentes.
  - _Requirements: R4.4_

- [ ] 2. Crear el archivo `vistas_reportes.sql` en la raíz del proyecto
  - Crear el archivo con los cuatro bloques del diseño:

    ```sql
    -- ============================================================
    -- vistas_reportes.sql
    -- Implementación y validación de vistas transaccionales
    -- y de reportes para FoodStore
    -- Base de datos: foodstore_dev
    -- ============================================================


    -- ============================================================
    -- BLOQUE 1: Creación de las tres vistas
    -- ============================================================

    -- V1: Productos vigentes con categoría activa
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

    -- V2: Pedidos con datos del cliente — sin columna direccion
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

    -- V3: Detalle de pedido completo con subtotal calculado
    CREATE OR REPLACE VIEW vw_detalle_pedido_completo AS
    SELECT
        dp.id_pedido,
        dp.id_producto,
        pr.nombre                                        AS nombre_producto,
        dp.cantidad,
        dp.precio_unitario_historico,
        (dp.cantidad * dp.precio_unitario_historico)     AS subtotal
    FROM detalle_pedido dp
    INNER JOIN producto pr ON dp.id_producto = pr.id_producto;


    -- ============================================================
    -- BLOQUE 2: Verificación de columnas expuestas
    -- ============================================================

    SELECT table_name, column_name, data_type, ordinal_position
    FROM information_schema.columns
    WHERE table_name IN (
        'vw_productos_vigentes',
        'vw_pedidos_cliente_segura',
        'vw_detalle_pedido_completo'
    )
    ORDER BY table_name, ordinal_position;
    -- Verificar: 'vw_pedidos_cliente_segura' NO debe mostrar 'direccion'.


    -- ============================================================
    -- BLOQUE 3: Prueba de seguridad — 'direccion' ausente en V2
    -- ============================================================

    SELECT column_name
    FROM information_schema.columns
    WHERE table_name = 'vw_pedidos_cliente_segura'
      AND column_name = 'direccion';
    -- Resultado esperado: 0 filas.


    -- ============================================================
    -- BLOQUE 4: Pruebas de equivalencia EXCEPT (bidireccionales)
    -- Todas deben retornar 0 filas.
    -- ============================================================

    -- V1: consulta nativa EXCEPT vista
    SELECT p.id_producto, p.nombre, p.descripcion, p.precio_lista, p.stock,
           p.id_categoria, c.nombre
    FROM producto p INNER JOIN categoria c ON p.id_categoria = c.id_categoria
    WHERE p.activo = TRUE AND c.activo = TRUE
    EXCEPT
    SELECT id_producto, nombre_producto, descripcion, precio_lista, stock,
           id_categoria, nombre_categoria
    FROM vw_productos_vigentes;

    -- V1 inversa: vista EXCEPT consulta nativa
    SELECT id_producto, nombre_producto, descripcion, precio_lista, stock,
           id_categoria, nombre_categoria
    FROM vw_productos_vigentes
    EXCEPT
    SELECT p.id_producto, p.nombre, p.descripcion, p.precio_lista, p.stock,
           p.id_categoria, c.nombre
    FROM producto p INNER JOIN categoria c ON p.id_categoria = c.id_categoria
    WHERE p.activo = TRUE AND c.activo = TRUE;

    -- V2: consulta nativa EXCEPT vista
    SELECT p.id_pedido, p.fecha_hora, p.forma_pago,
           c.id_cliente, c.nombre, c.email, c.telefono
    FROM pedido p INNER JOIN cliente c ON p.id_cliente = c.id_cliente
    EXCEPT
    SELECT id_pedido, fecha_hora, forma_pago,
           id_cliente, nombre_cliente, email, telefono
    FROM vw_pedidos_cliente_segura;

    -- V2 inversa: vista EXCEPT consulta nativa
    SELECT id_pedido, fecha_hora, forma_pago,
           id_cliente, nombre_cliente, email, telefono
    FROM vw_pedidos_cliente_segura
    EXCEPT
    SELECT p.id_pedido, p.fecha_hora, p.forma_pago,
           c.id_cliente, c.nombre, c.email, c.telefono
    FROM pedido p INNER JOIN cliente c ON p.id_cliente = c.id_cliente;

    -- V3: consulta nativa EXCEPT vista
    SELECT dp.id_pedido, dp.id_producto, pr.nombre, dp.cantidad,
           dp.precio_unitario_historico,
           (dp.cantidad * dp.precio_unitario_historico)
    FROM detalle_pedido dp INNER JOIN producto pr ON dp.id_producto = pr.id_producto
    EXCEPT
    SELECT id_pedido, id_producto, nombre_producto, cantidad,
           precio_unitario_historico, subtotal
    FROM vw_detalle_pedido_completo;

    -- V3 inversa: vista EXCEPT consulta nativa
    SELECT id_pedido, id_producto, nombre_producto, cantidad,
           precio_unitario_historico, subtotal
    FROM vw_detalle_pedido_completo
    EXCEPT
    SELECT dp.id_pedido, dp.id_producto, pr.nombre, dp.cantidad,
           dp.precio_unitario_historico,
           (dp.cantidad * dp.precio_unitario_historico)
    FROM detalle_pedido dp INNER JOIN producto pr ON dp.id_producto = pr.id_producto;


    -- ============================================================
    -- BLOQUE 5: Prueba funcional — subtotales sin discrepancia
    -- ============================================================

    SELECT v.id_pedido,
           SUM(v.subtotal)                                       AS total_por_vista,
           SUM(dp.cantidad * dp.precio_unitario_historico)       AS total_directo
    FROM vw_detalle_pedido_completo v
    JOIN detalle_pedido dp USING (id_pedido, id_producto)
    GROUP BY v.id_pedido
    HAVING SUM(v.subtotal) <> SUM(dp.cantidad * dp.precio_unitario_historico);
    -- Resultado esperado: 0 filas.


    -- ============================================================
    -- BLOQUE 6: Prueba de filtro de vigencia doble — V1
    -- Ejecutar dentro de BEGIN/ROLLBACK para no alterar datos reales
    -- ============================================================

    BEGIN;
        -- Desactivar la primera categoría temporalmente:
        UPDATE categoria SET activo = FALSE WHERE id_categoria = 1;

        -- Los productos de esa categoría NO deben aparecer en la vista:
        SELECT COUNT(*) AS productos_de_categ_1_en_vista
        FROM vw_productos_vigentes
        WHERE id_categoria = 1;
        -- Resultado esperado: 0 filas.

    ROLLBACK;
    -- La categoría queda restaurada a activo = TRUE.
    ```

  - _Requirements: R1.1, R2.1, R3.1, R4.1, R4.3_

- [ ] 3. Ejecutar el Bloque 1: crear las tres vistas en `foodstore_dev`
  - Ejecutar las tres instrucciones `CREATE OR REPLACE VIEW` del Bloque 1 en orden.
  - Confirmar que cada una retorna `CREATE VIEW` en la consola de `psql`.
  - Verificar que las vistas existen en el catálogo:
    ```sql
    SELECT table_name FROM information_schema.views
    WHERE table_schema = 'public'
      AND table_name IN (
          'vw_productos_vigentes',
          'vw_pedidos_cliente_segura',
          'vw_detalle_pedido_completo'
      );
    ```
  - Resultado esperado: 3 filas.
  - _Requirements: R1.1, R2.1, R3.1_

- [ ] 4. Ejecutar el Bloque 2: verificar columnas expuestas por cada vista
  - Ejecutar la consulta a `information_schema.columns` del Bloque 2.
  - Verificar columna por columna para cada vista:
    - `vw_productos_vigentes`: debe mostrar exactamente `id_producto`, `nombre_producto`, `descripcion`, `precio_lista`, `stock`, `id_categoria`, `nombre_categoria` (7 columnas).
    - `vw_pedidos_cliente_segura`: debe mostrar exactamente `id_pedido`, `fecha_hora`, `forma_pago`, `id_cliente`, `nombre_cliente`, `email`, `telefono` (7 columnas).
    - `vw_detalle_pedido_completo`: debe mostrar exactamente `id_pedido`, `id_producto`, `nombre_producto`, `cantidad`, `precio_unitario_historico`, `subtotal` (6 columnas).
  - _Requirements: R1.2, R2.2, R3.2_

- [ ] 5. Ejecutar el Bloque 3: prueba de seguridad — `direccion` ausente en V2
  - Ejecutar la consulta del Bloque 3.
  - **Resultado esperado: 0 filas.**
  - Si retorna 1 fila (con `column_name = 'direccion'`): la vista fue creada con `SELECT *` o la columna fue incluida por error. Corregir con `CREATE OR REPLACE VIEW vw_pedidos_cliente_segura AS ...` usando columnas explícitas.
  - _Requirements: R2.2, R2.3, R4.5_

- [ ] 6. Ejecutar el Bloque 4: pruebas de equivalencia EXCEPT (6 consultas)
  - Ejecutar las 6 consultas EXCEPT del Bloque 4 una por una.
  - Registrar el resultado de cada una:

    | Prueba | Consulta | Resultado | ¿OK? |
    |--------|----------|-----------|------|
    | V1: nativa EXCEPT vista | Bloque 4 — Q1 | ? filas | ? |
    | V1 inversa: vista EXCEPT nativa | Bloque 4 — Q2 | ? filas | ? |
    | V2: nativa EXCEPT vista | Bloque 4 — Q3 | ? filas | ? |
    | V2 inversa: vista EXCEPT nativa | Bloque 4 — Q4 | ? filas | ? |
    | V3: nativa EXCEPT vista | Bloque 4 — Q5 | ? filas | ? |
    | V3 inversa: vista EXCEPT nativa | Bloque 4 — Q6 | ? filas | ? |

  - **Todas deben retornar 0 filas.**
  - Si alguna retorna filas: ver Caso 3 del Error Handling en `spec_vistas_reportes_design.md`.
  - _Requirements: R1.5, R2.5, R3.4, R4.1, R4.2_

- [ ] 7. Ejecutar el Bloque 5: prueba funcional de subtotales
  - Ejecutar la consulta del Bloque 5 (sum de subtotales vista vs. cálculo directo).
  - **Resultado esperado: 0 filas** (ningún pedido con discrepancia).
  - _Requirements: R3.3, R3.6_

- [ ] 8. Ejecutar el Bloque 6: prueba de filtro de vigencia doble (BEGIN/ROLLBACK)
  - Ejecutar el bloque transaccional del Bloque 6 completo.
  - Verificar que los productos de la categoría desactivada retornan 0 filas en `vw_productos_vigentes`.
  - Confirmar que el ROLLBACK restaura el estado (`activo = TRUE`) sin cambios permanentes.
  - _Requirements: R1.3, R1.4, R4.3_

- [ ] 9. Checkpoint — Registrar resultados de todas las pruebas
  - Completar la tabla de la tarea 6 con los resultados reales.
  - Confirmar que los 6 EXCEPT, la prueba de seguridad, la prueba funcional y la prueba de vigencia doble retornaron los resultados esperados.
  - Documentar los resultados en `informe_mediciones.md` o `bitacora_competencia.md`.

- [ ]* 10. [OPCIONAL] Otorgar permisos sobre las vistas a un rol analítico
  - Solo ejecutar si existe un rol analítico en `foodstore_dev` o si se requiere para la entrega.
  - Crear el rol y otorgar permisos:
    ```sql
    -- Crear un rol de lectura si no existe:
    DO $$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'rol_reportes') THEN
            CREATE ROLE rol_reportes;
        END IF;
    END;
    $$;

    -- Otorgar SELECT sobre las tres vistas:
    GRANT SELECT ON vw_productos_vigentes       TO rol_reportes;
    GRANT SELECT ON vw_pedidos_cliente_segura   TO rol_reportes;
    GRANT SELECT ON vw_detalle_pedido_completo  TO rol_reportes;
    ```
  - Verificar que el rol puede consultar las vistas pero no las tablas base:
    ```sql
    -- Como rol_reportes, esto debe funcionar:
    SET ROLE rol_reportes;
    SELECT COUNT(*) FROM vw_productos_vigentes;
    SELECT COUNT(*) FROM vw_pedidos_cliente_segura;
    SELECT COUNT(*) FROM vw_detalle_pedido_completo;
    RESET ROLE;
    ```
  - _Requirements: R2.4_

- [ ]* 11. [OPCIONAL] Prueba de consultas de uso típico sobre las vistas
  - Ejecutar las consultas de uso típico documentadas en el design.md para confirmar que las vistas responden correctamente a casos de uso reales:
    ```sql
    -- V1: Listado del menú disponible
    SELECT nombre_producto, precio_lista, stock, nombre_categoria
    FROM vw_productos_vigentes WHERE stock > 0
    ORDER BY nombre_categoria, nombre_producto;

    -- V2: Historial de pedidos del primer cliente
    SELECT id_pedido, fecha_hora, forma_pago, nombre_cliente, email
    FROM vw_pedidos_cliente_segura
    WHERE id_cliente = (SELECT MIN(id_cliente) FROM cliente)
    ORDER BY fecha_hora DESC;

    -- V3: Total de un pedido específico
    SELECT id_pedido, SUM(subtotal) AS total_pedido
    FROM vw_detalle_pedido_completo
    WHERE id_pedido = (SELECT MIN(id_pedido) FROM pedido)
    GROUP BY id_pedido;
    ```
  - _Requirements: R1.1, R2.1, R3.1_

---

## Notes

- **`CREATE OR REPLACE VIEW`** permite recrear una vista sin necesidad de `DROP VIEW` previo. Si la vista ya existe con una firma diferente (por ejemplo, distinta cantidad de columnas), PostgreSQL puede requerir el DROP manual. En ese caso: `DROP VIEW IF EXISTS <nombre>; CREATE VIEW ...`.
- **Pruebas EXCEPT con tablas vacías**: si alguna tabla base no tiene datos, las pruebas devuelven 0 filas técnicamente pero no validan la lógica de JOIN ni los filtros. Siempre ejecutar con `data.sql` cargado.
- **`direccion` es la columna sensible en este esquema**: la tabla `cliente` de FoodStore no tiene columna de contraseña. `direccion` es el dato personal a omitir por criterio de mínimo privilegio.
- **Subtotal no se almacena**: `vw_detalle_pedido_completo.subtotal` es `cantidad * precio_unitario_historico` calculado en tiempo de consulta. Si se necesita materializar para reportes de alto volumen, considerar una vista materializada o una tabla de staging.
- **Prueba de vigencia doble (tarea 8)**: siempre envolver en `BEGIN; ... ROLLBACK;` para no dejar categorías desactivadas permanentemente en `foodstore_dev`.
- Las tareas marcadas con `*` son **opcionales** y no bloquean la validación técnica del TP. El experimento mínimo viable comprende las tareas 1–9.

---

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1"] },
    { "id": 1, "tasks": ["2"] },
    { "id": 2, "tasks": ["3"] },
    { "id": 3, "tasks": ["4", "5"] },
    { "id": 4, "tasks": ["6"] },
    { "id": 5, "tasks": ["7", "8"] },
    { "id": 6, "tasks": ["9"] },
    { "id": 7, "tasks": ["10", "11"] }
  ]
}
```
