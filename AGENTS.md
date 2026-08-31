# Instrucciones para Agentes de IA - TP2_Concurrencia

Este archivo guía a los agentes de IA para evitar errores comunes y agilizar el desarrollo en este proyecto de base de datos PostgreSQL enfocada en concurrencia e integridad.

## 1. Entorno y Comandos Clave (Win32 / PowerShell)
* **Base de Datos de Pruebas (Sandbox):** `foodstore_dev`
* **Crear Base de Datos:** `createdb -U postgres foodstore_dev`
* **Aplicar Esquema:** `psql -U postgres -d foodstore_dev -f schema.sql`
* **Tipo de Repositorio:** Únicamente base de datos SQL. No existen servidores de aplicación ni frameworks (Node.js/Python). Toda verificación se hace mediante consultas psql directas.

## 2. Protocolo de Seguridad Ineludible
Antes de confirmar o ejecutar cualquier script DDL o DML:
1. Pruébalo únicamente en la base de datos de desarrollo/desecho (`foodstore_dev`).
2. Pruébalo siempre dentro de una transacción con ROLLBACK para verificar sintaxis y comportamiento sin alterar el estado:
   ```sql
   BEGIN;
   -- Código a probar
   ROLLBACK;
   ```

## 3. Restricciones Críticas del Esquema (`schema.sql`)
Estas son las reglas del esquema que un agente suele omitir o violar al generar consultas o datos de prueba:

* **Columnas Autoincrementales (`IDENTITY`):** Todas las claves primarias (`id_*`) usan `GENERATED ALWAYS AS IDENTITY`.
  * *Error común:* No intentes insertar un ID explícito (ej: `INSERT INTO cliente (id_cliente, ...) VALUES (1, ...)`) ya que provocará un error en PostgreSQL, a menos que especifiques `OVERRIDING SYSTEM VALUE`. Deja que PostgreSQL los asigne solos.
* **Integridad Referencial (`ON DELETE RESTRICT`):** Todas las claves foráneas tienen restricción `ON DELETE RESTRICT`.
  * *Error común:* Intentar eliminar un registro padre (categoría, cliente, producto, pedido) con dependencias fallará. Se debe limpiar primero el detalle o manejar la restricción de integridad.
* **Tipo Enumerado (`forma_pago_enum`):** Solo admite `'EFECTIVO'`, `'TARJETA'`, `'TRANSFERENCIA'`.
  * *Error común:* Los enums de PostgreSQL son sensibles a mayúsculas/minúsculas. Valores como `'efectivo'` o `'Tarjeta'` fallarán.
* **Restricciones de Verificación (`CHECK`):**
  * El stock de producto debe ser `>= 0` (`chk_producto_stock`).
  * El precio de lista debe ser `>= 0` (`chk_producto_precio`).
  * La cantidad en `detalle_pedido` debe ser **estrictamente mayor a cero** (`chk_detalle_cantidad`: `cantidad > 0`). `cantidad = 0` fallará.
  * El precio unitario histórico en el detalle debe ser `>= 0` (`chk_detalle_precio`).
* **Fechas con Zona Horaria (`TIMESTAMPTZ`):** Usa siempre tipos compatibles con zona horaria o funciones como `now()` al simular o insertar pedidos.

## 4. Enfoque en Concurrencia (TP2)
* El enfoque principal de la materia es concurrencia, niveles de aislamiento (`Read Committed`, `Repeatable Read`, `Serializable`) y bloqueos (`SELECT ... FOR UPDATE`, `SELECT ... FOR SHARE`).
* Para probar escenarios de concurrencia y simular condiciones de carrera en tiempo real (ej. reserva concurrente de stock), abre múltiples sesiones de terminal `psql` paralelas.
