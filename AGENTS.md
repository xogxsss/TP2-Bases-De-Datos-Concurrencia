# Instrucciones para Agentes de IA - TP2_Concurrencia

Este repositorio contiene el proyecto para **Food Store** basado en PostgreSQL, enfocado en el manejo de concurrencia e integridad (`TP2_Concurrencia`).

## Tecnologías Utilizadas
- **Base de Datos:** PostgreSQL.
- **Esquema Principal:** Definido en `schema.sql`.

## Contexto del Proyecto
- Muestra del proyecto integrador para la materia **Bases de Datos II (UTN)**.
- **Enfoque Principal:** Concurrencia, aislamiento de transacciones, bloqueos e integridad.
- El archivo `schema.sql` realiza una limpieza previa (`DROP TABLE IF EXISTS ... CASCADE`), permitiendo restablecer la base de datos a un estado limpio en cualquier momento.

## Flujo de Trabajo y Comandos Clave
- **Aplicar Esquema Base:** `psql -U postgres -d foodstore_dev -f schema.sql`
- **Protocolo de Seguridad Ineludible:** Todo script DDL o DML propuesto por una IA debe probarse dentro de una transacción (`BEGIN ... ROLLBACK;`) y sobre una copia de desarrollo antes de confirmarse.

## Restricciones y Reglas de Negocio
- **Categorías:** El campo `nombre` es único (`UNIQUE`).
- **Productos:** El campo `nombre` es único. El `precio_lista` y el `stock` deben ser `>= 0`.
- **Clientes:** El `email` es el identificador único.
- **Formas de Pago:** Dominio cerrado definido mediante un tipo enumerado (`forma_pago_enum`: 'EFECTIVO', 'TARJETA', 'TRANSFERENCIA').

## Comportamiento e Integridad
- Fechas registradas con zona horaria mediante `TIMESTAMPTZ`.
- Relaciones protegidas mediante `ON DELETE RESTRICT` para evitar eliminaciones accidentales en cascada y resguardar el historial de ventas.