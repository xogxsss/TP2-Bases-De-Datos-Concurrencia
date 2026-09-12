-- SQLBook: Code


/*
=============================================================================
ESQUEMA DEFINITIVO - FOOD STORE
Archivo: schema.sql
Motor: PostgreSQL
=============================================================================
*/

/* Limpieza de esquema previa (permite reejecución limpia) */
DROP TABLE IF EXISTS detalle_pedido CASCADE;
DROP TABLE IF EXISTS pedido CASCADE;
DROP TABLE IF EXISTS cliente CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;
DROP TYPE IF EXISTS forma_pago_enum CASCADE;

/*
-----------------------------------------------------------------------------
TIPOS ENUMERADOS
-----------------------------------------------------------------------------
Dominio cerrado para las formas de pago permitidas en el negocio.
Creamos el ENUM para utilizarlo luego en la tabla `pedido`
Esto nos proporciona ventajas como:
Legibilidad, orden, reutilización, consistencia, etc.
*/
CREATE TYPE forma_pago_enum AS ENUM ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA');


/*
-----------------------------------------------------------------------------
TABLA: CATEGORIA
-----------------------------------------------------------------------------
'BIGINT GENERATED ALWAYS AS IDENTITY'
Es la forma moderna de PostgreSQL de autoincrementar una PK
Protege la columna de que no se ingresen datos manualmente
*/
CREATE TABLE categoria (
    id_categoria BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, 
    nombre VARCHAR(80) NOT NULL UNIQUE,
    activo BOOLEAN NOT NULL DEFAULT TRUE
);


/*
-----------------------------------------------------------------------------
TABLA: PRODUCTO
-----------------------------------------------------------------------------
*/
/*
UNIQUE
Especifica la unicidad y no nulidad de la columna, en este caso `nombre`
*/

/*
DEFAULT
Asigna un valor por defecto en caso de no darle un valor a esa columna
`activo` -> TRUE (valor booleano)
`stock` -> 0 (valor numérico)
*/

/*
NUMERIC Y DECIMAL
Son exactamente lo mismo; evitan errores de redondeo, garantizando exactitud
a diferencia de REAL o DOUBLE PRECISION
Sintaxis: NUMERIC/DECIMAL(precisión, escala)
Presición -> Límite máximo de dígitos antes y después de la coma.
Escala -> Límite máximo de dígitos para la parte decimal.
*/

/*
CONSTRAINT
Agrega limitaciones; le ponemos nombre a una 'regla'

- CHECK:
  Se asegura de cumplir determinado criterio o regla de negocio.
  Por ejemplo: el precio/stock del producto no puede ser menor a 0.

- FK -> `producto_categoria`:
  Relaciona obligatoriamente a producto y categoría para que un
  producto no exista sin categoría o que tenga una que no esté registrada en el sistema.

- ON DELETE RESTRICT:
  Sirve como guardia de seguridad: 
  Si intentamos eliminar una categoría con productos aún relacionados a ella por accidente,
  se bloquea el borrado para conservar el historial u otros casos.
  Es decir, bloquea la eliminación de un registro principal si todavía hay datos dependientes de él,
  protegiendo la integridad del historial.
*/
CREATE TABLE producto (
    id_producto BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT NULL,
    precio_lista NUMERIC(10, 2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    id_categoria BIGINT NOT NULL,

    CONSTRAINT chk_producto_precio CHECK (precio_lista >= 0),
    CONSTRAINT chk_producto_stock CHECK (stock >= 0),
    CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria) 
        REFERENCES categoria (id_categoria) ON DELETE RESTRICT
);


/*
-----------------------------------------------------------------------------
TABLA: CLIENTE
-----------------------------------------------------------------------------
PK y Clave Candidata (o Identificador Único)
Una tabla puede tener ambas: 
- PK -> Usada como identificador interno de la BD para acceder a los datos. Es inmutable.
- Clave Candidata -> Regla de negocio del mundo real. Cada cliente se identifica a través de su email.
  Es mutable (se recomienda buscar un dato que no cambie o que no cambie tanto, como el DNI, por ejemplo).
*/
CREATE TABLE cliente (
    id_cliente BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE, /* Requisito R6: Identificador único / Clave candidata */
    nombre VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NULL,
    direccion VARCHAR(200) NOT NULL
);


/*
-----------------------------------------------------------------------------
TABLA: PEDIDO
-----------------------------------------------------------------------------
- forma_pago forma_pago_enum NOT NULL:
  Utilizamos el ENUM creado al principio para definir `forma_pago`.

- `fk_pedido_cliente`:
  Relacionamos sí o sí un pedido a un cliente.
*/
CREATE TABLE pedido (
    id_pedido BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT now(),
    forma_pago forma_pago_enum NOT NULL,
    id_cliente BIGINT NOT NULL,
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (id_cliente) 
        REFERENCES cliente (id_cliente) ON DELETE RESTRICT
);


/*
-----------------------------------------------------------------------------
TABLA: DETALLE_PEDIDO (Tabla Intermedia N:M)
-----------------------------------------------------------------------------
*/
CREATE TABLE detalle_pedido (
    /* PK compuesta -> pedido + producto */
    id_pedido BIGINT NOT NULL,
    id_producto BIGINT NOT NULL,
    
    /* La cantidad debe ser mayor al valor 0 */
    cantidad INT NOT NULL,
    
    /* El precio debe tener una longitud máxima de 10, con 2 decimales. Puede ser igual o mayor a 0. */
    precio_unitario_historico NUMERIC(10, 2) NOT NULL,
    

    CONSTRAINT pk_detalle_pedido PRIMARY KEY (id_pedido, id_producto),

    CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT chk_detalle_precio CHECK (precio_unitario_historico >= 0),

    /* 
    El detalle de un pedido está ligado sí o sí a un pedido a través de su id (fk); y también al id de un producto. 
    Si eliminamos un producto/pedido ligado a un detalle de pedido, se bloquea la eliminación.
    */
    CONSTRAINT fk_detalle_pedido FOREIGN KEY (id_pedido) 
        REFERENCES pedido (id_pedido) ON DELETE RESTRICT,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto) 
        REFERENCES producto (id_producto) ON DELETE RESTRICT
);


/*
-----------------------------------------------------------------------------
ÍNDICES (Optimización de Consultas Frecuentes)
-----------------------------------------------------------------------------
*/

/* 
Acelera el listado de pedidos de un cliente específico (ej. historial de compras)
Creamos un índice para acceder más rápido al id de un cliente en la tabla `pedido`
*/
CREATE INDEX idx_pedido_cliente ON pedido (id_cliente);

/* 
Acelera la búsqueda de productos vigentes y en stock filtrados por su categoría (pantalla del menú)
Creamos un índice para acceder a las categorías activas
*/
CREATE INDEX idx_producto_categoria_activo ON producto (id_categoria, activo) WHERE activo = TRUE;

/* Datos iniciales de prueba -> TP2 */
INSERT INTO categoria (nombre) VALUES ('Pizzas'), ('Bebidas');

INSERT INTO producto (nombre, precio_lista, stock, id_categoria) 
VALUES ('Muzzarella', 1000.00, 10, 1), ('Coca 1.5L', 800.00, 20, 2);

INSERT INTO cliente (email, nombre, direccion) 
VALUES ('ana@gmail.com', 'Ana Gómez', 'Calle Falsa 123');

INSERT INTO pedido (forma_pago, id_cliente) 
VALUES ('EFECTIVO', 1);

INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico) 
VALUES (1, 1, 2, 1000.00);
