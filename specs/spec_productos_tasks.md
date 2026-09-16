# Implementation Plan: Query & Index Optimization — FoodStore

## Overview

Plan de implementación del experimento de optimización de consulta sobre la tabla `producto` de FoodStore. Las tareas siguen el flujo experimental definido en el diseño: verificación de precondiciones → medición de baseline → construcción del script completo → ejecución del experimento transaccional → evaluación de resultados → acciones opcionales de seguimiento.

Todos los scripts se ejecutan con `psql -U postgres -d foodstore_dev`. Toda operación DDL debe estar contenida en bloques `BEGIN; ... ROLLBACK;` salvo el paso de promoción a producción (Bloque D), que requiere ejecutarse fuera de transacción.

---

## Tasks

- [ ] 1. Verificar precondiciones del planificador
  - [ ] 1.1 Confirmar que `enable_indexscan` y `enable_seqscan` están en `on`
    - Ejecutar en `psql`:
      ```sql
      SHOW enable_indexscan;
      SHOW enable_seqscan;
      ```
    - Ambos deben retornar `on`. Si alguno retorna `off`, corregir antes de continuar:
      ```sql
      SET enable_seqscan = on;
      SET enable_indexscan = on;
      ```
    - _Requirements: R3.5, R1_

  - [ ] 1.2 Confirmar que no existe el índice `idx_producto_precio_stock` en la tabla
    - Ejecutar en `psql`:
      ```sql
      \d producto
      ```
    - Verificar que la sección "Indexes" no muestra `idx_producto_precio_stock` ni `idx_producto_precio_stock_activo`.
    - _Requirements: R1.5_

- [ ] 2. Medir baseline sin índice (3 ejecuciones consecutivas)
  - [ ] 2.1 Ejecutar EXPLAIN ANALYZE tres veces consecutivas sin consultas intermedias sobre `producto`
    - Ejecutar el siguiente bloque **tres veces** en la misma sesión de `psql`, sin interrupciones:
      ```sql
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_producto, nombre, precio_lista, stock
      FROM producto
      WHERE precio_lista BETWEEN 1000 AND 2500
        AND stock > 50
      ORDER BY precio_lista DESC;
      ```
    - _Requirements: R1.1, R1.2, R1.3, R3.1_

  - [ ] 2.2 Registrar los valores de la 3ra ejecución como baseline de referencia
    - Anotar los siguientes campos de la salida de la 3ra ejecución (warm cache):
      - Nodo de acceso a la tabla (debe ser `Seq Scan on producto`)
      - Presencia del nodo `Sort`
      - `Planning Time` (ms)
      - `Execution Time` (ms) → **este valor es el baseline**
      - Filas estimadas vs. filas reales
      - `Buffers: shared hit` y bloques de heap leídos
    - _Requirements: R1.3, R3.2_

- [ ] 3. Verificar selectividad real de los predicados
  - [ ] 3.1 Ejecutar la consulta de conteo para estimar selectividad
    - Ejecutar en `psql`:
      ```sql
      SELECT COUNT(*) FROM producto
      WHERE precio_lista BETWEEN 1000 AND 2500
        AND stock > 50;
      ```
    - Interpretar el resultado:
      - Si `COUNT` < ~7.500 filas (< 15% de 50.000): el índice debería ser preferido por el Optimizador.
      - Si `COUNT` > ~7.500 filas (> 15% de 50.000): el Optimizador puede legítimamente preferir Seq_Scan; documentar el hallazgo.
    - _Requirements: R2.5, R4.4_

