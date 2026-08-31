# Agent Instructions - TP2_Concurrencia

This repository contains a PostgreSQL-based project for managing a Food Store, specifically focused on concurrency (`TP2_Concurrencia`).

## Tech Stack
- **Database:** PostgreSQL
- **Schema:** Defined in `schema.sql`.

## Project Context
- The project is likely part of a University course ("BD II" - Bases de Datos II).
- Focus: **Concurrency**. Future tasks will likely involve writing stored procedures, triggers, or specific SQL queries to test concurrent transactions (Read Committed, Serializable, etc.).
- `schema.sql` handles cleanup (`DROP TABLE IF EXISTS ... CASCADE`) at the start, making it safe to re-run for a clean state.

## Core Commands & Workflow
- **Apply Schema:** `psql -U <user> -d <database> -f schema.sql` (Adjust parameters based on your local environment).
- **Verify Data:** `select * from producto;` is included at the end of `schema.sql`.

## Key Data Constraints
- **Categories:** `nombre` is unique.
- **Products:** `nombre` is unique. Price and stock must be `>= 0`.
- **Clients:** `email` is the unique identifier (R6).
- **Payment Types:** Uses custom enum `forma_pago_enum` ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA').

## Known Limitations / Quirks
- The schema uses `TIMESTAMPTZ` for orders.
- Deletions on parent tables (category, client, product, pedido) use `ON DELETE RESTRICT`, requiring explicit child deletion or status changes (like `activo = FALSE`).
