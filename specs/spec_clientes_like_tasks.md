# Plan de Implementación: Optimización LIKE Prefijado — `cliente.nombre`

## Overview

Este plan implementa el experimento de optimización de índice sobre la tabla `cliente` (~20.000 registros) de `foodstore_dev`. El flujo opera en una única sesión `psql` y sigue estrictamente el protocolo de seguridad del proyecto: **toda instrucción DDL debe ejecutarse dentro de un bloque `BEGIN; … ROLLBACK;`** durante la fase experimental.

El experimento cubre:
1. Diagnóstico del plan actual (Seq_Scan + Sort).
2. Verificación del collation para determinar la clase de operador necesaria.
3. Medición de baseline (3 ejecuciones, registrar 3ra).
4. Creación y ejecución del script `cliente_like_experiment.sql`.
5. Bloque transaccional con Variante C (cubriente, `text_pattern_ops`).
6. Comparación de métricas y evaluación de criterios de éxito R4.1–R4.6.
7. Pasos opcionales: Variante B (collation C), Variante A (sin INCLUDE).
8. Paso condicional: `CREATE INDEX CONCURRENTLY` para producción.

---

## Tasks

- [ ] 1. Verificar estado inicial del catálogo (`pg_indexes`)
  - Ejecutar en `psql -U postgres -d foodstore_dev`:
    ```sql
    SELECT indexname, indexdef
    FROM pg_indexes
    WHERE tablename = 'cliente';
    ```
  - Confirmar que **ninguna entrada** muestra `nombre` en `indexdef`.
  - Si existe un índice previo sobre `nombre`, detener el experimento y ejecutar `DROP INDEX <nombre_indice>` antes de continuar.
  - _Requirements: R1.6, R3.6_

- [ ] 2. Verificar parámetros del planificador
  - En la misma sesión abierta en el paso 1:
    ```sql
    SHOW enable_indexscan;
    SHOW enable_seqscan;
    ```
  - Ambos deben retornar `on`. Si alguno es `off`:
    ```sql
    SET enable_seqscan   = on;
    SET enable_indexscan = on;
    ```
  - _Requirements: R1.5, R3.5_

- [ ] 3. Verificar collation de la base de datos
  - Ejecutar:
    ```sql
    SELECT datname, datcollate, datctype
    FROM pg_database
    WHERE datname = current_database();
    ```
  - **Interpretar el resultado:**
    - Si `datcollate` es `C` o `POSIX` → se puede usar índice B-Tree estándar (Variante B) y el Sort desaparece.
    - Si `datcollate` es cualquier otro valor (p. ej. `es_AR.UTF-8`, `en_US.UTF-8`) → **es obligatorio** usar `text_pattern_ops` (Variante C) para que el índice funcione con `LIKE`.
  - Registrar el valor de `datcollate` — define qué variante usar en los pasos siguientes.
  - _Requirements: R2.7, R3.4_

- [ ] 4. Medir baseline sin índice (3 ejecuciones consecutivas)
  - Ejecutar el siguiente bloque **tres veces seguidas** sin cerrar la sesión ni ejecutar consultas intermedias sobre `cliente`:
    ```sql
    EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
    SELECT id_cliente, nombre, email, telefono
    FROM cliente
    WHERE nombre LIKE 'Cliente de Prueba 15%'
    ORDER BY nombre;
    ```
  - Registrar **únicamente los valores de la tercera ejecución** (warm cache):
    - Nodo de acceso (debe ser `Seq Scan`)
    - Presencia del nodo `Sort`
    - `Planning Time` (ms, dos decimales)
    - `Execution Time` (ms, dos decimales) → **valor de referencia baseline**
    - `shared hit` y `shared read`
    - Heap blocks leídos
  - Confirmar que `Execution Time > 0.50 ms` en las tres ejecuciones (R1.3) y que `rows` estimado está entre 18.000 y 22.000 (R1.4).
  - _Requirements: R1.1, R1.2, R1.3, R1.4, R3.1, R3.2_

