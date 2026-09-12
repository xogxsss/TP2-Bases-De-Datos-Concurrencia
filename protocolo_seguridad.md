# Protocolo de Seguridad para Operaciones en Base de Datos

Este documento define el procedimiento obligatorio aplicado antes de ejecutar cualquier script (manual o generado por agentes de IA como OpenCode o Kiro; en este caso, utilizaremos OpenCode) sobre la base de datos del proyecto **FoodStore**.

---

## 1. Copia de Trabajo (Entorno Aislado)
Nunca se ejecutan scripts de prueba o modificaciones generadas por IA sobre la base de producción o plantilla original con el fin de proteger el esquema. Lo ejecutaremos en la base de datos de desarrollo aislada llamada `foodstore_dev`.

* **Procedimiento:** Toda modificación se realiza sobre una base de datos de desarrollo/desecho creada específicamente para pruebas.
* **Comandos en mi entorno:**
```
  # Creación de la base de datos de copia/trabajo desde la terminal de PostgreSQL
  createdb -U postgres foodstore_dev
```

## 2. Transacción de Prueba (`BEGIN` y `ROLLBACK`)
Todo script que escriba o modifique (`INSERT`, `UPDATE`, `DELETE`) se ejecuta de manera transaccional para inspeccionar el impacto ANTES de confirmar.

### Sintaxis:
```
  BEGIN;
  -- [Inserción o prueba del script generado por IA]
  -- Si algo falla o no es lo esperado:
  ROLLBACK;
  -- Solo si se verificó el resultado esperado:
  -- COMMIT;
```
* **BEGIN**: Abre el bloque. Ninguna modificación hecha después de `BEGIN` se graba definitivamente en el disco.
* **ROLLBACK**: Cancela y revierte las modificaciones hechas desde el `BEGIN`. Devuelve la base de datos al estado en el que se encontraba antes de iniciar la transacción.
* **COMMIT**: Guarda de forma permanente los cambios.


## 3. Respaldo estructural con pg_dump
Hay modificaciones que no pueden revertirse con un simple `ROLLBACK`:
* **`ALTER TABLE`** 
* **`DROP`** 
* **Migraciones de esquema** 
Antes de aplicar cambios estructurales mayores a Definición de Datos, se genera una copia de seguridad física externa.
* **Directorio de destino local**: `C:\Program Files\PostgreSQL\17\data\base\25475` 
* **Comando por terminal**: `pg_dump -U postgres -d foodstore_dev -F c -b -v -f "C:\respaldos_food_store\foodstore_dev_backup.backup"`. Esta carpeta pertenece al sistema de almacenamiento interno de PostgreSQL, por eso utilizamos una diferente ruta al momento de tirar un comando por terminal. Modificar archivos de respaldo dentro de la ruta verdadera de la Base de Datos puede romper la consistencia del motor.

