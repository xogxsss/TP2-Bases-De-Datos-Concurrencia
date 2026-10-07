/*
=============================================================================
EJERCICIO FNBC -- CONTROL DE LOTE EN ALMACEN
Archivo : tp_fnbc_control_lote.sql
Motor   : PostgreSQL 17
Base    : foodstore_dev
Autora  : Agustina Micaela Guzmán
=============================================================================

OBJETIVO
--------
Demostrar la deteccion de una violacion a la Forma Normal de Boyce-Codd
(FNBC) y su correccion por descomposicion sin perdida de informacion
(lossless-join decomposition), segun el Teorema de Heath.

TABLA ORIGINAL: control_lote_almacen(L, D, R)
  Atributos:
    L = lote_id                (BIGINT)
    D = deposito_id            (BIGINT)
    R = responsable_control_id (BIGINT)
  PK compuesta: (L, D)

ANALISIS DE DEPENDENCIAS FUNCIONALES
  DF1: {L, D} -> R   valida: {L,D} es superclave (PK)     -- satisface FNBC
  DF2:  R    -> D    problematica: R no es superclave      -- viola FNBC

PRUEBA DE VIOLACION FNBC PARA DF2
  Cerradura de R bajo F:  R+ = {R, D}
  R+ != {L, D, R}  -->  R NO es superclave  -->  DF2 viola FNBC

DESCOMPOSICION POR TEOREMA DE HEATH (sobre DF2: R -> D)
  R1: responsable_deposito(R, D)       -- aisla DF2; PK = R       -- FNBC OK
  R2: control_lote_responsable(L, R)   -- conserva vinculo L-R    -- FNBC OK

  Prueba de reunion sin perdida:
    R1 join R2 = control_lote_almacen  (sin tuplas espurias ni perdidas)

JUSTIFICACION TEORICA DE LA REUNION SIN PERDIDA (Punto 4.2.f)
  Atributo comun entre R1 y R2:
    Atributos(R1) interseccion Atributos(R2) = {responsable_control_id}

  Criterio de superclave sobre el atributo comun:
    En R1 = responsable_deposito(R, D), la PK es {R}.
    La cerradura R+ en R1 = {R, D} = todos los atributos de R1.
    Por tanto, R es superclave (clave candidata) de R1.

  Conclusion por Teorema de Heath:
    Como R -> D pertenece al conjunto de DFs y R es superclave de R1,
    se garantiza matematicamente que R1 join R2 reconstruye exactamente
    la instancia original sin tuplas espurias ni perdida de informacion.
    No pueden generarse combinaciones (L, D, R) inexistentes porque cada
    valor de R en R2 tiene exactamente un valor de D en R1.

PROTOCOLO DE SEGURIDAD
  Todo el script esta encapsulado en BEGIN ... COMMIT.
  Para ejecutar en modo prueba, reemplazar COMMIT por ROLLBACK.

IDEMPOTENCIA
  - CREATE TABLE IF NOT EXISTS  -- no falla si la tabla ya existe
  - ON CONFLICT ... DO NOTHING  -- no duplica filas en reinserciones
  - DROP DOMAIN IF EXISTS ... CASCADE antes de cada CREATE DOMAIN,
    ya que PostgreSQL no admite CREATE DOMAIN IF NOT EXISTS

COMPATIBILIDAD DE CODIFICACION
  Los comentarios del encabezado usan exclusivamente caracteres ASCII
  para garantizar compatibilidad con codificaciones WIN1252 y UTF-8
  en cualquier cliente psql. Los literales de datos con acentos en los
  INSERT son seguros porque se procesan dentro de la transaccion ya
  iniciada.
=============================================================================
*/

BEGIN;

-- ============================================================
-- PASO 0.A -- DOMINIOS REUTILIZABLES
-- ============================================================
-- Los dominios de PostgreSQL (CREATE DOMAIN) centralizan las
-- reglas de validacion en un unico lugar. Cualquier tabla futura
-- que use el mismo tipo de dato hereda la restriccion sin repetir
-- el CHECK en cada columna.
--
-- Se usa DROP ... IF EXISTS CASCADE para idempotencia: si el
-- dominio ya existe de una ejecucion anterior, se reemplaza.
-- CASCADE elimina las dependencias antes de recrearlo; los datos
-- almacenados no se ven afectados porque el DROP solo elimina
-- la definicion de tipo, no las filas de las tablas.
-- ============================================================

