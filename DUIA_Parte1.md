# Declaración de Uso de IA (DUIA) - Parte 1

| Campo | Detalle |
| :--- | :--- |
| **Herramienta** | OpenCode |
| **Spec / Prompt utilizado** | *"Crear restricciones en PostgreSQL para impedir pedidos con fecha futura en `pedido` y evitar que se agreguen productos inactivos en `detalle_pedido`."* |
| **Qué generó** | Archivo `restricciones_integridad.sql` con la función/trigger `trg_validar_fecha_pedido` sobre `pedido` y `trg_validar_producto_activo` sobre `detalle_pedido`. |
| **Qué se aceptó** | La totalidad del código SQL y la lógica de validación PL/pgSQL generada por OpenCode. |
| **Qué se modificó o descartó** | Se mantuvo el código tal como fue generado tras validar su efectividad. |
| **Verificación realizada** | Se ejecutaron inserciones con fecha futura (`NOW() + 2 days`) y productos con `activo = FALSE` dentro de transacciones aisladas, confirmando que la base de datos aborta con el error `P0001` esperado. |