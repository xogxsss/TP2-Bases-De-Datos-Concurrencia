# Requirements Document — FNBC: Control de Lote en Almacén

## Introduction

Esta especificación define los requisitos técnicos para la detección, análisis y corrección de una violación a la Forma Normal de Boyce-Codd (FNBC) en el contexto de la extensión mayorista de FoodStore. La tabla `control_lote_almacen` concentra tres atributos bajo una clave primaria compuesta `(lote_id, deposito_id)`, pero contiene una dependencia funcional adicional —`responsable_control_id → deposito_id`— cuyo determinante no es superclave. Esto produce anomalías de actualización y redundancia estructural que deben eliminarse mediante descomposición sin pérdida de información (lossless-join decomposition), conforme al Teorema de Heath.

El objetivo es modelar formalmente las dependencias funcionales, demostrar la violación de FNBC, descomponer el esquema en dos relaciones canónicas en FNBC, verificar la reunión sin pérdida mediante prueba de equivalencia de conjuntos con `EXCEPT`, y consolidar todo el proceso en un script DDL idempotente ejecutable en PostgreSQL 17.

---

## Glossary

- **FNBC (Forma Normal de Boyce-Codd):** Una relación está en FNBC si, para toda dependencia funcional no trivial X → Y, X es superclave de la relación. Es una forma más estricta que la 3FN.
- **Dependencia funcional (DF):** Restricción semántica X → Y que establece que el valor de X determina unívocamente el valor de Y en toda instancia válida de la relación.
- **Superclave:** Conjunto de atributos que determina unívocamente a todos los demás atributos de la relación. La clave primaria es la superclave minimal.
- **Descomposición lossless-join:** Partición de una relación R en R1 y R2 tal que R = R1 ⋈ R2 (la reunión natural reconstruye exactamente la instancia original, sin tuplas espurias ni pérdida de tuplas).
- **Teorema de Heath:** Si R(A, B, C) y se cumple la DF A → B, entonces R se puede descomponer sin pérdida en R1(A, B) y R2(A, C).
- **Tupla espuria:** Fila generada por la reunión natural que no existía en la relación original, síntoma de una descomposición con pérdida.
- **Anomalía de actualización:** Inconsistencia que surge cuando un hecho del mundo real (p. ej., el depósito de un responsable) está representado en múltiples filas y una actualización parcial deja la base en estado contradictorio.
- **Prueba EXCEPT:** Técnica de verificación SQL que compara dos conjuntos de tuplas en ambas direcciones usando el operador `EXCEPT`. Si ambas direcciones devuelven 0 filas, los conjuntos son equivalentes.
- **Vista de compatibilidad:** Vista SQL que reconstruye la proyección original a partir de las tablas descompuestas, permitiendo que el código existente continúe operando sin cambios inmediatos.
- **Idempotencia:** Propiedad de un script que puede ejecutarse múltiples veces sobre la misma base sin producir errores ni efectos duplicados.

---

## Requirements

### Requisito 1: Modelado formal de dependencias funcionales

**User Story:** Como estudiante de Bases de Datos II, quiero modelar formalmente las dependencias funcionales de `control_lote_almacen`, para poder identificar con precisión cuál de ellas viola FNBC y justificar la necesidad de descomposición.

#### Criterios de Aceptación

1. THE Sistema SHALL reconocer los siguientes atributos en la relación original:
   - **L** = `lote_id` (BIGINT, referencia a `lote`)
   - **D** = `deposito_id` (BIGINT, referencia a `deposito`)
   - **R** = `responsable_control_id` (BIGINT, referencia a `responsable_control`)

2. THE Sistema SHALL identificar las siguientes dependencias funcionales sobre la relación `control_lote_almacen(L, D, R)`:
   - **DF1:** {L, D} → R — la PK compuesta determina unívocamente al responsable asignado al control de ese lote en ese depósito. Esta DF es válida porque {L, D} es superclave.
   - **DF2:** R → D — un responsable de control siempre opera en el mismo depósito, independientemente del lote auditado. Esta DF es problemática porque R no es superclave.

