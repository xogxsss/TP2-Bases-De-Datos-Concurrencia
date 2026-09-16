# Implementation Plan: pedido-date-index-optimization

## Overview

Este plan implementa el experimento de optimización de índice sobre la tabla `pedido` (~200.000 registros) de la base de datos `foodstore_dev`. El flujo es estrictamente secuencial y opera en una única sesión `psql`:

1. **Precondición**: verificar que no existe ningún índice sobre `fecha_hora` y que los parámetros del planificador están en sus valores por defecto.
2. **Diagnóstico**: estimar la selectividad de la ventana temporal y medir el baseline de la consulta objetivo sin ningún índice nuevo.
3. **Creación del script**: consolidar todos los bloques SQL en el archivo `pedido_experiment.sql`.
4. **Experimento transaccional**: crear el índice (Variante A) dentro de un bloque `BEGIN … ROLLBACK`, ejecutar `EXPLAIN ANALYZE` dos veces (cold y warm) y revertir.
5. **Verificación post-ROLLBACK**: confirmar que el índice fue eliminado del catálogo.
6. **Evaluación**: comparar métricas y verificar los criterios de éxito R4.1–R4.5.
7. **Pasos opcionales/condicionales**: Variante C con `VACUUM` previo, Variante B para consultas con filtro de cliente, y promoción a producción con `CREATE INDEX CONCURRENTLY`.

Todas las instrucciones DDL se ejecutan dentro de bloques `BEGIN; … ROLLBACK;` conforme al protocolo de seguridad del proyecto. Ninguna modificación permanente al esquema se realiza sin haber validado los criterios de éxito.

---

## Tasks

- [ ] 1. Verificar estado inicial del catálogo (`pg_indexes`)
  - Ejecutar la siguiente consulta en `psql -U postgres -d foodstore_dev`:
    ```sql
    SELECT indexname, indexdef
    FROM   pg_indexes
    WHERE  tablename = 'pedido';
    ```
  - Confirmar que **ninguna fila** contiene `fecha_hora` en `indexdef`.
  - Si existe un índice previo sobre `fecha_hora`, detener el experimento, identificar su nombre y eliminarlo con `DROP INDEX <nombre>` antes de continuar.
  - _Requirements: R1.3, R3.8_

- [ ] 2. Verificar parámetros del planificador
  - Ejecutar los dos comandos `SHOW` en la misma sesión abierta en el paso anterior:
    ```sql
    SHOW enable_indexscan;
    SHOW enable_seqscan;
    ```
  - Confirmar que ambos devuelven `on`. Si alguno devuelve `off`, ejecutar el `SET` correspondiente y reiniciar desde la tarea 1:
    ```sql
    SET enable_seqscan   = on;
    SET enable_indexscan = on;
    ```
  - _Requirements: R1.6, R3.5_

- [ ] 3. Estimar selectividad de la ventana temporal
  - Ejecutar el conteo de filas dentro del rango de 30 días:
    ```sql
    SELECT COUNT(*)
    FROM   pedido
    WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW();
    ```
  - Registrar el resultado. Si supera ~40.000 filas (>20% de 200.000), documentar la advertencia: el Optimizador puede preferir Seq_Scan incluso con índice disponible (ver R2.7 y Caso 1 del Error Handling). El experimento continúa de todas formas.
  - _Requirements: R3.6, R2.7_

- [ ] 4. Medir baseline sin índice (tres ejecuciones consecutivas)
  - Ejecutar la siguiente instrucción **tres veces seguidas** sin cerrar la sesión entre ejecuciones:
    ```sql
    EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
    SELECT id_pedido, fecha_hora, forma_pago, id_cliente
    FROM   pedido
    WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
    ORDER BY fecha_hora DESC;
    ```
  - Registrar **únicamente los valores de la tercera ejecución** (datos en `shared_buffers`, tiempo de I/O estabilizado) como referencia de baseline:
    - Nodo de acceso (debe ser `Seq_Scan`)
    - Presencia del nodo `Sort`
    - `Planning Time` (ms, dos decimales)
    - `Execution Time` (ms, dos decimales) — **este es el valor de referencia R3.1**
    - `shared hit` y `shared read`
    - Heap blocks leídos
  - Confirmar que `Execution Time > 1.00 ms` en las tres ejecuciones (R1.4) y que el plan muestra `Seq_Scan` con `rows` estimado entre 180.000 y 220.000 (R1.5).
  - _Requirements: R1.1, R1.2, R1.4, R1.5, R3.1, R3.2_