-- ----------------------------------------------------------
-- codigo_producto_dom
-- Acepta codigos alfanumericos en mayusculas con guiones internos.
-- Regla: primer y ultimo caracter deben ser [A-Z0-9]; los
-- intermedios tambien pueden ser guion. Longitud: 2 a 50 chars.
-- Valido:   PROD-01, ABC-123, X1-Y2
-- Invalido: prod-01 (minusculas), -PROD (guion inicial),
--           PROD- (guion final), P (un solo caracter)
-- ----------------------------------------------------------
DROP DOMAIN IF EXISTS codigo_producto_dom CASCADE;
CREATE DOMAIN codigo_producto_dom AS VARCHAR(50)
    CONSTRAINT ck_codigo_producto_formato
        CHECK (VALUE ~ '^[A-Z0-9][A-Z0-9\-]{1,48}[A-Z0-9]$');

-- ----------------------------------------------------------
-- dni_arg_dom
-- DNI argentino: exactamente 7 u 8 digitos numericos.
-- Rechaza puntos, espacios, letras y guiones.
-- Valido:   30111222, 7654321
-- Invalido: 30.111.222, 3011122A, 301112223 (9 digitos)
-- ----------------------------------------------------------
DROP DOMAIN IF EXISTS dni_arg_dom CASCADE;
CREATE DOMAIN dni_arg_dom AS VARCHAR(20)
    CONSTRAINT ck_dni_arg_formato
        CHECK (VALUE ~ '^\d{7,8}$');


-- ============================================================
-- PASO 0.B -- TABLAS MAESTRAS PREVIAS
-- ============================================================
-- Estas tablas son catalogos de referencia independientes del
-- modelo a analizar. Se crean con IF NOT EXISTS para idempotencia.
-- Las FKs de las tablas del experimento apuntan a estas entidades.
-- ============================================================

-- ----------------------------------------------------------
-- deposito: almacen fisico identificado por nombre y ubicacion.
-- Es el determinado de la DF problematica:
--   responsable_control_id -> deposito_id  (DF2)
--
-- CHECK (capacidad > 0): una capacidad nula o negativa carece
-- de sentido fisico para un almacen real.
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS deposito (
    id        BIGINT        PRIMARY KEY,
    nombre    VARCHAR(100)  NOT NULL,
    ubicacion VARCHAR(255)  NOT NULL,
    capacidad INT           NOT NULL
        CONSTRAINT chk_deposito_capacidad CHECK (capacidad > 0)
);

-- ----------------------------------------------------------
-- lote: unidad de trazabilidad de un producto con vencimiento.
-- Representa el lado "muchos" de la relacion original (atributo L).
--
-- codigo_producto usa el dominio codigo_producto_dom para validar
-- el formato estructurado (ej. PROD-01) sin repetir el CHECK.
--
-- fecha_vencimiento es DATE (no TIMESTAMPTZ): la caducidad legal
-- de un alimento se expresa como dia calendario, no como instante
-- con hora y zona horaria. La comparacion de negocio relevante es
-- "fecha_vencimiento < CURRENT_DATE", que opera sobre fechas puras.
--
-- CHECK (fecha_vencimiento >= CURRENT_DATE): impide registrar
-- lotes ya vencidos al momento de la insercion.
-- NOTA: los datos de prueba usan fechas en 2027 para superar
-- esta validacion durante la ejecucion en 2026.
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS lote (
    id                 BIGINT                PRIMARY KEY,
    codigo_producto    codigo_producto_dom   NOT NULL,
    fecha_vencimiento  DATE                  NOT NULL
        CONSTRAINT chk_lote_vencimiento CHECK (fecha_vencimiento >= CURRENT_DATE)
);

