# Instrucciones y Guía Técnica para Agentes de IA — Proyecto FoodStore (TP2)

Este documento establece el marco operativo y las restricciones técnicas obligatorias para guiar a los agentes de asistencia en el desarrollo, prueba y validación de scripts sobre el proyecto de base de datos PostgreSQL. Su propósito es prevenir errores comunes de sintaxis, violaciones de integridad y problemas de concurrencia.

---

## 1. Entorno de Trabajo y Especificaciones del Stack

* **Base de datos de pruebas (Sandbox):** `foodstore_dev` (aislada de cualquier esquema de producción o plantilla original).
* **Comando de creación en terminal:** `createdb -U postgres foodstore_dev`
* **Aplicación de esquema:** `psql -U postgres -d foodstore_dev -f schema.sql`
* **Naturaleza del repositorio:** Proyecto puramente de base de datos SQL. No cuenta con servidores de aplicación, ORMs ni frameworks de backend (como Node.js, Python o Django). Toda validación, prueba e inserción de datos se verifica mediante comandos y consultas directas en la terminal de `psql` o gestores compatibles (como DBeaver).

---

## 2. Protocolo de Seguridad Operativa e Ineludible

Antes de confirmar o ejecutar cualquier script de Definición de Datos (DDL) o Manipulación de Datos (DML) generado por herramientas de asistencia:

1. **Aislamiento absoluto:** Todo script debe ejecutarse exclusivamente en la base de datos de desarrollo `foodstore_dev`.
2. **Prueba transaccional preventiva:** Ninguna modificación o inserción se ejecuta directamente sin un contenedor transaccional de prueba. Se debe utilizar obligatoriamente el flujo de transacciones con `ROLLBACK` para inspeccionar errores de sintaxis y efectos colaterales antes de un `COMMIT`:
```
  BEGIN;
  -- Bloque de código o inserción a probar
  ROLLBACK;

```



---

## 3. Restricciones Críticas y Reglas del Esquema (`schema.sql`)

Los agentes de IA suelen omitir o infringir estas reglas estructurales al proponer consultas o datos de prueba. Deben respetarse estrictamente:

* **Columnas Autoincrementales (`IDENTITY`):**
* Todas las claves primarias (`id_*`) se encuentran definidas mediante `GENERATED ALWAYS AS IDENTITY`.
* *Error frecuente a evitar:* Intentar insertar un valor explícito en una clave primaria (ej: `INSERT INTO cliente (id_cliente, ...) VALUES (1, ...)`) generará un error directo en PostgreSQL, a menos que se anteprenda la cláusula `OVERRIDING SYSTEM VALUE`. Por defecto, se debe omitir la columna en el `INSERT` y dejar que el motor asigne el identificador automáticamente.


* **Integridad Referencial y Cascada (`ON DELETE RESTRICT`):**
* Todas las claves foráneas del esquema tienen configurada una política restrictiva de borrado (`ON DELETE RESTRICT`).
* *Error frecuente a evitar:* Intentar eliminar un registro padre (como una categoría, un cliente, un producto o un pedido principal) que posea registros hijos asociados fallará por violación de llave foránea. Es obligatorio limpiar o eliminar primero los registros dependientes.


* **Tipos de Datos Enumerados (`forma_pago_enum`):**
* El dominio de formas de pago acepta exclusivamente los valores literales: `'EFECTIVO'`, `'TARJETA'`, `'TRANSFERENCIA'`.
* *Error frecuente a evitar:* Los tipos `ENUM` en PostgreSQL son estrictamente sensibles a mayúsculas y minúsculas. Enviar variaciones como `'efectivo'` o `'Tarjeta'` provocará un rechazo inmediato por parte del motor.


* **Restricciones de Verificación lógicas (`CHECK`):**
* `chk_producto_stock`: El stock del producto debe ser mayor o igual a cero (`stock >= 0`).
* `chk_producto_precio`: El precio de lista debe ser mayor o igual a cero (`precio_lista >= 0`).
* `chk_detalle_cantidad`: La cantidad en el detalle del pedido es **estrictamente mayor a cero** (`cantidad > 0`). Ingresar un valor de `cantidad = 0` o negativo disparará un error de validación.
* `chk_detalle_precio`: El precio unitario histórico registrado en el detalle debe ser mayor o igual a cero.


* **Manejo de Fechas y Marcas de Tiempo (`TIMESTAMPTZ`):**
* Todas las columnas temporales emplean tipos con zona horaria (`TIMESTAMPTZ`). Se deben utilizar funciones compatibles como `now()` o literales de intervalo precisos al simular transacciones o cargas de pedidos.



---

## 4. Enfoque Avanzado en Concurrencia y Transaccionalidad (TP2)

* **Objetivo de la materia:** El foco central del proyecto reside en la gestión analítica de la concurrencia, el análisis de anomalías y la correcta utilización de los niveles de aislamiento definidos por el estándar SQL (`Read Committed`, `Repeatable Read`, `Serializable`).
* **Mecanismos de bloqueo explícito:** Se debe dominar el uso de bloqueos a nivel de fila mediante cláusulas de control de concurrencia pesimista como `SELECT ... FOR UPDATE` y `SELECT ... FOR SHARE`.
* **Metodología de prueba en paralelo:** Para simular escenarios reales de condiciones de carrera (por ejemplo, reservas simultáneas de stock o modificaciones concurrentes de precios), se deben abrir y mantener activas múltiples sesiones de terminal independientes en `psql`, ejecutando los pasos de las transacciones de forma intercalada (Sesión A y Sesión B).