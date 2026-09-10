# Parte 3: Ejercicio de Lectura Crítica de EXPLAIN ANALYZE

**Asignatura:** Bases de Datos II  
**Estudiante:** Guzmán, Agustina Micaela  
**Proyecto / Esquema:** FoodStore  
**Motor de BD:** PostgreSQL  

---

## 1. Contexto y Plan de Ejecución Real

Para este ejercicio, tomamos el plan de ejecución real obtenido en el Laboratorio (Parte 2) tras aplicar el índice `idx_pedido_fecha_hora` en la tabla `pedido`. 

**Consulta:** Historial de pedidos de los últimos 30 días ordenados por fecha.
**Plan de ejecución obtenido (`EXPLAIN ANALYZE`):**

```
Index Scan using idx_pedido_fecha_hora on pedido  (cost=0.43..7964.71 rows=67059 width=28) (actual time=0.016..21.587 rows=66627 loops=1)
  Index Cond: ((fecha_hora >= (now() - '30 days'::interval)) AND (fecha_hora <= now()))
Planning Time: 1.194 ms
Execution Time: 23.119 ms
```


## 2. Explicación generada por la IA

Se le solicitó a un asistente de IA que explicara este plan nodo por nodo. La IA devolvió la siguiente respuesta en lenguaje natural:

> *"El motor de base de datos utilizó un Index Scan gracias al índice creado. El costo de 7964.71 indica que la consulta tarda aproximadamente 7.9 segundos en ejecutarse. El B-Tree devuelve exactamente 67.059 filas al motor. Además, podemos ver que el Planning Time de 1.194 ms representa el tiempo que tardó el disco rígido en leer los datos de la tabla, y finalmente, el nodo Index Scan tuvo que realizar un ordenamiento posterior en memoria RAM para cumplir con el ORDER BY."*

---

## 3. Contraste Técnico y Detección de Errores

Al someter la respuesta de la IA a una lectura crítica técnica, se detectaron severas imprecisiones conceptuales respecto a cómo funciona el motor de PostgreSQL. A continuación se documentan los hallazgos:

| Frase / Afirmación de la IA | Evaluación | Corrección Técnica |
| --- | --- | --- |
| *"El costo de 7964.71 indica que la consulta tarda aproximadamente 7.9 segundos en ejecutarse."* | **Incorrecto** | Confunde el **costo estimado del optimizador** (medido en unidades arbitrarias de costo de E/S y CPU) con el **tiempo real de ejecución**. El tiempo real medido en milisegundos fue de apenas **23.119 ms** (`Execution Time`). |
| *"El B-Tree devuelve exactamente 67.059 filas al motor."* | **Impreciso** | Confunde la estimación estadística con el resultado real. **67.059** es la estimación inicial del planificador (`rows=67059`), pero el número real de filas filtradas y devueltas fue **66.627** (`rows=66627`). |
| *"El Planning Time de 1.194 ms representa el tiempo que tardó el disco rígido en leer los datos..."* | **Incorrecto** | El `Planning Time` es el tiempo que le tomó al procesador **analizar la sintaxis SQL y construir el árbol de ejecución**, antes de tocar cualquier dato físico en disco o memoria caché. |
| *"El nodo Index Scan tuvo que realizar un ordenamiento posterior en memoria RAM."* | **Incorrecto** | Al utilizar un índice B-Tree creado explícitamente como `DESC`, las filas ya se leen desde la estructura en el orden solicitado. No hubo ningún nodo de tipo `Sort` ni gasto de RAM para ordenar, justamente esa es la ventaja del índice. |

### Conclusión

Este ejercicio demuestra el riesgo fundacional de delegar la interpretación de diagnósticos de rendimiento a una IA sin supervisión. La IA es capaz de hilar conceptos relacionados con bases de datos en oraciones coherentes, pero puede fallar críticamente al distinguir entre estimaciones y valores reales, o al atribuir correctamente los procesos físicos (CPU vs. Disco RAM) descritos en el plan de ejecución.