- [ ] 4. Crear el archivo `optimization_experiment.sql`
  - [ ] 4.1 Crear el archivo con los 4 bloques del experimento
    - Crear el archivo `optimization_experiment.sql` en la raíz del proyecto con el siguiente contenido completo:

      ```sql
      -- ============================================================
      -- optimization_experiment.sql
      -- Experimento de optimización: índice B-Tree compuesto sobre
      -- producto (precio_lista DESC, stock)
      -- Base de datos: foodstore_dev
      -- Ejecutar con: psql -U postgres -d foodstore_dev -f optimization_experiment.sql
      -- ============================================================


      -- ============================================================
      -- BLOQUE A — Verificación de precondiciones del planificador
      -- Requisitos: R3.5
      -- ============================================================

      SHOW enable_indexscan;
      -- Resultado esperado: on

      SHOW enable_seqscan;
      -- Resultado esperado: on


      -- ============================================================
      -- BLOQUE B — Medición de baseline (sin índice, 3 ejecuciones)
      -- Ejecutar 3 veces consecutivas; registrar la 3ra como baseline
      -- Requisitos: R1.1, R1.2, R1.3, R3.1, R3.2
      -- ============================================================

      -- Ejecución 1 de 3
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_producto, nombre, precio_lista, stock
      FROM producto
      WHERE precio_lista BETWEEN 1000 AND 2500
        AND stock > 50
      ORDER BY precio_lista DESC;

      -- Ejecución 2 de 3
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_producto, nombre, precio_lista, stock
      FROM producto
      WHERE precio_lista BETWEEN 1000 AND 2500
        AND stock > 50
      ORDER BY precio_lista DESC;

      -- Ejecución 3 de 3 — BASELINE DE REFERENCIA (warm cache)
      EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
      SELECT id_producto, nombre, precio_lista, stock
      FROM producto
      WHERE precio_lista BETWEEN 1000 AND 2500
        AND stock > 50
      ORDER BY precio_lista DESC;


      -- ============================================================
      -- BLOQUE C — Experimento transaccional (con índice + ROLLBACK)
      -- El ROLLBACK garantiza que no queden efectos permanentes en la BD
      -- Requisitos: R2.1, R2.2, R2.3, R2.4, R2.7, R3.3, R3.4, R3.6
      -- ============================================================

      BEGIN;

          -- Crear el índice B-Tree compuesto propuesto
          CREATE INDEX idx_producto_precio_stock
          ON producto (precio_lista DESC, stock);

          -- Actualizar estadísticas OBLIGATORIO antes de medir
          ANALYZE producto;

          -- Medición cold cache (1ra ejecución post-índice)
          EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
          SELECT id_producto, nombre, precio_lista, stock
          FROM producto
          WHERE precio_lista BETWEEN 1000 AND 2500
            AND stock > 50
          ORDER BY precio_lista DESC;

          -- Medición warm cache (2da ejecución post-índice) — medición de comparación
          EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
          SELECT id_producto, nombre, precio_lista, stock
          FROM producto
          WHERE precio_lista BETWEEN 1000 AND 2500
            AND stock > 50
          ORDER BY precio_lista DESC;

      ROLLBACK;
      -- El índice queda eliminado; no hay efectos permanentes en la BD


      -- ============================================================
      -- BLOQUE D — Promoción a producción (SOLO si el experimento es exitoso)
      -- IMPORTANTE: Ejecutar FUERA de bloque transaccional
      -- CONCURRENTLY evita bloqueos de escritura durante la construcción
      -- Requisitos: R4.7
      -- ============================================================

      -- Descomentar SOLO si se decide promover el índice:
      -- CREATE INDEX CONCURRENTLY idx_producto_precio_stock
      -- ON producto (precio_lista DESC, stock);
      ```
    - _Requirements: R2.1, R2.7, R3.1, R3.3, R3.4, R3.6, R4.7_

- [ ] 5. Ejecutar el experimento transaccional
  - [ ] 5.1 Ejecutar el Bloque C del script y registrar resultados cold cache
    - Abrir `psql` y ejecutar el bloque transaccional del Bloque C:
      ```sql
      BEGIN;
          CREATE INDEX idx_producto_precio_stock
          ON producto (precio_lista DESC, stock);
          ANALYZE producto;
          -- 1ra ejecución (cold cache):
          EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
          SELECT id_producto, nombre, precio_lista, stock
          FROM producto
          WHERE precio_lista BETWEEN 1000 AND 2500
            AND stock > 50
          ORDER BY precio_lista DESC;
      ```
    - Registrar de la 1ra ejecución (cold cache): nodo de acceso, presencia de Sort, Execution Time, Buffers shared hit.
    - _Requirements: R2.2, R2.3, R2.4, R3.4, R4.1, R4.2_

  - [ ] 5.2 Ejecutar la 2da medición (warm cache) y cerrar con ROLLBACK
    - Continuar en la misma sesión y transacción:
      ```sql
          -- 2da ejecución (warm cache):
          EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
          SELECT id_producto, nombre, precio_lista, stock
          FROM producto
          WHERE precio_lista BETWEEN 1000 AND 2500
            AND stock > 50
          ORDER BY precio_lista DESC;
      ROLLBACK;
      ```
    - Registrar de la 2da ejecución (warm cache): nodo de acceso, presencia de Sort, Execution Time, Buffers shared hit, heap blocks leídos.
    - Confirmar que después del ROLLBACK el índice ya no existe con `\d producto`.
    - _Requirements: R2.2, R2.3, R3.4, R3.6, R4.1, R4.2, R4.3, R4.5_

