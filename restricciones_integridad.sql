-- SQLBook: Code
-- =============================================================================
-- RESTRICCIONES DE INTEGRIDAD ADICIONALES - FOOD STORE
-- Archivo: restricciones_integridad.sql
-- Motor: PostgreSQL
-- =============================================================================

-- -----------------------------------------------------------------------------
-- REGLA 1: La fecha_hora de pedido no puede ser futura
-- -----------------------------------------------------------------------------
/*
`CREATE OR REPLACE FUNCTION fn_validar_fecha_pedido()`
Crea o sobreescribe una función en el motor bajo ese nombre (`fn_validar_fecha_pedido`)

`RETURNS TRIGGER AS $$` ... `$$
Delimitamos la función en un bloque de código que será considerado un TRIGGER al momento de usarse.

`BEGIN` y `END`
Si bien la línea anterior delimita una función, estas palabras reservadas indican
el inicio y fin de un bloque de código ejecutable.

`IF NEW.fecha_hora > now() THEN`: Si la fecha que querés cargar es mayor al momento exacto de ahora...
`RAISE EXCEPTION ...`: ...frená todo, cancelá la operación y tirá un error informando que no se puede.
`END IF;`: Acá cierra la validación.
`RETURN NEW;`: Si pasó la prueba bien, dejá que el registro se guarde tal cual.
*/
CREATE OR REPLACE FUNCTION fn_validar_fecha_pedido()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.fecha_hora > now() THEN
        RAISE EXCEPTION 'La fecha y hora del pedido (%) no puede ser posterior a la fecha/hora actual (%)', NEW.fecha_hora, now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

/*
    Borra el disparador anterior si ya existía en `pedido`para que no se duplique
    o genere error al volver a ejecutar el script de creación.
*/
DROP TRIGGER IF EXISTS trg_validar_fecha_pedido ON pedido;

/*
`CREATE TRIGGER trg_validar_fecha_pedido`: Registra y activa oficialmente el disparador en la base de datos bajo ese nombre.

`BEFORE INSERT OR UPDATE ON pedido`: Define que la regla se ejecute de forma preventiva **antes** de insertar un registro nuevo o modificar uno existente en la tabla `pedido`.

`FOR EACH ROW`: Indica que el trigger se va a aplicar **fila por fila**, evaluando individualmente cada registro afectado por la sentencia SQL.

`EXECUTE FUNCTION fn_validar_fecha_pedido();`: Conecta el disparador con la función PL/pgSQL que programamos antes para que se encargue de hacer la validación de la fecha.
*/
CREATE TRIGGER trg_validar_fecha_pedido
BEFORE INSERT OR UPDATE ON pedido
FOR EACH ROW
EXECUTE FUNCTION fn_validar_fecha_pedido();


-- -----------------------------------------------------------------------------
-- REGLA 2: No agregar productos inactivos en el detalle de pedido
-- -----------------------------------------------------------------------------

/*
`CREATE OR REPLACE FUNCTION fn_validar_producto_activo()`: Crea o sobrescribe la función encargada de verificar que el producto esté habilitado.
`DECLARE v_activo BOOLEAN;`: Declara una variable local para almacenar el estado booleano del producto.
`SELECT activo INTO v_activo ... WHERE id_producto = NEW.id_producto;`: Consulta el estado actual del producto que se intenta comprar.
`IF v_activo IS FALSE THEN RAISE EXCEPTION ... END IF;`: Si el producto está inactivo, frena la operación y lanza un error descriptivo.
`RETURN NEW;`: Si está activo, permite que el registro avance con normalidad.
*/
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

/*
`DROP TRIGGER IF EXISTS ...`: Limpia cualquier versión previa del disparador en la tabla `detalle_pedido`.
*/
DROP TRIGGER IF EXISTS trg_validar_producto_activo ON detalle_pedido;

/*
`CREATE TRIGGER trg_validar_producto_activo`: Registra el disparador de validación de productos.
`BEFORE INSERT ON detalle_pedido`: Se ejecuta preventivamente antes de insertar nuevos ítems en el detalle.
`FOR EACH ROW`: Evalúa cada fila de forma individual.
`EXECUTE FUNCTION fn_validar_producto_activo();`: Asocia el trigger a la función de validación escrita arriba.
*/
CREATE TRIGGER trg_validar_producto_activo
BEFORE INSERT ON detalle_pedido
FOR EACH ROW
EXECUTE FUNCTION fn_validar_producto_activo();


-- Probar que las excepciones de OpenCode funcionan (Transacción aislada)

-- PRUEBA 1: Probar fecha futura en pedido
/*
`BEGIN;`: Abre una transacción aislada para proteger los datos de prueba.
`INSERT INTO pedido ... VALUES (NOW() + INTERVAL '2 days', ...)`: Intenta ingresar un pedido con fecha del futuro para forzar el salto del trigger 1.
`ROLLBACK;`: Revierte los cambios de la prueba para dejar la base de datos intacta.
*/
BEGIN;
INSERT INTO pedido (fecha_hora, forma_pago, id_cliente) 
VALUES (NOW() + INTERVAL '2 days', 'EFECTIVO', 1);
-- (Acá PostgreSQL debe tirar la excepción del trigger de OpenCode)
ROLLBACK;


-- PRUEBA 2: Probar producto inactivo
/*
`BEGIN;`: Inicia un bloque transaccional de prueba.
`UPDATE producto SET activo = FALSE ...`: Desactiva un producto específico de forma temporal para la prueba.
`INSERT INTO detalle_pedido ...`: Intenta registrar una compra de ese producto inactivo para forzar el salto del trigger 2.
`ROLLBACK;`: Deshace todas las modificaciones de la prueba.
*/
BEGIN;
UPDATE producto SET activo = FALSE WHERE id_producto = 2; -- Desactivamos la Coca-Cola

INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico) 
VALUES (1, 2, 1, 800.00);
-- (Acá PostgreSQL debe tirar la excepción del trigger de OpenCode)
ROLLBACK;