```
# Bitácora de Competencia - TP3 (Cierre de Práctica)

**Asignatura:** Bases de Datos II  
**Estudiante:** Guzmán, Agustina Micaela  
**Proyecto / Esquema:** FoodStore (PostgreSQL)  
**Consulta a optimizar:** Listado de productos de la categoría 'Pizzas', filtrado por precio (1500-4500), solo activos, ordenados por stock descendente (Top 20).

---

## 1. Medición Base (El "Antes")
* **Objetivo de la prueba:** Evaluar el rendimiento de la consulta sin modificaciones de índices específicos para identificar cuellos de botella iniciales.
* **Plan de ejecución original:** El diagnóstico arrojó un escaneo secuencial completo (`Seq Scan on producto p`) combinado con un nodo de ordenamiento explícito en memoria RAM (`Sort Method: quicksort Memory: 25kB`) para resolver la cláusula `ORDER BY p.stock DESC`.
* **Execution Time original:** **~0.029 ms**.

---

## 2. Análisis y Evaluación de Estrategias Propuestas

### Estrategia 1: Índice Parcial Compuesto Extremo
* **Script aplicado:**
  ```
  CREATE INDEX idx_comp_estrategia1 
  ON producto (id_categoria, precio_lista, stock DESC) 
  WHERE activo = TRUE;

```

* **Resultado empírico:** El tiempo de ejecución real se redujo a **~0.016 ms**.
* **Análisis técnico:** Esta estrategia resultó ganadora porque alinea de forma directa las columnas del filtro (`id_categoria`, `precio_lista`, `activo`) con el orden descendente del stock. El optimizador del motor logra acceder de forma selectiva a los datos sin necesidad de generar nodos adicionales de ordenamiento en memoria.

### Estrategia 2: Subconsulta en lugar de JOIN (Paso 3)

* **Script aplicado:** Reescritura lógica de la consulta aislando la categoría mediante un `InitPlan` con subconsulta en el `WHERE`.
* **Resultado empírico:** **Execution Time de 0.034 ms** (y ~0.058 ms en el plan completo).
* **Análisis técnico:** Si bien el plan muestra un prolijo `InitPlan` con un `Index Scan` sobre la tabla de categorías (`categoria_nombre_key`), al no contar con un índice compuesto adecuado para los productos, el motor se ve obligado a realizar un `Seq Scan` sobre la tabla `producto` y aplicar el `quicksort`. Esto demuestra que la reescritura sintáctica por sí sola no suple la falta de indexación física.

### Estrategia 3: Índice BRIN (Paso 4)

* **Script aplicado:**
```
CREATE INDEX idx_comp_estrategia3 ON producto USING BRIN (precio_lista, stock);

```

* **Resultado empírico:** **Execution Time de 0.015 ms**.
* **Análisis técnico y justificación del empate numérico:** Aunque el número bruto de ejecución arrojó un empate técnico estadístico con la Estrategia 1, el plan de ejecución reveló que el motor seguía realizando un `Seq Scan` y ordenando mediante `quicksort`. Este fenómeno ocurre debido al tamaño acotado de la base de datos de desarrollo y el uso de caché en memoria RAM. Conceptualmente, el índice BRIN fue **descartado de forma categórica**, ya que este tipo de índices está diseñado exclusivamente para bloques masivos de Big Data con ordenamiento físico secuencial, y no para tablas transaccionales dinámicas con filtros cruzados.

---

## 3. Conclusión de la Competencia

* **Estrategia Seleccionada:** Índice Parcial Compuesto (`idx_comp_estrategia1`).
* **Veredicto Final:** La experimentación empírica con `EXPLAIN ANALYZE` demostró que la indexación estructural precisa es la única alternativa que modifica de raíz el plan físico de PostgreSQL, eliminando costos ocultos de procesamiento y garantizando la escalabilidad real de la base de datos en entornos de producción.

```