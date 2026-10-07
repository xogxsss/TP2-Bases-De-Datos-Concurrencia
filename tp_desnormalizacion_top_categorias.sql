/*
=============================================================================
DESNORMALIZACION CONTROLADA -- TOP 5 CATEGORIAS POR VENTAS DEL DIA
Archivo : tp_desnormalizacion_top_categorias.sql
Motor   : PostgreSQL 17
Base    : foodstore_dev
Autora  : Agustina Micaela Guzmán
=============================================================================

OBJETIVO
--------
Implementar una estrategia de desnormalizacion controlada mediante una
vista materializada que precalcula la facturacion diaria por categoria.
El objetivo es eliminar el costo del JOIN cuadruplicado + GROUP BY en
tiempo real, sustituyendolo por una lectura directa sobre datos ya
agregados y actualizados periodicamente.

PROBLEMA QUE RESUELVE
---------------------
La consulta original del Top 5 ejecuta un Parallel Seq Scan sobre
200.000+ pedidos para filtrar unicamente los del dia actual, descartando
el 97.4% de las filas leidas. Con la vista materializada, esa lectura
se reemplaza por un Index Scan sobre un conjunto preagregado y compacto.
-- 
RAZON TECNICA DE LA OPCION A (MV con columna fecha)
----------------------------------------------------
PostgreSQL no permite funciones volatiles (CURRENT_DATE, NOW()) en el
DDL de una vista materializada. Por eso la MV agrupa por fecha y
categoria, almacenando el historico completo. La consulta del Top 5
del dia filtra sobre la columna fecha precomputada, lo que habilita
el uso del indice unico y el refresco concurrente sin bloqueos.

ESTRUCTURA DE OBJETOS
---------------------
  MV  : mv_ventas_categoria_diario   -- datos preagregados por fecha y categoria
  IDX : idx_mv_ventas_fecha_cat      -- indice unico compuesto (fecha, categoria)
  FN  : fn_refrescar_top5_categorias -- funcion de refresco para programador externo

IDEMPOTENCIA
------------
  DROP ... IF EXISTS CASCADE antes de cada CREATE para que el script
  pueda reejecutarse sin errores sobre una base ya configurada.

COMPATIBILIDAD DE CODIFICACION
-------------------------------
  Comentarios exclusivamente en ASCII para evitar errores de codificacion
  WIN1252/UTF-8 al ejecutar con psql desde terminales Windows.
=============================================================================
*/


-- ============================================================
-- PASO 1 -- VISTA MATERIALIZADA: mv_ventas_categoria_diario
-- ============================================================
-- Precalcula la facturacion total agrupada por fecha calendario
-- y nombre de categoria.
--
-- Columnas resultantes:
--   fecha         : DATE extraida de pedido.fecha_hora (TIMESTAMPTZ -> DATE)
--   categoria     : nombre de la categoria del producto
--   total_vendido : SUM(cantidad * precio_unitario_historico)
--
-- Por que agrupa por fecha y no filtra por CURRENT_DATE:
--   PostgreSQL rechaza funciones volatiles en el DDL de una MV.
--   Agrupar por fecha almacena el historico completo; la consulta
--   del Top 5 filtra por fecha = CURRENT_DATE sobre datos ya
--   preagregados, lo cual es eficiente y estable.
--
-- Por que usar precio_unitario_historico en lugar de precio_lista:
--   El precio puede cambiar despues de cerrar un pedido. El campo
--   precio_unitario_historico en detalle_pedido registra el precio
--   real al momento de la venta, garantizando exactitud contable.
-- ============================================================

DROP MATERIALIZED VIEW IF EXISTS mv_ventas_categoria_diario CASCADE;

CREATE MATERIALIZED VIEW mv_ventas_categoria_diario AS
SELECT
    DATE(ped.fecha_hora)                              AS fecha,
    c.nombre                                          AS categoria,
    SUM(dp.cantidad * dp.precio_unitario_historico)   AS total_vendido
FROM detalle_pedido dp
JOIN producto  pr  ON pr.id_producto  = dp.id_producto
JOIN categoria c   ON c.id_categoria  = pr.id_categoria
JOIN pedido    ped ON ped.id_pedido   = dp.id_pedido
GROUP BY DATE(ped.fecha_hora), c.nombre;


-- ============================================================
-- PASO 2 -- INDICE UNICO: idx_mv_ventas_fecha_cat
-- ============================================================
-- Indice unico compuesto sobre (fecha, categoria).
--
-- Por que es obligatorio:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY requiere que exista
--   al menos un indice unico sobre la MV. Sin el, PostgreSQL
--   rechaza el refresco concurrente y obliga a un REFRESH
--   bloqueante que impide lecturas durante la actualizacion.
--
-- Por que (fecha, categoria) y no solo (categoria):
--   La combinacion (fecha, categoria) es la clave natural de la
--   MV: un mismo nombre de categoria puede aparecer en multiples
--   fechas. El indice compuesto garantiza unicidad real y ademas
--   acelera el filtro WHERE fecha = CURRENT_DATE de la consulta
--   del Top 5, que es el patron de acceso dominante.
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_ventas_fecha_cat
    ON mv_ventas_categoria_diario (fecha, categoria);