-- ----------------------------------------------------------
-- responsable_control: empleado que audita un deposito.
-- Es el determinante de la DF problematica (atributo R en DF2).
--
-- dni usa el dominio dni_arg_dom (7-8 digitos numericos).
-- UNIQUE en dni: clave candidata del mundo real.
-- CHECK en mail: formato minimo de email (algo@dominio.tld).
-- nombre_completo con mayor longitud que nombre simple porque
-- incluye nombre y apellido completos.
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS responsable_control (
    id              BIGINT        PRIMARY KEY,
    dni             dni_arg_dom   NOT NULL UNIQUE,
    mail            VARCHAR(100)  NOT NULL
        CONSTRAINT chk_responsable_mail
            CHECK (mail ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    nombre_completo VARCHAR(150)  NOT NULL
);


-- ============================================================
-- PASO 0.C -- DATOS MAESTROS DE PRUEBA
-- ============================================================
-- ON CONFLICT (id) DO NOTHING garantiza idempotencia:
-- si el registro ya existe no falla ni duplica.
-- ============================================================

INSERT INTO deposito (id, nombre, ubicacion, capacidad)
VALUES
    (30, 'Deposito Central', 'Mendoza',    10000),
    (31, 'Deposito Sur',     'San Martin',  5000)
ON CONFLICT (id) DO NOTHING;

-- Fechas en 2027 para superar el CHECK chk_lote_vencimiento
-- durante ejecuciones en 2026.
INSERT INTO lote (id, codigo_producto, fecha_vencimiento)
VALUES
    (501, 'PROD-01', '2027-12-31'),
    (502, 'PROD-02', '2027-11-15'),
    (503, 'PROD-03', '2027-10-20')
ON CONFLICT (id) DO NOTHING;

INSERT INTO responsable_control (id, dni, mail, nombre_completo)
VALUES
    (801, '30111222', 'carlos@foodstore.com', 'Carlos Gomez'),
    (802, '32333444', 'ana@foodstore.com',    'Ana Lopez')
ON CONFLICT (id) DO NOTHING;


-- ============================================================
-- PASO 1 -- ESQUEMA ORIGINAL DEFECTUOSO (PRE-FNBC)
-- ============================================================
-- control_lote_almacen(L, D, R) con PK compuesta (L, D).
--
-- INSTANCIA DE PRUEBA:
--   lote_id | deposito_id | responsable_control_id
--   --------+-------------+-----------------------
--     501   |     30      |  801
--     502   |     30      |  801  <- mismo responsable, mismo deposito
--     503   |     31      |  802
--
-- ANOMALIA VISIBLE:
--   El par (responsable=801, deposito=30) aparece en dos filas.
--   Esto evidencia DF2: R -> D. Si Carlos cambia de deposito,
--   habria que actualizar multiples filas; una actualizacion parcial
--   dejaria la base en estado inconsistente (anomalia de actualizacion).
--
-- Esta tabla se conserva en el script porque:
--   1. Es el sujeto del analisis FNBC.
--   2. Sirve como oraculo en la prueba lossless-join del Paso 5.
-- ============================================================

CREATE TABLE IF NOT EXISTS control_lote_almacen (
    lote_id                 BIGINT  NOT NULL
        REFERENCES lote(id),
    deposito_id             BIGINT  NOT NULL
        REFERENCES deposito(id),
    responsable_control_id  BIGINT  NOT NULL
        REFERENCES responsable_control(id),
    PRIMARY KEY (lote_id, deposito_id)
);

-- Tuplas de la instancia provista en el enunciado.
INSERT INTO control_lote_almacen
    (lote_id, deposito_id, responsable_control_id)
VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802)
ON CONFLICT DO NOTHING;


-- ============================================================
-- PASO 2 -- DESCOMPOSICION EN FNBC
-- ============================================================
-- Se aplica el Teorema de Heath sobre DF2: R -> D.
--
-- Heath: R(L,D,R) con DF2 R -> D se descompone sin perdida en:
--   R1 = pi{R,D}(R)  -->  responsable_deposito(R, D)
--   R2 = pi{L,R}(R)  -->  control_lote_responsable(L, R)
--
-- Verificacion FNBC de R1:
--   Unica DF no trivial: R -> D.  R es PK --> superclave.  FNBC OK
--
-- Verificacion FNBC de R2:
--   Sin atributos no-clave adicionales. PK {L,R} --> superclave. FNBC OK
-- ============================================================

