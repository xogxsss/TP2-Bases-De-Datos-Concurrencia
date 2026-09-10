# Protocolo de Seguridad para Operaciones en Base de Datos

Este documento define el procedimiento estándar e ineludible aplicado antes de ejecutar cualquier script (manual o generado por agentes de IA como OpenCode o Kiro) sobre la base de datos del proyecto **FoodStore**.

---

## 1. Copia de Trabajo (Entorno Aislado)
Nunca se ejecutan scripts de prueba o modificaciones generadas por IA sobre la base de producción o plantilla original.
* **Procedimiento:** Toda modificación se realiza sobre una base de datos de desarrollo/desecho creada específicamente para pruebas.
* **Comandos en mi entorno:**
  ```
  # Creación de la base de datos de copia/trabajo desde la terminal de PostgreSQL
  createdb -U postgres foodstore_dev