- [ ] 6. Comparar métricas y evaluar criterios de éxito
  - [ ] 6.1 Completar la tabla de métricas comparativas
    - Completar la siguiente tabla con los valores registrados en los pasos 2.2, 5.1 y 5.2:

      | Métrica | Baseline (3ra ejec.) | Post-índice cold (1ra) | Post-índice warm (2da) |
      |---|---|---|---|
      | Nodo de acceso | `Seq Scan` | ? | ? |
      | Nodo Sort presente | Sí | ? | ? |
      | Planning Time (ms) | — | — | — |
      | Execution Time (ms) | X | ? | ? |
      | Filas estimadas | — | — | — |
      | Filas reales | — | — | — |
      | Shared Hit — índice | 0 | ? | ? |
      | Heap blocks leídos | N | ? | ? |

    - _Requirements: R3.2, R4_

  - [ ] 6.2 Evaluar los criterios de éxito del experimento
    - Verificar cada criterio usando los valores de la tabla anterior:

      | Criterio | Verificación | ¿Cumplido? |
      |---|---|---|
      | R4.1 — Reemplazo de Seq_Scan | Plan post-índice usa `Index Scan` o `Bitmap Index Scan` | ? |
      | R4.2 — Eliminación del nodo Sort | Plan post-índice no contiene nodo `Sort` | ? |
      | R4.3 — Reducción ≥ 20% en Execution Time | `(baseline_ms - warm_ms) / baseline_ms >= 0.20` | ? |
      | R4.5 — Shared Hit índice > 0 | `Buffers: shared hit` incluye páginas del índice | ? |
      | R4.5 — Heap blocks < baseline | Bloques de heap leídos post-índice < baseline | ? |

    - Fórmula: `reducción (%) = ((ET_baseline - ET_warm) / ET_baseline) × 100`
    - Si todos se cumplen → experimento exitoso (continuar con tarea 8 si se desea promover).
    - Si el Optimizador mantiene Seq_Scan → documentar hallazgo (ver R4.4) y evaluar tarea 7.
    - _Requirements: R4.1, R4.2, R4.3, R4.4, R4.5, R4.6_

- [ ] 7. Checkpoint — Verificar resultados y consultar al usuario
  - Revisar que los pasos 1 al 6 estén completos y que la tabla de métricas esté registrada.
  - Confirmar al usuario si los criterios de éxito se cumplieron.
  - Si surgió el caso de baja selectividad (R4.4), preguntar si se desea evaluar la variante parcial (tarea 8).
  - Si el experimento fue exitoso, preguntar si se desea promover el índice a producción (tarea 9).

- [ ]* 8. [OPCIONAL] Evaluar la variante de índice parcial
  - [ ]* 8.1 Ejecutar el experimento transaccional con el índice parcial
    - Ejecutar en `psql` (dentro de BEGIN/ROLLBACK):
      ```sql
      BEGIN;

          CREATE INDEX idx_producto_precio_stock_activo
          ON producto (precio_lista DESC, stock)
          WHERE activo = TRUE;

          ANALYZE producto;

          EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
          SELECT id_producto, nombre, precio_lista, stock
          FROM producto
          WHERE precio_lista BETWEEN 1000 AND 2500
            AND stock > 50
            AND activo = TRUE          -- predicado obligatorio para usar el índice parcial
          ORDER BY precio_lista DESC;

      ROLLBACK;
      ```
    - Registrar: nodo de acceso, presencia de Sort, Execution Time, Buffers shared hit.
    - Comparar con el baseline de la tarea 2.2 usando la misma tabla de métricas.
    - _Requirements: R2.6_

- [ ]* 9. [OPCIONAL] Promover el índice a producción con CREATE INDEX CONCURRENTLY
  - [ ]* 9.1 Ejecutar el Bloque D del script fuera de cualquier bloque transaccional
    - Ejecutar **solo** si el experimento fue exitoso (todos los criterios de R4 cumplidos):
      ```sql
      -- FUERA de BEGIN/COMMIT — CONCURRENTLY no puede ejecutarse dentro de una transacción
      CREATE INDEX CONCURRENTLY idx_producto_precio_stock
      ON producto (precio_lista DESC, stock);
      ```
    - Verificar que el índice se creó correctamente:
      ```sql
      \d producto
      ```
    - La sección "Indexes" debe mostrar `idx_producto_precio_stock`.
    - _Requirements: R4.7_

---

## Notes

- Las tareas marcadas con `*` son opcionales y pueden omitirse si el objetivo es solo el experimento académico del TP2.
- El orden de las tareas es secuencial y no puede alterarse: cada tarea depende del estado dejado por la anterior.
- El Bloque C del script (tarea 5) siempre termina con `ROLLBACK`; esto es intencional y garantiza un estado limpio de la base de datos de desarrollo `foodstore_dev`.
- `CREATE INDEX CONCURRENTLY` (tarea 9) no puede ejecutarse dentro de un bloque `BEGIN`/`COMMIT`; si se intenta, PostgreSQL emite un error. Solo ejecutarlo fuera de transacción.
- Si el Optimizador elige Seq_Scan después de crear el índice, esto no es un error del índice; es un comportamiento correcto del planificador cuando la selectividad es baja (R4.4). Documentar el hallazgo.
- Toda la evidencia del experimento (salidas de EXPLAIN ANALYZE) debe guardarse para el informe final del TP2, tal como establece R4.6.

---

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["2.1"] },
    { "id": 2, "tasks": ["2.2", "3.1"] },
    { "id": 3, "tasks": ["4.1"] },
    { "id": 4, "tasks": ["5.1"] },
    { "id": 5, "tasks": ["5.2"] },
    { "id": 6, "tasks": ["6.1"] },
    { "id": 7, "tasks": ["6.2"] },
    { "id": 8, "tasks": ["8.1", "9.1"] }
  ]
}
```
