# Declaración de Uso de IA (DUIA) - Trabajo Práctico 2

**Asignatura:** Bases de Datos II  
**Estudiante:** Guzmán, Agustina Micaela  
**Proyecto / Esquema:** FoodStore  
**Motor de BD:** PostgreSQL  

---

## 1. Declaración General
En este Trabajo Práctico se utilizó la Inteligencia Artificial (mediante el agente OpenCode) como herramienta de asistencia pedagógica e interactiva para la generación de reglas de integridad (Triggers) y la formulación de hipótesis teóricas sobre fenómenos de concurrencia en transacciones SQL.

Todas las propuestas, scripts y explicaciones generadas por la IA fueron **verificadas y validadas directamente en el motor PostgreSQL** mediante casos de prueba e interacción multisesión en DBeaver.

---

## 2. Parte 1: Integridad Versionada (Triggers y Restricciones)

- **Uso de IA:** Se solicitó a la IA la creación de disparadores (Triggers) en PL/pgSQL para garantizar reglas de negocio clave:
  1. Impedir la carga de pedidos con fechas/horas futuras (`fecha_hora <= NOW()`).
  2. Garantizar que solo se puedan agregar productos activos (`activo = TRUE`) en los detalles de pedido.
- **Validación en el Motor:** Se diseñaron e intentaron ejecutar inserciones/actualizaciones inválidas para confirmar que el motor rechazara la transacción.
- **Ajustes Realizados:** Se corrigió el uso de funciones mutables en restricciones `CHECK` estándar reemplazándolas por triggers `BEFORE INSERT OR UPDATE`, respetando las limitaciones técnicas de PostgreSQL.

---

## 3. Parte 2: Laboratorio de Concurrencia

- **Uso de IA:** Se solicitó a la IA explicaciones teóricas y soluciones propuestas (niveles de aislamiento o bloqueos) para tres escenarios reproducidos en DBeaver:
  1. **Lectura No Repetible (*Non-Repeatable Read*):** Explicación del comportamiento de *snapshots* por consulta en `READ COMMITTED`.
  2. **Espera por Bloqueo (*Lock Wait / Row Locking*):** Explicación del funcionamiento de la cláusula `SELECT ... FOR UPDATE` y bloqueos exclusivos a nivel de fila.
  3. **Lectura Fantasma (*Phantom Read*):** Explicación del impacto de inserciones concurrentes sobre consultas agregadas (`COUNT(*)`) en `READ COMMITTED`.
- **Validación en el Motor:** Se ejecutaron las transacciones paso a paso en dos sesiones concurrentes en DBeaver. Posteriormente se elevó el aislamiento a `REPEATABLE READ` o se aplicó el bloqueo explícito.
- **Evaluación de Aciertos:** El motor PostgreSQL confirmó al 100% las hipótesis de la IA. El detalle técnico paso a paso de las dos sesiones se encuentra documentado en el archivo `informe_concurrencia.md`.

---

## 4. Conclusión sobre la Asistencia de la IA
El uso de la IA permitió acelerar el diseño de triggers y comprender los fundamentos de la teoría de transacciones y niveles de aislamiento (ACID). El proceso de verificación empírica en DBeaver garantizó que ningún script o teoría fuera aceptado de forma pasiva sin su correspondiente validación en el motor real.