- [ ] 5. Crear el archivo `pedido_experiment.sql` con los 6 bloques del diseño
  - Crear el archivo `pedido_experiment.sql` en la raíz del repositorio con exactamente los siguientes seis bloques en orden, separados por comentarios de sección:

    ```sql
    -- ============================================================
    -- pedido_experiment.sql
    -- Experimento de optimización de índice sobre pedido.fecha_hora
    -- Base de datos: foodstore_dev
    -- PROTOCOLO: ejecutar en orden, dentro de una única sesión psql
    -- ============================================================

    -- BLOQUE 0 — Verificación de estado inicial del catálogo
    -- Precondición: no debe existir ningún índice sobre fecha_hora.
    SELECT indexname, indexdef
    FROM   pg_indexes
    WHERE  tablename = 'pedido';

    -- BLOQUE A — Verificación de parámetros del planificador
    -- Ambos deben retornar 'on'. Si alguno es 'off', invalidar el experimento.
    SHOW enable_indexscan;
    SHOW enable_seqscan;

    -- BLOQUE B — Estimación de selectividad de la ventana temporal
    -- Si el resultado supera ~40.000 filas (>20% de 200k), documentar la advertencia.
    SELECT COUNT(*)
    FROM   pedido
    WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW();

    -- BLOQUE C — Medición de baseline sin índice (ejecutar 3 veces)
    -- Registrar únicamente los valores de la TERCERA ejecución como referencia.
    EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
    SELECT id_pedido, fecha_hora, forma_pago, id_cliente
    FROM   pedido
    WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
    ORDER BY fecha_hora DESC;
    -- (repetir 2 veces más antes del BLOQUE D)

    -- BLOQUE D — Bloque transaccional de prueba (Variante A)
    -- El ROLLBACK al final elimina el índice y deja la tabla exactamente como estaba.
    BEGIN;

      CREATE INDEX idx_pedido_fecha_hora
          ON pedido (fecha_hora DESC);

      ANALYZE pedido;

      -- 1ra ejecución post-índice (cold cache — índice recién creado):
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_pedido, fecha_hora, forma_pago, id_cliente
      FROM   pedido
      WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
      ORDER BY fecha_hora DESC;

      -- 2da ejecución post-índice (warm cache — índice ya en shared_buffers):
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_pedido, fecha_hora, forma_pago, id_cliente
      FROM   pedido
      WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
      ORDER BY fecha_hora DESC;

    ROLLBACK;

    -- BLOQUE E — Verificación post-ROLLBACK
    -- idx_pedido_fecha_hora NO debe aparecer en el resultado.
    SELECT indexname, indexdef
    FROM   pg_indexes
    WHERE  tablename = 'pedido';

    -- BLOQUE F — Creación definitiva en producción (CONDICIONAL)
    -- SOLO ejecutar si TODOS los criterios R4.1–R4.5 se cumplen.
    -- CONCURRENTLY permite construir el índice sin bloquear escrituras.
    -- IMPORTANTE: ejecutar FUERA de cualquier bloque BEGIN…COMMIT.
    --
    -- CREATE INDEX CONCURRENTLY idx_pedido_fecha_hora
    --     ON pedido (fecha_hora DESC);
    --
    -- Alternativa Variante C (si se validó en el paso opcional):
    -- CREATE INDEX CONCURRENTLY idx_pedido_fecha_cubriente
    --     ON pedido (fecha_hora DESC)
    --     INCLUDE (forma_pago, id_cliente);
    ```

  - Verificar que el archivo fue creado correctamente y que los seis bloques están presentes y en orden.
  - _Requirements: R2.1, R2.4, R2.5, R3.3, R3.8, R3.9_

- [ ] 6. Ejecutar el bloque transaccional (Bloque D): BEGIN → CREATE INDEX → ANALYZE → EXPLAIN ×2 → ROLLBACK
  - Abrir `pedido_experiment.sql` en `psql` o pegar el Bloque D en la sesión activa:
    ```sql
    BEGIN;

      CREATE INDEX idx_pedido_fecha_hora
          ON pedido (fecha_hora DESC);

      ANALYZE pedido;

      -- Cold (1ra ejecución post-índice):
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_pedido, fecha_hora, forma_pago, id_cliente
      FROM   pedido
      WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
      ORDER BY fecha_hora DESC;

      -- Warm (2da ejecución post-índice):
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_pedido, fecha_hora, forma_pago, id_cliente
      FROM   pedido
      WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
      ORDER BY fecha_hora DESC;

    ROLLBACK;
    ```
  - Registrar para cada una de las dos ejecuciones post-índice:
    - Nodo de acceso (`Index_Scan`, `Bitmap_Index_Scan` o `Index_Only_Scan`)
    - Presencia o ausencia del nodo `Sort`
    - `Execution Time` (ms, dos decimales)
    - `shared hit` del índice y heap blocks leídos
  - Confirmar que `ROLLBACK` se ejecutó sin errores y que la sesión muestra `ROLLBACK` en la consola.
  - _Requirements: R2.2, R2.3, R2.8, R3.3, R3.4, R3.5_

