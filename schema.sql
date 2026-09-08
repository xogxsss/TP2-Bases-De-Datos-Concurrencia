-- SQLBook: Code
-- Active: 1788182283344@@127.0.0.1@5432@postgres
-- =============================================================================
-- ESQUEMA DEFINITIVO - FOOD STORE
-- Archivo: schema.sql
-- Motor: PostgreSQL
-- =============================================================================

-- Limpieza de esquema previa (permite reejecución limpia)
DROP TABLE IF EXISTS detalle_pedido CASCADE;
DROP TABLE IF EXISTS pedido CASCADE;
DROP TABLE IF EXISTS cliente CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;
DROP TYPE IF EXISTS forma_pago_enum CASCADE;

-- -----------------------------------------------------------------------------
-- TIPOS ENUMERADOS
-- -----------------------------------------------------------------------------
-- Dominio cerrado para las formas de pago permitidas en el negocio.
CREATE TYPE forma_pago_enum AS ENUM ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA');


-- -----------------------------------------------------------------------------
-- TABLA: CATEGORIA
-- -----------------------------------------------------------------------------
CREATE TABLE categoria (
    id_categoria BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    activo BOOLEAN NOT NULL DEFAULT TRUE
);


-- -----------------------------------------------------------------------------
-- TABLA: PRODUCTO
-- -----------------------------------------------------------------------------
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


-- -----------------------------------------------------------------------------
-- TABLA: CLIENTE
-- -----------------------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE, -- Requisito R6: Identificador único / Clave candidata
    nombre VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NULL,
    direccion VARCHAR(200) NOT NULL
);


-- -----------------------------------------------------------------------------
-- TABLA: PEDIDO
-- -----------------------------------------------------------------------------
CREATE TABLE pedido (
    id_pedido BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT now(),
    forma_pago forma_pago_enum NOT NULL,
    id_cliente BIGINT NOT NULL,
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (id_cliente) 
        REFERENCES cliente (id_cliente) ON DELETE RESTRICT
);


-- -----------------------------------------------------------------------------
-- TABLA: DETALLE_PEDIDO (Tabla Intermedia N:M)
-- -----------------------------------------------------------------------------
CREATE TABLE detalle_pedido (
    id_pedido BIGINT NOT NULL,
    id_producto BIGINT NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario_historico NUMERIC(10, 2) NOT NULL,
    

    CONSTRAINT pk_detalle_pedido PRIMARY KEY (id_pedido, id_producto),

    CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT chk_detalle_precio CHECK (precio_unitario_historico >= 0),

    CONSTRAINT fk_detalle_pedido FOREIGN KEY (id_pedido) 
        REFERENCES pedido (id_pedido) ON DELETE RESTRICT,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto) 
        REFERENCES producto (id_producto) ON DELETE RESTRICT
);


-- -----------------------------------------------------------------------------
-- ÍNDICES (Optimización de Consultas Frecuentes)
-- -----------------------------------------------------------------------------

-- Acelera el listado de pedidos de un cliente específico (ej. historial de compras)
CREATE INDEX idx_pedido_cliente ON pedido (id_cliente);

-- Acelera la búsqueda de productos vigentes y en stock filtrados por su categoría (pantalla del menú)
CREATE INDEX idx_producto_categoria_activo ON producto (id_categoria, activo) WHERE activo = TRUE;

-- Datos iniciales de prueba -> TP2
INSERT INTO categoria (nombre) VALUES ('Pizzas'), ('Bebidas');

INSERT INTO producto (nombre, precio_lista, stock, id_categoria) 
VALUES ('Muzzarella', 1000.00, 10, 1), ('Coca 1.5L', 800.00, 20, 2);

INSERT INTO cliente (email, nombre, direccion) 
VALUES ('ana@gmail.com', 'Ana Gómez', 'Calle Falsa 123');

INSERT INTO pedido (forma_pago, id_cliente) 
VALUES ('EFECTIVO', 1);

INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico) 
VALUES (1, 1, 2, 1000.00);

