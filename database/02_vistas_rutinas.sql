-- =====================================================================
--  DrogueriaGestión
--  Script 02: Vistas, función, disparadores (triggers) y procedimientos
-- =====================================================================

USE drogueria_gestion;

-- ---------------------------------------------------------------------
--  VISTA: existencias consolidadas por medicamento.
--  Solo cuentan como disponibles los lotes que no han vencido.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_stock_medicamentos AS
SELECT
    m.id_medicamento,
    m.codigo,
    m.nombre,
    m.principio_activo,
    m.concentracion,
    m.forma_farmaceutica,
    m.presentacion,
    m.laboratorio,
    m.registro_invima,
    m.id_categoria,
    c.nombre AS categoria,
    m.requiere_formula,
    m.es_controlado,
    m.precio_compra,
    m.precio_venta,
    m.iva_porcentaje,
    m.stock_minimo,
    m.ubicacion,
    m.activo,
    COALESCE(SUM(CASE WHEN l.fecha_vencimiento >= CURDATE() THEN l.cantidad_actual END), 0) AS stock_disponible,
    COALESCE(SUM(CASE WHEN l.fecha_vencimiento <  CURDATE() THEN l.cantidad_actual END), 0) AS stock_vencido,
    MIN(CASE WHEN l.cantidad_actual > 0 AND l.fecha_vencimiento >= CURDATE() THEN l.fecha_vencimiento END) AS proximo_vencimiento,
    CASE
        WHEN COALESCE(SUM(CASE WHEN l.fecha_vencimiento >= CURDATE() THEN l.cantidad_actual END), 0) = 0 THEN 'AGOTADO'
        WHEN COALESCE(SUM(CASE WHEN l.fecha_vencimiento >= CURDATE() THEN l.cantidad_actual END), 0) <= m.stock_minimo THEN 'BAJO'
        ELSE 'NORMAL'
    END AS estado_stock
FROM medicamentos m
JOIN categorias c ON c.id_categoria = m.id_categoria
LEFT JOIN lotes l ON l.id_medicamento = m.id_medicamento
GROUP BY m.id_medicamento, c.nombre;

-- ---------------------------------------------------------------------
--  VISTA: semáforo de vencimiento por lote.
--  VENCIDO (< hoy) | CRITICO (<= 30 días) | PROXIMO (<= 90 días) | VIGENTE
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_lotes_vencimiento AS
SELECT
    l.id_lote,
    l.numero_lote,
    l.id_medicamento,
    m.codigo,
    m.nombre AS medicamento,
    m.concentracion,
    m.forma_farmaceutica,
    c.nombre AS categoria,
    l.id_proveedor,
    p.razon_social AS proveedor,
    l.fecha_fabricacion,
    l.fecha_vencimiento,
    l.cantidad_inicial,
    l.cantidad_actual,
    l.costo_unitario,
    (l.cantidad_actual * l.costo_unitario) AS valor_costo,
    DATEDIFF(l.fecha_vencimiento, CURDATE()) AS dias_para_vencer,
    CASE
        WHEN l.fecha_vencimiento < CURDATE() THEN 'VENCIDO'
        WHEN DATEDIFF(l.fecha_vencimiento, CURDATE()) <= 30 THEN 'CRITICO'
        WHEN DATEDIFF(l.fecha_vencimiento, CURDATE()) <= 90 THEN 'PROXIMO'
        ELSE 'VIGENTE'
    END AS estado_vencimiento,
    l.fecha_ingreso
FROM lotes l
JOIN medicamentos m ON m.id_medicamento = l.id_medicamento
JOIN categorias c ON c.id_categoria = m.id_categoria
LEFT JOIN proveedores p ON p.id_proveedor = l.id_proveedor;

-- ---------------------------------------------------------------------
--  VISTA: ventas con el nombre del cliente y del vendedor
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ventas AS
SELECT
    v.id_venta,
    v.numero_factura,
    v.fecha_venta,
    v.id_cliente,
    CONCAT_WS(' ', c.nombres, c.apellidos) AS cliente,
    c.tipo_documento,
    c.numero_documento,
    v.id_usuario,
    CONCAT_WS(' ', u.nombres, u.apellidos) AS vendedor,
    v.subtotal,
    v.descuento,
    v.impuesto,
    v.total,
    v.metodo_pago,
    v.monto_recibido,
    v.cambio,
    v.formula_medica,
    v.medico,
    v.observaciones,
    v.estado,
    v.motivo_anulacion,
    v.fecha_anulacion,
    (SELECT COALESCE(SUM(d.cantidad), 0) FROM detalle_venta d WHERE d.id_venta = v.id_venta) AS unidades
FROM ventas v
JOIN clientes c ON c.id_cliente = v.id_cliente
JOIN usuarios u ON u.id_usuario = v.id_usuario;

-- ---------------------------------------------------------------------
--  VISTA: resumen diario de ventas efectivas (no anuladas)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ventas_diarias AS
SELECT
    DATE(fecha_venta)  AS fecha,
    COUNT(*)           AS numero_ventas,
    SUM(subtotal)      AS subtotal,
    SUM(descuento)     AS descuentos,
    SUM(impuesto)      AS impuestos,
    SUM(total)         AS total_ventas,
    ROUND(AVG(total), 2) AS ticket_promedio