- [ ] 7. Verificar `pg_indexes` post-ROLLBACK (Bloque E)
  - Ejecutar inmediatamente después del `ROLLBACK` la consulta del Bloque E:
    ```sql
    SELECT indexname, indexdef
    FROM   pg_indexes
    WHERE  tablename = 'pedido';
    ```
  - Confirmar que `idx_pedido_fecha_hora` **no aparece** en el resultado.
  - Si el índice persiste, el `ROLLBACK` no se completó correctamente: verificar el estado de la transacción con `\echo :SQLSTATE` o cerrando y reabriendo la sesión.
  - _Requirements: R3.9_

- [ ] 8. Comparar métricas y evaluar criterios de éxito R4.1–R4.5
  - Con los valores registrados en las tareas 4 y 6, completar la siguiente tabla comparativa:

    | Métrica | Baseline (3ra ejec.) | Post-índice cold (1ra) | Post-índice warm (2da) |
    |---------|---------------------|-----------------------|-----------------------|
    | Nodo de acceso | Seq_Scan | ? | ? |
    | Sort presente | Sí | ? | ? |
    | Execution Time (ms) | X ms | ? ms | ? ms |
    | Shared Hit (índice) | 0 | ? | ? |
    | Heap blocks leídos | N | ? | ? |

  - Verificar cada criterio:

    | Criterio | Descripción | ¿Cumplido? |
    |----------|-------------|-----------|
    | R4.1 | Seq_Scan reemplazado por Index_Scan / Bitmap_Index_Scan / Index_Only_Scan | Sí / No |
    | R4.2 | Nodo Sort ausente del plan post-índice | Sí / No |
    | R4.3 | Reducción de Execution Time ≥ 20% (warm post-índice vs. baseline 3ra ejec.) | Sí / No |
    | R4.4a | Shared hit del índice > 0 en medición warm | Sí / No |
    | R4.4b | Heap blocks leídos post-índice < heap blocks en baseline | Sí / No |
    | R4.5 | Si Seq_Scan persiste: selectividad documentada con COUNT(*) | N/A / Sí |

  - Si R4.3 no se cumple pero R4.1 y R4.2 sí, verificar la selectividad (tarea 3) y documentar si supera el 20%.
  - _Requirements: R4.1, R4.2, R4.3, R4.4, R4.5, R4.6_

- [ ] 9. Checkpoint — Confirmar resultados antes de continuar
  - Asegurarse de que:
    - Los valores de la tabla comparativa de la tarea 8 están completos.
    - El estado de cada criterio R4.1–R4.5 está registrado.
    - `pg_indexes` no muestra `idx_pedido_fecha_hora` (tarea 7 completada).
  - Preguntar al usuario si hay dudas o si se desea proceder a los pasos opcionales.

- [ ]* 10. [OPCIONAL] Evaluar Variante C con `VACUUM` previo (índice cubriente)
  - Solo ejecutar si los criterios R4.1–R4.5 se cumplieron en la tarea 8 y se desea verificar la eliminación total de Heap Fetches.
  - Ejecutar `VACUUM` fuera de cualquier bloque transaccional:
    ```sql
    VACUUM pedido;
    ```
  - Ejecutar el bloque transaccional para la Variante C:
    ```sql
    BEGIN;

      CREATE INDEX idx_pedido_fecha_cubriente
          ON pedido (fecha_hora DESC)
          INCLUDE (forma_pago, id_cliente);

      ANALYZE pedido;

      -- Ejecución warm (Index_Only_Scan esperado con Heap Fetches = 0):
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_pedido, fecha_hora, forma_pago, id_cliente
      FROM   pedido
      WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
      ORDER BY fecha_hora DESC;

    ROLLBACK;
    ```
  - Verificar que el plan muestra `Index_Only_Scan` y `Heap Fetches: 0`.
  - Si `Heap Fetches > 0`, documentar que el visibility map no estaba completamente poblado (ver Caso 3 del Error Handling en el diseño).
  - _Requirements: R2.5, R2.6, R2.8_

- [ ]* 11. [OPCIONAL] Evaluar Variante B para consultas con filtro de cliente
  - Solo ejecutar si se desea validar el comportamiento con la consulta compuesta.
  - Ejecutar el bloque transaccional para la Variante B:
    ```sql
    BEGIN;

      CREATE INDEX idx_pedido_fecha_cliente
          ON pedido (fecha_hora DESC, id_cliente);

      ANALYZE pedido;

      -- Consulta con filtro de cliente (caso de uso óptimo de Variante B):
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_pedido, fecha_hora, forma_pago, id_cliente
      FROM   pedido
      WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
        AND  id_cliente = 1  -- reemplazar con un id_cliente real de la tabla
      ORDER BY fecha_hora DESC;

      -- Consulta objetivo original (sin filtro de cliente):
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_pedido, fecha_hora, forma_pago, id_cliente
      FROM   pedido
      WHERE  fecha_hora BETWEEN NOW() - INTERVAL '30 days' AND NOW()
      ORDER BY fecha_hora DESC;

    ROLLBACK;
    ```
  - Verificar que la consulta con `AND id_cliente = <valor>` usa `Index_Scan` sobre `idx_pedido_fecha_cliente`.
  - Verificar que la consulta objetivo sin filtro de cliente puede usar este índice (aunque el Optimizador puede preferir el índice simple si ambos coexisten).
  - _Requirements: R2.4_

