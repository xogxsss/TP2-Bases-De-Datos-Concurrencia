# Implementation Plan: fnbc-control-lote

## Overview

Este plan implementa el análisis de violación FNBC y la descomposición sin pérdida de la relación `control_lote_almacen` en la base de datos `foodstore_dev`. El flujo es estrictamente secuencial y produce un único script DDL autónomo e idempotente (`tp_fnbc_control_lote.sql`):

1. **Dominios:** crear los tipos de dominio reutilizables `codigo_producto_dom` y `dni_arg_dom`.
2. **Tablas maestras:** crear y poblar las entidades de catálogo (`deposito`, `lote`, `responsable_control`).
3. **Esquema original:** crear `control_lote_almacen` con la instancia de prueba que evidencia la violación FNBC.
4. **Descomposición:** crear las tablas R1 (`responsable_deposito`) y R2 (`control_lote_responsable`) en FNBC.
5. **Vista de compatibilidad:** crear `vw_control_lote_almacen_compatibilidad` que reconstituye la proyección original.
6. **Migración:** poblar R1 y R2 a partir de `control_lote_almacen`.
7. **Verificación lossless-join:** ejecutar la prueba `EXCEPT` bidireccional y confirmar 0 filas en ambas direcciones.

Todo el script está encapsulado en `BEGIN; … COMMIT;` conforme al protocolo de seguridad del proyecto.

---

## Tasks

- [ ] 1. Crear el archivo `tp_fnbc_control_lote.sql` con encabezado y estructura de pasos
  - Crear el archivo en la raíz del repositorio con el encabezado del script, incluyendo: nombre del archivo, motor, base de datos, autora, objetivo, análisis de DFs, descripción de la descomposición y protocolo de seguridad.
  - Abrir el bloque transaccional con `BEGIN;`.
  - Definir los marcadores de sección `-- PASO 0`, `-- PASO 1`, etc. como esqueleto del archivo.
  - _Requirements: R6.1, R6.5_

- [ ] 2. Implementar el Paso 0.A — Dominios reutilizables
  - Agregar en el Paso 0.A los dos dominios PostgreSQL con `DROP DOMAIN IF EXISTS … CASCADE` previo para idempotencia:
    ```sql
    DROP DOMAIN IF EXISTS codigo_producto_dom CASCADE;
    CREATE DOMAIN codigo_producto_dom AS VARCHAR(50)
        CONSTRAINT ck_codigo_producto_formato
            CHECK (VALUE ~ '^[A-Z0-9][A-Z0-9\-]{1,48}[A-Z0-9]$');

    DROP DOMAIN IF EXISTS dni_arg_dom CASCADE;
    CREATE DOMAIN dni_arg_dom AS VARCHAR(20)
        CONSTRAINT ck_dni_arg_formato
            CHECK (VALUE ~ '^\d{7,8}$');
    ```
  - Verificar que los dominios se crean correctamente consultando `information_schema.domains`.
  - _Requirements: R6.2_

- [ ] 3. Implementar el Paso 0.B — Tablas maestras con restricciones de integridad
  - Crear las tres tablas maestras con `CREATE TABLE IF NOT EXISTS` y todas las restricciones de dominio e integridad:
    - `deposito`: con `CHECK (capacidad > 0)`.
    - `lote`: usando el dominio `codigo_producto_dom` y `CHECK (fecha_vencimiento >= CURRENT_DATE)`.
    - `responsable_control`: usando el dominio `dni_arg_dom` y `CHECK` de formato de email.
  - _Requirements: R6.2, R6.3_

- [ ] 4. Implementar el Paso 0.C — Inserción de datos maestros de prueba
  - Insertar los datos maestros con `ON CONFLICT (id) DO NOTHING`:
    - `deposito`: `(30, 'Depósito Central', 'Mendoza', 10000)`, `(31, 'Depósito Sur', 'San Martín', 5000)`.
    - `lote`: `(501, 'PROD-01', '2027-12-31')`, `(502, 'PROD-02', '2027-11-15')`, `(503, 'PROD-03', '2027-10-20')`.
    - `responsable_control`: `(801, '30111222', 'carlos@foodstore.com', 'Carlos Gómez')`, `(802, '32333444', 'ana@foodstore.com', 'Ana López')`.
  - Nota: las fechas de `lote` se fijan en 2027 para superar el `CHECK (fecha_vencimiento >= CURRENT_DATE)` en ejecuciones durante 2026.
  - _Requirements: R6.2_

- [ ] 5. Implementar el Paso 1 — Esquema original defectuoso y datos de prueba
  - Crear `control_lote_almacen` con `CREATE TABLE IF NOT EXISTS`, PK compuesta `(lote_id, deposito_id)` y las tres FKs hacia las tablas maestras.
  - Incluir comentario de bloque que documente:
    - La instancia de ejemplo con las tres tuplas y la redundancia visible.
    - La DF problemática: `responsable_control_id → deposito_id`.
    - La anomalía de actualización que genera.
  - Insertar las tuplas de prueba `(501,30,801)`, `(502,30,801)`, `(503,31,802)` con `ON CONFLICT DO NOTHING`.
  - _Requirements: R1.3, R2.3, R6.2_

