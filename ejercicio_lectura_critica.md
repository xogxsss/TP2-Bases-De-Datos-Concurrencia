
# Parte 3: Ejercicio de Lectura Crítica - El riesgo fundacional

**Asignatura:** Bases de Datos II

**Estudiante:** Guzmán, Agustina Micaela

---

## Análisis de Script 1

**Intención declarada:** Dar de baja las funciones de películas retiradas de cartel.

**Script generado por la IA:**

```sql
UPDATE funcion
SET activa = FALSE;

```

### 1. ¿Qué filas afectaría realmente?

Tal como está escrito, este script afectaría a **absolutamente todas las filas** de la tabla `funcion`.

### 2. ¿Por qué no coincide con la consigna?

El script carece de una cláusula `WHERE`. Al omitir la condición de filtrado, el motor de base de datos aplica la actualización (`SET activa = FALSE`) de manera masiva a toda la tabla. En la vida real, esto daría de baja no solo las películas retiradas, sino también los estrenos, las funciones futuras y las funciones activas, causando un desastre en el sistema.

### 3. Versión Corregida

Se debe incluir una cláusula `WHERE` que filtre las funciones que pertenecen a una película que ya no está en cartel:

```sql
UPDATE funcion
SET activa = FALSE
WHERE id_pelicula IN (
    SELECT id_pelicula 
    FROM pelicula 
    WHERE en_cartel = FALSE
);

```

---

## Análisis de Script 2

**Intención declarada:** Limpiar las categorías sin productos asociados.

**Script generado por la IA:**

```sql
DELETE FROM categoria
WHERE id NOT IN (SELECT categoria_id FROM producto);

```

### 1. ¿Qué filas afectaría realmente?

Depende puramente de los datos de la tabla producto. Si llega a existir **un solo producto** que tenga `categoria_id = NULL` (es decir, un producto sin categoría asignada), este script **no eliminará absolutamente nada** (afectará a cero filas), dejando las categorías vacías intactas.

### 2. ¿Por qué no coincide con la consigna?

El problema está en cómo SQL maneja la lógica de los valores nulos con la cláusula `NOT IN`. Si la subconsulta devuelve una lista de valores que incluye un `NULL` (por ejemplo: `1, 2, NULL`), la pregunta lógica que hace el motor es: *"¿El ID de esta categoría NO ESTÁ en esta lista?"*. Al compararlo con `NULL` (que significa "desconocido"), el resultado es `UNKNOWN` (desconocido), no es `TRUE`.
Como el `WHERE` exige que el resultado sea estrictamente `TRUE` para borrar la fila, la consulta falla silenciosamente y no borra nada.

### 3. Versión Corregida

La mejor práctica para evitar el problema de los nulos es utilizar `NOT EXISTS` en lugar de `NOT IN`:

```sql
DELETE FROM categoria c
WHERE NOT EXISTS (
    SELECT 1 
    FROM producto p 
    WHERE p.categoria_id = c.id
);

```

