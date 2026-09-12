# Informe de Concurrencia y Niveles de Aislamiento

**Asignatura:** Bases de Datos II  
**Estudiante:** Guzmán, Agustina Micaela 
**Proyecto / Esquema:** FoodStore  
**Motor de BD:** PostgreSQL  

---

## Escenario 1: Lectura No Repetible (*Non-Repeatable Read*)

### 1. Reproducción del escenario y comandos exactos
- **Sesión 1 (T1):**
```
  BEGIN ISOLATION LEVEL READ COMMITTED;

  SELECT id_producto, nombre, precio_lista
  FROM producto 
  WHERE id_producto = 1;
  -- Resultado: Devuelve precio_lista original (ej. 1000.00).

```

* **Sesión 2 (T2):**
```
  BEGIN;

  UPDATE producto 
  SET precio_lista = 1500.00 
  WHERE id_producto = 1;

  COMMIT;

```


* **Sesión 1 (T3):**
```
  SELECT id_producto, nombre, precio_lista
  FROM producto 
  WHERE id_producto = 1;
  -- Resultado: Devuelve 1500.00 (El precio cambió en medio de la misma transacción).

  ROLLBACK;

```

### 2. Explicación brindada por la IA

> Bajo el nivel `READ COMMITTED`, PostgreSQL genera una nueva instantánea (*snapshot*) al inicio de cada consulta individual. Al hacer `COMMIT` la Sesión 2, la siguiente consulta de la Sesión 1 leyó los datos actualizados dentro de su misma transacción. Elevar el aislamiento a `REPEATABLE READ` congela la visión de la base de datos al inicio de la transacción para evitar esta anomalía.

### 3. Verificación en el motor real

Se repitió el experimento iniciando la Sesión 1 con `BEGIN ISOLATION LEVEL REPEATABLE READ;`.

* **Resultado:** En el paso T3, la Sesión 1 mantuvo el precio congelado en `1500.00` (el valor inicial del snapshot), ignorando el cambio a `2000.00` realizado y confirmado por la Sesión 2 hasta que se cerró la transacción con `ROLLBACK;`.

### 4. Evaluación del acierto de la IA

* **Veredicto:** **Acertó**. El comportamiento de *Snapshot Isolation* en PostgreSQL operó tal como predijo la IA.

---

## Escenario 2: Espera por Bloqueo (*Lock Wait / Row Locking*)

### 1. Reproducción del escenario y comandos exactos

* **Sesión 1 (T1):**
```
  BEGIN;

  SELECT id_producto, nombre, precio_lista 
  FROM producto 
  WHERE id_producto = 1 
  FOR UPDATE;
  -- Resultado: Aplica bloqueo exclusivo a nivel de fila sobre el producto 1.

```


* **Sesión 2 (T2):**
```
  BEGIN;

  SELECT id_producto, nombre, precio_lista 
  FROM producto 
  WHERE id_producto = 1 
  FOR UPDATE;
  -- Resultado: La consulta se queda suspendida en pantalla ("Executing... / Esperando").

```


* **Sesión 1 (T3):**
```
  COMMIT;
  -- Resultado: Apenas se ejecuta COMMIT en la Sesión 1, la Sesión 2 se destraba automáticamente y muestra el resultado de su SELECT.

```


* **Sesión 2 (Cierre):**
```
  ROLLBACK;

```



### 2. Explicación brindada por la IA

> La cláusula `FOR UPDATE` obtiene un bloqueo exclusivo sobre las filas retornadas (*Row Exclusive Lock*). Cuando otra transacción intenta bloquear o modificar los mismos registros, el motor la coloca en un estado de espera (*Lock Wait*) hasta que la transacción poseedora del candado finalice con `COMMIT` o `ROLLBACK`.

### 3. Verificación en el motor real

Se comprobó interactivamente en DBeaver observando cómo la pestaña de la Sesión 2 quedó congelada en ejecución hasta el instante exacto en que la Sesión 1 liberó el recurso con el `COMMIT`.

### 4. Evaluación del acierto de la IA

* **Veredicto:** **Acertó**. El mecanismo de colas de bloqueo exclusivo a nivel de fila funcionó exactamente como fue descrito.

---

## Escenario 3: Lectura Fantasma (*Phantom Read* / Inserción Concurrente)

### 1. Reproducción del escenario y comandos exactos

* **Sesión 1 (T1):**
```
  BEGIN ISOLATION LEVEL READ COMMITTED;

  SELECT count(*) 
  FROM producto 
  WHERE activo = TRUE;
  -- Resultado: Devuelve la cantidad inicial de productos activos (ej. 5).

```


* **Sesión 2 (T2):**
```
  BEGIN;

  INSERT INTO producto (nombre, precio_lista, activo, id_categoria) 
  VALUES ('Empanada de Jamón y Queso', 1200.00, TRUE, 1);

  COMMIT;

```


* **Sesión 1 (T3):**
```
  SELECT count(*) 
  FROM producto 
  WHERE activo = TRUE;
  -- Resultado: Devuelve 6 (Aparece la fila "fantasma" insertada por la Sesión 2).

  ROLLBACK;

```

### 2. Explicación brindada por la IA

> En `READ COMMITTED`, las inserciones confirmadas por otras sesiones afectan los conteos y sumatorias de consultas agregadas repetidas dentro de una misma transacción. Elevar a `REPEATABLE READ` activa el aislamiento por instantánea, manteniendo congelado el universo de filas al momento de iniciar la transacción.

### 3. Verificación en el motor real

Se repitió la prueba iniciando la Sesión 1 en `REPEATABLE READ` e insertando la 'Empanada de Carne Suave' en la Sesión 2.

* **Resultado:** En el segundo `SELECT count(*)`, el número se mantuvo congelado en `6`, ignorando la inserción de la Sesión 2. Una vez cerrado el bloque con `ROLLBACK;`, una nueva consulta mostró el total real actualizado de `7`.

### 4. Evaluación del acierto de la IA

* **Veredicto:** **Acertó**. PostgreSQL evitó la lectura fantasma congelando el conjunto de datos de la transacción en `REPEATABLE READ`.
