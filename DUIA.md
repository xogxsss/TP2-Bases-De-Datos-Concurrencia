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

## Declaración de Uso de IA - Parte 2 y 3

### 1. Herramienta utilizada
* **Modelo / Asistente:** Gemini / OpenCode.

### 2. Alcance del uso
* **Parte 2 (Laboratorio de Optimización):**
  - Generación y ajuste del script de carga masiva (`insertar_datos_masivos.sql`).
  - Asistencia en el diseño de los índices estratégicos (`idx_producto_precio_stock`, `idx_cliente_nombre_pattern`, `idx_pedido_fecha_hora`).
  - Formateo y consolidación de la tabla comparativa de resultados de `EXPLAIN ANALYZE`.
* **Parte 3 (Lectura Crítica):**
  - Generación del desglose nodo por nodo en lenguaje natural a partir del plan de ejecución real.
  - Auditoría y contraste técnico de las explicaciones para la detección de imprecisiones (confusión entre `cost` y milisegundos, estimación vs. filas reales, etc.).

### 3. Validación y Responsabilidad Humana
* Todas las sentencias SQL, `CREATE INDEX` y planes de ejecución fueron ejecutados, probados y validados manualmente en el entorno local (`foodstore_dev` en PostgreSQL via DBeaver/Terminal).
* Se verificó la precisión técnica de cada interpretación antes de volcarla al informe final.

### Declaración de Uso de IA - Parte 4 (Consultas bajo especificación precisa)

1. **Herramienta utilizada:** OpenCode (asistente de IA en VS Code) / Gemini.
2. **Uso realizado:** Generación del script `consultas_resumen_subconsultas.sql` a partir de especificaciones técnicas precisas (tablas, filtros de estado/fecha, funciones de agregación y subconsultas).
3. **Validación y Responsabilidad Humana:**
   - Se analizaron y probaron dos versiones estructuralmente distintas (ej. JOIN explícito vs. CTE) para cada requerimiento.
   - Se validó empíricamente la equivalencia estricta de resultados utilizando el operador `EXCEPT` directo en el motor de PostgreSQL, confirmando diferencias de cero filas.