-- ============================================================
-- PASO 3 -- FUNCION DE REFRESCO: fn_refrescar_top5_categorias
-- ============================================================
-- Encapsula el refresco concurrente de la MV en una funcion
-- invocable por cualquier programador externo (pg_cron,
-- background worker, cron del sistema operativo via psql -c).
--
-- Por que CONCURRENTLY:
--   El refresco concurrente actualiza la MV sin adquirir un
--   bloqueo exclusivo sobre ella. Las consultas de lectura
--   siguen respondiendo con los datos del ciclo anterior
--   mientras se calcula el nuevo snapshot. Requiere el indice
--   unico del Paso 2.
--
-- Por que RETURNS void:
--   La funcion solo tiene efecto colateral (actualizar la MV).
--   No necesita devolver filas; RETURNS void es el tipo correcto
--   para funciones de mantenimiento en PostgreSQL.
-- ============================================================

DROP FUNCTION IF EXISTS fn_refrescar_top5_categorias() CASCADE;

CREATE OR REPLACE FUNCTION fn_refrescar_top5_categorias()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_categoria_diario;
END;
$$;


-- ============================================================
-- CONSULTA DE USO -- TOP 5 DEL DIA SOBRE LA MV
-- ============================================================
-- Una vez refrescada la MV, el Top 5 del dia se obtiene con
-- una lectura directa sobre datos preagregados, sin JOINs ni
-- GROUP BY en tiempo real:
--
--   SELECT categoria, total_vendido
--   FROM   mv_ventas_categoria_diario
--   WHERE  fecha = CURRENT_DATE
--   ORDER  BY total_vendido DESC
--   LIMIT  5;
--
-- El filtro WHERE fecha = CURRENT_DATE usa el indice compuesto
-- idx_mv_ventas_fecha_cat, convirtiendo el Parallel Seq Scan
-- original sobre 200.000+ pedidos en un Index Scan sobre las
-- pocas filas del dia actual preagregadas en la MV.
-- ============================================================


-- ============================================================
-- MECANISMO DE SINCRONIZACION AUTOMATICA
-- ============================================================
-- La funcion fn_refrescar_top5_categorias() puede invocarse
-- de forma automatica mediante un programador externo.
--
-- OPCION 1 -- pg_cron (extension de PostgreSQL):
--   Requiere instalar pg_cron y agregar 'pg_cron' a
--   shared_preload_libraries en postgresql.conf.
--   Ejemplo: refresco cada 5 minutos durante el horario de negocio:
--
--   SELECT cron.schedule(
--       'refrescar_top5_categorias',
--       '*/5 8-22 * * *',
--       $$ SELECT fn_refrescar_top5_categorias(); $$
--   );
--
--   Para eliminar el job programado:
--   SELECT cron.unschedule('refrescar_top5_categorias');
--
-- OPCION 2 -- cron del sistema operativo (sin extension):
--   Agregar una entrada al crontab del servidor que ejecute
--   psql con la funcion directamente:
--
--   */5 8-22 * * * psql -U postgres -d foodstore_dev \
--       -c "SELECT fn_refrescar_top5_categorias();"
--
-- OPCION 3 -- background worker o job scheduler externo:
--   Cualquier orquestador (Airflow, pgAgent, scripts de deploy)
--   puede invocar la funcion mediante una conexion psql estandar:
--
--   SELECT fn_refrescar_top5_categorias();
--
-- FRECUENCIA RECOMENDADA:
--   Cada 5 minutos durante el horario de operacion del negocio.
--   En horas de baja actividad, el refresco puede espaciarse
--   a cada 30 o 60 minutos para reducir el costo de I/O.
--   El refresco concurrente garantiza que las lecturas nunca
--   se bloqueen independientemente de la frecuencia elegida.
-- ============================================================

-- ============================================================
-- PASO 4 -- CONSULTA DE MEDICION DE RENDIMIENTO (Punto 5.2.d)
-- ============================================================
-- Consulta sobre la vista materializada analizada con EXPLAIN ANALYZE
-- para comprobar la reduccion del tiempo de ejecucion (< 1 ms).

EXPLAIN ANALYZE
SELECT 
    categoria, 
    total_vendido
FROM mv_ventas_categoria_diario
WHERE fecha = CURRENT_DATE
ORDER BY total_vendido DESC
LIMIT 5;


-- ============================================================
-- PASO 5 -- SCRIPT DE AUDITORIA DE CONSISTENCIA (Punto 5.2.e)
-- ============================================================
-- Compara el resultado de la consulta sobre la vista materializada 
-- contra la consulta compleja original en 3FN mediante EXCEPT bidireccional.
-- Resultado esperado: 0 filas (vacio = 100% de consistencia).

WITH datos_3fn AS (
    SELECT 
        c.nombre AS categoria,
        SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido
    FROM detalle_pedido dp
    JOIN producto pr ON pr.id_producto = dp.id_producto
    JOIN categoria c ON c.id_categoria = pr.id_categoria
    JOIN pedido ped ON ped.id_pedido = dp.id_pedido
    WHERE DATE(ped.fecha_hora) = CURRENT_DATE
    GROUP BY c.nombre
),
datos_mv AS (
    SELECT 
        categoria,
        total_vendido
    FROM mv_ventas_categoria_diario
    WHERE fecha = CURRENT_DATE
)
(
    SELECT categoria, total_vendido FROM datos_3fn
    EXCEPT
    SELECT categoria, total_vendido FROM datos_mv
)
UNION ALL
(
    SELECT categoria, total_vendido FROM datos_mv
    EXCEPT
    SELECT categoria, total_vendido FROM datos_3fn
);