-- R1 ---------------------------------------------------------
-- Aisla la DF problematica: responsable_control_id -> deposito_id.
-- La PK es responsable_control_id (el determinante de DF2), lo que
-- garantiza que cada responsable tenga exactamente un deposito
-- asignado: la redundancia desaparece estructuralmente.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS responsable_deposito (
    responsable_control_id  BIGINT  PRIMARY KEY
        REFERENCES responsable_control(id),
    deposito_id             BIGINT  NOT NULL
        REFERENCES deposito(id)
);

-- R2 ---------------------------------------------------------
-- Conserva el vinculo entre lote y responsable (L, R).
-- PK compuesta: (lote_id, responsable_control_id).
--
-- DECISION CRITICA: la FK de R2 apunta a responsable_deposito
-- (R1), no a responsable_control directamente.
-- Razon: garantiza que solo se puedan vincular responsables
-- cuya asignacion de deposito ya existe en R1, lo que hace
-- posible la reunion natural sin tuplas espurias.
-- Sin esta referencia cruzada, la reunion podria producir
-- tuplas espurias si un responsable existiera en
-- responsable_control pero no en responsable_deposito.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS control_lote_responsable (
    lote_id                 BIGINT  NOT NULL
        REFERENCES lote(id),
    responsable_control_id  BIGINT  NOT NULL
        REFERENCES responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
);


-- ============================================================
-- PASO 3 -- VISTA DE COMPATIBILIDAD
-- ============================================================
-- Reconstituye la proyeccion original (L, D, R) mediante la
-- reunion natural de R1 y R2 sobre responsable_control_id.
-- Esta es exactamente la operacion inversa de la descomposicion
-- por Teorema de Heath: R1 join R2 = control_lote_almacen.
--
-- Proposito dual:
--   1. Compatibilidad hacia atras: el codigo existente que
--      consulta control_lote_almacen no requiere cambios
--      inmediatos durante la transicion al nuevo esquema.
--   2. Oraculo para la prueba lossless-join del Paso 5: si la
--      vista produce exactamente las mismas tuplas que la tabla
--      original, la descomposicion es sin perdida.
-- ============================================================

CREATE OR REPLACE VIEW vw_control_lote_almacen_compatibilidad AS
SELECT
    clr.lote_id,
    rd.deposito_id,
    clr.responsable_control_id
FROM control_lote_responsable  clr
JOIN responsable_deposito       rd
    ON clr.responsable_control_id = rd.responsable_control_id;


-- ============================================================
-- PASO 4 -- MIGRACION DE DATOS A LAS TABLAS FNBC
-- ============================================================
-- Se pueblan R1 y R2 desde la instancia original.
-- El orden es obligatorio: R2 tiene FK hacia R1.
--
-- Migracion a R1:
--   SELECT DISTINCT colapsa las dos filas donde responsable=801
--   aparecia con deposito=30 en una unica fila (801, 30).
--   Sin DISTINCT, la insercion fallaria por violacion de PK
--   porque el par (801, 30) aparece dos veces en la instancia.
--   Esto es exactamente la correccion que FNBC exige: el hecho
--   "Carlos trabaja en el Deposito Central" se almacena una vez.
--
-- Migracion a R2:
--   Las tres filas de la instancia original se migran completas
--   porque el par (lote_id, responsable_control_id) es unico.
--
-- ON CONFLICT DO NOTHING garantiza idempotencia al reejecutar.
-- ============================================================

-- Poblar R1: pares unicos (responsable -> deposito)
INSERT INTO responsable_deposito
    (responsable_control_id, deposito_id)
SELECT DISTINCT
    responsable_control_id,
    deposito_id
FROM control_lote_almacen
ON CONFLICT DO NOTHING;

-- Poblar R2: pares (lote, responsable)
INSERT INTO control_lote_responsable
    (lote_id, responsable_control_id)
SELECT
    lote_id,
    responsable_control_id
FROM control_lote_almacen
ON CONFLICT DO NOTHING;