3. IF la instancia de prueba contiene las tuplas `(501, 30, 801)`, `(502, 30, 801)` y `(503, 31, 802)`, THEN THE Sistema SHALL evidenciar DF2 observando que el responsable 801 aparece siempre asociado al depósito 30 en múltiples filas, lo que representa redundancia estructural derivada de la dependencia funcional R → D.

4. WHEN se evalúa DF2 contra la definición de FNBC, THE Sistema SHALL concluir que DF2 viola FNBC porque el determinante R (`responsable_control_id`) no es superclave de `control_lote_almacen`, ya que no determina L (`lote_id`).

---

### Requisito 2: Prueba formal de violación de FNBC

**User Story:** Como estudiante de Bases de Datos II, quiero demostrar formalmente que `control_lote_almacen` no está en FNBC, para fundamentar la decisión de descomposición con un argumento teórico riguroso.

#### Criterios de Aceptación

1. THE Sistema SHALL verificar la condición de FNBC para DF1: {L, D} → R. Dado que {L, D} es la clave primaria de la relación y, por tanto, superclave, DF1 satisface FNBC.

2. THE Sistema SHALL verificar la condición de FNBC para DF2: R → D. Dado que R (`responsable_control_id`) no determina L (`lote_id`), R no es superclave de `control_lote_almacen`. Por tanto, DF2 viola FNBC.

3. WHEN se confirma la violación de FNBC por DF2, THE Sistema SHALL identificar la anomalía de actualización concreta: si el responsable 801 cambia de depósito, deben actualizarse todas las filas donde aparece `responsable_control_id = 801`, lo que expone la redundancia estructural y el riesgo de inconsistencia.

4. IF se intenta insertar una tupla `(504, 31, 801)` en `control_lote_almacen`, THEN THE instancia resultante contendría `(responsable=801, deposito=30)` y `(responsable=801, deposito=31)` simultáneamente, evidenciando que el esquema original no puede representar el hecho "801 trabaja en 30" con consistencia garantizada a nivel estructural.

---

### Requisito 3: Descomposición en FNBC por aplicación del Teorema de Heath

**User Story:** Como estudiante de Bases de Datos II, quiero descomponer `control_lote_almacen` en dos relaciones que estén en FNBC, para eliminar la anomalía de actualización y garantizar que la reunión natural reconstruye la instancia original sin pérdida de información.

#### Criterios de Aceptación

1. THE Sistema SHALL aplicar el Teorema de Heath sobre la DF problemática R → D para descomponer `control_lote_almacen(L, D, R)` en:
   - **R1:** `responsable_deposito(R, D)` — aisla la DF R → D. PK: R.
   - **R2:** `control_lote_responsable(L, R)` — conserva el vínculo lote-responsable. PK compuesta: {L, R}.

2. THE Sistema SHALL verificar que R1 está en FNBC: la única DF no trivial en R1 es R → D, y R es la clave primaria (superclave minimal). Por tanto, R1 satisface FNBC.

3. THE Sistema SHALL verificar que R2 está en FNBC: la única DF no trivial en R2 es {L, R} → ∅ (no hay atributos no-clave adicionales). La PK {L, R} es superclave, por tanto R2 satisface FNBC.

4. WHEN se ejecuta la reunión natural R1 ⋈ R2 sobre el atributo compartido R (`responsable_control_id`), THE Sistema SHALL reconstruir exactamente las tuplas `(501, 30, 801)`, `(502, 30, 801)` y `(503, 31, 802)`, sin tuplas espurias ni omisiones, demostrando la propiedad lossless-join.

5. IF la FK de R2 referencia a R1 en lugar de referenciar directamente a `responsable_control`, THEN THE Motor SHALL garantizar que toda inserción en R2 requiere la existencia previa del par (R, D) en R1, preservando la integridad referencial que hace posible la reunión sin pérdida.

---

### Requisito 4: Vista de compatibilidad hacia atrás