- [ ] 5. Crear el archivo `cliente_like_experiment.sql`
  - Crear el archivo `cliente_like_experiment.sql` en la raíz del repositorio con el siguiente contenido:

    ```sql
    -- ============================================================
    -- cliente_like_experiment.sql
    -- Experimento de optimización: índice sobre cliente.nombre
    -- para búsqueda LIKE prefijada y ORDER BY nombre
    -- Base de datos: foodstore_dev
    -- Ejecutar en orden dentro de una única sesión psql
    -- ============================================================

    -- BLOQUE 0: Estado inicial del catálogo
    SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'cliente';

    -- BLOQUE A: Verificar parámetros del planificador
    SHOW enable_indexscan;
    SHOW enable_seqscan;

    -- BLOQUE B: Verificar collation
    SELECT datname, datcollate, datctype FROM pg_database WHERE datname = current_database();

    -- BLOQUE C: Baseline sin índice (ejecutar 3 veces; registrar 3ra)
    EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
    SELECT id_cliente, nombre, email, telefono
    FROM cliente
    WHERE nombre LIKE 'Cliente de Prueba 15%'
    ORDER BY nombre;

    -- BLOQUE D: Experimento transaccional — Variante C (cubriente, text_pattern_ops)
    BEGIN;

        CREATE INDEX idx_cliente_nombre_cubriente
        ON cliente (nombre text_pattern_ops)
        INCLUDE (email, telefono);

        ANALYZE cliente;

        -- Cold cache (1ra ejecución post-índice):
        EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
        SELECT id_cliente, nombre, email, telefono
        FROM cliente
        WHERE nombre LIKE 'Cliente de Prueba 15%'
        ORDER BY nombre;

        -- Warm cache (2da ejecución post-índice):
        EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
        SELECT id_cliente, nombre, email, telefono
        FROM cliente
        WHERE nombre LIKE 'Cliente de Prueba 15%'
        ORDER BY nombre;

    ROLLBACK;

    -- BLOQUE E: Verificar eliminación del índice post-ROLLBACK
    SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'cliente';

    -- BLOQUE F: Creación definitiva en producción (CONDICIONAL — solo si R4.1-R4.6 se cumplen)
    -- IMPORTANTE: ejecutar FUERA de bloque BEGIN/COMMIT
    -- CREATE INDEX CONCURRENTLY idx_cliente_nombre_cubriente
    -- ON cliente (nombre text_pattern_ops)
    -- INCLUDE (email, telefono);
    ```

  - _Requirements: R2.1, R2.3, R2.8, R3.3_

- [ ] 6. Ejecutar el bloque transaccional (Bloque D): BEGIN → CREATE INDEX → ANALYZE → EXPLAIN ×2 → ROLLBACK
  - Ejecutar el Bloque D del script en la sesión activa de `psql`:
    ```sql
    BEGIN;
        CREATE INDEX idx_cliente_nombre_cubriente
        ON cliente (nombre text_pattern_ops)
        INCLUDE (email, telefono);
        ANALYZE cliente;
        -- Cold cache:
        EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
        SELECT id_cliente, nombre, email, telefono
        FROM cliente WHERE nombre LIKE 'Cliente de Prueba 15%' ORDER BY nombre;
        -- Warm cache:
        EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
        SELECT id_cliente, nombre, email, telefono
        FROM cliente WHERE nombre LIKE 'Cliente de Prueba 15%' ORDER BY nombre;
    ROLLBACK;
    ```
  - Registrar para cada ejecución:
    - Nodo de acceso (esperado: `Index Scan` o `Index Only Scan`)
    - Presencia o ausencia del nodo `Sort`
    - `Execution Time` (ms)
    - `shared hit` del índice y heap blocks leídos
    - `Heap Fetches` (esperado: 0 si VACUUM fue ejecutado)
  - _Requirements: R2.4, R2.8, R3.3, R3.4, R3.5_

- [ ] 7. Verificar `pg_indexes` post-ROLLBACK (Bloque E)
  - Ejecutar inmediatamente después del ROLLBACK:
    ```sql
    SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'cliente';
    ```
  - Confirmar que `idx_cliente_nombre_cubriente` **no aparece** en el resultado.
  - _Requirements: R3.6_

- [ ] 8. Comparar métricas y evaluar criterios de éxito R4.1–R4.6
  - Completar la tabla comparativa con los valores de los pasos 4 y 6:

    | Métrica | Baseline (3ra ejec.) | Post-índice cold (1ra) | Post-índice warm (2da) |
    |---------|---------------------|-----------------------|-----------------------|
    | Nodo de acceso | Seq_Scan | ? | ? |
    | Sort presente | Sí | ? | ? |
    | Execution Time (ms) | X ms | ? ms | ? ms |
    | Shared Hit (índice) | 0 | ? | ? |
    | Heap blocks leídos | N | ? | ? |
    | Heap Fetches | N/A | ? | ? |

  - Verificar cada criterio:

    | Criterio | Descripción | ¿Cumplido? |
    |----------|-------------|-----------|
    | R4.1 | Seq_Scan reemplazado por Index_Scan / Index_Only_Scan | ? |
    | R4.2 | Nodo Sort ausente del plan | ? |
    | R4.3 | Reducción Execution Time ≥ 20% (warm vs. baseline 3ra) | ? |
    | R4.4 | Shared hit del índice > 0 Y heap blocks < baseline | ? |
    | R4.5 | Si Seq_Scan persiste: verificar collation y text_pattern_ops | N/A/? |
    | R4.6 | Evidencia completa de EXPLAIN ANALYZE guardada para TP2 | ? |

  - **Fórmula R4.3:** `reducción (%) = ((baseline_ms - warm_ms) / baseline_ms) × 100`
  - Si R4.2 no se cumple (Sort persiste) pero R4.1 sí → es comportamiento esperado con `text_pattern_ops` en collation != C. Documentar (ver Caso 4 del design.md).
  - _Requirements: R4.1, R4.2, R4.3, R4.4, R4.5, R4.6_