-- ============================================================
-- PASO 5 -- VERIFICACION DE REUNION SIN PERDIDA (LOSSLESS-JOIN)
-- ============================================================
-- JUSTIFICACION TEORICA (Punto 4.2.f -- Teorema de Heath)
-- --------------------------------------------------------
-- La propiedad lossless-join esta garantizada matematicamente
-- porque el atributo comun de la reunion, responsable_control_id
-- (R), es la clave primaria de R1 (responsable_deposito).
--
-- Argumento formal:
--   Atributos(R1) interseccion Atributos(R2) = {R}
--   PK(R1) = {R}  -->  R es superclave de R1
--   DF valida: R -> D pertenece al conjunto de DFs
--
--   Por Teorema de Heath: si el atributo comun es superclave
--   en alguna de las tablas descompuestas, entonces
--   R1 join R2 = relacion_original  (sin perdida, sin espurias)
--
-- Consecuencia practica:
--   Cada valor de R en R2 tiene exactamente un valor de D en R1
--   (garantizado por la PK de R1). Por eso el JOIN no puede
--   "inventar" nuevas combinaciones (L, D, R); solo reconstruye
--   las que existian en la instancia original.
--
-- VERIFICACION PRACTICA con EXCEPT en ambas direcciones
-- -------------------------------------------------------
-- EXCEPT elimina duplicados y compara conjuntos de tuplas.
-- Si los dos conjuntos son identicos, ambas direcciones
-- devuelven el conjunto vacio (0 filas).
--
-- Interpretacion de los resultados:
--   Direccion A devuelve filas --> la vista contiene tuplas que
--     no estaban en el original (tuplas espurias: JOIN incorrecto)
--   Direccion B devuelve filas --> hay tuplas en el original que
--     la descomposicion no puede reconstruir (perdida de datos)
--   Ambas devuelven 0 filas --> descomposicion lossless-join OK
-- ============================================================

-- ----------------------------------------------------------
-- Direccion A: vw_compatibilidad EXCEPT original
-- Comprueba que la vista NO contiene tuplas espurias.
-- Una tupla espuria seria una combinacion (lote, deposito,
-- responsable) que el JOIN invento y que no existia en la
-- relacion original. Resultado esperado: (0 rows).
-- Envuelto en subquery para compatibilidad con DBeaver,
-- que agrega LIMIT automaticamente al final de cada SELECT.
-- ----------------------------------------------------------
SELECT * FROM (
    SELECT
        lote_id,
        deposito_id,
        responsable_control_id
    FROM vw_control_lote_almacen_compatibilidad

    EXCEPT

    SELECT
        lote_id,
        deposito_id,
        responsable_control_id
    FROM control_lote_almacen
) dir_a;

-- ----------------------------------------------------------
-- Direccion B: original EXCEPT vw_compatibilidad
-- Comprueba que NO se perdio ninguna tupla de la relacion
-- original durante la descomposicion y migracion. Una fila
-- aqui significaria que esa tupla no puede ser reconstruida
-- por la reunion R1 join R2. Resultado esperado: (0 rows).
-- Envuelto en subquery por la misma razon que Direccion A.
-- ----------------------------------------------------------
SELECT * FROM (
    SELECT
        lote_id,
        deposito_id,
        responsable_control_id
    FROM control_lote_almacen

    EXCEPT

    SELECT
        lote_id,
        deposito_id,
        responsable_control_id
    FROM vw_control_lote_almacen_compatibilidad
) dir_b;

COMMIT;

-- PARTE 2
EXPLAIN ANALYZE
SELECT c.nombre AS categoria,
       SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido -- No hay columna 'subtotal' en dp; lo calculamos acá
FROM detalle_pedido dp
JOIN producto pr      ON pr.id_producto  = dp.id_producto
JOIN categoria c      ON c.id_categoria  = pr.id_categoria
JOIN pedido ped       ON ped.id_pedido   = dp.id_pedido
WHERE DATE(ped.fecha_hora) = CURRENT_DATE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;

-- ============================================================
-- LIMPIEZA TEMPORAL (ejecutar manualmente en caso de error)
-- Orden obligatorio: primero objetos dependientes, luego padres.
-- ============================================================

-- ROLLBACK;
-- DROP VIEW IF EXISTS vw_control_lote_almacen_compatibilidad;

-- DROP TABLE IF EXISTS control_lote_responsable;
-- DROP TABLE IF EXISTS responsable_deposito;
-- DROP TABLE IF EXISTS control_lote_almacen;

-- DROP TABLE IF EXISTS responsable_control;
-- DROP TABLE IF EXISTS lote;
-- DROP TABLE IF EXISTS deposito;

-- DROP DOMAIN IF EXISTS codigo_producto_dom;
-- DROP DOMAIN IF EXISTS dni_arg_dom;