**User Story:** Como estudiante de Bases de Datos II, quiero crear una vista que reconstituya la estructura original de `control_lote_almacen` a partir de las tablas descompuestas, para que el código existente pueda seguir operando sin cambios durante la transición.

#### Criterios de Aceptación

1. THE Sistema SHALL crear la vista `vw_control_lote_almacen_compatibilidad` que proyecte `(lote_id, deposito_id, responsable_control_id)` mediante `JOIN` entre R2 y R1 sobre `responsable_control_id`.

2. WHEN se consulta `vw_control_lote_almacen_compatibilidad`, THE Vista SHALL devolver exactamente las mismas filas que `control_lote_almacen`, en cualquier orden, verificable mediante la prueba `EXCEPT` bidireccional del Requisito 5.

3. IF se agrega una nueva fila en R1 y su correspondiente fila en R2, THEN THE Vista SHALL incluir automáticamente la fila correspondiente al consultar `vw_control_lote_almacen_compatibilidad`, sin necesidad de redefinirla.

---

### Requisito 5: Verificación de reunión sin pérdida mediante prueba EXCEPT

**User Story:** Como estudiante de Bases de Datos II, quiero verificar mediante una prueba SQL formal que la descomposición es lossless-join, para demostrar que ninguna información fue perdida ni inventada durante el proceso.

#### Criterios de Aceptación

1. THE Sistema SHALL ejecutar la prueba en dirección A: `vw_control_lote_almacen_compatibilidad EXCEPT control_lote_almacen`. El resultado esperado es 0 filas, lo que prueba que la vista no contiene tuplas espurias ausentes en la relación original.

2. THE Sistema SHALL ejecutar la prueba en dirección B: `control_lote_almacen EXCEPT vw_control_lote_almacen_compatibilidad`. El resultado esperado es 0 filas, lo que prueba que ninguna tupla de la relación original fue perdida por la descomposición.

3. IF cualquiera de las dos direcciones de la prueba `EXCEPT` devuelve al menos una fila, THEN THE Sistema SHALL considerar la descomposición como incorrecta y requerir revisión del JOIN en la vista o de la migración de datos.

4. WHEN ambas pruebas `EXCEPT` devuelven 0 filas, THE Sistema SHALL considerar la descomposición como válida y la propiedad lossless-join como demostrada experimentalmente sobre la instancia de prueba provista.

---

### Requisito 6: Script DDL autónomo e idempotente

**User Story:** Como estudiante de Bases de Datos II, quiero que todo el proceso esté consolidado en un único script DDL ejecutable, para poder reproducir el experimento completo en `foodstore_dev` sin dependencias externas ni intervención manual.

#### Criterios de Aceptación

1. THE Script SHALL estar encapsulado en un único bloque `BEGIN; … COMMIT;`, conforme al protocolo de seguridad del proyecto.

2. THE Script SHALL ser idempotente: ejecutarlo múltiples veces sobre la misma base no debe producir errores. Para ello, SHALL usar `CREATE TABLE IF NOT EXISTS` para toda sentencia DDL de creación de tablas y `ON CONFLICT … DO NOTHING` para toda sentencia DML de inserción de datos.

3. THE Script SHALL ser autónomo: no debe requerir la ejecución previa de ningún archivo externo (ni `schema.sql`, ni `data.sql`, ni ningún otro script del repositorio) para funcionar correctamente en una base vacía o en `foodstore_dev`.

4. WHEN el script se ejecuta en `foodstore_dev` con el comando `psql -U postgres -d foodstore_dev -f tp_fnbc_control_lote.sql`, THE Motor SHALL completar todas las sentencias sin errores y confirmar la transacción con `COMMIT`.

5. THE Script SHALL incluir encabezados de sección claramente delimitados (`-- PASO 0`, `-- PASO 1`, etc.) y comentarios técnicos por cada sentencia DDL/DML que expliquen la regla de negocio o la dependencia funcional que justifica esa decisión de diseño.