- [ ]* 12. [CONDICIONAL] Crear índice definitivo con `CREATE INDEX CONCURRENTLY` para producción
  - Solo ejecutar si **todos** los criterios R4.1–R4.5 se cumplen (tarea 8) y se decide promover el índice a producción.
  - **IMPORTANTE**: `CREATE INDEX CONCURRENTLY` debe ejecutarse **fuera de cualquier bloque `BEGIN … COMMIT`**.
  - Elegir la variante validada y ejecutar:
    ```sql
    -- Variante A (recomendada si solo se validó la tarea 8):
    CREATE INDEX CONCURRENTLY idx_pedido_fecha_hora
        ON pedido (fecha_hora DESC);

    -- Variante C (si también se validó la tarea 10 con Heap Fetches = 0):
    -- CREATE INDEX CONCURRENTLY idx_pedido_fecha_cubriente
    --     ON pedido (fecha_hora DESC)
    --     INCLUDE (forma_pago, id_cliente);
    ```
  - Verificar la creación del índice:
    ```sql
    SELECT indexname, indexdef
    FROM   pg_indexes
    WHERE  tablename = 'pedido';
    ```
  - Confirmar que el nuevo índice aparece en `pg_indexes` y es usable por el Optimizador.
  - _Requirements: R4.7_

---

## Notes

- **Protocolo de seguridad obligatorio**: toda instrucción DDL (`CREATE INDEX`) debe ejecutarse dentro de un bloque `BEGIN; … ROLLBACK;` durante la fase de experimentación. Nunca ejecutar `CREATE INDEX` directamente sin este contenedor, excepto en la tarea 12 (producción condicional).
- **Sesión única**: todas las tareas de 1 a 9 deben ejecutarse en la **misma sesión `psql`** sin cerrar la conexión entre pasos, para garantizar que los datos de `shared_buffers` sean consistentes entre el baseline y las mediciones post-índice.
- **Tercera ejecución del baseline**: la referencia de baseline siempre es la **tercera ejecución** del Bloque C, no la primera ni la segunda. Las dos primeras sirven para calentar el cache.
- **ANALYZE obligatorio**: siempre ejecutar `ANALYZE pedido` inmediatamente después de `CREATE INDEX` dentro del bloque transaccional. Sin esto, el Optimizador puede tomar decisiones incorrectas por estadísticas desactualizadas.
- **Selectividad alta (>20%)**: si el COUNT(*) de la tarea 3 supera ~40.000 filas, el Optimizador puede mantener el `Seq_Scan` incluso con el índice disponible. Esto **no es un error** del índice; es el comportamiento correcto del planificador por razones de costo.
- **Variante C requiere VACUUM**: para obtener `Index_Only_Scan` con `Heap Fetches = 0`, es obligatorio ejecutar `VACUUM pedido` antes del bloque transaccional. Sin VACUUM, el visibility map puede estar incompleto y el plan degrada a `Index_Scan`.
- **`CREATE INDEX CONCURRENTLY` fuera de transacción**: este comando no puede ejecutarse dentro de un bloque `BEGIN … COMMIT`. Intentarlo genera un error de PostgreSQL. Solo aplica a la tarea 12 (promoción a producción).
- **Parámetros del planificador**: si `enable_seqscan = off` o `enable_indexscan = off` en la sesión, los resultados de `EXPLAIN ANALYZE` no reflejan el comportamiento real del Optimizador y el experimento queda **invalidado**. Verificar siempre en la tarea 2.
- Las tareas marcadas con `*` son **opcionales** y pueden omitirse para completar el experimento mínimo viable (tareas 1–9).

---

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1"] },
    { "id": 1, "tasks": ["2"] },
    { "id": 2, "tasks": ["3"] },
    { "id": 3, "tasks": ["4"] },
    { "id": 4, "tasks": ["5"] },
    { "id": 5, "tasks": ["6"] },
    { "id": 6, "tasks": ["7"] },
    { "id": 7, "tasks": ["8"] },
    { "id": 8, "tasks": ["9", "10", "11"] },
    { "id": 9, "tasks": ["12"] }
  ]
}
```
