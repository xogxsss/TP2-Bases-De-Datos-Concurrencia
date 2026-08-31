# Declaración de Uso de IA (DUIA) - Parte 2: Laboratorio de Concurrencia

**Asignatura:** Bases de Datos II  
**Integrantes:** Guzmán, Agustina Micaela 
**Proyecto / Esquema:** FoodStore  
**Motor de BD:** PostgreSQL  

---

## 1. Declaración General
En el marco de la Parte 2 del Trabajo Práctico 2, se utilizó IA como asistente conceptual para la generación de hipótesis explicativas sobre anomalías de concurrencia en entornos multisesión. Todas las hipótesis y soluciones propuestas por el modelo fueron contrastadas y verificadas de manera directa sobre el motor de base de datos PostgreSQL en dos sesiones concurrentes en DBeaver.

---

## 2. Experimentos de Concurrencia Realizados

| # | Escenario Probadized | Comportamiento en `READ COMMITTED` | Propuesta de la IA | Comportamiento Verificado en el Motor | ¿La IA acertó? |
| :-: | :--- | :--- | :--- | :--- | :-: |
| **1** | **Lectura No Repetible** (*Non-Repeatable Read*) | La Sesión 1 consultó el `precio_lista` de un producto. La Sesión 2 lo modificó e hizo `COMMIT`. La Sesión 1 volvió a consultar en la misma transacción y el valor cambió. | Cambiar el nivel de aislamiento a `REPEATABLE READ`. | Se ejecutó la prueba con `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ`. La Sesión 1 mantuvo la visión congelada del valor inicial durante toda la transacción a pesar de las modificaciones de la Sesión 2. | **SÍ** |
| **2** | **Espera por Bloqueo** (*Lock Wait / Row Locking*) | La Sesión 1 ejecutó un `SELECT ... FOR UPDATE` sobre la fila del producto `id_producto = 1`. | Explicación del mecanismo de bloqueo exclusivo de fila (*Row Exclusive Lock*). | La Sesión 2 intentó hacer `FOR UPDATE` sobre la misma fila y quedó suspendida en espera. Apenas la Sesión 1 ejecutó `COMMIT`, la Sesión 2 se destrabó automáticamente. | **SÍ** |
| **3** | **Lectura Fantasma** (*Phantom Read / Inserción Concurrente*) | La Sesión 1 ejecutó un `SELECT COUNT(*)` sobre productos activos. La Sesión 2 insertó un nuevo producto activo e hizo `COMMIT`. En la Sesión 1, el conteo aumentó en +1 dentro de la misma transacción. | Elevar el nivel de aislamiento a `REPEATABLE READ` para aplicar *Snapshot Isolation*. | En `REPEATABLE READ`, la consulta de la Sesión 1 ignoró las inserciones concurrentes de la Sesión 2, manteniendo el resultado del conteo constante hasta cerrar la transacción. | **SÍ** |

---

## 3. Conclusión sobre el Criterio del Motor
Se confirmó que en PostgreSQL el nivel por defecto es `READ COMMITTED`, el cual prioriza el rendimiento permitiendo ver datos confirmados por otras sesiones en medio de una transacción. El uso de `REPEATABLE READ` implementa una instantánea (*Snapshot*) al inicio de la primera consulta, garantizando el aislamiento de las operaciones de lectura en procesos complejos o reportes.