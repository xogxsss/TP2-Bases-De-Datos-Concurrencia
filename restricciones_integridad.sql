-- SQLBook: Code


-- =============================================================================
-- RESTRICCIONES DE INTEGRIDAD ADICIONALES - FOOD STORE
-- Archivo: restricciones_integridad.sql
-- Motor: PostgreSQL
-- =============================================================================

-- -----------------------------------------------------------------------------
-- REGLA 1: La fecha_hora de pedido no puede ser futura
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_validar_fecha_pedido()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.fecha_hora > now() THEN
        RAISE EXCEPTION 'La fecha y hora del pedido (%) no puede ser posterior a la fecha/hora actual (%)', NEW.fecha_hora, now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_fecha_pedido ON pedido;

CREATE TRIGGER trg_validar_fecha_pedido
BEFORE INSERT OR UPDATE ON pedido
FOR EACH ROW
EXECUTE FUNCTION fn_validar_fecha_pedido();


-- -----------------------------------------------------------------------------
-- REGLA 2: No agregar productos inactivos en el detalle de pedido
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_validar_producto_activo()
RETURNS TRIGGER AS $$
DECLARE
    v_activo BOOLEAN;
BEGIN
    SELECT activo INTO v_activo 
    FROM producto 
    WHERE id_producto = NEW.id_producto;

    IF v_activo IS FALSE THEN
        RAISE EXCEPTION 'No se puede agregar el producto (ID %) al detalle porque está inactivo (activo = FALSE)', NEW.id_producto;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_producto_activo ON detalle_pedido;

CREATE TRIGGER trg_validar_producto_activo
BEFORE INSERT ON detalle_pedido
FOR EACH ROW
EXECUTE FUNCTION fn_validar_producto_activo();


-- Probar que las excepciones de OpenCode funcionan (Transacción aislada)

-- PRUEBA 1: Probar fecha futura en pedido
BEGIN;
INSERT INTO pedido (fecha_hora, forma_pago, id_cliente) 
VALUES (NOW() + INTERVAL '2 days', 'EFECTIVO', 1);
-- (Acá PostgreSQL debe tirar la excepción del trigger de OpenCode)
ROLLBACK;


-- PRUEBA 2: Probar producto inactivo
BEGIN;
UPDATE producto SET activo = FALSE WHERE id_producto = 2; -- Desactivamos la Coca-Cola

INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico) 
VALUES (1, 2, 1, 800.00);
-- (Acá PostgreSQL debe tirar la excepción del trigger de OpenCode)
ROLLBACK;
