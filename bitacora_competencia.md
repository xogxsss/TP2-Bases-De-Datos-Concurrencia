```markdown
# Bitácora de Competencia - TP3 (Cierre de Práctica)

**Equipo / Estudiante:** Guzmán, Agustina Micaela  
**Proyecto / Esquema:** FoodStore (PostgreSQL)  
**Consulta a optimizar:** Listado de productos de la categoría 'Pizzas', filtrado por precio (1500-4500), solo activos, ordenados por stock descendente (Top 20).

---

## 1. Medición Base (El "Antes")
* **Plan original:** El plan de ejecución mostró un cuello de botella clásico: un escaneo secuencial completo (`Seq Scan on producto p`) combinado con un nodo explícito de ordenamiento en memoria (`Sort Method: quicksort Memory: 25kB`) para resolver el `ORDER BY p.stock DESC`.
* **Execution Time original:** ~0.029 ms (en entorno de desarrollo con datos de prueba).

---

## 2. Estrategias Propuestas por la IA y Análisis Crítico

### Estrategia 1: Índice Parcial Compuesto Extremo
* **Propuesta:** 
  ```sql
  CREATE INDEX idx_comp_estrategia1 
  ON producto (id_categoria, precio_lista, stock DESC) 
  WHERE activo = TRUE;

```

* **Decisión:** **Aplicada y Ganadora**.
* **Justificación:** Al incluir exactamente las columnas por las que filtramos (`id_categoria`, `precio_lista`, `activo`) y ordenar previamente por `stock DESC`, el optimizador de PostgreSQL evita por completo el nodo de ordenamiento (`Sort`) y accede de forma directa a los registros requeridos.

### Estrategia 2: Subconsulta en lugar de JOIN

* **Propuesta:** Reescritura lógica aislando la categoría mediante una subconsulta en el `WHERE`.
* **Decisión:** **Descartada para la producción final**.
* **Justificación:** Aunque reestructurar la consulta ayuda a la legibilidad en algunos motores, en PostgreSQL el optimizador moderno ya maneja eficientemente el `JOIN` si cuenta con las estadísticas y los índices adecuados. No aportaba una ventaja real frente a la combinación de índices.

### Estrategia 3: Índice BRIN (Block Range Index)

* **Propuesta:**
```sql
CREATE INDEX idx_comp_estrategia3 ON producto USING BRIN (precio_lista, stock);

```


* **Decisión:** **Descartada categóricamente**.
* **Justificación:** Los índices BRIN están diseñados exclusivamente para tablas masivas ordenadas de forma natural por rangos físicos (como logs de fecha/hora). Usarlo en una tabla transaccional con filtros cruzados de precio y stock habría resultado ineficiente e incorrecto para este caso de uso.

---

## 3. Resultado Final (El "Después")

* **Estrategia Ganadora:** Índice Parcial Compuesto (`idx_comp_estrategia1`).
* **Nuevo Plan de Ejecución:** El nodo `Sort` desapareció del plan y el tiempo de respuesta mejoró notablemente.
* **Execution Time Final:** ~0.016 ms.
* **Conclusión del Equipo:** La asistencia de la IA permitió idear rápidamente el índice compuesto adecuado, el cual fue validado empíricamente mediante `EXPLAIN ANALYZE`, logrando eliminar sobrecostos de memoria RAM en el ordenamiento y optimizando el rendimiento general de la consulta masiva.

```