FROM ventas
WHERE estado = 'COMPLETADA'
GROUP BY DATE(fecha_venta);

DELIMITER $$

-- ---------------------------------------------------------------------
--  FUNCIÓN: existencia disponible (no vencida) de un medicamento
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_stock_disponible$$
CREATE FUNCTION fn_stock_disponible(p_id_medicamento INT UNSIGNED)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_stock INT DEFAULT 0;

    SELECT COALESCE(SUM(cantidad_actual), 0)
      INTO v_stock
      FROM lotes
     WHERE id_medicamento = p_id_medicamento
       AND fecha_vencimiento >= CURDATE();

    RETURN v_stock;
END$$

-- ---------------------------------------------------------------------
--  TRIGGER: guarda el historial cuando cambia el precio de venta.
--  La aplicación asigna @app_id_usuario en cada conexión.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_medicamentos_precio_au$$
CREATE TRIGGER trg_medicamentos_precio_au
AFTER UPDATE ON medicamentos
FOR EACH ROW
BEGIN
    IF OLD.precio_venta <> NEW.precio_venta THEN
        INSERT INTO historial_precios (id_medicamento, precio_venta_anterior, precio_venta_nuevo, id_usuario)
        VALUES (NEW.id_medicamento, OLD.precio_venta, NEW.precio_venta, @app_id_usuario);
    END IF;
END$$

-- ---------------------------------------------------------------------
--  TRIGGER: valida en la base de datos cada línea dispensada.
--  Impide vender lotes vencidos, de otro medicamento o sin existencias.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_detalle_venta_bi$$
CREATE TRIGGER trg_detalle_venta_bi
BEFORE INSERT ON detalle_venta
FOR EACH ROW
BEGIN
    DECLARE v_id_medicamento INT UNSIGNED;
    DECLARE v_vencimiento DATE;
    DECLARE v_existencia INT UNSIGNED;

    SELECT id_medicamento, fecha_vencimiento, cantidad_actual
      INTO v_id_medicamento, v_vencimiento, v_existencia
      FROM lotes
     WHERE id_lote = NEW.id_lote;

    IF v_id_medicamento IS NULL OR v_id_medicamento <> NEW.id_medicamento THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El lote no corresponde al medicamento vendido';
    END IF;

    IF v_vencimiento < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede dispensar un lote vencido';
    END IF;

    IF NEW.cantidad > v_existencia THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Existencias insuficientes en el lote';
    END IF;
END$$

-- ---------------------------------------------------------------------
--  TRIGGER: una venta anulada no puede volver a modificarse
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_ventas_bu$$
CREATE TRIGGER trg_ventas_bu
BEFORE UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado = 'ANULADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Una venta anulada no puede modificarse';
    END IF;
END$$

-- ---------------------------------------------------------------------
--  PROCEDIMIENTO: da de baja todas las existencias vencidas,
--  dejando la trazabilidad en el kárdex. Devuelve lotes y unidades.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_dar_baja_lotes_vencidos$$
CREATE PROCEDURE sp_dar_baja_lotes_vencidos(IN p_id_usuario INT UNSIGNED)
BEGIN
    DECLARE v_lotes INT DEFAULT 0;
    DECLARE v_unidades INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT COUNT(*), COALESCE(SUM(cantidad_actual), 0)
      INTO v_lotes, v_unidades
      FROM lotes
     WHERE fecha_vencimiento < CURDATE()
       AND cantidad_actual > 0
     FOR UPDATE;

    INSERT INTO movimientos_inventario (id_lote, id_medicamento, tipo, cantidad, saldo_lote, motivo, id_usuario)
    SELECT id_lote, id_medicamento, 'BAJA_VENCIMIENTO', cantidad_actual, 0,
           CONCAT('Baja por vencimiento (', DATE_FORMAT(fecha_vencimiento, '%Y-%m-%d'), ')'), p_id_usuario
      FROM lotes
     WHERE fecha_vencimiento < CURDATE()
       AND cantidad_actual > 0;

    UPDATE lotes
       SET cantidad_actual = 0
     WHERE fecha_vencimiento < CURDATE()
       AND cantidad_actual > 0;

    COMMIT;

    SELECT v_lotes AS lotes_afectados, v_unidades AS unidades_retiradas;
END$$

-- ---------------------------------------------------------------------
--  PROCEDIMIENTO: reporte de ventas por día en un rango de fechas
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_reporte_ventas$$
CREATE PROCEDURE sp_reporte_ventas(IN p_desde DATE, IN p_hasta DATE)
BEGIN
    SELECT fecha, numero_ventas, subtotal, descuentos, impuestos, total_ventas, ticket_promedio
      FROM v_ventas_diarias
     WHERE fecha BETWEEN p_desde AND p_hasta
     ORDER BY fecha;
END$$

DELIMITER ;