- [ ] 6. Implementar el Paso 2 — Tablas descompuestas en FNBC
  - Crear R1 (`responsable_deposito`) con `CREATE TABLE IF NOT EXISTS`:
    - `responsable_control_id BIGINT PRIMARY KEY REFERENCES responsable_control(id)`
    - `deposito_id BIGINT NOT NULL REFERENCES deposito(id)`
    - Comentario: "aisla DF2: R → D; la PK es el determinante, satisface FNBC".
  - Crear R2 (`control_lote_responsable`) con `CREATE TABLE IF NOT EXISTS`:
    - `lote_id BIGINT NOT NULL REFERENCES lote(id)`
    - `responsable_control_id BIGINT NOT NULL REFERENCES responsable_deposito(responsable_control_id)`
    - `PRIMARY KEY (lote_id, responsable_control_id)`
    - Comentario: "FK a R1 (no a responsable_control directo) para garantizar la reunión sin pérdida".
  - _Requirements: R3.1, R3.2, R3.3, R3.5_

- [ ] 7. Implementar el Paso 3 — Vista de compatibilidad
  - Crear la vista con `CREATE OR REPLACE VIEW`:
    ```sql
    CREATE OR REPLACE VIEW vw_control_lote_almacen_compatibilidad AS
    SELECT
        clr.lote_id,
        rd.deposito_id,
        clr.responsable_control_id
    FROM control_lote_responsable  clr
    JOIN responsable_deposito       rd
        ON clr.responsable_control_id = rd.responsable_control_id;
    ```
  - Incluir comentario que explique el propósito dual: compatibilidad hacia atrás y oráculo para la prueba lossless-join.
  - _Requirements: R4.1, R4.2, R4.3_

- [ ] 8. Implementar el Paso 4 — Migración de datos a las tablas FNBC
  - Migrar a R1 con `INSERT INTO … SELECT DISTINCT … ON CONFLICT DO NOTHING`:
    ```sql
    INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
    SELECT DISTINCT responsable_control_id, deposito_id
    FROM control_lote_almacen
    ON CONFLICT DO NOTHING;
    ```
    Comentario: "DISTINCT colapsa las dos filas de responsable=801 en una sola, que es la corrección que FNBC exige".
  - Migrar a R2 con `INSERT INTO … SELECT … ON CONFLICT DO NOTHING`:
    ```sql
    INSERT INTO control_lote_responsable (lote_id, responsable_control_id)
    SELECT lote_id, responsable_control_id
    FROM control_lote_almacen
    ON CONFLICT DO NOTHING;
    ```
  - _Requirements: R3.4, R6.2_

- [ ] 9. Implementar el Paso 5 — Prueba de reunión sin pérdida con EXCEPT
  - Agregar las dos consultas `EXCEPT` con etiquetas descriptivas como columna adicional:
    - **Dirección A:** `vw_control_lote_almacen_compatibilidad EXCEPT control_lote_almacen` — prueba ausencia de tuplas espurias. Resultado esperado: 0 filas.
    - **Dirección B:** `control_lote_almacen EXCEPT vw_control_lote_almacen_compatibilidad` — prueba que no hay pérdida de tuplas. Resultado esperado: 0 filas.
  - Incluir comentario que explique el significado de cada dirección y el criterio de éxito.
  - _Requirements: R5.1, R5.2, R5.3, R5.4_

- [ ] 10. Cerrar la transacción y verificar ejecución completa
  - Agregar `COMMIT;` al final del script.
  - Ejecutar el script completo en `foodstore_dev`:
    ```bash
    psql -U postgres -d foodstore_dev -f tp_fnbc_control_lote.sql
    ```
  - Verificar que:
    - El motor confirma `COMMIT` sin errores.
    - Las dos consultas `EXCEPT` del Paso 5 devuelven `(0 rows)` en ambas direcciones.
    - Las tablas `responsable_deposito` y `control_lote_responsable` contienen los datos migrados correctamente.
  - _Requirements: R5.4, R6.4_

---

## Notes

- **Idempotencia:** el script puede ejecutarse múltiples veces sobre `foodstore_dev` sin errores. `CREATE TABLE IF NOT EXISTS` y `ON CONFLICT … DO NOTHING` garantizan esta propiedad. Los dominios usan `DROP … IF EXISTS CASCADE` previo porque PostgreSQL no soporta `CREATE DOMAIN IF NOT EXISTS`.
- **Orden de creación:** respetar estrictamente el orden de los pasos. Las FKs de `control_lote_almacen` dependen de las tablas maestras (Paso 0), y las FKs de R2 dependen de R1 (Paso 2).
- **Fechas de prueba en 2027:** el `CHECK (fecha_vencimiento >= CURRENT_DATE)` en `lote` rechazaría las fechas originales del enunciado (`2026-10-20`, `2026-11-15`, `2026-12-31`) si el script se ejecuta después de esas fechas. Las fechas se ajustaron a 2027 para garantizar la validez durante el período académico.
- **FK de R2 hacia R1:** la referencia `REFERENCES responsable_deposito(responsable_control_id)` en lugar de `REFERENCES responsable_control(id)` es intencional y crítica. Sin esta referencia cruzada, la reunión natural podría producir tuplas espurias si un responsable está en `responsable_control` pero no en R1.
- **DISTINCT en la migración de R1:** al migrar de `control_lote_almacen` a `responsable_deposito`, el `SELECT DISTINCT` es obligatorio. Sin él, la inserción falla por violación de PK (el par `(801, 30)` aparece dos veces en el esquema original).
- **Protocolo de seguridad:** encapsular en `BEGIN; … COMMIT;`. Para modo prueba, reemplazar `COMMIT` por `ROLLBACK`.

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
    { "id": 8, "tasks": ["9"] },
    { "id": 9, "tasks": ["10"] }
  ]
}
```
