# **Declaración de Uso de IA (DUIA) - Parte 1**
**Asignatura:** Bases de Datos II  
**Estudiante:** Guzmán, Agustina Micaela 
**Proyecto / Esquema:** FoodStore  
**Motor de BD:** PostgreSQL  
**Herramienta utilizada:** OpenCode (asistente de IA)

## PARTE 1

* Spec o prompt utilizado: "Generar triggers en PL/pgSQL para la base de datos FoodStore que garanticen dos reglas de negocio: 
    1) Impedir la carga de pedidos con fechas futuras (`fecha_hora <= NOW()`). 
    2) Garantizar que solo se agreguen productos activos (`activo = TRUE`) en los detalles de pedido."

* Qué generó: Una propuesta inicial que incluía restricciones estándar de tipo `CHECK` y un esquema preliminar de función y trigger en PL/pgSQL.

* Qué se aceptó: Se adoptó la lógica general de validación de los disparadores y las condiciones diseñadas específicamente para las tablas del proyecto Food Store.

* Qué se modificó o descartó: Se descartaron las restricciones CHECK directas con funciones basadas en tiempo como NOW(), ya que PostgreSQL las considera mutables y no permite su uso directo de esa forma; en su lugar, se implementó un trigger de tipo `BEFORE INSERT OR UPDATE` para cumplir estrictamente con las limitaciones técnicas del motor.

* Verificación realizada: Se ejecutaron pruebas transaccionales completas utilizando bloques `BEGIN` y `ROLLBACK`, validando operaciones de inserción correctas que pasaron con éxito e inserciones inválidas que fueron rechazadas de manera automática por el motor de la base de datos.

---

## PARTE 2

* **Herramienta utilizada:** OpenCode / Asistente de IA
* **Spec o prompt utilizado:** *"Explicar las anomalías de concurrencia (lectura no repetible, espera por bloqueo y lectura fantasma) en PostgreSQL para las tablas del proyecto FoodStore y proponer los niveles de aislamiento adecuados."*
* **Qué generó:** Explicaciones teóricas detalladas de los bloqueos en memoria, el comportamiento de MVCC y los comandos para configurar los niveles de aislamiento mediante `SET TRANSACTION ISOLATION LEVEL`.
* **Qué se aceptó:** La estructura conceptual de los escenarios concurrentes y la lógica de los bloqueos exclusivos con `FOR UPDATE`.
* **Qué se modificó o descartó, y por qué:** No se descartó información, pero se adaptaron estrictamente los ejemplos teóricos genéricos propuestos por la IA a los nombres reales de tablas y columnas del esquema de *Food Store*.
* **Verificación realizada:** Ejecución paso a paso en doble sesión concurrente dentro del entorno local de desarrollo (`foodstore_dev`), contrastando los resultados obtenidos en pantalla con las hipótesis del modelo.