- [ ] 9. Checkpoint — Confirmar resultados
  - Verificar que la tabla comparativa del paso 8 está completa.
  - Confirmar que `pg_indexes` no muestra el índice experimental.
  - Si el Sort persiste → revisar el collation registrado en el paso 3 y consultar si se desea probar la Variante B (tarea 10 opcional).

- [ ]* 10. [OPCIONAL] Evaluar Variante B — índice estándar ASC (solo si collation = C)
  - Solo ejecutar si el paso 3 reportó `datcollate = C` o `POSIX`.
  - Bloque transaccional:
    ```sql
    BEGIN;
        CREATE INDEX idx_cliente_nombre_asc ON cliente (nombre ASC);
        ANALYZE cliente;
        EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
        SELECT id_cliente, nombre, email, telefono
        FROM cliente WHERE nombre LIKE 'Cliente de Prueba 15%' ORDER BY nombre;
    ROLLBACK;
    ```
  - Verificar que el plan muestra Index_Scan **sin** nodo Sort (el índice estándar con collation C satisface ambos predicados).
  - _Requirements: R2.2_

- [ ]* 11. [OPCIONAL] Probar Variante C con VACUUM previo (Index_Only_Scan, Heap Fetches = 0)
  - Solo ejecutar si se desea verificar la eliminación total de Heap Fetches.
  - Ejecutar fuera de transacción:
    ```sql
    VACUUM cliente;
    ```
  - Luego ejecutar el mismo bloque D del paso 6 y verificar `Heap Fetches: 0` en la salida de EXPLAIN_ANALYZE.
  - Si `Heap Fetches > 0`, documentar que el visibility map no estaba completamente poblado.
  - _Requirements: R2.6_

- [ ]* 12. [CONDICIONAL] Crear índice definitivo con `CREATE INDEX CONCURRENTLY` para producción
  - Solo ejecutar si todos los criterios R4.1–R4.6 se cumplen en el paso 8.
  - **FUERA de cualquier bloque `BEGIN … COMMIT`:**
    ```sql
    CREATE INDEX CONCURRENTLY idx_cliente_nombre_cubriente
    ON cliente (nombre text_pattern_ops)
    INCLUDE (email, telefono);
    ```
  - Verificar la creación:
    ```sql
    SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'cliente';
    ```
  - _Requirements: R4.7_

---

## Notes

- **Protocolo de seguridad obligatorio**: toda instrucción `CREATE INDEX` durante la fase experimental debe estar dentro de `BEGIN; … ROLLBACK;`. Nunca ejecutar DDL directamente sin este contenedor, excepto la tarea 12.
- **Sesión única**: las tareas 1 a 9 deben ejecutarse en la misma sesión `psql` sin cerrar la conexión, para que los datos de `shared_buffers` sean consistentes entre baseline y mediciones post-índice.
- **text_pattern_ops es obligatorio con collation != C**: si la base de datos tiene cualquier collation lingüístico (lo más frecuente), un índice B-Tree estándar NO es usado por el Optimizador para predicados `LIKE`. Verificar siempre en la tarea 3.
- **Sort puede persistir con text_pattern_ops**: es el comportamiento esperado y correcto cuando el collation != C (ver Caso 4 del design.md). No es un error del índice.
- **ANALYZE obligatorio**: ejecutar `ANALYZE cliente` después de `CREATE INDEX` dentro del bloque transaccional. Sin esto, el Optimizador usa estadísticas desactualizadas.
- **VACUUM para Index_Only_Scan**: la Variante C solo produce `Heap Fetches: 0` si el visibility map está actualizado. Si no se ejecutó VACUUM, el plan puede degradar a Index_Scan. Esto es correcto y esperado (tarea 11 opcional).
- **CREATE INDEX CONCURRENTLY fuera de transacción**: este comando no puede ejecutarse dentro de `BEGIN … COMMIT`. Solo aplica a la tarea 12.
- Las tareas marcadas con `*` son **opcionales**. El experimento mínimo viable comprende las tareas 1–9.

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
