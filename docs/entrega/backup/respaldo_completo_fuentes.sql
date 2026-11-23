-- RESPALDO LOGICO COMPLETO BASADO EN LOS SCRIPTS DEL PROYECTO
-- Fecha de armado: 2026-11-23
-- Incluye las bases drogueria_gestion y drogueria_db: esquemas, objetos SQL y datos ficticios de prueba.
-- IMPORTANTE: MySQL no estaba disponible al generar este archivo; no contiene datos extraidos de una instancia activa.
-- Los scripts de esquema ejecutan DROP DATABASE y recrean ambas bases. Esto reemplaza su contenido actual.
-- Ejecutar desde una consola: mysql -u USUARIO_ADMIN -p < respaldo_completo_fuentes.sql
-- No usar sobre una instancia con datos reales que se deban conservar.


-- =====================================================================
-- GESTION - ESQUEMA
-- Fuente: database/01_esquema.sql
-- =====================================================================
-- =====================================================================
--  DrogueriaGestión - Sistema web para la gestión integral de una droguería
--  Script 01: Esquema de la base de datos (tablas, llaves y restricciones)
--  Motor: MySQL 8.0  |  Juego de caracteres: utf8mb4
-- =====================================================================

DROP DATABASE IF EXISTS drogueria_gestion;
CREATE DATABASE drogueria_gestion
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE drogueria_gestion;

-- ---------------------------------------------------------------------
--  Seguridad: roles y usuarios del sistema
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    id_rol          TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nombre          VARCHAR(30)  NOT NULL,
    descripcion     VARCHAR(150) NULL,
    CONSTRAINT uq_roles_nombre UNIQUE (nombre)
) ENGINE = InnoDB COMMENT = 'Cargos que determinan los permisos de cada usuario';

CREATE TABLE usuarios (
    id_usuario          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_rol              TINYINT UNSIGNED NOT NULL,
    documento           VARCHAR(20)  NOT NULL,
    nombres             VARCHAR(80)  NOT NULL,
    apellidos           VARCHAR(80)  NOT NULL,
    email               VARCHAR(120) NOT NULL,
    usuario             VARCHAR(40)  NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,
    activo              TINYINT(1)   NOT NULL DEFAULT 1,
    intentos_fallidos   TINYINT UNSIGNED NOT NULL DEFAULT 0,
    bloqueado_hasta     DATETIME     NULL,
    ultimo_acceso       DATETIME     NULL,
    creado_en           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_usuarios_usuario   UNIQUE (usuario),
    CONSTRAINT uq_usuarios_email     UNIQUE (email),
    CONSTRAINT uq_usuarios_documento UNIQUE (documento),
    CONSTRAINT fk_usuarios_rol FOREIGN KEY (id_rol) REFERENCES roles (id_rol)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_usuarios_email CHECK (email LIKE '%_@_%._%')
) ENGINE = InnoDB COMMENT = 'Personas autorizadas para ingresar al sistema';

-- ---------------------------------------------------------------------
--  Catálogo: categorías terapéuticas, proveedores y medicamentos
-- ---------------------------------------------------------------------
CREATE TABLE categorias (
    id_categoria    SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nombre          VARCHAR(80)  NOT NULL,
    descripcion     VARCHAR(255) NULL,
    activo          TINYINT(1)   NOT NULL DEFAULT 1,
    creado_en       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_categorias_nombre UNIQUE (nombre)
) ENGINE = InnoDB COMMENT = 'Categorías terapéuticas de los medicamentos';

CREATE TABLE proveedores (
    id_proveedor    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nit             VARCHAR(20)  NOT NULL,
    razon_social    VARCHAR(150) NOT NULL,
    nombre_contacto VARCHAR(100) NULL,
    telefono        VARCHAR(20)  NULL,
    email           VARCHAR(120) NULL,
    direccion       VARCHAR(150) NULL,
    ciudad          VARCHAR(60)  NULL,
    activo          TINYINT(1)   NOT NULL DEFAULT 1,
    creado_en       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_proveedores_nit UNIQUE (nit)
) ENGINE = InnoDB COMMENT = 'Laboratorios y distribuidores que abastecen la droguería';

CREATE TABLE medicamentos (
    id_medicamento      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    codigo              VARCHAR(30)  NOT NULL COMMENT 'Código interno o de barras',
    nombre              VARCHAR(120) NOT NULL,
    principio_activo    VARCHAR(150) NOT NULL,
    concentracion       VARCHAR(50)  NULL,
    forma_farmaceutica  VARCHAR(40)  NOT NULL,
    presentacion        VARCHAR(80)  NULL,
    laboratorio         VARCHAR(100) NULL,
    registro_invima     VARCHAR(40)  NULL,
    id_categoria        SMALLINT UNSIGNED NOT NULL,
    requiere_formula    TINYINT(1)   NOT NULL DEFAULT 0,
    es_controlado       TINYINT(1)   NOT NULL DEFAULT 0 COMMENT 'Medicamento de control especial',
    precio_compra       DECIMAL(12,2) NOT NULL DEFAULT 0,
    precio_venta        DECIMAL(12,2) NOT NULL,
    iva_porcentaje      DECIMAL(5,2)  NOT NULL DEFAULT 0,
    stock_minimo        INT UNSIGNED  NOT NULL DEFAULT 10,
    ubicacion           VARCHAR(40)  NULL COMMENT 'Estante o góndola',
    activo              TINYINT(1)   NOT NULL DEFAULT 1,
    creado_en           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_medicamentos_codigo UNIQUE (codigo),
    CONSTRAINT fk_medicamentos_categoria FOREIGN KEY (id_categoria) REFERENCES categorias (id_categoria)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_medicamentos_precios CHECK (precio_compra >= 0 AND precio_venta > 0),
    CONSTRAINT ck_medicamentos_iva CHECK (iva_porcentaje BETWEEN 0 AND 100),
    CONSTRAINT ck_medicamentos_control CHECK (es_controlado = 0 OR requiere_formula = 1)
) ENGINE = InnoDB COMMENT = 'Catálogo de medicamentos y productos';

CREATE INDEX ix_medicamentos_nombre ON medicamentos (nombre);
CREATE INDEX ix_medicamentos_principio ON medicamentos (principio_activo);

CREATE TABLE historial_precios (
    id_historial            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_medicamento          INT UNSIGNED  NOT NULL,
    precio_venta_anterior   DECIMAL(12,2) NOT NULL,
    precio_venta_nuevo      DECIMAL(12,2) NOT NULL,
    id_usuario              INT UNSIGNED  NULL,
    fecha                   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_historial_medicamento FOREIGN KEY (id_medicamento) REFERENCES medicamentos (id_medicamento)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_historial_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE = InnoDB COMMENT = 'Registro automático (trigger) de cambios de precio';

-- ---------------------------------------------------------------------
--  Clientes (Ley 1581 de 2012: autorización de tratamiento de datos)
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tipo_documento      ENUM('CC','TI','CE','PA','NIT','RC') NOT NULL DEFAULT 'CC',
    numero_documento    VARCHAR(20)  NOT NULL,
    nombres             VARCHAR(80)  NOT NULL,
    apellidos           VARCHAR(80)  NULL,
    telefono            VARCHAR(20)  NULL,
    email               VARCHAR(120) NULL,
    direccion           VARCHAR(150) NULL,
    ciudad              VARCHAR(50)  NULL,
    pais                VARCHAR(50)  NULL COMMENT 'País o nacionalidad para clasificación de clientes',
    fecha_nacimiento    DATE         NULL,
    autoriza_datos      TINYINT(1)   NOT NULL DEFAULT 0 COMMENT 'Autorización Ley 1581 de 2012',
    activo              TINYINT(1)   NOT NULL DEFAULT 1,
    creado_en           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_clientes_documento UNIQUE (tipo_documento, numero_documento)
) ENGINE = InnoDB COMMENT = 'Clientes de la droguería';

CREATE INDEX ix_clientes_nombres ON clientes (nombres, apellidos);
CREATE INDEX ix_clientes_pais ON clientes (pais, ciudad);

-- ---------------------------------------------------------------------
--  Inventario: entradas de mercancía, lotes y kárdex
-- ---------------------------------------------------------------------
CREATE TABLE entradas (
    id_entrada      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_proveedor    INT UNSIGNED  NOT NULL,
    numero_factura  VARCHAR(40)   NOT NULL COMMENT 'Factura del proveedor',
    fecha_entrada   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total           DECIMAL(14,2) NOT NULL DEFAULT 0,
    observaciones   VARCHAR(255)  NULL,
    id_usuario      INT UNSIGNED  NOT NULL,
    CONSTRAINT uq_entradas_factura UNIQUE (id_proveedor, numero_factura),
    CONSTRAINT fk_entradas_proveedor FOREIGN KEY (id_proveedor) REFERENCES proveedores (id_proveedor)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_entradas_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_entradas_total CHECK (total >= 0)
) ENGINE = InnoDB COMMENT = 'Recepción de mercancía comprada a proveedores';

CREATE TABLE lotes (
    id_lote             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_medicamento      INT UNSIGNED  NOT NULL,
    id_proveedor        INT UNSIGNED  NULL,
    numero_lote         VARCHAR(40)   NOT NULL,
    fecha_fabricacion   DATE          NULL,
    fecha_vencimiento   DATE          NOT NULL,
    cantidad_inicial    INT UNSIGNED  NOT NULL,
    cantidad_actual     INT UNSIGNED  NOT NULL,
    costo_unitario      DECIMAL(12,2) NOT NULL DEFAULT 0,
    fecha_ingreso       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_lotes_medicamento_lote UNIQUE (id_medicamento, numero_lote),
    CONSTRAINT fk_lotes_medicamento FOREIGN KEY (id_medicamento) REFERENCES medicamentos (id_medicamento)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_lotes_proveedor FOREIGN KEY (id_proveedor) REFERENCES proveedores (id_proveedor)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT ck_lotes_fechas CHECK (fecha_fabricacion IS NULL OR fecha_vencimiento > fecha_fabricacion),
    CONSTRAINT ck_lotes_costo CHECK (costo_unitario >= 0)
) ENGINE = InnoDB COMMENT = 'Existencias por lote con su fecha de vencimiento';

CREATE INDEX ix_lotes_vencimiento ON lotes (fecha_vencimiento);
CREATE INDEX ix_lotes_fefo ON lotes (id_medicamento, fecha_vencimiento, cantidad_actual);

CREATE TABLE stock (
    id_medicamento  INT UNSIGNED NOT NULL PRIMARY KEY,
    cantidad_total  BIGINT UNSIGNED NOT NULL DEFAULT 0,
    actualizado_en  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_stock_medicamento FOREIGN KEY (id_medicamento) REFERENCES medicamentos (id_medicamento)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_stock_cantidad CHECK (cantidad_total >= 0)
) ENGINE = InnoDB COMMENT = 'Existencia resumida por medicamento; se sincroniza desde los lotes';

CREATE TABLE detalle_entrada (
    id_detalle_entrada  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_entrada          INT UNSIGNED  NOT NULL,
    id_lote             INT UNSIGNED  NOT NULL,
    cantidad            INT UNSIGNED  NOT NULL,
    costo_unitario      DECIMAL(12,2) NOT NULL,
    subtotal            DECIMAL(14,2) NOT NULL,
    CONSTRAINT fk_detalle_entrada_entrada FOREIGN KEY (id_entrada) REFERENCES entradas (id_entrada)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_detalle_entrada_lote FOREIGN KEY (id_lote) REFERENCES lotes (id_lote)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_detalle_entrada_cantidad CHECK (cantidad > 0)
) ENGINE = InnoDB COMMENT = 'Productos recibidos en cada entrada';

-- ---------------------------------------------------------------------
--  Ventas y dispensación
-- ---------------------------------------------------------------------
CREATE TABLE consecutivos (
    tipo            VARCHAR(20)  PRIMARY KEY,
    prefijo         VARCHAR(10)  NOT NULL,
    ultimo_numero   INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE = InnoDB COMMENT = 'Numeración consecutiva de documentos (facturas)';

CREATE TABLE ventas (
    id_venta            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    numero_factura      VARCHAR(20)   NOT NULL,
    id_cliente          INT UNSIGNED  NOT NULL,
    id_usuario          INT UNSIGNED  NOT NULL COMMENT 'Usuario que dispensa',
    fecha_venta         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    subtotal            DECIMAL(14,2) NOT NULL DEFAULT 0,
    descuento           DECIMAL(14,2) NOT NULL DEFAULT 0,
    impuesto            DECIMAL(14,2) NOT NULL DEFAULT 0,
    total               DECIMAL(14,2) NOT NULL DEFAULT 0,
    metodo_pago         ENUM('EFECTIVO','TARJETA_DEBITO','TARJETA_CREDITO','TRANSFERENCIA') NOT NULL DEFAULT 'EFECTIVO',
    monto_recibido      DECIMAL(14,2) NULL,
    cambio              DECIMAL(14,2) NULL,
    formula_medica      VARCHAR(60)   NULL COMMENT 'Número de la fórmula o prescripción',
    medico              VARCHAR(120)  NULL COMMENT 'Profesional que prescribe',
    observaciones       VARCHAR(255)  NULL,
    estado              ENUM('COMPLETADA','ANULADA') NOT NULL DEFAULT 'COMPLETADA',
    motivo_anulacion    VARCHAR(255)  NULL,
    anulada_por         INT UNSIGNED  NULL,
    fecha_anulacion     DATETIME      NULL,
    CONSTRAINT uq_ventas_factura UNIQUE (numero_factura),
    CONSTRAINT fk_ventas_cliente FOREIGN KEY (id_cliente) REFERENCES clientes (id_cliente)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_ventas_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_ventas_anulada_por FOREIGN KEY (anulada_por) REFERENCES usuarios (id_usuario)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_ventas_valores CHECK (subtotal >= 0 AND descuento >= 0 AND impuesto >= 0 AND total >= 0),
    CONSTRAINT ck_ventas_descuento CHECK (descuento <= subtotal + impuesto)
) ENGINE = InnoDB COMMENT = 'Encabezado de las ventas (facturas)';

CREATE INDEX ix_ventas_fecha ON ventas (fecha_venta);
CREATE INDEX ix_ventas_estado_fecha ON ventas (estado, fecha_venta);

CREATE TABLE historial_facturas (
    id_historial_factura BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_venta             INT UNSIGNED NOT NULL,
    numero_factura       VARCHAR(20) NOT NULL,
    fecha_venta          DATETIME NOT NULL,
    id_cliente           INT UNSIGNED NOT NULL,
    subtotal             DECIMAL(14,2) NOT NULL,
    descuento            DECIMAL(14,2) NOT NULL,
    impuesto             DECIMAL(14,2) NOT NULL,
    total                DECIMAL(14,2) NOT NULL,
    metodo_pago          ENUM('EFECTIVO','TARJETA_DEBITO','TARJETA_CREDITO','TRANSFERENCIA') NOT NULL,
    fecha_registro       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_historial_factura_venta UNIQUE (id_venta),
    CONSTRAINT uq_historial_factura_numero UNIQUE (numero_factura),
    CONSTRAINT fk_historial_factura_venta FOREIGN KEY (id_venta) REFERENCES ventas (id_venta)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_historial_factura_valores CHECK (subtotal >= 0 AND descuento >= 0 AND impuesto >= 0 AND total >= 0)
) ENGINE = InnoDB COMMENT = 'Cabecera histórica inmutable de las facturas emitidas';

CREATE TABLE detalle_venta (
    id_detalle_venta    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_venta            INT UNSIGNED  NOT NULL,
    id_medicamento      INT UNSIGNED  NOT NULL,
    id_lote             INT UNSIGNED  NOT NULL COMMENT 'Lote dispensado (FEFO)',
    cantidad            INT UNSIGNED  NOT NULL,
    precio_unitario     DECIMAL(12,2) NOT NULL,
    iva_porcentaje      DECIMAL(5,2)  NOT NULL DEFAULT 0,
    subtotal            DECIMAL(14,2) NOT NULL,
    impuesto            DECIMAL(14,2) NOT NULL DEFAULT 0,
    costo_unitario      DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT 'Costo del lote al momento de la venta',
    CONSTRAINT fk_detalle_venta_venta FOREIGN KEY (id_venta) REFERENCES ventas (id_venta)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_detalle_venta_medicamento FOREIGN KEY (id_medicamento) REFERENCES medicamentos (id_medicamento)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_detalle_venta_lote FOREIGN KEY (id_lote) REFERENCES lotes (id_lote)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_detalle_venta_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_detalle_venta_precio CHECK (precio_unitario >= 0),
    CONSTRAINT ck_detalle_venta_costo CHECK (costo_unitario >= 0)
) ENGINE = InnoDB COMMENT = 'Productos vendidos en cada venta, discriminados por lote';

-- ---------------------------------------------------------------------
--  Kárdex: todo movimiento que altera las existencias de un lote
-- ---------------------------------------------------------------------
CREATE TABLE movimientos_inventario (
    id_movimiento   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_lote         INT UNSIGNED NOT NULL,
    id_medicamento  INT UNSIGNED NOT NULL,
    tipo            ENUM('ENTRADA','VENTA','AJUSTE_ENTRADA','AJUSTE_SALIDA','BAJA_VENCIMIENTO','ANULACION_VENTA') NOT NULL,
    cantidad        INT UNSIGNED NOT NULL,
    saldo_lote      INT UNSIGNED NOT NULL COMMENT 'Existencia del lote después del movimiento',
    motivo          VARCHAR(255) NULL,
    id_venta        INT UNSIGNED NULL,
    id_entrada      INT UNSIGNED NULL,
    id_usuario      INT UNSIGNED NULL,
    fecha           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_movimientos_lote FOREIGN KEY (id_lote) REFERENCES lotes (id_lote)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_movimientos_medicamento FOREIGN KEY (id_medicamento) REFERENCES medicamentos (id_medicamento)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_movimientos_venta FOREIGN KEY (id_venta) REFERENCES ventas (id_venta)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT fk_movimientos_entrada FOREIGN KEY (id_entrada) REFERENCES entradas (id_entrada)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT fk_movimientos_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT ck_movimientos_cantidad CHECK (cantidad > 0)
) ENGINE = InnoDB COMMENT = 'Kárdex de entradas, salidas y ajustes de inventario';

CREATE INDEX ix_movimientos_fecha ON movimientos_inventario (fecha);
CREATE INDEX ix_movimientos_medicamento_fecha ON movimientos_inventario (id_medicamento, fecha);

-- ---------------------------------------------------------------------
--  Auditoría y configuración general
-- ---------------------------------------------------------------------
CREATE TABLE auditoria (
    id_auditoria    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_usuario      INT UNSIGNED NULL,
    accion          VARCHAR(40)  NOT NULL,
    modulo          VARCHAR(40)  NOT NULL,
    descripcion     VARCHAR(255) NULL,
    ip              VARCHAR(45)  NULL,
    fecha           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_auditoria_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE = InnoDB COMMENT = 'Trazabilidad de las acciones de los usuarios';

CREATE INDEX ix_auditoria_fecha ON auditoria (fecha);

CREATE TABLE configuracion (
    clave           VARCHAR(50)  PRIMARY KEY,
    valor           VARCHAR(255) NOT NULL,
    descripcion     VARCHAR(150) NULL
) ENGINE = InnoDB COMMENT = 'Parámetros generales de la droguería';


-- =====================================================================
-- GESTION - VISTAS, FUNCION, TRIGGERS Y PROCEDIMIENTOS
-- Fuente: database/02_vistas_rutinas.sql
-- =====================================================================
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


-- =====================================================================
-- GESTION - DATOS DE PRUEBA
-- Fuente: database/03_datos_prueba.sql
-- =====================================================================
-- =====================================================================
--  DrogueriaGestión
--  Script 03: Datos de prueba (ficticios)
--  Las fechas se calculan respecto al día de instalación (CURDATE/NOW)
--  para que siempre existan lotes vigentes, próximos a vencer y vencidos.
-- =====================================================================

USE drogueria_gestion;

-- ---------------------------------------------------------------------
--  Roles, usuarios y configuración
-- ---------------------------------------------------------------------
INSERT INTO roles (id_rol, nombre, descripcion) VALUES
(1, 'ADMINISTRADOR', 'Acceso total: usuarios, configuración, auditoría y todos los módulos'),
(2, 'REGENTE',       'Regente de farmacia: medicamentos, inventario, ventas, anulaciones, proveedores y reportes'),
(3, 'VENDEDOR',      'Auxiliar de dispensación: ventas, clientes y consulta de medicamentos'),
(4, 'BODEGA',        'Encargado de inventario: entradas, ajustes, lotes, vencimientos y proveedores');

-- Contraseñas de prueba (ver README): se almacenan con hash scrypt, nunca en texto plano.
INSERT INTO usuarios (id_usuario, id_rol, documento, nombres, apellidos, email, usuario, password_hash) VALUES
(1, 1, '1121000001', 'Andrea Camila', 'Rojas Pinzón', 'admin@drogueriagestion.com.co', 'admin', 'scrypt:32768:8:1$H8OaKCIVoxWwlzCZ$cf06a121fe60ccd9e9c47bf4d977106e16e322019db0c632003088bbccd51ba517bf44afb1bda7df43fdbdb084ca5369a8259321f0766698f4ae09d88a1783da'),
(2, 2, '1121000002', 'Jorge Iván', 'Pardo Gómez', 'regente@drogueriagestion.com.co', 'regente', 'scrypt:32768:8:1$XBrKt1BNBjpyjwEp$877f81722f30cc022aefe1767c312b0aab902f1e47bf3b4c8f55077d4c26c9b9fd6c704b09ab46d9f9983e19312a734bd5773342c03bcf0feb35611a05e0e9b2'),
(3, 3, '1121000003', 'Laura Sofía', 'Méndez Ruiz', 'ventas@drogueriagestion.com.co', 'vendedor', 'scrypt:32768:8:1$HHLwKqLln9Feb1TL$8ba3af458973c36c23dc897ebea755759e2fbf1b1707cfa850b729c15179f361433868b78c1fc2b338191700d48b06462c12b02dd062f04cde2ab7bec9c6edd0'),
(4, 4, '1121000004', 'Miguel Ángel', 'Suárez León', 'bodega@drogueriagestion.com.co', 'bodega', 'scrypt:32768:8:1$VdOmRbXgTUdkCbz4$6dd8715578bc22cb347b8e2e67dc1d367929fe473498a780caa0f8a2676495139f896629572c86b669db9d8727bbab89a200a46331bf221cc32f84ffbbedcb59');

INSERT INTO configuracion (clave, valor, descripcion) VALUES
('nombre_drogueria', 'Droguería Salud Llanera', 'Nombre comercial del establecimiento'),
('nit', '901.234.567-8', 'NIT del establecimiento'),
('direccion', 'Calle 38 # 30A-15, Centro, Villavicencio, Meta', 'Dirección del establecimiento'),
('telefono', '(608) 662 0000', 'Teléfono de contacto'),
('email', 'contacto@saludllanera.com.co', 'Correo electrónico de contacto'),
('mensaje_factura', 'Gracias por su compra. Conserve este comprobante.', 'Mensaje al pie del comprobante de venta'),
('descuento_maximo_vendedor', '10', 'Descuento máximo (%) que puede aplicar un vendedor; regente y administrador no tienen tope');

INSERT INTO consecutivos (tipo, prefijo, ultimo_numero) VALUES ('VENTA', 'FV', 0);

-- ---------------------------------------------------------------------
--  Categorías terapéuticas
-- ---------------------------------------------------------------------
INSERT INTO categorias (id_categoria, nombre, descripcion) VALUES
(1,  'Analgésicos y antipiréticos', 'Alivio del dolor y control de la fiebre'),
(2,  'Antiinflamatorios (AINE)', 'Antiinflamatorios no esteroideos de uso oral y tópico'),
(3,  'Antibióticos', 'Antiinfecciosos de venta bajo fórmula médica'),
(4,  'Cardiovasculares', 'Antihipertensivos, hipolipemiantes y antiagregantes'),
(5,  'Antidiabéticos', 'Control de la glucemia'),
(6,  'Antihistamínicos', 'Tratamiento de alergias'),
(7,  'Gastrointestinales', 'Antiácidos, protectores gástricos y antidiarreicos'),
(8,  'Respiratorios', 'Broncodilatadores, mucolíticos y antitusivos'),
(9,  'Vitaminas y suplementos', 'Vitaminas, minerales y suplementos nutricionales'),
(10, 'Dermatológicos', 'Cremas y ungüentos de uso tópico'),
(11, 'Antiparasitarios y antimicóticos', 'Tratamiento de parásitos y hongos'),
(12, 'Control especial', 'Medicamentos de control especial (psicotrópicos)'),
(13, 'Primeros auxilios y cuidado', 'Material de curación y productos de cuidado');

-- ---------------------------------------------------------------------
--  Proveedores
-- ---------------------------------------------------------------------
INSERT INTO proveedores (id_proveedor, nit, razon_social, nombre_contacto, telefono, email, direccion, ciudad) VALUES
(1, '900123456-1', 'Distribuidora Farmacéutica del Llano S.A.S.', 'Carlos Andrés Rey', '3104567001', 'pedidos@farmallano.com.co', 'Av. 40 # 26C-10', 'Villavicencio'),
(2, '830045678-2', 'Mayoristas Andinos de Medicamentos Ltda.', 'Paola Andrea Vargas', '3157894002', 'ventas@mayoristasandinos.com.co', 'Calle 13 # 65-21', 'Bogotá D.C.'),
(3, '901234567-3', 'Medisalud Distribuciones S.A.S.', 'Hernán Darío Quintero', '3209871003', 'comercial@medisalud.com.co', 'Carrera 22 # 7-45', 'Villavicencio'),
(4, '860512345-4', 'Farmacéuticos Unidos de Colombia S.A.', 'Natalia Pérez Ortiz', '3012347004', 'servicio@farmaunidos.com.co', 'Autopista Sur # 71-75', 'Bogotá D.C.'),
(5, '900765432-5', 'Insumos Médicos Orinoquía S.A.S.', 'Ricardo Salazar Mora', '3184561005', 'insumos@orinoquia.com.co', 'Km 2 Vía Puerto López', 'Villavicencio');

-- ---------------------------------------------------------------------
--  Medicamentos
-- ---------------------------------------------------------------------
INSERT INTO medicamentos (id_medicamento, codigo, nombre, principio_activo, concentracion, forma_farmaceutica, presentacion,
    laboratorio, registro_invima, id_categoria, requiere_formula, es_controlado, precio_compra, precio_venta,
    iva_porcentaje, stock_minimo, ubicacion) VALUES
(1, '7702030509027', 'Acetaminofén 500 mg', 'Acetaminofén', '500 mg', 'Tableta', 'Caja x 20 tabletas', 'Genfar', 'INVIMA 2017M-2857850', 1, 0, 0, 2800, 4500, 0, 30, 'A1'),
(2, '7705716095802', 'Acetaminofén jarabe', 'Acetaminofén', '150 mg/5 mL', 'Jarabe', 'Frasco x 90 mL', 'MK', 'INVIMA 2016M-9225646', 1, 0, 0, 4200, 7500, 0, 15, 'A1'),
(3, '7708212920593', 'Dipirona 500 mg', 'Metamizol sódico', '500 mg', 'Tableta', 'Caja x 10 tabletas', 'La Santé', 'INVIMA 2019M-7664202', 1, 0, 0, 3000, 5200, 0, 15, 'A1'),
(4, '7706375207868', 'Ibuprofeno 400 mg', 'Ibuprofeno', '400 mg', 'Tableta', 'Caja x 10 tabletas', 'Genfar', 'INVIMA 2021M-7314012', 2, 0, 0, 2500, 4800, 0, 30, 'A2'),
(5, '7709917726066', 'Ibuprofeno suspensión', 'Ibuprofeno', '100 mg/5 mL', 'Suspensión', 'Frasco x 120 mL', 'MK', 'INVIMA 2021M-2504328', 2, 0, 0, 5500, 9800, 0, 10, 'A2'),
(6, '7706549621184', 'Naproxeno 250 mg', 'Naproxeno sódico', '250 mg', 'Tableta', 'Caja x 10 tabletas', 'La Santé', 'INVIMA 2023M-3363714', 2, 0, 0, 3200, 6000, 0, 15, 'A2'),
(7, '7707774981744', 'Diclofenaco 50 mg', 'Diclofenaco sódico', '50 mg', 'Tableta', 'Caja x 30 tabletas', 'Genfar', 'INVIMA 2016M-7188185', 2, 0, 0, 3500, 6500, 0, 15, 'A2'),
(8, '7706856369309', 'Diclofenaco gel', 'Diclofenaco dietilamonio', '1 %', 'Gel', 'Tubo x 50 g', 'Procaps', 'INVIMA 2022M-2521428', 2, 0, 0, 7800, 13500, 0, 8, 'A2'),
(9, '7705795107404', 'Amoxicilina 500 mg', 'Amoxicilina', '500 mg', 'Cápsula', 'Caja x 50 cápsulas', 'Genfar', 'INVIMA 2024M-9238128', 3, 1, 0, 9500, 16500, 0, 10, 'B1'),
(10, '7707548333555', 'Azitromicina 500 mg', 'Azitromicina', '500 mg', 'Tableta', 'Caja x 3 tabletas', 'MK', 'INVIMA 2022M-9039473', 3, 1, 0, 6200, 11900, 0, 10, 'B1'),
(11, '7704458192345', 'Cefalexina 500 mg', 'Cefalexina', '500 mg', 'Cápsula', 'Caja x 10 cápsulas', 'La Santé', 'INVIMA 2019M-3164241', 3, 1, 0, 5800, 10500, 0, 10, 'B1'),
(12, '7704513851069', 'Ciprofloxacino 500 mg', 'Ciprofloxacino', '500 mg', 'Tableta', 'Caja x 10 tabletas', 'Genfar', 'INVIMA 2024M-2720946', 3, 1, 0, 4500, 8900, 0, 10, 'B1'),
(13, '7707139267178', 'Amoxicilina suspensión', 'Amoxicilina', '250 mg/5 mL', 'Polvo para suspensión', 'Frasco x 100 mL', 'MK', 'INVIMA 2018M-9088515', 3, 1, 0, 7000, 12500, 0, 8, 'B1'),
(14, '7704798065994', 'Losartán 50 mg', 'Losartán potásico', '50 mg', 'Tableta', 'Caja x 30 tabletas', 'Genfar', 'INVIMA 2017M-8663770', 4, 1, 0, 4200, 8500, 0, 20, 'B2'),
(15, '7708191077343', 'Enalapril 20 mg', 'Enalapril maleato', '20 mg', 'Tableta', 'Caja x 30 tabletas', 'La Santé', 'INVIMA 2024M-5211189', 4, 1, 0, 3600, 7200, 0, 15, 'B2'),
(16, '7707699273039', 'Amlodipino 5 mg', 'Amlodipino besilato', '5 mg', 'Tableta', 'Caja x 30 tabletas', 'MK', 'INVIMA 2020M-9420478', 4, 1, 0, 3900, 7800, 0, 15, 'B2'),
(17, '7708294244131', 'Atorvastatina 20 mg', 'Atorvastatina cálcica', '20 mg', 'Tableta', 'Caja x 30 tabletas', 'Procaps', 'INVIMA 2022M-8265655', 4, 1, 0, 8500, 15900, 0, 10, 'B2'),
(18, '7706164832776', 'Ácido acetilsalicílico 100 mg', 'Ácido acetilsalicílico', '100 mg', 'Tableta', 'Caja x 30 tabletas', 'Bayer', 'INVIMA 2020M-1155640', 4, 0, 0, 5200, 9500, 0, 15, 'B2'),
(19, '7701142203221', 'Metformina 850 mg', 'Metformina clorhidrato', '850 mg', 'Tableta', 'Caja x 30 tabletas', 'Genfar', 'INVIMA 2023M-9772618', 5, 1, 0, 3800, 7500, 0, 20, 'B3'),
(20, '7709276220344', 'Glibenclamida 5 mg', 'Glibenclamida', '5 mg', 'Tableta', 'Caja x 30 tabletas', 'La Santé', 'INVIMA 2021M-4352718', 5, 1, 0, 3100, 6200, 0, 10, 'B3'),
(21, '7707380470856', 'Loratadina 10 mg', 'Loratadina', '10 mg', 'Tableta', 'Caja x 10 tabletas', 'Genfar', 'INVIMA 2024M-9340912', 6, 0, 0, 1800, 3900, 0, 20, 'A3'),
(22, '7708765125956', 'Cetirizina 10 mg', 'Cetirizina diclorhidrato', '10 mg', 'Tableta', 'Caja x 10 tabletas', 'MK', 'INVIMA 2024M-1564049', 6, 0, 0, 2200, 4500, 0, 15, 'A3'),
(23, '7708865815672', 'Loratadina jarabe', 'Loratadina', '5 mg/5 mL', 'Jarabe', 'Frasco x 60 mL', 'La Santé', 'INVIMA 2021M-8678186', 6, 0, 0, 4500, 8200, 0, 8, 'A3'),
(24, '7705717480361', 'Omeprazol 20 mg', 'Omeprazol', '20 mg', 'Cápsula', 'Caja x 30 cápsulas', 'Genfar', 'INVIMA 2024M-5342466', 7, 0, 0, 3500, 7900, 0, 25, 'A4'),
(25, '7705145795381', 'Esomeprazol 40 mg', 'Esomeprazol magnésico', '40 mg', 'Tableta', 'Caja x 14 tabletas', 'Procaps', 'INVIMA 2022M-9038740', 7, 1, 0, 12500, 22900, 0, 8, 'A4'),
(26, '7705037861054', 'Hidróxido de aluminio y magnesio', 'Hidróxido de aluminio + hidróxido de magnesio', '400/400 mg/5 mL', 'Suspensión', 'Frasco x 360 mL', 'MK', 'INVIMA 2020M-9362112', 7, 0, 0, 6800, 11500, 0, 10, 'A4'),
(27, '7702589690976', 'Loperamida 2 mg', 'Loperamida clorhidrato', '2 mg', 'Tableta', 'Caja x 6 tabletas', 'La Santé', 'INVIMA 2019M-7900650', 7, 0, 0, 2100, 4200, 0, 10, 'A4'),
(28, '7705923573028', 'Sales de rehidratación oral', 'Glucosa + electrolitos', '27,9 g', 'Sobre', 'Sobre x 27,9 g', 'Genfar', 'INVIMA 2016M-2546333', 7, 0, 0, 900, 2000, 0, 30, 'A4'),
(29, '7705295886288', 'Salbutamol inhalador', 'Salbutamol sulfato', '100 mcg/dosis', 'Inhalador', 'Frasco x 200 dosis', 'Genfar', 'INVIMA 2024M-2393608', 8, 1, 0, 11000, 19500, 0, 8, 'C1'),
(30, '7701853803852', 'Ambroxol jarabe', 'Ambroxol clorhidrato', '30 mg/5 mL', 'Jarabe', 'Frasco x 120 mL', 'MK', 'INVIMA 2017M-1749254', 8, 0, 0, 5200, 9500, 0, 10, 'C1'),
(31, '7709402531820', 'Dextrometorfano jarabe', 'Dextrometorfano bromhidrato', '15 mg/5 mL', 'Jarabe', 'Frasco x 120 mL', 'La Santé', 'INVIMA 2021M-3596457', 8, 0, 0, 5800, 10200, 0, 10, 'C1'),
(32, '7705317005189', 'Vitamina C 500 mg', 'Ácido ascórbico', '500 mg', 'Tableta masticable', 'Frasco x 100 tabletas', 'Procaps', 'INVIMA 2023M-3262652', 9, 0, 0, 9500, 16900, 0, 10, 'C2'),
(33, '7703344208658', 'Complejo B', 'Tiamina + piridoxina + cianocobalamina', '100/5/0,05 mg', 'Tableta', 'Caja x 30 tabletas', 'La Santé', 'INVIMA 2023M-3201443', 9, 0, 0, 4800, 8900, 0, 10, 'C2'),
(34, '7707462729157', 'Ácido fólico 1 mg', 'Ácido fólico', '1 mg', 'Tableta', 'Caja x 30 tabletas', 'Genfar', 'INVIMA 2017M-8009167', 9, 0, 0, 2200, 4500, 0, 10, 'C2'),
(35, '7703871421313', 'Clotrimazol crema', 'Clotrimazol', '1 %', 'Crema', 'Tubo x 40 g', 'Genfar', 'INVIMA 2018M-6133900', 11, 0, 0, 3300, 6500, 0, 10, 'C3'),
(36, '7707475530314', 'Betametasona crema', 'Betametasona dipropionato', '0,05 %', 'Crema', 'Tubo x 40 g', 'MK', 'INVIMA 2022M-3492025', 10, 1, 0, 4200, 8200, 0, 8, 'C3'),
(37, '7706139774956', 'Albendazol 400 mg', 'Albendazol', '400 mg', 'Tableta', 'Caja x 1 tableta', 'Genfar', 'INVIMA 2016M-2780632', 11, 0, 0, 1500, 3500, 0, 15, 'C3'),
(38, '7701315393763', 'Metronidazol 500 mg', 'Metronidazol', '500 mg', 'Tableta', 'Caja x 20 tabletas', 'La Santé', 'INVIMA 2021M-6929115', 11, 1, 0, 4000, 7800, 0, 10, 'C3'),
(39, '7705059049801', 'Clonazepam 2 mg', 'Clonazepam', '2 mg', 'Tableta', 'Caja x 30 tabletas', 'Lafrancol', 'INVIMA 2016M-9562887', 12, 1, 1, 6500, 12900, 0, 5, 'D1'),
(40, '7707339476609', 'Alprazolam 0,5 mg', 'Alprazolam', '0,5 mg', 'Tableta', 'Caja x 30 tabletas', 'MK', 'INVIMA 2020M-8552102', 12, 1, 1, 7200, 13800, 0, 5, 'D1'),
(41, '7705816259704', 'Alcohol antiséptico 70 %', 'Alcohol etílico', '70 %', 'Solución', 'Frasco x 350 mL', 'JGB', NULL, 13, 0, 0, 3500, 6200, 19, 15, 'E1'),
(42, '7703231723970', 'Gasa estéril', 'Gasa de algodón', '10 x 10 cm', 'Material de curación', 'Paquete x 10 unidades', 'Insumos Orinoquía', NULL, 13, 0, 0, 1800, 3500, 19, 15, 'E1'),
(43, '7704053217866', 'Apósitos adhesivos', 'Apósito adhesivo', '1,9 x 7,2 cm', 'Material de curación', 'Caja x 30 unidades', 'Insumos Orinoquía', NULL, 13, 0, 0, 2800, 5200, 19, 10, 'E1'),
(44, '7701146684679', 'Suero fisiológico', 'Cloruro de sodio', '0,9 %', 'Solución', 'Frasco x 500 mL', 'Corpaul', 'INVIMA 2018M-1758944', 13, 0, 0, 3200, 5900, 0, 10, 'E1');

-- ---------------------------------------------------------------------
--  Clientes (id 1 = consumidor final)
-- ---------------------------------------------------------------------
INSERT INTO clientes (id_cliente, tipo_documento, numero_documento, nombres, apellidos, telefono, email, direccion, fecha_nacimiento, autoriza_datos) VALUES
(1,  'CC',  '222222222222', 'Consumidor', 'Final', NULL, NULL, NULL, NULL, 0),
(2,  'CC',  '1121845632', 'María Fernanda', 'López Rojas', '3104567890', 'mafe.lopez@ejemplo.com', 'Calle 37 # 29-45, Barzal', '1988-04-12', 1),
(3,  'CC',  '17345678', 'José Antonio', 'Rincón Pardo', '3112345678', NULL, 'Carrera 33 # 15-20, La Esperanza', '1959-09-03', 1),
(4,  'CC',  '40189234', 'Luz Marina', 'Gutiérrez Cruz', '3209876543', 'luzma.gutierrez@ejemplo.com', 'Manzana 4 Casa 12, Ciudadela La Madrid', '1970-02-25', 1),
(5,  'TI',  '1121987654', 'Santiago', 'Herrera Castro', '3001239876', NULL, 'Calle 15 # 40-12, El Buque', '2010-07-19', 1),
(6,  'CC',  '1006789123', 'Valentina', 'Ruiz Ospina', '3014567812', 'vale.ruiz@ejemplo.com', 'Carrera 45 # 23-08, Los Centauros', '1999-11-30', 1),
(7,  'CE',  '987654', 'Carlos Eduardo', 'Pérez Mendoza', '3156782345', NULL, 'Calle 7 Sur # 45-30, Porfía', '1985-05-05', 0),
(8,  'CC',  '86045123', 'Andrés Felipe', 'Moreno Díaz', '3187654321', 'afmoreno@ejemplo.com', 'Transversal 25 # 33-10, San Benito', '1979-01-14', 1),
(9,  'CC',  '1121876543', 'Daniela', 'Castaño Vargas', '3045678901', 'dani.castano@ejemplo.com', 'Carrera 19 # 9-60, Villa Julia', '1995-08-08', 1),
(10, 'NIT', '900456789', 'Fundación Hogar del Adulto Mayor Llano Verde', NULL, '6086612345', 'compras@llanoverde.org', 'Vereda Apiay, Km 5', NULL, 1),
(11, 'CC',  '21234567', 'Gloria Inés', 'Beltrán Silva', '3123456780', NULL, 'Calle 26 # 38-15, Siete de Agosto', '1952-03-17', 1),
(12, 'CC',  '1122334455', 'Julián David', 'Torres Medina', '3176549870', 'jdtorres@ejemplo.com', 'Carrera 30 # 41-22, Caudal', '2001-06-21', 0);

-- ---------------------------------------------------------------------
-- Datos geográficos demostrativos para el reporte del parcial. No se asigna
-- nacionalidad al cliente con cédula de extranjería porque el documento no la determina.
UPDATE clientes SET ciudad = 'Villavicencio' WHERE id_cliente BETWEEN 2 AND 12;
UPDATE clientes SET pais = 'Colombia' WHERE id_cliente BETWEEN 2 AND 6 OR id_cliente BETWEEN 8 AND 12;

--  Entradas de mercancía (dos facturas por proveedor)
-- ---------------------------------------------------------------------
INSERT INTO entradas (id_entrada, id_proveedor, numero_factura, fecha_entrada, observaciones, id_usuario) VALUES
(1, 1, 'FP-12951A', NOW() - INTERVAL 121 DAY - INTERVAL 1 HOUR, 'Pedido inicial', 4),
(2, 1, 'FP-16234B', NOW() - INTERVAL 98 DAY - INTERVAL 8 HOUR, 'Pedido de reposición', 4),
(3, 2, 'FP-29233A', NOW() - INTERVAL 124 DAY - INTERVAL 4 HOUR, 'Pedido inicial', 4),
(4, 2, 'FP-29385B', NOW() - INTERVAL 100 DAY - INTERVAL 8 HOUR, 'Pedido de reposición', 4),
(5, 3, 'FP-32681A', NOW() - INTERVAL 127 DAY - INTERVAL 1 HOUR, 'Pedido inicial', 4),
(6, 3, 'FP-34658B', NOW() - INTERVAL 102 DAY - INTERVAL 3 HOUR, 'Pedido de reposición', 4),
(7, 4, 'FP-47891A', NOW() - INTERVAL 130 DAY - INTERVAL 4 HOUR, 'Pedido inicial', 4),
(8, 4, 'FP-49975B', NOW() - INTERVAL 104 DAY - INTERVAL 3 HOUR, 'Pedido de reposición', 4),
(9, 5, 'FP-59042A', NOW() - INTERVAL 133 DAY - INTERVAL 3 HOUR, 'Pedido inicial', 4),
(10, 5, 'FP-58226B', NOW() - INTERVAL 106 DAY - INTERVAL 3 HOUR, 'Pedido de reposición', 4);

-- ---------------------------------------------------------------------
--  Lotes (existencias con fechas de vencimiento relativas a hoy)
-- ---------------------------------------------------------------------
INSERT INTO lotes (id_lote, id_medicamento, id_proveedor, numero_lote, fecha_fabricacion, fecha_vencimiento,
    cantidad_inicial, cantidad_actual, costo_unitario, fecha_ingreso) VALUES
(1, 1, 1, 'GF25E291', CURDATE() + INTERVAL -331 DAY, CURDATE() + INTERVAL 399 DAY, 57, 57, 2750, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(2, 1, 1, 'GF24H609', CURDATE() + INTERVAL -148 DAY, CURDATE() + INTERVAL 646 DAY, 35, 35, 2900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(3, 2, 2, 'MK25E578', CURDATE() + INTERVAL -712 DAY, CURDATE() + INTERVAL 18 DAY, 25, 25, 4100, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(4, 2, 2, 'MK26H555', CURDATE() + INTERVAL -310 DAY, CURDATE() + INTERVAL 420 DAY, 40, 40, 4050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 4)),
(5, 3, 3, 'LS23A195', CURDATE() + INTERVAL -262 DAY, CURDATE() + INTERVAL 468 DAY, 90, 90, 3050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(6, 3, 3, 'LS24G658', CURDATE() + INTERVAL -166 DAY, CURDATE() + INTERVAL 564 DAY, 43, 43, 3050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(7, 4, 1, 'GF26K686', CURDATE() + INTERVAL -437 DAY, CURDATE() + INTERVAL 293 DAY, 41, 41, 2550, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(8, 4, 1, 'GF23B735', CURDATE() + INTERVAL -150 DAY, CURDATE() + INTERVAL 580 DAY, 52, 52, 2550, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(9, 5, 2, 'MK23J401', CURDATE() + INTERVAL -246 DAY, CURDATE() + INTERVAL 484 DAY, 88, 88, 5500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(10, 6, 3, 'LS26C203', CURDATE() + INTERVAL -668 DAY, CURDATE() + INTERVAL 62 DAY, 30, 30, 3250, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(11, 6, 3, 'LS22G275', CURDATE() + INTERVAL -220 DAY, CURDATE() + INTERVAL 510 DAY, 40, 40, 3100, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(12, 7, 1, 'GF22I421', CURDATE() + INTERVAL -500 DAY, CURDATE() + INTERVAL 230 DAY, 88, 88, 3450, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(13, 7, 1, 'GF22E422', CURDATE() + INTERVAL -163 DAY, CURDATE() + INTERVAL 745 DAY, 41, 41, 3400, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(14, 8, 4, 'PC25A158', CURDATE() + INTERVAL -399 DAY, CURDATE() + INTERVAL 331 DAY, 44, 44, 7550, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 7)),
(15, 8, 4, 'PC22E225', CURDATE() + INTERVAL -124 DAY, CURDATE() + INTERVAL 738 DAY, 46, 46, 7550, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 8)),
(16, 9, 1, 'GF24F898', CURDATE() + INTERVAL -243 DAY, CURDATE() + INTERVAL 487 DAY, 76, 76, 9400, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(17, 10, 2, 'MK22G423', CURDATE() + INTERVAL -210 DAY, CURDATE() + INTERVAL 520 DAY, 81, 81, 6200, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(18, 11, 3, 'LS26H536', CURDATE() + INTERVAL -742 DAY, CURDATE() + INTERVAL -12 DAY, 9, 9, 5950, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(19, 11, 3, 'LS22K483', CURDATE() + INTERVAL -350 DAY, CURDATE() + INTERVAL 380 DAY, 35, 35, 5900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(20, 12, 1, 'GF22L832', CURDATE() + INTERVAL -402 DAY, CURDATE() + INTERVAL 328 DAY, 64, 64, 4450, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(21, 12, 1, 'GF22E811', CURDATE() + INTERVAL -133 DAY, CURDATE() + INTERVAL 749 DAY, 52, 52, 4400, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(22, 13, 2, 'MK22E886', CURDATE() + INTERVAL -706 DAY, CURDATE() + INTERVAL 24 DAY, 14, 14, 6900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(23, 14, 1, 'GF26A838', CURDATE() + INTERVAL -231 DAY, CURDATE() + INTERVAL 499 DAY, 41, 41, 4350, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(24, 14, 1, 'GF23J225', CURDATE() + INTERVAL -103 DAY, CURDATE() + INTERVAL 627 DAY, 42, 42, 4050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(25, 15, 3, 'LS22G692', CURDATE() + INTERVAL -466 DAY, CURDATE() + INTERVAL 264 DAY, 73, 73, 3500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(26, 15, 3, 'LS25G486', CURDATE() + INTERVAL -137 DAY, CURDATE() + INTERVAL 705 DAY, 49, 49, 3500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(27, 16, 2, 'MK26A777', CURDATE() + INTERVAL -315 DAY, CURDATE() + INTERVAL 415 DAY, 82, 82, 3950, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(28, 16, 2, 'MK26K668', CURDATE() + INTERVAL -158 DAY, CURDATE() + INTERVAL 572 DAY, 41, 41, 3850, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 4)),
(29, 17, 4, 'PC24C333', CURDATE() + INTERVAL -430 DAY, CURDATE() + INTERVAL 300 DAY, 7, 7, 8150, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 7)),
(30, 18, 2, 'BY23K707', CURDATE() + INTERVAL -389 DAY, CURDATE() + INTERVAL 341 DAY, 74, 74, 5000, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(31, 18, 2, 'BY23I138', CURDATE() + INTERVAL -123 DAY, CURDATE() + INTERVAL 607 DAY, 50, 50, 5250, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 4)),
(32, 19, 1, 'GF22K960', CURDATE() + INTERVAL -267 DAY, CURDATE() + INTERVAL 463 DAY, 56, 56, 3650, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(33, 19, 1, 'GF23H159', CURDATE() + INTERVAL -163 DAY, CURDATE() + INTERVAL 673 DAY, 50, 50, 3900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(34, 20, 3, 'LS25L468', CURDATE() + INTERVAL -270 DAY, CURDATE() + INTERVAL 460 DAY, 49, 49, 3200, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(35, 21, 1, 'GF24D483', CURDATE() + INTERVAL -411 DAY, CURDATE() + INTERVAL 319 DAY, 75, 75, 1750, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(36, 22, 2, 'MK26E292', CURDATE() + INTERVAL -296 DAY, CURDATE() + INTERVAL 434 DAY, 75, 75, 2150, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(37, 23, 3, 'LS25C596', CURDATE() + INTERVAL -655 DAY, CURDATE() + INTERVAL 75 DAY, 18, 18, 4600, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(38, 24, 1, 'GF22K276', CURDATE() + INTERVAL -349 DAY, CURDATE() + INTERVAL 381 DAY, 73, 73, 3400, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(39, 25, 4, 'PC24I848', CURDATE() + INTERVAL -320 DAY, CURDATE() + INTERVAL 410 DAY, 9, 9, 12250, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 7)),
(40, 26, 2, 'MK22A646', CURDATE() + INTERVAL -755 DAY, CURDATE() + INTERVAL -25 DAY, 6, 6, 6650, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(41, 26, 2, 'MK26E686', CURDATE() + INTERVAL -440 DAY, CURDATE() + INTERVAL 290 DAY, 22, 22, 6550, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 4)),
(42, 27, 3, 'LS25G651', CURDATE() + INTERVAL -718 DAY, CURDATE() + INTERVAL 12 DAY, 15, 15, 2150, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(43, 27, 3, 'LS26K777', CURDATE() + INTERVAL -130 DAY, CURDATE() + INTERVAL 600 DAY, 30, 30, 2050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(44, 28, 1, 'GF24I367', CURDATE() + INTERVAL -270 DAY, CURDATE() + INTERVAL 460 DAY, 46, 46, 900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(45, 28, 1, 'GF26K906', CURDATE() + INTERVAL -118 DAY, CURDATE() + INTERVAL 727 DAY, 54, 54, 900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(46, 29, 1, 'GF24E654', CURDATE() + INTERVAL -380 DAY, CURDATE() + INTERVAL 350 DAY, 5, 5, 10800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(47, 30, 2, 'MK23G293', CURDATE() + INTERVAL -675 DAY, CURDATE() + INTERVAL 55 DAY, 20, 20, 5350, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(48, 30, 2, 'MK22J763', CURDATE() + INTERVAL -250 DAY, CURDATE() + INTERVAL 480 DAY, 30, 30, 5150, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 4)),
(49, 31, 3, 'LS25F931', CURDATE() + INTERVAL -709 DAY, CURDATE() + INTERVAL 21 DAY, 12, 12, 5900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(50, 31, 3, 'LS26C839', CURDATE() + INTERVAL -200 DAY, CURDATE() + INTERVAL 530 DAY, 25, 25, 5800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(51, 32, 4, 'PC22I783', CURDATE() + INTERVAL -439 DAY, CURDATE() + INTERVAL 291 DAY, 60, 60, 9700, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 7)),
(52, 32, 4, 'PC22F165', CURDATE() + INTERVAL -149 DAY, CURDATE() + INTERVAL 581 DAY, 31, 31, 9350, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 8)),
(53, 33, 3, 'LS23I257', CURDATE() + INTERVAL -770 DAY, CURDATE() + INTERVAL -40 DAY, 11, 11, 4800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(54, 33, 3, 'LS23C208', CURDATE() + INTERVAL -370 DAY, CURDATE() + INTERVAL 360 DAY, 20, 20, 4950, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(55, 34, 1, 'GF22G368', CURDATE() + INTERVAL -282 DAY, CURDATE() + INTERVAL 448 DAY, 46, 46, 2200, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(56, 35, 1, 'GF26I352', CURDATE() + INTERVAL -470 DAY, CURDATE() + INTERVAL 260 DAY, 62, 62, 3350, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(57, 35, 1, 'GF25J453', CURDATE() + INTERVAL -148 DAY, CURDATE() + INTERVAL 667 DAY, 37, 37, 3200, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(58, 36, 2, 'MK22H896', CURDATE() + INTERVAL -646 DAY, CURDATE() + INTERVAL 84 DAY, 16, 16, 4100, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(59, 37, 1, 'GF24F841', CURDATE() + INTERVAL -415 DAY, CURDATE() + INTERVAL 315 DAY, 50, 50, 1500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(60, 37, 1, 'GF25G421', CURDATE() + INTERVAL -118 DAY, CURDATE() + INTERVAL 669 DAY, 65, 65, 1450, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(61, 38, 3, 'LS24F519', CURDATE() + INTERVAL -293 DAY, CURDATE() + INTERVAL 437 DAY, 54, 54, 4050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(62, 39, 4, 'LF23G374', CURDATE() + INTERVAL -228 DAY, CURDATE() + INTERVAL 502 DAY, 64, 64, 6400, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 7)),
(63, 39, 4, 'LF22F372', CURDATE() + INTERVAL -169 DAY, CURDATE() + INTERVAL 653 DAY, 66, 66, 6600, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 8)),
(64, 40, 2, 'MK25E248', CURDATE() + INTERVAL -738 DAY, CURDATE() + INTERVAL -8 DAY, 4, 4, 7200, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(65, 41, 5, 'JG22E400', CURDATE() + INTERVAL -393 DAY, CURDATE() + INTERVAL 337 DAY, 54, 54, 3500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 9)),
(66, 41, 5, 'JG25G122', CURDATE() + INTERVAL -154 DAY, CURDATE() + INTERVAL 576 DAY, 65, 65, 3500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 10)),
(67, 42, 5, 'IO26I314', CURDATE() + INTERVAL -362 DAY, CURDATE() + INTERVAL 368 DAY, 83, 83, 1800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 9)),
(68, 42, 5, 'IO24A509', CURDATE() + INTERVAL -166 DAY, CURDATE() + INTERVAL 564 DAY, 61, 61, 1800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 10)),
(69, 43, 5, 'IO24C442', CURDATE() + INTERVAL -525 DAY, CURDATE() + INTERVAL 205 DAY, 57, 57, 2800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 9)),
(70, 44, 5, 'CP26G952', CURDATE() + INTERVAL -685 DAY, CURDATE() + INTERVAL 45 DAY, 18, 18, 3250, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 9)),
(71, 44, 5, 'CP25H446', CURDATE() + INTERVAL -141 DAY, CURDATE() + INTERVAL 700 DAY, 30, 30, 3050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 10));

INSERT INTO detalle_entrada (id_entrada, id_lote, cantidad, costo_unitario, subtotal) VALUES
(1, 1, 57, 2750, 156750),
(2, 2, 35, 2900, 101500),
(3, 3, 25, 4100, 102500),
(4, 4, 40, 4050, 162000),
(5, 5, 90, 3050, 274500),
(6, 6, 43, 3050, 131150),
(1, 7, 41, 2550, 104550),
(2, 8, 52, 2550, 132600),
(3, 9, 88, 5500, 484000),
(5, 10, 30, 3250, 97500),
(6, 11, 40, 3100, 124000),
(1, 12, 88, 3450, 303600),
(2, 13, 41, 3400, 139400),
(7, 14, 44, 7550, 332200),
(8, 15, 46, 7550, 347300),
(1, 16, 76, 9400, 714400),
(3, 17, 81, 6200, 502200),
(5, 18, 9, 5950, 53550),
(6, 19, 35, 5900, 206500),
(1, 20, 64, 4450, 284800),
(2, 21, 52, 4400, 228800),
(3, 22, 14, 6900, 96600),
(1, 23, 41, 4350, 178350),
(2, 24, 42, 4050, 170100),
(5, 25, 73, 3500, 255500),
(6, 26, 49, 3500, 171500),
(3, 27, 82, 3950, 323900),
(4, 28, 41, 3850, 157850),
(7, 29, 7, 8150, 57050),
(3, 30, 74, 5000, 370000),
(4, 31, 50, 5250, 262500),
(1, 32, 56, 3650, 204400),
(2, 33, 50, 3900, 195000),
(5, 34, 49, 3200, 156800),
(1, 35, 75, 1750, 131250),
(3, 36, 75, 2150, 161250),
(5, 37, 18, 4600, 82800),
(1, 38, 73, 3400, 248200),
(7, 39, 9, 12250, 110250),
(3, 40, 6, 6650, 39900),
(4, 41, 22, 6550, 144100),
(5, 42, 15, 2150, 32250),
(6, 43, 30, 2050, 61500),
(1, 44, 46, 900, 41400),
(2, 45, 54, 900, 48600),
(1, 46, 5, 10800, 54000),
(3, 47, 20, 5350, 107000),
(4, 48, 30, 5150, 154500),
(5, 49, 12, 5900, 70800),
(6, 50, 25, 5800, 145000),
(7, 51, 60, 9700, 582000),
(8, 52, 31, 9350, 289850),
(5, 53, 11, 4800, 52800),
(6, 54, 20, 4950, 99000),
(1, 55, 46, 2200, 101200),
(1, 56, 62, 3350, 207700),
(2, 57, 37, 3200, 118400),
(3, 58, 16, 4100, 65600),
(1, 59, 50, 1500, 75000),
(2, 60, 65, 1450, 94250),
(5, 61, 54, 4050, 218700),
(7, 62, 64, 6400, 409600),
(8, 63, 66, 6600, 435600),
(3, 64, 4, 7200, 28800),
(9, 65, 54, 3500, 189000),
(10, 66, 65, 3500, 227500),
(9, 67, 83, 1800, 149400),
(10, 68, 61, 1800, 109800),
(9, 69, 57, 2800, 159600),
(9, 70, 18, 3250, 58500),
(10, 71, 30, 3050, 91500);

UPDATE entradas e
   SET total = (SELECT COALESCE(SUM(d.subtotal), 0) FROM detalle_entrada d WHERE d.id_entrada = e.id_entrada);

-- Kárdex: cada lote recibido genera su movimiento de ENTRADA
INSERT INTO movimientos_inventario (id_lote, id_medicamento, tipo, cantidad, saldo_lote, motivo, id_entrada, id_usuario, fecha)
SELECT l.id_lote, l.id_medicamento, 'ENTRADA', d.cantidad, d.cantidad,
       CONCAT('Entrada factura ', e.numero_factura), e.id_entrada, e.id_usuario, e.fecha_entrada
  FROM detalle_entrada d
  JOIN lotes l    ON l.id_lote = d.id_lote
  JOIN entradas e ON e.id_entrada = d.id_entrada
 ORDER BY e.fecha_entrada, l.id_lote;


-- =====================================================================
-- GESTION - MEJORAS
-- Fuente: database/04_mejoras.sql
-- =====================================================================
-- =====================================================================
--  DrogueriaGestión · 04_mejoras.sql
--  Cambios aditivos e idempotentes para instalaciones nuevas o existentes:
--  agrega columnas/tablas si faltan, hace backfill y crea sus propios triggers.
--  No elimina datos ni altera las tablas de negocio existentes.
--
--  Aplicar a una base ya instalada (sin recrearla):
--      python database/init_db.py --solo-mejoras
--  o con el cliente de MySQL:
--      mysql -u root -p drogueria_gestion < database/04_mejoras.sql
--
--  Contenido:
--    1. Ciudad/país de clientes e índices.
--    2. Tablas stock e historial_facturas, backfill y sincronización transaccional.
--    3. ix_ventas_estado_fecha_valores: índice de cobertura de reportes.
--    4. sp_modelo_objetos(): definiciones de objetos para «Modelo de datos».
-- =====================================================================

USE drogueria_gestion;

DELIMITER $$

-- ---------------------------------------------------------------------
--  0. Ciudad y país para el CRUD y la clasificación de clientes.
--  Aplicable a instalaciones existentes y nuevas sin asignar nacionalidades
--  inventadas: los registros históricos quedan como NULL hasta actualizarlos.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_mejoras_geografia_clientes$$
CREATE PROCEDURE sp_mejoras_geografia_clientes()
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'clientes' AND COLUMN_NAME = 'ciudad') THEN
        ALTER TABLE clientes ADD COLUMN ciudad VARCHAR(50) NULL AFTER direccion;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'clientes' AND COLUMN_NAME = 'pais') THEN
        ALTER TABLE clientes ADD COLUMN pais VARCHAR(50) NULL
            COMMENT 'País o nacionalidad para clasificación de clientes' AFTER ciudad;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'clientes' AND INDEX_NAME = 'ix_clientes_pais') THEN
        CREATE INDEX ix_clientes_pais ON clientes (pais, ciudad);
    END IF;
END$$

CALL sp_mejoras_geografia_clientes()$$
DROP PROCEDURE IF EXISTS sp_mejoras_geografia_clientes$$

-- Tablas explícitas del parcial. La existencia resumida se mantiene por delta
-- desde lotes; FEFO y vencimientos siguen usando el detalle real de cada lote.
CREATE TABLE IF NOT EXISTS stock (
    id_medicamento  INT UNSIGNED NOT NULL PRIMARY KEY,
    cantidad_total  BIGINT UNSIGNED NOT NULL DEFAULT 0,
    actualizado_en  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_stock_medicamento FOREIGN KEY (id_medicamento) REFERENCES medicamentos (id_medicamento)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_stock_cantidad CHECK (cantidad_total >= 0)
) ENGINE = InnoDB COMMENT = 'Existencia resumida por medicamento; se sincroniza desde los lotes'$$

CREATE TABLE IF NOT EXISTS historial_facturas (
    id_historial_factura BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_venta             INT UNSIGNED NOT NULL,
    numero_factura       VARCHAR(20) NOT NULL,
    fecha_venta          DATETIME NOT NULL,
    id_cliente           INT UNSIGNED NOT NULL,
    subtotal             DECIMAL(14,2) NOT NULL,
    descuento            DECIMAL(14,2) NOT NULL,
    impuesto             DECIMAL(14,2) NOT NULL,
    total                DECIMAL(14,2) NOT NULL,
    metodo_pago          ENUM('EFECTIVO','TARJETA_DEBITO','TARJETA_CREDITO','TRANSFERENCIA') NOT NULL,
    fecha_registro       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_historial_factura_venta UNIQUE (id_venta),
    CONSTRAINT uq_historial_factura_numero UNIQUE (numero_factura),
    CONSTRAINT fk_historial_factura_venta FOREIGN KEY (id_venta) REFERENCES ventas (id_venta)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_historial_factura_valores CHECK (subtotal >= 0 AND descuento >= 0 AND impuesto >= 0 AND total >= 0)
) ENGINE = InnoDB COMMENT = 'Cabecera histórica inmutable de las facturas emitidas'$$

-- Backfill idempotente para las instalaciones que ya tenían ventas y lotes.
INSERT INTO stock (id_medicamento, cantidad_total)
SELECT m.id_medicamento, COALESCE(SUM(l.cantidad_actual), 0)
  FROM medicamentos m LEFT JOIN lotes l ON l.id_medicamento = m.id_medicamento
 GROUP BY m.id_medicamento
ON DUPLICATE KEY UPDATE cantidad_total = VALUES(cantidad_total)$$

INSERT INTO historial_facturas
       (id_venta, numero_factura, fecha_venta, id_cliente, subtotal, descuento, impuesto, total, metodo_pago)
SELECT id_venta, numero_factura, fecha_venta, id_cliente, subtotal, descuento, impuesto, total, metodo_pago
  FROM ventas
ON DUPLICATE KEY UPDATE numero_factura = VALUES(numero_factura), fecha_venta = VALUES(fecha_venta),
                        id_cliente = VALUES(id_cliente), subtotal = VALUES(subtotal), descuento = VALUES(descuento),
                        impuesto = VALUES(impuesto), total = VALUES(total), metodo_pago = VALUES(metodo_pago)$$

-- Nuevos medicamentos comienzan con stock cero; cada cambio de lote mantiene
-- el resumen dentro de la misma transacción que cambió la existencia real.
DROP TRIGGER IF EXISTS trg_medicamentos_stock_ai$$
CREATE TRIGGER trg_medicamentos_stock_ai
AFTER INSERT ON medicamentos
FOR EACH ROW
BEGIN
    INSERT IGNORE INTO stock (id_medicamento, cantidad_total) VALUES (NEW.id_medicamento, 0);
END$$

DROP TRIGGER IF EXISTS trg_lotes_stock_ai$$
CREATE TRIGGER trg_lotes_stock_ai
AFTER INSERT ON lotes
FOR EACH ROW
BEGIN
    INSERT INTO stock (id_medicamento, cantidad_total) VALUES (NEW.id_medicamento, NEW.cantidad_actual)
    ON DUPLICATE KEY UPDATE cantidad_total = cantidad_total + NEW.cantidad_actual;
END$$

DROP TRIGGER IF EXISTS trg_lotes_stock_au$$
CREATE TRIGGER trg_lotes_stock_au
AFTER UPDATE ON lotes
FOR EACH ROW
BEGIN
    IF OLD.id_medicamento = NEW.id_medicamento THEN
        UPDATE stock
           SET cantidad_total = cantidad_total - OLD.cantidad_actual + NEW.cantidad_actual
         WHERE id_medicamento = NEW.id_medicamento;
    ELSE
        UPDATE stock
           SET cantidad_total = cantidad_total - OLD.cantidad_actual
         WHERE id_medicamento = OLD.id_medicamento;
        INSERT INTO stock (id_medicamento, cantidad_total) VALUES (NEW.id_medicamento, NEW.cantidad_actual)
        ON DUPLICATE KEY UPDATE cantidad_total = cantidad_total + NEW.cantidad_actual;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_lotes_stock_ad$$
CREATE TRIGGER trg_lotes_stock_ad
AFTER DELETE ON lotes
FOR EACH ROW
BEGIN
    UPDATE stock
       SET cantidad_total = cantidad_total - OLD.cantidad_actual
     WHERE id_medicamento = OLD.id_medicamento;
END$$

-- Cada venta confirmada deja una cabecera histórica, en la misma transacción.
DROP TRIGGER IF EXISTS trg_ventas_historial_factura_ai$$
CREATE TRIGGER trg_ventas_historial_factura_ai
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO historial_facturas
           (id_venta, numero_factura, fecha_venta, id_cliente, subtotal, descuento, impuesto, total, metodo_pago)
    VALUES (NEW.id_venta, NEW.numero_factura, NEW.fecha_venta, NEW.id_cliente, NEW.subtotal,
            NEW.descuento, NEW.impuesto, NEW.total, NEW.metodo_pago);
END$$

-- ---------------------------------------------------------------------
--  Procedimiento auxiliar (temporal): crea un índice solo si no existe.
--  MySQL no tiene CREATE INDEX IF NOT EXISTS; se consulta information_schema
--  y se ejecuta la sentencia con PREPARE. Se elimina al final del script.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_mejoras_crear_indice$$
CREATE PROCEDURE sp_mejoras_crear_indice(IN p_tabla VARCHAR(64), IN p_indice VARCHAR(64), IN p_columnas VARCHAR(255))
BEGIN
    IF NOT EXISTS (SELECT 1
                     FROM information_schema.STATISTICS
                    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_tabla AND INDEX_NAME = p_indice) THEN
        SET @ddl_mejoras = CONCAT('CREATE INDEX `', p_indice, '` ON `', p_tabla, '` (', p_columnas, ')');
        PREPARE sentencia FROM @ddl_mejoras;
        EXECUTE sentencia;
        DEALLOCATE PREPARE sentencia;
    END IF;
END$$

-- ---------------------------------------------------------------------
--  1. Índice de cobertura sobre ventas para el análisis ABC y los totales de los
--  reportes. Ambas consultas filtran por estado y rango de fechas y solo leen los
--  valores de la venta: con estas columnas MySQL responde desde el índice, sin leer
--  las filas de la tabla («Using index» en EXPLAIN).
--  Empieza por estado (no es una llave foránea) a propósito: si empezara por una
--  columna con llave foránea, MySQL borraría por su cuenta el índice implícito de esa
--  llave y el cambio dejaría de ser solo aditivo.
-- ---------------------------------------------------------------------
CALL sp_mejoras_crear_indice('ventas', 'ix_ventas_estado_fecha_valores',
                             'estado, fecha_venta, subtotal, descuento, impuesto, total')$$

DROP PROCEDURE IF EXISTS sp_mejoras_crear_indice$$

-- ---------------------------------------------------------------------
--  2. Objetos programados de la base, con su definición.
--  El usuario de la aplicación no ve los triggers en information_schema (exige el
--  privilegio TRIGGER, que además permitiría crearlos y borrarlos) ni el código de
--  las rutinas y vistas. Con SQL SECURITY DEFINER el procedimiento consulta
--  information_schema con los privilegios de quien lo creó; la aplicación solo
--  necesita EXECUTE (que ya tiene) y recibe metadatos de solo lectura de esta base.
--  Devuelve tres resultados: triggers, rutinas y vistas.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_modelo_objetos$$
CREATE PROCEDURE sp_modelo_objetos()
    SQL SECURITY DEFINER
    READS SQL DATA
    COMMENT 'Triggers, rutinas y vistas de la base con su definición (pantalla Modelo de datos)'
BEGIN
    SELECT TRIGGER_NAME       AS nombre,
           EVENT_OBJECT_TABLE AS tabla,
           ACTION_TIMING      AS momento,
           EVENT_MANIPULATION AS evento,
           ACTION_STATEMENT   AS definicion
      FROM information_schema.TRIGGERS
     WHERE TRIGGER_SCHEMA = DATABASE()
     ORDER BY EVENT_OBJECT_TABLE, TRIGGER_NAME;

    SELECT ROUTINE_NAME       AS nombre,
           ROUTINE_TYPE       AS tipo,
           DTD_IDENTIFIER     AS retorna,
           SECURITY_TYPE      AS seguridad,
           ROUTINE_COMMENT    AS comentario,
           ROUTINE_DEFINITION AS definicion
      FROM information_schema.ROUTINES
     WHERE ROUTINE_SCHEMA = DATABASE()
     ORDER BY ROUTINE_TYPE, ROUTINE_NAME;

    SELECT TABLE_NAME      AS nombre,
           VIEW_DEFINITION AS definicion
      FROM information_schema.VIEWS
     WHERE TABLE_SCHEMA = DATABASE()
     ORDER BY TABLE_NAME;
END$$

DELIMITER ;


-- =====================================================================
-- TIENDA - ESQUEMA
-- Fuente: database/schema.sql
-- =====================================================================
-- =====================================================================
--  Tienda en línea de la droguería (e-commerce)
--  schema.sql — Esquema de la base de datos drogueria_db
--  Motor: MySQL 8.x (InnoDB) | Juego de caracteres: utf8mb4 / utf8mb4_unicode_ci
--
--  Ejecutar en un servidor limpio con un usuario que pueda crear bases de datos:
--      mysql -u <usuario_admin> -p < database/schema.sql
--  ATENCIÓN: borra y recrea SOLO la base drogueria_db.
-- =====================================================================

DROP DATABASE IF EXISTS drogueria_db;
CREATE DATABASE drogueria_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE drogueria_db;

-- ---------------------------------------------------------------------
--  1. Seguridad: roles y usuarios                          (RF-12, RF-13)
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    id_rol          TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    codigo          VARCHAR(20)  NOT NULL COMMENT 'CLIENTE, FARMACEUTICO, ADMINISTRADOR',
    nombre          VARCHAR(50)  NOT NULL,
    descripcion     VARCHAR(255) NULL,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_roles PRIMARY KEY (id_rol),
    CONSTRAINT uq_roles_codigo UNIQUE (codigo)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Roles del sistema: cliente, farmacéutico y administrador';

CREATE TABLE usuarios (
    id_usuario              INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_rol                  TINYINT UNSIGNED NOT NULL,
    tipo_documento          ENUM('CC','CE','TI','PA','PPT') NOT NULL DEFAULT 'CC',
    numero_documento        VARCHAR(20)  NOT NULL,
    nombres                 VARCHAR(80)  NOT NULL,
    apellidos               VARCHAR(80)  NOT NULL,
    email                   VARCHAR(120) NOT NULL,
    telefono                VARCHAR(20)  NULL,
    password_hash           VARCHAR(255) NOT NULL COMMENT 'Argon2id en formato PHC',
    acepta_tratamiento_datos TINYINT     NOT NULL DEFAULT 0 COMMENT 'Autorización Ley 1581 de 2012',
    fecha_autorizacion_datos DATETIME    NULL,
    activo                  TINYINT      NOT NULL DEFAULT 1,
    ultimo_acceso           DATETIME     NULL,
    created_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_usuarios PRIMARY KEY (id_usuario),
    CONSTRAINT uq_usuarios_email UNIQUE (email),
    CONSTRAINT uq_usuarios_documento UNIQUE (tipo_documento, numero_documento),
    CONSTRAINT fk_usuarios_rol FOREIGN KEY (id_rol) REFERENCES roles (id_rol)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_usuarios_email CHECK (email LIKE '%_@_%._%'),
    CONSTRAINT ck_usuarios_autorizacion CHECK (acepta_tratamiento_datos = 0 OR fecha_autorizacion_datos IS NOT NULL)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Personas registradas (clientes y personal)';

CREATE INDEX ix_usuarios_rol ON usuarios (id_rol);

-- ---------------------------------------------------------------------
--  2. Ubicación: ciudades con cobertura, direcciones y sedes (RF-14, RF-15, RF-24)
-- ---------------------------------------------------------------------
CREATE TABLE ciudades (
    id_ciudad           SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre              VARCHAR(80)   NOT NULL,
    departamento        VARCHAR(80)   NOT NULL,
    codigo_dane         CHAR(5)       NOT NULL COMMENT 'Código DANE del municipio',
    costo_domicilio     DECIMAL(12,2) NOT NULL DEFAULT 0,
    tiene_cobertura     TINYINT       NOT NULL DEFAULT 1,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_ciudades PRIMARY KEY (id_ciudad),
    CONSTRAINT uq_ciudades_dane UNIQUE (codigo_dane),
    CONSTRAINT ck_ciudades_costo CHECK (costo_domicilio >= 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Municipios con cobertura de domicilios y su tarifa';

CREATE TABLE direcciones (
    id_direccion        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    id_usuario          INT UNSIGNED  NOT NULL,
    id_ciudad           SMALLINT UNSIGNED NOT NULL,
    alias               VARCHAR(40)   NOT NULL COMMENT 'Casa, Oficina...',
    direccion           VARCHAR(150)  NOT NULL,
    barrio              VARCHAR(80)   NULL,
    indicaciones        VARCHAR(255)  NULL COMMENT 'Torre, apartamento, referencias',
    es_principal        TINYINT       NOT NULL DEFAULT 0,
    activo              TINYINT       NOT NULL DEFAULT 1,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_direcciones PRIMARY KEY (id_direccion),
    CONSTRAINT fk_direcciones_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_direcciones_ciudad FOREIGN KEY (id_ciudad) REFERENCES ciudades (id_ciudad)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Direcciones de entrega de cada cliente';

CREATE INDEX ix_direcciones_usuario ON direcciones (id_usuario);
CREATE INDEX ix_direcciones_ciudad ON direcciones (id_ciudad);

CREATE TABLE sedes (
    id_sede             SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_ciudad           SMALLINT UNSIGNED NOT NULL,
    nombre              VARCHAR(80)   NOT NULL,
    direccion           VARCHAR(150)  NOT NULL,
    telefono            VARCHAR(20)   NOT NULL,
    horario             VARCHAR(120)  NOT NULL COMMENT 'Ej.: Lun-Sáb 7:00-21:00; Dom 8:00-14:00',
    latitud             DECIMAL(9,6)  NULL,
    longitud            DECIMAL(9,6)  NULL,
    permite_retiro      TINYINT       NOT NULL DEFAULT 1 COMMENT 'Recoger en tienda',
    activo              TINYINT       NOT NULL DEFAULT 1,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_sedes PRIMARY KEY (id_sede),
    CONSTRAINT uq_sedes_nombre UNIQUE (nombre),
    CONSTRAINT fk_sedes_ciudad FOREIGN KEY (id_ciudad) REFERENCES ciudades (id_ciudad)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_sedes_coordenadas CHECK (
        (latitud IS NULL OR latitud BETWEEN -90 AND 90) AND (longitud IS NULL OR longitud BETWEEN -180 AND 180))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Puntos de venta físicos (inventario propio, retiro en tienda)';

CREATE INDEX ix_sedes_ciudad ON sedes (id_ciudad);

-- ---------------------------------------------------------------------
--  3. Catálogo: categorías, laboratorios, principios activos y productos
--                                                    (RF-01 a RF-06, RF-27)
-- ---------------------------------------------------------------------
CREATE TABLE categorias (
    id_categoria        SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_categoria_padre  SMALLINT UNSIGNED NULL COMMENT 'NULL = categoría principal',
    nombre              VARCHAR(80)   NOT NULL,
    slug                VARCHAR(90)   NOT NULL COMMENT 'Fragmento de URL',
    descripcion         VARCHAR(255)  NULL,
    icono               VARCHAR(40)   NULL COMMENT 'Nombre del ícono SVG del frontend',
    orden               SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    activo              TINYINT       NOT NULL DEFAULT 1,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_categorias PRIMARY KEY (id_categoria),
    CONSTRAINT uq_categorias_slug UNIQUE (slug),
    CONSTRAINT fk_categorias_padre FOREIGN KEY (id_categoria_padre) REFERENCES categorias (id_categoria)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Árbol de categorías del catálogo (menú)';

CREATE INDEX ix_categorias_padre ON categorias (id_categoria_padre);
CREATE INDEX ix_categorias_activo_orden ON categorias (activo, orden);

CREATE TABLE laboratorios (
    id_laboratorio      SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre              VARCHAR(100)  NOT NULL,
    pais                VARCHAR(60)   NOT NULL DEFAULT 'Colombia',
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_laboratorios PRIMARY KEY (id_laboratorio),
    CONSTRAINT uq_laboratorios_nombre UNIQUE (nombre)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Laboratorios fabricantes o titulares del registro';

CREATE TABLE principios_activos (
    id_principio_activo SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre              VARCHAR(120)  NOT NULL COMMENT 'Denominación común internacional (DCI)',
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_principios_activos PRIMARY KEY (id_principio_activo),
    CONSTRAINT uq_principios_activos_nombre UNIQUE (nombre)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Sustancias activas (un producto puede combinar varias)';

CREATE TABLE productos (
    id_producto         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    id_categoria        SMALLINT UNSIGNED NOT NULL,
    id_laboratorio      SMALLINT UNSIGNED NOT NULL,
    sku                 VARCHAR(30)   NOT NULL COMMENT 'Código interno o EAN',
    nombre              VARCHAR(150)  NOT NULL,
    slug                VARCHAR(170)  NOT NULL,
    descripcion         TEXT          NULL,
    presentacion        VARCHAR(80)   NOT NULL COMMENT 'Ej.: Caja x 30 tabletas',
    forma_farmaceutica  VARCHAR(40)   NOT NULL COMMENT 'Tableta, jarabe, crema...',
    registro_invima     VARCHAR(40)   NULL COMMENT 'Registro sanitario INVIMA',
    requiere_formula    TINYINT       NOT NULL DEFAULT 0 COMMENT '1 = venta bajo fórmula médica',
    precio              DECIMAL(12,2) NOT NULL COMMENT 'Precio de venta sin promoción, IVA incluido',
    iva_porcentaje      DECIMAL(5,2)  NOT NULL DEFAULT 0,
    imagen_url          VARCHAR(255)  NULL,
    destacado           TINYINT       NOT NULL DEFAULT 0 COMMENT 'Aparece en el carrusel de inicio',
    activo              TINYINT       NOT NULL DEFAULT 1,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_productos PRIMARY KEY (id_producto),
    CONSTRAINT uq_productos_sku UNIQUE (sku),
    CONSTRAINT uq_productos_slug UNIQUE (slug),
    CONSTRAINT fk_productos_categoria FOREIGN KEY (id_categoria) REFERENCES categorias (id_categoria)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_productos_laboratorio FOREIGN KEY (id_laboratorio) REFERENCES laboratorios (id_laboratorio)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_productos_precio CHECK (precio >= 0),
    CONSTRAINT ck_productos_iva CHECK (iva_porcentaje IN (0, 5, 19)),
    FULLTEXT INDEX ft_productos_nombre_descripcion (nombre, descripcion)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Catálogo de medicamentos y productos de cuidado';

CREATE INDEX ix_productos_categoria ON productos (id_categoria);
CREATE INDEX ix_productos_laboratorio ON productos (id_laboratorio);
CREATE INDEX ix_productos_nombre ON productos (nombre);
CREATE INDEX ix_productos_destacado ON productos (activo, destacado);

CREATE TABLE producto_principio_activo (
    id_producto         INT UNSIGNED  NOT NULL,
    id_principio_activo SMALLINT UNSIGNED NOT NULL,
    concentracion       VARCHAR(40)   NOT NULL COMMENT 'Ej.: 500 mg, 12,5 mg/5 mL',
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_producto_principio_activo PRIMARY KEY (id_producto, id_principio_activo),
    CONSTRAINT fk_ppa_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ppa_principio_activo FOREIGN KEY (id_principio_activo) REFERENCES principios_activos (id_principio_activo)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Tabla puente N:M producto - principio activo, con su concentración';

CREATE INDEX ix_ppa_principio_activo ON producto_principio_activo (id_principio_activo);

-- ---------------------------------------------------------------------
--  4. Inventario por sede, con lotes y vencimientos     (RF-21, RF-22, RF-23)
-- ---------------------------------------------------------------------
CREATE TABLE lotes (
    id_lote             INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    id_producto         INT UNSIGNED  NOT NULL,
    numero_lote         VARCHAR(40)   NOT NULL,
    fecha_fabricacion   DATE          NULL,
    fecha_vencimiento   DATE          NOT NULL,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_lotes PRIMARY KEY (id_lote),
    CONSTRAINT uq_lotes_producto_numero UNIQUE (id_producto, numero_lote),
    CONSTRAINT fk_lotes_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_lotes_fechas CHECK (fecha_fabricacion IS NULL OR fecha_vencimiento > fecha_fabricacion)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Lotes de fabricante con su fecha de vencimiento';

CREATE INDEX ix_lotes_vencimiento ON lotes (fecha_vencimiento);

CREATE TABLE inventario (
    id_inventario       INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    id_sede             SMALLINT UNSIGNED NOT NULL,
    id_lote             INT UNSIGNED  NOT NULL,
    cantidad            INT UNSIGNED  NOT NULL DEFAULT 0 COMMENT 'Existencia actual del lote en la sede',
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_inventario PRIMARY KEY (id_inventario),
    CONSTRAINT uq_inventario_sede_lote UNIQUE (id_sede, id_lote),
    CONSTRAINT fk_inventario_sede FOREIGN KEY (id_sede) REFERENCES sedes (id_sede)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_inventario_lote FOREIGN KEY (id_lote) REFERENCES lotes (id_lote)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_inventario_cantidad CHECK (cantidad >= 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Tabla puente N:M sede - lote con la existencia';

CREATE INDEX ix_inventario_lote ON inventario (id_lote);

-- ---------------------------------------------------------------------
--  5. Promociones                                              (RF-25)
-- ---------------------------------------------------------------------
CREATE TABLE promociones (
    id_promocion        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    nombre              VARCHAR(100)  NOT NULL,
    descripcion         VARCHAR(255)  NULL,
    tipo_descuento      ENUM('PORCENTAJE','VALOR') NOT NULL,
    valor_descuento     DECIMAL(12,2) NOT NULL COMMENT '% (1-90) o pesos por unidad',
    fecha_inicio        DATETIME      NOT NULL,
    fecha_fin           DATETIME      NOT NULL,
    mostrar_en_banner   TINYINT       NOT NULL DEFAULT 0 COMMENT 'Alimenta el banner rotativo de inicio',
    titulo_banner       VARCHAR(80)   NULL,
    subtitulo_banner    VARCHAR(150)  NULL,
    imagen_banner_url   VARCHAR(255)  NULL,
    activo              TINYINT       NOT NULL DEFAULT 1,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_promociones PRIMARY KEY (id_promocion),
    CONSTRAINT ck_promociones_fechas CHECK (fecha_fin > fecha_inicio),
    CONSTRAINT ck_promociones_valor CHECK (
        valor_descuento > 0 AND (tipo_descuento = 'VALOR' OR valor_descuento <= 90)),
    CONSTRAINT ck_promociones_banner CHECK (mostrar_en_banner = 0 OR titulo_banner IS NOT NULL)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Campañas de descuento con vigencia';

CREATE INDEX ix_promociones_vigencia ON promociones (activo, fecha_inicio, fecha_fin);

CREATE TABLE promocion_producto (
    id_promocion        INT UNSIGNED  NOT NULL,
    id_producto         INT UNSIGNED  NOT NULL,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_promocion_producto PRIMARY KEY (id_promocion, id_producto),
    CONSTRAINT fk_pp_promocion FOREIGN KEY (id_promocion) REFERENCES promociones (id_promocion)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pp_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Tabla puente N:M promoción - producto';

CREATE INDEX ix_pp_producto ON promocion_producto (id_producto);

-- ---------------------------------------------------------------------
--  6. Carrito                                              (RF-07, RF-08)
-- ---------------------------------------------------------------------
CREATE TABLE carritos (
    id_carrito          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    id_usuario          INT UNSIGNED  NULL COMMENT 'NULL mientras el visitante no inicia sesión',
    token               CHAR(36)      NOT NULL COMMENT 'UUID guardado en una cookie',
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_carritos PRIMARY KEY (id_carrito),
    CONSTRAINT uq_carritos_token UNIQUE (token),
    CONSTRAINT uq_carritos_usuario UNIQUE (id_usuario),
    CONSTRAINT fk_carritos_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Carrito activo (anónimo por token o asociado 1:1 a un usuario)';

CREATE TABLE carrito_items (
    id_carrito          INT UNSIGNED  NOT NULL,
    id_producto         INT UNSIGNED  NOT NULL,
    cantidad            SMALLINT UNSIGNED NOT NULL,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_carrito_items PRIMARY KEY (id_carrito, id_producto),
    CONSTRAINT fk_ci_carrito FOREIGN KEY (id_carrito) REFERENCES carritos (id_carrito)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ci_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_ci_cantidad CHECK (cantidad > 0 AND cantidad <= 99)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Tabla puente N:M carrito - producto con la cantidad';

CREATE INDEX ix_ci_producto ON carrito_items (id_producto);

-- ---------------------------------------------------------------------
--  7. Fórmulas médicas                                    (RF-18, RF-19, RF-20)
-- ---------------------------------------------------------------------
CREATE TABLE formulas_medicas (
    id_formula          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    id_usuario          INT UNSIGNED  NOT NULL COMMENT 'Cliente que la carga',
    id_revisor          INT UNSIGNED  NULL COMMENT 'Farmacéutico que la valida',
    archivo             MEDIUMBLOB    NOT NULL COMMENT 'Imagen o PDF (máx. 5 MB, validado en la API)',
    archivo_mime        VARCHAR(50)   NOT NULL,
    archivo_sha256      CHAR(64)      NOT NULL,
    medico_nombre       VARCHAR(120)  NULL,
    medico_registro     VARCHAR(30)   NULL COMMENT 'Registro profesional del prescriptor',
    fecha_emision       DATE          NOT NULL,
    estado              ENUM('PENDIENTE','APROBADA','RECHAZADA') NOT NULL DEFAULT 'PENDIENTE',
    observaciones       VARCHAR(255)  NULL,
    revisada_en         DATETIME      NULL,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_formulas_medicas PRIMARY KEY (id_formula),
    CONSTRAINT fk_formulas_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_formulas_revisor FOREIGN KEY (id_revisor) REFERENCES usuarios (id_usuario)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT ck_formulas_mime CHECK (archivo_mime IN ('image/jpeg','image/png','application/pdf')),
    CONSTRAINT ck_formulas_revision CHECK (estado = 'PENDIENTE' OR revisada_en IS NOT NULL)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Fórmulas médicas cargadas por los clientes y su validación';

CREATE INDEX ix_formulas_usuario ON formulas_medicas (id_usuario);
CREATE INDEX ix_formulas_revisor ON formulas_medicas (id_revisor);
CREATE INDEX ix_formulas_estado ON formulas_medicas (estado, created_at);

-- ---------------------------------------------------------------------
--  8. Pedidos                                    (RF-09, RF-10, RF-11, RF-16)
-- ---------------------------------------------------------------------
CREATE TABLE pedidos (
    id_pedido           INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    codigo              VARCHAR(20)   NOT NULL COMMENT 'Ej.: PED-000123',
    id_usuario          INT UNSIGNED  NOT NULL,
    id_sede             SMALLINT UNSIGNED NOT NULL COMMENT 'Sede que despacha o donde se retira',
    id_direccion        INT UNSIGNED  NULL COMMENT 'NULL si es retiro en tienda',
    tipo_entrega        ENUM('DOMICILIO','RETIRO') NOT NULL,
    direccion_entrega   VARCHAR(400)  NULL COMMENT 'Copia de la dirección al momento de comprar',
    estado              ENUM('PENDIENTE_FORMULA','CONFIRMADO','EN_PREPARACION','EN_CAMINO',
                             'LISTO_PARA_RETIRO','ENTREGADO','CANCELADO') NOT NULL DEFAULT 'CONFIRMADO',
    metodo_pago         ENUM('CONTRA_ENTREGA','TARJETA','PSE') NOT NULL,
    subtotal            DECIMAL(12,2) NOT NULL,
    descuento           DECIMAL(12,2) NOT NULL DEFAULT 0,
    costo_envio         DECIMAL(12,2) NOT NULL DEFAULT 0,
    total               DECIMAL(12,2) NOT NULL,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_pedidos PRIMARY KEY (id_pedido),
    CONSTRAINT uq_pedidos_codigo UNIQUE (codigo),
    CONSTRAINT fk_pedidos_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pedidos_sede FOREIGN KEY (id_sede) REFERENCES sedes (id_sede)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pedidos_direccion FOREIGN KEY (id_direccion) REFERENCES direcciones (id_direccion)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT ck_pedidos_valores CHECK (subtotal >= 0 AND descuento >= 0 AND costo_envio >= 0 AND total >= 0),
    CONSTRAINT ck_pedidos_total CHECK (total = subtotal - descuento + costo_envio),
    -- La regla de domicilio usa la copia de texto: MySQL no permite CHECK sobre columnas con acción FK
    CONSTRAINT ck_pedidos_entrega CHECK (tipo_entrega = 'RETIRO' OR direccion_entrega IS NOT NULL)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Encabezado de los pedidos de la tienda en línea';

CREATE INDEX ix_pedidos_usuario ON pedidos (id_usuario, created_at);
CREATE INDEX ix_pedidos_sede ON pedidos (id_sede);
CREATE INDEX ix_pedidos_direccion ON pedidos (id_direccion);
CREATE INDEX ix_pedidos_estado ON pedidos (estado, created_at);

CREATE TABLE pedido_items (
    id_pedido_item      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    id_pedido           INT UNSIGNED  NOT NULL,
    id_producto         INT UNSIGNED  NOT NULL,
    id_formula          INT UNSIGNED  NULL COMMENT 'Fórmula que respalda un producto que la requiere',
    cantidad            SMALLINT UNSIGNED NOT NULL,
    precio_unitario     DECIMAL(12,2) NOT NULL COMMENT 'Precio de lista al comprar',
    descuento_unitario  DECIMAL(12,2) NOT NULL DEFAULT 0,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_pedido_items PRIMARY KEY (id_pedido_item),
    CONSTRAINT uq_pedido_items_producto UNIQUE (id_pedido, id_producto),
    CONSTRAINT fk_pi_pedido FOREIGN KEY (id_pedido) REFERENCES pedidos (id_pedido)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pi_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pi_formula FOREIGN KEY (id_formula) REFERENCES formulas_medicas (id_formula)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_pi_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_pi_precios CHECK (precio_unitario >= 0 AND descuento_unitario >= 0
                                    AND descuento_unitario <= precio_unitario)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Productos de cada pedido (precio congelado al comprar)';

CREATE INDEX ix_pi_producto ON pedido_items (id_producto);
CREATE INDEX ix_pi_formula ON pedido_items (id_formula);

CREATE TABLE pedido_item_lotes (
    id_pedido_item      INT UNSIGNED  NOT NULL,
    id_lote             INT UNSIGNED  NOT NULL,
    cantidad            SMALLINT UNSIGNED NOT NULL,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_pedido_item_lotes PRIMARY KEY (id_pedido_item, id_lote),
    CONSTRAINT fk_pil_pedido_item FOREIGN KEY (id_pedido_item) REFERENCES pedido_items (id_pedido_item)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pil_lote FOREIGN KEY (id_lote) REFERENCES lotes (id_lote)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_pil_cantidad CHECK (cantidad > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Tabla puente N:M ítem de pedido - lote despachado (trazabilidad FEFO)';

CREATE INDEX ix_pil_lote ON pedido_item_lotes (id_lote);

-- Lote real del inventario administrativo (otra base del mismo servidor MySQL; no admite FK entre esquemas).
CREATE TABLE pedido_item_lotes_gestion (
    id_pedido_item      INT UNSIGNED NOT NULL,
    id_lote_gestion     INT UNSIGNED NOT NULL,
    cantidad            SMALLINT UNSIGNED NOT NULL,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_pilg PRIMARY KEY (id_pedido_item, id_lote_gestion),
    CONSTRAINT fk_pilg_pedido_item FOREIGN KEY (id_pedido_item) REFERENCES pedido_items (id_pedido_item)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_pilg_cantidad CHECK (cantidad > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Trazabilidad del pedido contra lotes de drogueria_gestion';

CREATE INDEX ix_pilg_lote_gestion ON pedido_item_lotes_gestion (id_lote_gestion);

CREATE TABLE pedido_historial (
    id_historial        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    id_pedido           INT UNSIGNED  NOT NULL,
    id_usuario          INT UNSIGNED  NULL COMMENT 'Quién cambió el estado (NULL = sistema)',
    estado              ENUM('PENDIENTE_FORMULA','CONFIRMADO','EN_PREPARACION','EN_CAMINO',
                             'LISTO_PARA_RETIRO','ENTREGADO','CANCELADO') NOT NULL,
    comentario          VARCHAR(255)  NULL,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_pedido_historial PRIMARY KEY (id_historial),
    CONSTRAINT fk_ph_pedido FOREIGN KEY (id_pedido) REFERENCES pedidos (id_pedido)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ph_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Línea de tiempo de estados de cada pedido';

CREATE INDEX ix_ph_pedido ON pedido_historial (id_pedido, created_at);
CREATE INDEX ix_ph_usuario ON pedido_historial (id_usuario);

-- ---------------------------------------------------------------------
--  9. Kárdex y auditoría                                  (RF-23, RF-29)
-- ---------------------------------------------------------------------
CREATE TABLE movimientos_inventario (
    id_movimiento       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_inventario       INT UNSIGNED  NOT NULL,
    id_pedido           INT UNSIGNED  NULL,
    id_usuario          INT UNSIGNED  NULL,
    tipo                ENUM('ENTRADA','VENTA','AJUSTE_ENTRADA','AJUSTE_SALIDA','BAJA_VENCIMIENTO','DEVOLUCION') NOT NULL,
    cantidad            INT UNSIGNED  NOT NULL,
    saldo               INT UNSIGNED  NOT NULL COMMENT 'Existencia del lote en la sede después del movimiento',
    motivo              VARCHAR(255)  NULL,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_movimientos_inventario PRIMARY KEY (id_movimiento),
    CONSTRAINT fk_mi_inventario FOREIGN KEY (id_inventario) REFERENCES inventario (id_inventario)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_mi_pedido FOREIGN KEY (id_pedido) REFERENCES pedidos (id_pedido)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_mi_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT ck_mi_cantidad CHECK (cantidad > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Kárdex: cada cambio de existencias de un lote en una sede';

CREATE INDEX ix_mi_inventario ON movimientos_inventario (id_inventario, created_at);
CREATE INDEX ix_mi_pedido ON movimientos_inventario (id_pedido);
CREATE INDEX ix_mi_usuario ON movimientos_inventario (id_usuario);

CREATE TABLE auditoria (
    id_auditoria        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_usuario          INT UNSIGNED  NULL,
    accion              VARCHAR(40)   NOT NULL COMMENT 'CREAR, ACTUALIZAR, APROBAR_FORMULA, LOGIN...',
    entidad             VARCHAR(40)   NOT NULL COMMENT 'Tabla afectada',
    id_entidad          VARCHAR(40)   NULL,
    detalle             VARCHAR(500)  NULL,
    ip                  VARCHAR(45)   NULL,
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_auditoria PRIMARY KEY (id_auditoria),
    CONSTRAINT fk_auditoria_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Bitácora de acciones del personal en el panel administrativo';

CREATE INDEX ix_auditoria_usuario ON auditoria (id_usuario);
CREATE INDEX ix_auditoria_fecha ON auditoria (created_at);


-- =====================================================================
-- TIENDA - DATOS DE PRUEBA
-- Fuente: database/seed.sql
-- =====================================================================
-- =====================================================================
--  Tienda en línea de la droguería — seed.sql
--  Datos FICTICIOS de prueba para drogueria_db (ejecutar después de schema.sql):
--      mysql -u <usuario> -p drogueria_db < database/seed.sql
--  Generado con un script determinista. Las fechas son relativas al día de la
--  instalación (CURDATE()/NOW()), así siempre hay lotes vigentes y promociones activas.
--
--  Usuarios de prueba (contraseñas guardadas solo como hash Argon2id):
--    cliente@tienda-demo.co       / Cliente2026*    (rol CLIENTE)
--    farmaceutico@tienda-demo.co  / Farmacia2026*   (rol FARMACEUTICO)
--    admin@tienda-demo.co         / Admin2026*      (rol ADMINISTRADOR)
--
--  Contenido: 12 categorías, 42 productos (11 con fórmula), 3 sedes,
--  64 lotes, 190 registros de inventario, 4 promociones, 3 usuarios.
-- =====================================================================

USE drogueria_db;
SET NAMES utf8mb4;
START TRANSACTION;

-- Roles

INSERT INTO roles (id_rol, codigo, nombre, descripcion) VALUES
(1, 'CLIENTE', 'Cliente', 'Compra en la tienda en línea'),
(2, 'FARMACEUTICO', 'Farmacéutico', 'Valida fórmulas médicas y prepara pedidos'),
(3, 'ADMINISTRADOR', 'Administrador', 'Gestiona catálogo, inventario, promociones y sedes');

-- Usuarios de prueba (contraseñas hasheadas con Argon2id; ver README.md para las claves de prueba)

INSERT INTO usuarios (id_usuario, id_rol, tipo_documento, numero_documento, nombres, apellidos, email, telefono, password_hash, acepta_tratamiento_datos, fecha_autorizacion_datos) VALUES
(1, 1, 'CC', '1000000001', 'Ana Lucía', 'Pérez Gómez', 'cliente@tienda-demo.co', '3000000001', '$argon2id$v=19$m=65536,t=3,p=4$5HCREijW4SglV975l/4mtw$pOE1z/KV72AKbGLi8OrY43BEjkAVJAxZwb8TwPbOr0k', 1, NOW() - INTERVAL 30 DAY),
(2, 2, 'CC', '1000000002', 'Carlos Andrés', 'Rojas Díaz', 'farmaceutico@tienda-demo.co', '3000000002', '$argon2id$v=19$m=65536,t=3,p=4$11DJrRqnefOrnZkC9xuaJA$sFY56nqabmFjKe2O2sv85Ei+T7nMHRiS5Lz7vx0Szc4', 1, NOW() - INTERVAL 30 DAY),
(3, 3, 'CC', '1000000003', 'Diana Marcela', 'Suárez León', 'admin@tienda-demo.co', '3000000003', '$argon2id$v=19$m=65536,t=3,p=4$iqSiyAmuoY7GAYsTHjKP9Q$fqtm8I0sWw0/Dqmb+p/ByeGA6v5QE3qlU0P7hRAPdwM', 1, NOW() - INTERVAL 30 DAY);

-- Ciudades con cobertura (códigos DANE)

INSERT INTO ciudades (id_ciudad, nombre, departamento, codigo_dane, costo_domicilio, tiene_cobertura) VALUES
(1, 'Bogotá D.C.', 'Bogotá D.C.', '11001', 6900, 1),
(2, 'Medellín', 'Antioquia', '05001', 7900, 1),
(3, 'Cali', 'Valle del Cauca', '76001', 7900, 1),
(4, 'Barranquilla', 'Atlántico', '08001', 8900, 0);

INSERT INTO direcciones (id_direccion, id_usuario, id_ciudad, alias, direccion, barrio, indicaciones, es_principal) VALUES
(1, 1, 1, 'Casa', 'Calle 100 # 10-20', 'Chicó', 'Apartamento 301, torre 2', 1),
(2, 1, 1, 'Oficina', 'Carrera 7 # 71-21', 'Quinta Camacho', 'Piso 5, recepción', 0);

-- Sedes (datos ficticios)

INSERT INTO sedes (id_sede, id_ciudad, nombre, direccion, telefono, horario, latitud, longitud) VALUES
(1, 1, 'Sede Chapinero', 'Carrera 13 # 60-10, Bogotá', '601 555 0101', 'Lun-Sáb 7:00-21:00; Dom y festivos 8:00-18:00', 4.645100, -74.063300),
(2, 2, 'Sede El Poblado', 'Calle 10 # 43-50, Medellín', '604 555 0102', 'Lun-Sáb 7:00-21:00; Dom 9:00-17:00', 6.209700, -75.567600),
(3, 3, 'Sede Granada', 'Avenida 8 Norte # 15-30, Cali', '602 555 0103', 'Lun-Dom 24 horas', 3.458700, -76.531300);

-- Categorías (10 principales y 2 subcategorías)

INSERT INTO categorias (id_categoria, id_categoria_padre, nombre, slug, descripcion, icono, orden) VALUES
(1, NULL, 'Dolor y fiebre', 'dolor-y-fiebre', 'Analgésicos y antipiréticos de venta libre', 'termometro', 1),
(2, NULL, 'Gripa y alergias', 'gripa-y-alergias', 'Antigripales, antihistamínicos y jarabes', 'nariz', 2),
(3, NULL, 'Digestión', 'digestion', 'Antiácidos, antidiarreicos y sales de rehidratación', 'estomago', 3),
(4, NULL, 'Corazón y presión', 'corazon-y-presion', 'Antihipertensivos e hipolipemiantes (con fórmula)', 'corazon', 4),
(5, NULL, 'Diabetes', 'diabetes', 'Control de la glucosa (con fórmula)', 'gota', 5),
(6, NULL, 'Antibióticos', 'antibioticos', 'Antiinfecciosos de venta bajo fórmula médica', 'capsula', 6),
(7, NULL, 'Vitaminas y suplementos', 'vitaminas-y-suplementos', 'Vitaminas, minerales y multivitamínicos', 'hoja', 7),
(8, NULL, 'Cuidado de la piel', 'cuidado-de-la-piel', 'Dermocosmética e hidratación', 'gota-piel', 8),
(9, NULL, 'Bebé y mamá', 'bebe-y-mama', 'Cuidado del bebé y maternidad', 'biberon', 9),
(10, NULL, 'Primeros auxilios', 'primeros-auxilios', 'Botiquín, curaciones y equipos', 'botiquin', 10),
(11, 8, 'Protección solar', 'proteccion-solar', 'Protectores solares faciales y corporales', 'sol', 11),
(12, 7, 'Multivitamínicos', 'multivitaminicos', 'Fórmulas con varias vitaminas y minerales', 'hoja', 12);

-- Laboratorios (nombres ficticios)

INSERT INTO laboratorios (id_laboratorio, nombre) VALUES
(1, 'Laboratorios Andinos'),
(2, 'Genéricos del Valle'),
(3, 'Farmacéutica Caribe'),
(4, 'Laboratorio Cordillera'),
(5, 'Bioandina Farma'),
(6, 'Vitalia Nutrición'),
(7, 'Dermacol Labs'),
(8, 'Pequesalud');

-- Principios activos

INSERT INTO principios_activos (id_principio_activo, nombre) VALUES
(1, 'Acetaminofén'),
(2, 'Alcohol etílico'),
(3, 'Ambroxol'),
(4, 'Amlodipino'),
(5, 'Amoxicilina'),
(6, 'Atorvastatina'),
(7, 'Azitromicina'),
(8, 'Cafeína'),
(9, 'Carbonato de calcio'),
(10, 'Cefalexina'),
(11, 'Cetirizina'),
(12, 'Ciprofloxacino'),
(13, 'Clorfeniramina'),
(14, 'Colecalciferol'),
(15, 'Enalapril'),
(16, 'Fenilefrina'),
(17, 'Glibenclamida'),
(18, 'Gluconato de zinc'),
(19, 'Hidroclorotiazida'),
(20, 'Hidróxido de aluminio'),
(21, 'Hidróxido de magnesio'),
(22, 'Ibuprofeno'),
(23, 'Loperamida'),
(24, 'Loratadina'),
(25, 'Losartán'),
(26, 'Metformina'),
(27, 'Naproxeno'),
(28, 'Omeprazol'),
(29, 'Sales de rehidratación oral'),
(30, 'Simeticona'),
(31, 'Ácido ascórbico'),
(32, 'Óxido de zinc');

-- Productos (42; 11 requieren fórmula médica)

INSERT INTO productos (id_producto, id_categoria, id_laboratorio, sku, nombre, slug, descripcion, presentacion, forma_farmaceutica, registro_invima, requiere_formula, precio, iva_porcentaje, imagen_url, destacado) VALUES
(1, 1, 2, 'DRG-0001', 'Acetaminofén 500 mg', 'acetaminofen-500-mg-caja-x-20-tabletas', 'Analgésico y antipirético para el alivio del dolor leve a moderado y la fiebre.', 'Caja x 20 tabletas', 'Tableta', 'INVIMA 2019M-0010037-R1', 0, 4900, 0, NULL, 1),
(2, 1, 1, 'DRG-0002', 'Ibuprofeno 400 mg', 'ibuprofeno-400-mg-caja-x-10-tabletas', 'Antiinflamatorio no esteroideo para dolor, inflamación y fiebre.', 'Caja x 10 tabletas', 'Tableta recubierta', 'INVIMA 2020M-0010074-R1', 0, 6500, 0, NULL, 1),
(3, 1, 3, 'DRG-0003', 'Naproxeno 250 mg', 'naproxeno-250-mg-caja-x-10-tabletas', 'Alivio del dolor muscular, articular y menstrual.', 'Caja x 10 tabletas', 'Tableta', 'INVIMA 2021M-0010111-R1', 0, 7200, 0, NULL, 0),
(4, 1, 8, 'DRG-0004', 'Acetaminofén jarabe infantil 150 mg/5 mL', 'acetaminofen-jarabe-infantil-150-mg-5-ml-frasco-x-90-ml', 'Jarabe sabor fresa para el alivio de la fiebre en niños.', 'Frasco x 90 mL', 'Jarabe', 'INVIMA 2022M-0010148-R1', 0, 9800, 0, NULL, 0),
(5, 1, 1, 'DRG-0005', 'Acetaminofén + Cafeína 500 mg/65 mg', 'acetaminofen-cafeina-500-mg-65-mg-caja-x-16-tabletas', 'Combinación para el dolor de cabeza.', 'Caja x 16 tabletas', 'Tableta', 'INVIMA 2023M-0010185-R1', 0, 11900, 0, NULL, 0),
(6, 2, 2, 'DRG-0006', 'Loratadina 10 mg', 'loratadina-10-mg-caja-x-10-tabletas', 'Antihistamínico para rinitis alérgica y urticaria.', 'Caja x 10 tabletas', 'Tableta', 'INVIMA 2024M-0010222-R1', 0, 5900, 0, NULL, 1),
(7, 2, 3, 'DRG-0007', 'Cetirizina 10 mg', 'cetirizina-10-mg-caja-x-10-tabletas', 'Antihistamínico de acción prolongada.', 'Caja x 10 tabletas', 'Tableta recubierta', 'INVIMA 2018M-0010259-R1', 0, 6900, 0, NULL, 0),
(8, 2, 4, 'DRG-0008', 'Ambroxol jarabe 30 mg/5 mL', 'ambroxol-jarabe-30-mg-5-ml-frasco-x-120-ml', 'Mucolítico que facilita la expulsión de las flemas.', 'Frasco x 120 mL', 'Jarabe', 'INVIMA 2019M-0010296-R1', 0, 12500, 0, NULL, 0),
(9, 2, 1, 'DRG-0009', 'Antigripal día y noche', 'antigripal-dia-y-noche-caja-x-12-capsulas', 'Alivio de los síntomas de la gripa: congestión, fiebre y malestar.', 'Caja x 12 cápsulas', 'Cápsula', 'INVIMA 2020M-0010333-R1', 0, 14900, 0, NULL, 1),
(10, 2, 5, 'DRG-0010', 'Pastillas para la garganta sabor miel', 'pastillas-para-la-garganta-sabor-miel-caja-x-16-pastillas', 'Pastillas para suavizar la garganta irritada.', 'Caja x 16 pastillas', 'Pastilla', NULL, 0, 8900, 19, NULL, 0),
(11, 3, 2, 'DRG-0011', 'Omeprazol 20 mg', 'omeprazol-20-mg-caja-x-14-capsulas', 'Reduce la acidez estomacal y la sensación de ardor.', 'Caja x 14 cápsulas', 'Cápsula', 'INVIMA 2022M-0010407-R1', 0, 8500, 0, NULL, 0),
(12, 3, 3, 'DRG-0012', 'Hidróxido de aluminio y magnesio suspensión', 'hidroxido-de-aluminio-y-magnesio-suspension-frasco-x-360-ml', 'Antiácido para el alivio rápido de la acidez.', 'Frasco x 360 mL', 'Suspensión', 'INVIMA 2023M-0010444-R1', 0, 15900, 0, NULL, 0),
(13, 3, 1, 'DRG-0013', 'Loperamida 2 mg', 'loperamida-2-mg-caja-x-6-tabletas', 'Control de la diarrea aguda.', 'Caja x 6 tabletas', 'Tableta', 'INVIMA 2024M-0010481-R1', 0, 5400, 0, NULL, 0),
(14, 3, 4, 'DRG-0014', 'Sales de rehidratación oral', 'sales-de-rehidratacion-oral-caja-x-4-sobres', 'Repone líquidos y electrolitos.', 'Caja x 4 sobres', 'Polvo para solución', 'INVIMA 2018M-0010518-R1', 0, 7900, 0, NULL, 0),
(15, 3, 5, 'DRG-0015', 'Simeticona 80 mg', 'simeticona-80-mg-caja-x-20-tabletas-masticables', 'Alivia los gases y la distensión abdominal.', 'Caja x 20 tabletas masticables', 'Tableta masticable', 'INVIMA 2019M-0010555-R1', 0, 9200, 0, NULL, 0),
(16, 4, 2, 'DRG-0016', 'Losartán 50 mg', 'losartan-50-mg-caja-x-30-tabletas', 'Antihipertensivo. Venta bajo fórmula médica.', 'Caja x 30 tabletas', 'Tableta recubierta', 'INVIMA 2020M-0010592-R1', 1, 12900, 0, NULL, 1),
(17, 4, 1, 'DRG-0017', 'Losartán + Hidroclorotiazida 50 mg/12,5 mg', 'losartan-hidroclorotiazida-50-mg-12-5-mg-caja-x-30-tabletas', 'Antihipertensivo combinado. Venta bajo fórmula médica.', 'Caja x 30 tabletas', 'Tableta recubierta', 'INVIMA 2021M-0010629-R1', 1, 24900, 0, NULL, 0),
(18, 4, 3, 'DRG-0018', 'Enalapril 20 mg', 'enalapril-20-mg-caja-x-30-tabletas', 'Tratamiento de la hipertensión arterial. Venta bajo fórmula médica.', 'Caja x 30 tabletas', 'Tableta', 'INVIMA 2022M-0010666-R1', 1, 9900, 0, NULL, 0),
(19, 4, 2, 'DRG-0019', 'Amlodipino 5 mg', 'amlodipino-5-mg-caja-x-30-tabletas', 'Antihipertensivo y antianginoso. Venta bajo fórmula médica.', 'Caja x 30 tabletas', 'Tableta', 'INVIMA 2023M-0010703-R1', 1, 11500, 0, NULL, 0),
(20, 4, 4, 'DRG-0020', 'Atorvastatina 20 mg', 'atorvastatina-20-mg-caja-x-30-tabletas', 'Reduce el colesterol. Venta bajo fórmula médica.', 'Caja x 30 tabletas', 'Tableta recubierta', 'INVIMA 2024M-0010740-R1', 1, 21900, 0, NULL, 1),
(21, 5, 2, 'DRG-0021', 'Metformina 850 mg', 'metformina-850-mg-caja-x-30-tabletas', 'Control de la diabetes tipo 2. Venta bajo fórmula médica.', 'Caja x 30 tabletas', 'Tableta', 'INVIMA 2018M-0010777-R1', 1, 8900, 0, NULL, 0),
(22, 5, 3, 'DRG-0022', 'Glibenclamida 5 mg', 'glibenclamida-5-mg-caja-x-30-tabletas', 'Hipoglucemiante oral. Venta bajo fórmula médica.', 'Caja x 30 tabletas', 'Tableta', 'INVIMA 2019M-0010814-R1', 1, 7900, 0, NULL, 0),
(23, 5, 5, 'DRG-0023', 'Tiras reactivas para glucómetro', 'tiras-reactivas-para-glucometro-caja-x-50-tiras', 'Tiras compatibles con glucómetros de la marca de la tienda.', 'Caja x 50 tiras', 'Dispositivo médico', NULL, 0, 64900, 19, NULL, 0),
(24, 6, 2, 'DRG-0024', 'Amoxicilina 500 mg', 'amoxicilina-500-mg-caja-x-30-capsulas', 'Antibiótico de amplio espectro. Venta bajo fórmula médica.', 'Caja x 30 cápsulas', 'Cápsula', 'INVIMA 2021M-0010888-R1', 1, 16900, 0, NULL, 1),
(25, 6, 1, 'DRG-0025', 'Azitromicina 500 mg', 'azitromicina-500-mg-caja-x-3-tabletas', 'Antibiótico macrólido. Venta bajo fórmula médica.', 'Caja x 3 tabletas', 'Tableta recubierta', 'INVIMA 2022M-0010925-R1', 1, 19900, 0, NULL, 0),
(26, 6, 3, 'DRG-0026', 'Cefalexina 500 mg', 'cefalexina-500-mg-caja-x-10-capsulas', 'Antibiótico cefalosporínico. Venta bajo fórmula médica.', 'Caja x 10 cápsulas', 'Cápsula', 'INVIMA 2023M-0010962-R1', 1, 13900, 0, NULL, 0),
(27, 6, 4, 'DRG-0027', 'Ciprofloxacino 500 mg', 'ciprofloxacino-500-mg-caja-x-10-tabletas', 'Antibiótico quinolónico. Venta bajo fórmula médica.', 'Caja x 10 tabletas', 'Tableta recubierta', 'INVIMA 2024M-0010999-R1', 1, 15900, 0, NULL, 0),
(28, 7, 6, 'DRG-0028', 'Vitamina C 500 mg', 'vitamina-c-500-mg-frasco-x-100-tabletas', 'Suplemento de vitamina C sabor naranja.', 'Frasco x 100 tabletas', 'Tableta masticable', 'INVIMA 2018M-0011036-R1', 0, 18900, 0, NULL, 1),
(29, 7, 6, 'DRG-0029', 'Calcio + Vitamina D3', 'calcio-vitamina-d3-frasco-x-60-tabletas', 'Contribuye al cuidado de los huesos.', 'Frasco x 60 tabletas', 'Tableta', 'INVIMA 2019M-0011073-R1', 0, 32900, 0, NULL, 0),
(30, 7, 5, 'DRG-0030', 'Zinc 50 mg', 'zinc-50-mg-frasco-x-60-tabletas', 'Suplemento mineral que apoya el sistema inmune.', 'Frasco x 60 tabletas', 'Tableta', 'INVIMA 2020M-0011110-R1', 0, 21900, 0, NULL, 0),
(31, 12, 6, 'DRG-0031', 'Multivitamínico adultos', 'multivitaminico-adultos-frasco-x-30-tabletas', 'Fórmula completa de vitaminas y minerales para adultos.', 'Frasco x 30 tabletas', 'Tableta', NULL, 0, 39900, 0, NULL, 1),
(32, 12, 8, 'DRG-0032', 'Multivitamínico infantil en gomitas', 'multivitaminico-infantil-en-gomitas-frasco-x-60-gomitas', 'Vitaminas para niños mayores de 4 años, sabor frutas.', 'Frasco x 60 gomitas', 'Gomita', NULL, 0, 34900, 0, NULL, 0),
(33, 8, 7, 'DRG-0033', 'Crema hidratante corporal', 'crema-hidratante-corporal-frasco-x-400-ml', 'Hidratación profunda para piel seca, sin fragancia.', 'Frasco x 400 mL', 'Crema', NULL, 0, 27900, 19, NULL, 0),
(34, 8, 7, 'DRG-0034', 'Gel limpiador facial piel grasa', 'gel-limpiador-facial-piel-grasa-tubo-x-150-ml', 'Limpieza diaria que controla el brillo.', 'Tubo x 150 mL', 'Gel', NULL, 0, 36900, 19, NULL, 0),
(35, 11, 7, 'DRG-0035', 'Protector solar facial FPS 50', 'protector-solar-facial-fps-50-tubo-x-50-ml', 'Protección alta UVA/UVB, toque seco, apto para piel sensible.', 'Tubo x 50 mL', 'Crema', NULL, 0, 49900, 19, NULL, 1),
(36, 11, 7, 'DRG-0036', 'Protector solar corporal FPS 30', 'protector-solar-corporal-fps-30-frasco-x-200-ml', 'Protección para toda la familia, resistente al agua.', 'Frasco x 200 mL', 'Loción', NULL, 0, 44900, 19, NULL, 0),
(37, 9, 8, 'DRG-0037', 'Pañitos húmedos para bebé', 'panitos-humedos-para-bebe-paquete-x-100-unidades', 'Pañitos hipoalergénicos con aloe vera.', 'Paquete x 100 unidades', 'Toalla húmeda', NULL, 0, 9900, 19, NULL, 0),
(38, 9, 8, 'DRG-0038', 'Crema antipañalitis óxido de zinc', 'crema-antipanalitis-oxido-de-zinc-tubo-x-60-g', 'Previene y alivia la irritación por el pañal.', 'Tubo x 60 g', 'Crema', 'INVIMA 2021M-0011406-R1', 0, 15900, 0, NULL, 0),
(39, 9, 8, 'DRG-0039', 'Pañales etapa 3', 'panales-etapa-3-paquete-x-30-unidades', 'Pañales con barreras antifugas para bebés de 7 a 11 kg.', 'Paquete x 30 unidades', 'Pañal', NULL, 0, 42900, 0, NULL, 0),
(40, 10, 4, 'DRG-0040', 'Alcohol antiséptico 70 %', 'alcohol-antiseptico-70-frasco-x-350-ml', 'Desinfección de la piel y de superficies.', 'Frasco x 350 mL', 'Solución', 'INVIMA 2023M-0011480-R1', 0, 6900, 0, NULL, 0),
(41, 10, 4, 'DRG-0041', 'Curitas surtidas', 'curitas-surtidas-caja-x-40-unidades', 'Apósitos adhesivos de varios tamaños.', 'Caja x 40 unidades', 'Apósito', NULL, 0, 7500, 19, NULL, 0),
(42, 10, 5, 'DRG-0042', 'Termómetro digital', 'termometro-digital-unidad', 'Lectura en 60 segundos con alarma de fiebre.', 'Unidad', 'Dispositivo médico', NULL, 0, 24900, 19, NULL, 0);

-- Composición: principios activos por producto (tabla puente N:M)

INSERT INTO producto_principio_activo (id_producto, id_principio_activo, concentracion) VALUES
(1, 1, '500 mg'),
(2, 22, '400 mg'),
(3, 27, '250 mg'),
(4, 1, '150 mg/5 mL'),
(5, 1, '500 mg'),
(5, 8, '65 mg'),
(6, 24, '10 mg'),
(7, 11, '10 mg'),
(8, 3, '30 mg/5 mL'),
(9, 1, '500 mg'),
(9, 16, '10 mg'),
(9, 13, '4 mg'),
(11, 28, '20 mg'),
(12, 20, '400 mg/5 mL'),
(12, 21, '400 mg/5 mL'),
(13, 23, '2 mg'),
(14, 29, '27,9 g'),
(15, 30, '80 mg'),
(16, 25, '50 mg'),
(17, 25, '50 mg'),
(17, 19, '12,5 mg'),
(18, 15, '20 mg'),
(19, 4, '5 mg'),
(20, 6, '20 mg'),
(21, 26, '850 mg'),
(22, 17, '5 mg'),
(24, 5, '500 mg'),
(25, 7, '500 mg'),
(26, 10, '500 mg'),
(27, 12, '500 mg'),
(28, 31, '500 mg'),
(29, 9, '600 mg'),
(29, 14, '400 UI'),
(30, 18, '50 mg'),
(38, 32, '40 %'),
(40, 2, '70 %');

-- Lotes (fechas relativas al día de la instalación)

INSERT INTO lotes (id_lote, id_producto, numero_lote, fecha_fabricacion, fecha_vencimiento) VALUES
(1, 1, 'L50Q9385', CURDATE() - INTERVAL 391 DAY, CURDATE() + INTERVAL 361 DAY),
(2, 1, 'L38T7891', CURDATE() - INTERVAL 353 DAY, CURDATE() + INTERVAL 86 DAY),
(3, 2, 'L72Y8226', CURDATE() - INTERVAL 182 DAY, CURDATE() + INTERVAL 800 DAY),
(4, 2, 'L88C2814', CURDATE() - INTERVAL 207 DAY, CURDATE() + INTERVAL 60 DAY),
(5, 3, 'L67A9032', CURDATE() - INTERVAL 220 DAY, CURDATE() + INTERVAL 340 DAY),
(6, 3, 'L60I6696', CURDATE() - INTERVAL 242 DAY, CURDATE() + INTERVAL 113 DAY),
(7, 4, 'L75U2250', CURDATE() - INTERVAL 234 DAY, CURDATE() + INTERVAL 625 DAY),
(8, 5, 'L81R5786', CURDATE() - INTERVAL 207 DAY, CURDATE() + INTERVAL 331 DAY),
(9, 6, 'L28U6062', CURDATE() - INTERVAL 72 DAY, CURDATE() + INTERVAL 708 DAY),
(10, 6, 'L56O7917', CURDATE() - INTERVAL 106 DAY, CURDATE() + INTERVAL 154 DAY),
(11, 7, 'L84R9166', CURDATE() - INTERVAL 119 DAY, CURDATE() + INTERVAL 648 DAY),
(12, 8, 'L74Z9045', CURDATE() - INTERVAL 263 DAY, CURDATE() + INTERVAL 675 DAY),
(13, 9, 'L43N8851', CURDATE() - INTERVAL 322 DAY, CURDATE() + INTERVAL 777 DAY),
(14, 9, 'L13S4678', CURDATE() - INTERVAL 126 DAY, CURDATE() + INTERVAL 192 DAY),
(15, 10, 'L76V2680', CURDATE() - INTERVAL 378 DAY, CURDATE() + INTERVAL 290 DAY),
(16, 11, 'L70E8898', CURDATE() - INTERVAL 177 DAY, CURDATE() + INTERVAL 679 DAY),
(17, 12, 'L90W8484', CURDATE() - INTERVAL 300 DAY, CURDATE() + INTERVAL 364 DAY),
(18, 12, 'L42R7587', CURDATE() - INTERVAL 217 DAY, CURDATE() + INTERVAL 199 DAY),
(19, 13, 'L92Q8846', CURDATE() - INTERVAL 265 DAY, CURDATE() + INTERVAL 45 DAY),
(20, 14, 'L35J5407', CURDATE() - INTERVAL 64 DAY, CURDATE() + INTERVAL 683 DAY),
(21, 15, 'L29U8507', CURDATE() - INTERVAL 327 DAY, CURDATE() + INTERVAL 273 DAY),
(22, 15, 'L56G5261', CURDATE() - INTERVAL 308 DAY, CURDATE() + INTERVAL 185 DAY),
(23, 16, 'L75Y9145', CURDATE() - INTERVAL 282 DAY, CURDATE() + INTERVAL 717 DAY),
(24, 16, 'L47K8498', CURDATE() - INTERVAL 110 DAY, CURDATE() + INTERVAL 68 DAY),
(25, 17, 'L98W9440', CURDATE() - INTERVAL 192 DAY, CURDATE() + INTERVAL 688 DAY),
(26, 18, 'L33N8850', CURDATE() - INTERVAL 92 DAY, CURDATE() + INTERVAL 703 DAY),
(27, 18, 'L73L2583', CURDATE() - INTERVAL 159 DAY, CURDATE() + INTERVAL 128 DAY),
(28, 19, 'L28O1229', CURDATE() - INTERVAL 107 DAY, CURDATE() + INTERVAL 661 DAY),
(29, 20, 'L67S9955', CURDATE() - INTERVAL 102 DAY, CURDATE() + INTERVAL 240 DAY),
(30, 20, 'L41D1731', CURDATE() - INTERVAL 339 DAY, CURDATE() + INTERVAL 110 DAY),
(31, 21, 'L95Y6853', CURDATE() - INTERVAL 139 DAY, CURDATE() + INTERVAL 514 DAY),
(32, 21, 'L50V9060', CURDATE() - INTERVAL 129 DAY, CURDATE() + INTERVAL 61 DAY),
(33, 22, 'L38P3149', CURDATE() - INTERVAL 366 DAY, CURDATE() + INTERVAL 798 DAY),
(34, 23, 'L47C7844', CURDATE() - INTERVAL 141 DAY, CURDATE() + INTERVAL 756 DAY),
(35, 24, 'L85J9318', CURDATE() - INTERVAL 270 DAY, CURDATE() + INTERVAL 378 DAY),
(36, 24, 'L29Q4222', CURDATE() - INTERVAL 252 DAY, CURDATE() + INTERVAL 159 DAY),
(37, 25, 'L23M2203', CURDATE() - INTERVAL 86 DAY, CURDATE() + INTERVAL 254 DAY),
(38, 26, 'L92L1422', CURDATE() - INTERVAL 73 DAY, CURDATE() + INTERVAL 595 DAY),
(39, 27, 'L70K5975', CURDATE() - INTERVAL 290 DAY, CURDATE() + INTERVAL 762 DAY),
(40, 27, 'L25P8644', CURDATE() - INTERVAL 352 DAY, CURDATE() + INTERVAL 143 DAY),
(41, 28, 'L31E9513', CURDATE() - INTERVAL 165 DAY, CURDATE() + INTERVAL 873 DAY),
(42, 28, 'L89K8517', CURDATE() - INTERVAL 366 DAY, CURDATE() + INTERVAL 171 DAY),
(43, 29, 'L96W2138', CURDATE() - INTERVAL 340 DAY, CURDATE() + INTERVAL 478 DAY),
(44, 30, 'L14G3840', CURDATE() - INTERVAL 83 DAY, CURDATE() + INTERVAL 648 DAY),
(45, 30, 'L16O4088', CURDATE() - INTERVAL 307 DAY, CURDATE() + INTERVAL 199 DAY),
(46, 31, 'L26U9682', CURDATE() - INTERVAL 171 DAY, CURDATE() + INTERVAL 260 DAY),
(47, 31, 'L27F4047', CURDATE() - INTERVAL 259 DAY, CURDATE() + INTERVAL 192 DAY),
(48, 32, 'L64R7784', CURDATE() - INTERVAL 100 DAY, CURDATE() + INTERVAL 519 DAY),
(49, 33, 'L49F6637', CURDATE() - INTERVAL 149 DAY, CURDATE() + INTERVAL 632 DAY),
(50, 33, 'L69P7811', CURDATE() - INTERVAL 207 DAY, CURDATE() + INTERVAL 127 DAY),
(51, 34, 'L32K9508', CURDATE() - INTERVAL 306 DAY, CURDATE() + INTERVAL 718 DAY),
(52, 35, 'L25Q9596', CURDATE() - INTERVAL 200 DAY, CURDATE() + INTERVAL 695 DAY),
(53, 35, 'L37H1080', CURDATE() - INTERVAL 107 DAY, CURDATE() + INTERVAL 84 DAY),
(54, 36, 'L92K7684', CURDATE() - INTERVAL 339 DAY, CURDATE() + INTERVAL 705 DAY),
(55, 36, 'L13L3568', CURDATE() - INTERVAL 240 DAY, CURDATE() + INTERVAL 106 DAY),
(56, 37, 'L97S9820', CURDATE() - INTERVAL 170 DAY, CURDATE() + INTERVAL 815 DAY),
(57, 38, 'L89W5595', CURDATE() - INTERVAL 344 DAY, CURDATE() + INTERVAL 352 DAY),
(58, 39, 'L37S5828', CURDATE() - INTERVAL 348 DAY, CURDATE() + INTERVAL 821 DAY),
(59, 39, 'L95R3172', CURDATE() - INTERVAL 111 DAY, CURDATE() + INTERVAL 128 DAY),
(60, 40, 'L22N3806', CURDATE() - INTERVAL 114 DAY, CURDATE() + INTERVAL 510 DAY),
(61, 41, 'L55X4039', CURDATE() - INTERVAL 390 DAY, CURDATE() + INTERVAL 301 DAY),
(62, 42, 'L23Q6137', CURDATE() - INTERVAL 201 DAY, CURDATE() + INTERVAL 885 DAY),
(63, 42, 'L47K3644', CURDATE() - INTERVAL 193 DAY, CURDATE() + INTERVAL 76 DAY),
(64, 1, 'L09X0001', CURDATE() - INTERVAL 800 DAY, CURDATE() - INTERVAL 10 DAY);

-- Promociones (3 vigentes, 1 vencida)

INSERT INTO promociones (id_promocion, nombre, descripcion, tipo_descuento, valor_descuento, fecha_inicio, fecha_fin, mostrar_en_banner, titulo_banner, subtitulo_banner, imagen_banner_url) VALUES
(1, 'Semana del bienestar', 'Descuento en analgésicos y antigripales', 'PORCENTAJE', 20, NOW() - INTERVAL 5 DAY, NOW() + INTERVAL 25 DAY, 1, 'Hasta 20 % en dolor y gripa', 'Alivio para toda la familia, con domicilio en tu ciudad', NULL),
(2, 'Mes de las vitaminas', 'Vitaminas y multivitamínicos seleccionados', 'PORCENTAJE', 15, NOW() - INTERVAL 2 DAY, NOW() + INTERVAL 28 DAY, 1, '15 % en vitaminas', 'Refuerza tus defensas con nuestras marcas seleccionadas', NULL),
(3, 'Cuidado del bebé', 'Descuento fijo por unidad', 'VALOR', 2000, NOW() - INTERVAL 1 DAY, NOW() + INTERVAL 14 DAY, 1, '$2.000 menos en productos para bebé', 'Pañitos, cremas y pañales con precio especial', NULL),
(4, 'Protección solar (finalizada)', 'Campaña de vacaciones', 'PORCENTAJE', 25, NOW() - INTERVAL 60 DAY, NOW() - INTERVAL 30 DAY, 0, NULL, NULL, NULL);

INSERT INTO promocion_producto (id_promocion, id_producto) VALUES
(1, 1),
(1, 2),
(1, 6),
(1, 9),
(2, 28),
(2, 29),
(2, 30),
(2, 31),
(2, 32),
(3, 37),
(3, 38),
(3, 39),
(4, 35),
(4, 36);

-- Carrito activo de la cliente de prueba

INSERT INTO carritos (id_carrito, id_usuario, token) VALUES
(1, 1, '6f1c2a3e-8d4b-4c1a-9e2f-0a1b2c3d4e5f');

INSERT INTO carrito_items (id_carrito, id_producto, cantidad) VALUES
(1, 6, 1),
(1, 28, 2);

-- Fórmula médica aprobada (archivo PDF ficticio de prueba)

INSERT INTO formulas_medicas (id_formula, id_usuario, id_revisor, archivo, archivo_mime, archivo_sha256, medico_nombre, medico_registro, fecha_emision, estado, observaciones, revisada_en) VALUES
(1, 1, 2, 0x255044462d312e340a2520466f726d756c61206d65646963612066696374696369612070617261206461746f73206465207072756562610a2525454f460a, 'application/pdf', 'a42f02b4e415e0da7df9bf9d8f3abdfc85ba23775208a5f135b92c81086ab4aa', 'Dra. Laura Méndez (ficticia)', 'RM-000123', CURDATE() - INTERVAL 12 DAY, 'APROBADA', 'Fórmula legible y vigente', NOW() - INTERVAL 11 DAY);

-- Pedidos de ejemplo de la cliente de prueba

INSERT INTO pedidos (id_pedido, codigo, id_usuario, id_sede, id_direccion, tipo_entrega, direccion_entrega, estado, metodo_pago, subtotal, descuento, costo_envio, total, created_at) VALUES
(1, 'PED-000001', 1, 1, 1, 'DOMICILIO', 'Calle 100 # 10-20, Chicó, Bogotá D.C. (Apartamento 301, torre 2)', 'ENTREGADO', 'TARJETA', 22700, 1960, 6900, 27640, NOW() - INTERVAL 4 DAY),
(2, 'PED-000002', 1, 1, NULL, 'RETIRO', NULL, 'LISTO_PARA_RETIRO', 'CONTRA_ENTREGA', 18900, 2835, 0, 16065, NOW() - INTERVAL 1 DAY);

INSERT INTO pedido_items (id_pedido_item, id_pedido, id_producto, id_formula, cantidad, precio_unitario, descuento_unitario) VALUES
(1, 1, 16, 1, 1, 12900, 0),
(2, 1, 1, NULL, 2, 4900, 980),
(3, 2, 28, NULL, 1, 18900, 2835);

-- Lotes despachados por ítem (FEFO: el que vence primero)

INSERT INTO pedido_item_lotes (id_pedido_item, id_lote, cantidad) VALUES
(1, 24, 1),
(2, 2, 2),
(3, 42, 1);

INSERT INTO pedido_historial (id_pedido, id_usuario, estado, comentario, created_at) VALUES
(1, NULL, 'CONFIRMADO', 'Pedido creado en la tienda en línea', NOW() - INTERVAL 4 DAY + INTERVAL 0 HOUR),
(1, 2, 'EN_PREPARACION', NULL, NOW() - INTERVAL 4 DAY + INTERVAL 2 HOUR),
(1, 2, 'EN_CAMINO', NULL, NOW() - INTERVAL 4 DAY + INTERVAL 4 HOUR),
(1, 2, 'ENTREGADO', NULL, NOW() - INTERVAL 4 DAY + INTERVAL 6 HOUR),
(2, NULL, 'CONFIRMADO', 'Pedido creado en la tienda en línea', NOW() - INTERVAL 1 DAY + INTERVAL 0 HOUR),
(2, 2, 'EN_PREPARACION', NULL, NOW() - INTERVAL 1 DAY + INTERVAL 2 HOUR),
(2, 2, 'LISTO_PARA_RETIRO', NULL, NOW() - INTERVAL 1 DAY + INTERVAL 4 HOUR);

-- Inventario por sede y lote (190 registros)

INSERT INTO inventario (id_inventario, id_sede, id_lote, cantidad) VALUES
(1, 1, 1, 40),
(2, 1, 2, 14),
(3, 2, 1, 9),
(4, 2, 2, 60),
(5, 3, 1, 40),
(6, 3, 2, 61),
(7, 1, 3, 9),
(8, 1, 4, 15),
(9, 2, 3, 20),
(10, 2, 4, 38),
(11, 3, 3, 10),
(12, 3, 4, 47),
(13, 1, 5, 23),
(14, 1, 6, 20),
(15, 2, 5, 79),
(16, 2, 6, 52),
(17, 3, 5, 48),
(18, 3, 6, 66),
(19, 1, 7, 12),
(20, 2, 7, 59),
(21, 3, 7, 48),
(22, 1, 8, 35),
(23, 2, 8, 67),
(24, 3, 8, 62),
(25, 1, 9, 23),
(26, 1, 10, 55),
(27, 2, 9, 72),
(28, 2, 10, 40),
(29, 3, 9, 57),
(30, 3, 10, 45),
(31, 1, 11, 53),
(32, 2, 11, 15),
(33, 3, 11, 63),
(34, 1, 12, 11),
(35, 2, 12, 44),
(36, 3, 12, 50),
(37, 1, 13, 45),
(38, 1, 14, 23),
(39, 2, 13, 46),
(40, 2, 14, 61),
(41, 3, 13, 48),
(42, 3, 14, 10),
(43, 1, 15, 77),
(44, 2, 15, 51),
(45, 3, 15, 33),
(46, 1, 16, 79),
(47, 2, 16, 15),
(48, 3, 16, 22),
(49, 1, 17, 28),
(50, 1, 18, 23),
(51, 2, 17, 23),
(52, 2, 18, 12),
(53, 3, 17, 24),
(54, 3, 18, 74),
(55, 1, 19, 53),
(56, 2, 19, 46),
(57, 3, 19, 11),
(58, 1, 20, 62),
(59, 2, 20, 24),
(60, 3, 20, 53),
(61, 1, 21, 61),
(62, 1, 22, 57),
(63, 2, 21, 56),
(64, 2, 22, 38),
(65, 3, 21, 61),
(66, 3, 22, 36),
(67, 1, 23, 24),
(68, 1, 24, 30),
(69, 2, 23, 77),
(70, 2, 24, 11),
(71, 3, 23, 77),
(72, 3, 24, 79),
(73, 1, 25, 58),
(74, 2, 25, 40),
(75, 3, 25, 26),
(76, 1, 26, 37),
(77, 1, 27, 10),
(78, 2, 26, 10),
(79, 2, 27, 43),
(80, 3, 26, 77),
(81, 3, 27, 69),
(82, 1, 28, 61),
(83, 2, 28, 41),
(84, 3, 28, 48),
(85, 1, 29, 25),
(86, 1, 30, 19),
(87, 2, 29, 30),
(88, 2, 30, 78),
(89, 3, 29, 12),
(90, 3, 30, 73),
(91, 1, 31, 41),
(92, 1, 32, 51),
(93, 2, 31, 74),
(94, 2, 32, 48),
(95, 3, 31, 15),
(96, 3, 32, 9),
(97, 1, 33, 39),
(98, 2, 33, 68),
(99, 3, 33, 15),
(100, 1, 34, 36),
(101, 2, 34, 73),
(102, 3, 34, 0),
(103, 1, 35, 27),
(104, 1, 36, 59),
(105, 2, 35, 54),
(106, 2, 36, 37),
(107, 3, 35, 79),
(108, 3, 36, 43),
(109, 1, 37, 51),
(110, 2, 37, 33),
(111, 3, 37, 55),
(112, 1, 38, 53),
(113, 2, 38, 66),
(114, 3, 38, 66),
(115, 1, 39, 78),
(116, 1, 40, 68),
(117, 2, 39, 47),
(118, 2, 40, 32),
(119, 3, 39, 28),
(120, 3, 40, 60),
(121, 1, 41, 27),
(122, 1, 42, 69),
(123, 2, 41, 8),
(124, 2, 42, 53),
(125, 3, 41, 74),
(126, 3, 42, 60),
(127, 1, 43, 12),
(128, 2, 43, 30),
(129, 3, 43, 18),
(130, 1, 44, 46),
(131, 1, 45, 55),
(132, 2, 44, 77),
(133, 2, 45, 41),
(134, 3, 44, 25),
(135, 3, 45, 20),
(136, 1, 46, 10),
(137, 1, 47, 76),
(138, 2, 46, 35),
(139, 2, 47, 47),
(140, 3, 46, 13),
(141, 3, 47, 58),
(142, 1, 48, 56),
(143, 2, 48, 76),
(144, 3, 48, 74),
(145, 1, 49, 28),
(146, 1, 50, 73),
(147, 2, 49, 21),
(148, 2, 50, 18),
(149, 3, 49, 26),
(150, 3, 50, 57),
(151, 1, 51, 50),
(152, 2, 51, 78),
(153, 3, 51, 41),
(154, 1, 52, 47),
(155, 1, 53, 13),
(156, 2, 52, 32),
(157, 2, 53, 28),
(158, 3, 52, 45),
(159, 3, 53, 45),
(160, 1, 54, 77),
(161, 1, 55, 44),
(162, 2, 54, 53),
(163, 2, 55, 25),
(164, 3, 54, 57),
(165, 3, 55, 32),
(166, 1, 56, 9),
(167, 2, 56, 69),
(168, 3, 56, 62),
(169, 1, 57, 53),
(170, 2, 57, 76),
(171, 3, 57, 29),
(172, 1, 58, 74),
(173, 1, 59, 11),
(174, 2, 58, 30),
(175, 2, 59, 48),
(176, 3, 58, 77),
(177, 3, 59, 26),
(178, 1, 60, 28),
(179, 2, 60, 11),
(180, 3, 60, 22),
(181, 1, 61, 73),
(182, 2, 61, 8),
(183, 3, 61, 55),
(184, 1, 62, 16),
(185, 1, 63, 55),
(186, 2, 62, 46),
(187, 2, 63, 35),
(188, 3, 62, 76),
(189, 3, 63, 27),
(190, 1, 64, 6);

-- Kárdex coherente con el inventario

INSERT INTO movimientos_inventario (id_inventario, id_pedido, id_usuario, tipo, cantidad, saldo, motivo, created_at) VALUES
(1, NULL, 3, 'ENTRADA', 40, 40, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(2, NULL, 3, 'ENTRADA', 16, 16, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(3, NULL, 3, 'ENTRADA', 9, 9, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(4, NULL, 3, 'ENTRADA', 60, 60, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(5, NULL, 3, 'ENTRADA', 40, 40, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(6, NULL, 3, 'ENTRADA', 61, 61, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(7, NULL, 3, 'ENTRADA', 9, 9, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(8, NULL, 3, 'ENTRADA', 15, 15, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(9, NULL, 3, 'ENTRADA', 20, 20, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(10, NULL, 3, 'ENTRADA', 38, 38, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(11, NULL, 3, 'ENTRADA', 10, 10, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(12, NULL, 3, 'ENTRADA', 47, 47, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(13, NULL, 3, 'ENTRADA', 23, 23, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(14, NULL, 3, 'ENTRADA', 20, 20, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(15, NULL, 3, 'ENTRADA', 79, 79, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(16, NULL, 3, 'ENTRADA', 52, 52, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(17, NULL, 3, 'ENTRADA', 48, 48, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(18, NULL, 3, 'ENTRADA', 66, 66, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(19, NULL, 3, 'ENTRADA', 12, 12, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(20, NULL, 3, 'ENTRADA', 59, 59, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(21, NULL, 3, 'ENTRADA', 48, 48, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(22, NULL, 3, 'ENTRADA', 35, 35, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(23, NULL, 3, 'ENTRADA', 67, 67, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(24, NULL, 3, 'ENTRADA', 62, 62, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(25, NULL, 3, 'ENTRADA', 23, 23, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(26, NULL, 3, 'ENTRADA', 55, 55, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(27, NULL, 3, 'ENTRADA', 72, 72, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(28, NULL, 3, 'ENTRADA', 40, 40, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(29, NULL, 3, 'ENTRADA', 57, 57, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(30, NULL, 3, 'ENTRADA', 45, 45, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(31, NULL, 3, 'ENTRADA', 53, 53, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(32, NULL, 3, 'ENTRADA', 15, 15, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(33, NULL, 3, 'ENTRADA', 63, 63, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(34, NULL, 3, 'ENTRADA', 11, 11, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(35, NULL, 3, 'ENTRADA', 44, 44, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(36, NULL, 3, 'ENTRADA', 50, 50, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(37, NULL, 3, 'ENTRADA', 45, 45, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(38, NULL, 3, 'ENTRADA', 23, 23, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(39, NULL, 3, 'ENTRADA', 46, 46, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(40, NULL, 3, 'ENTRADA', 61, 61, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(41, NULL, 3, 'ENTRADA', 48, 48, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(42, NULL, 3, 'ENTRADA', 10, 10, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(43, NULL, 3, 'ENTRADA', 77, 77, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(44, NULL, 3, 'ENTRADA', 51, 51, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(45, NULL, 3, 'ENTRADA', 33, 33, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(46, NULL, 3, 'ENTRADA', 79, 79, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(47, NULL, 3, 'ENTRADA', 15, 15, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(48, NULL, 3, 'ENTRADA', 22, 22, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(49, NULL, 3, 'ENTRADA', 28, 28, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(50, NULL, 3, 'ENTRADA', 23, 23, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(51, NULL, 3, 'ENTRADA', 23, 23, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(52, NULL, 3, 'ENTRADA', 12, 12, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(53, NULL, 3, 'ENTRADA', 24, 24, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(54, NULL, 3, 'ENTRADA', 74, 74, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(55, NULL, 3, 'ENTRADA', 53, 53, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(56, NULL, 3, 'ENTRADA', 46, 46, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(57, NULL, 3, 'ENTRADA', 11, 11, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(58, NULL, 3, 'ENTRADA', 62, 62, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(59, NULL, 3, 'ENTRADA', 24, 24, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(60, NULL, 3, 'ENTRADA', 53, 53, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(61, NULL, 3, 'ENTRADA', 61, 61, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(62, NULL, 3, 'ENTRADA', 57, 57, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(63, NULL, 3, 'ENTRADA', 56, 56, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(64, NULL, 3, 'ENTRADA', 38, 38, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(65, NULL, 3, 'ENTRADA', 61, 61, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(66, NULL, 3, 'ENTRADA', 36, 36, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(67, NULL, 3, 'ENTRADA', 24, 24, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(68, NULL, 3, 'ENTRADA', 31, 31, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(69, NULL, 3, 'ENTRADA', 77, 77, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(70, NULL, 3, 'ENTRADA', 11, 11, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(71, NULL, 3, 'ENTRADA', 77, 77, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(72, NULL, 3, 'ENTRADA', 79, 79, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(73, NULL, 3, 'ENTRADA', 58, 58, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(74, NULL, 3, 'ENTRADA', 40, 40, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(75, NULL, 3, 'ENTRADA', 26, 26, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(76, NULL, 3, 'ENTRADA', 37, 37, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(77, NULL, 3, 'ENTRADA', 10, 10, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(78, NULL, 3, 'ENTRADA', 10, 10, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(79, NULL, 3, 'ENTRADA', 43, 43, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(80, NULL, 3, 'ENTRADA', 77, 77, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(81, NULL, 3, 'ENTRADA', 69, 69, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(82, NULL, 3, 'ENTRADA', 61, 61, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(83, NULL, 3, 'ENTRADA', 41, 41, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(84, NULL, 3, 'ENTRADA', 48, 48, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(85, NULL, 3, 'ENTRADA', 25, 25, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(86, NULL, 3, 'ENTRADA', 19, 19, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(87, NULL, 3, 'ENTRADA', 30, 30, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(88, NULL, 3, 'ENTRADA', 78, 78, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(89, NULL, 3, 'ENTRADA', 12, 12, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(90, NULL, 3, 'ENTRADA', 73, 73, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(91, NULL, 3, 'ENTRADA', 41, 41, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(92, NULL, 3, 'ENTRADA', 51, 51, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(93, NULL, 3, 'ENTRADA', 74, 74, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(94, NULL, 3, 'ENTRADA', 48, 48, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(95, NULL, 3, 'ENTRADA', 15, 15, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(96, NULL, 3, 'ENTRADA', 9, 9, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(97, NULL, 3, 'ENTRADA', 39, 39, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(98, NULL, 3, 'ENTRADA', 68, 68, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(99, NULL, 3, 'ENTRADA', 15, 15, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(100, NULL, 3, 'ENTRADA', 36, 36, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(101, NULL, 3, 'ENTRADA', 73, 73, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(103, NULL, 3, 'ENTRADA', 27, 27, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(104, NULL, 3, 'ENTRADA', 59, 59, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(105, NULL, 3, 'ENTRADA', 54, 54, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(106, NULL, 3, 'ENTRADA', 37, 37, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(107, NULL, 3, 'ENTRADA', 79, 79, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(108, NULL, 3, 'ENTRADA', 43, 43, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(109, NULL, 3, 'ENTRADA', 51, 51, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(110, NULL, 3, 'ENTRADA', 33, 33, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(111, NULL, 3, 'ENTRADA', 55, 55, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(112, NULL, 3, 'ENTRADA', 53, 53, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(113, NULL, 3, 'ENTRADA', 66, 66, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(114, NULL, 3, 'ENTRADA', 66, 66, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(115, NULL, 3, 'ENTRADA', 78, 78, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(116, NULL, 3, 'ENTRADA', 68, 68, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(117, NULL, 3, 'ENTRADA', 47, 47, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(118, NULL, 3, 'ENTRADA', 32, 32, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(119, NULL, 3, 'ENTRADA', 28, 28, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(120, NULL, 3, 'ENTRADA', 60, 60, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(121, NULL, 3, 'ENTRADA', 27, 27, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(122, NULL, 3, 'ENTRADA', 70, 70, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(123, NULL, 3, 'ENTRADA', 8, 8, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(124, NULL, 3, 'ENTRADA', 53, 53, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(125, NULL, 3, 'ENTRADA', 74, 74, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(126, NULL, 3, 'ENTRADA', 60, 60, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(127, NULL, 3, 'ENTRADA', 12, 12, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(128, NULL, 3, 'ENTRADA', 30, 30, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(129, NULL, 3, 'ENTRADA', 18, 18, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(130, NULL, 3, 'ENTRADA', 46, 46, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(131, NULL, 3, 'ENTRADA', 55, 55, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(132, NULL, 3, 'ENTRADA', 77, 77, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(133, NULL, 3, 'ENTRADA', 41, 41, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(134, NULL, 3, 'ENTRADA', 25, 25, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(135, NULL, 3, 'ENTRADA', 20, 20, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(136, NULL, 3, 'ENTRADA', 10, 10, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(137, NULL, 3, 'ENTRADA', 76, 76, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(138, NULL, 3, 'ENTRADA', 35, 35, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(139, NULL, 3, 'ENTRADA', 47, 47, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(140, NULL, 3, 'ENTRADA', 13, 13, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(141, NULL, 3, 'ENTRADA', 58, 58, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(142, NULL, 3, 'ENTRADA', 56, 56, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(143, NULL, 3, 'ENTRADA', 76, 76, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(144, NULL, 3, 'ENTRADA', 74, 74, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(145, NULL, 3, 'ENTRADA', 28, 28, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(146, NULL, 3, 'ENTRADA', 73, 73, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(147, NULL, 3, 'ENTRADA', 21, 21, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(148, NULL, 3, 'ENTRADA', 18, 18, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(149, NULL, 3, 'ENTRADA', 26, 26, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(150, NULL, 3, 'ENTRADA', 57, 57, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(151, NULL, 3, 'ENTRADA', 50, 50, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(152, NULL, 3, 'ENTRADA', 78, 78, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(153, NULL, 3, 'ENTRADA', 41, 41, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(154, NULL, 3, 'ENTRADA', 47, 47, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(155, NULL, 3, 'ENTRADA', 13, 13, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(156, NULL, 3, 'ENTRADA', 32, 32, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(157, NULL, 3, 'ENTRADA', 28, 28, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(158, NULL, 3, 'ENTRADA', 45, 45, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(159, NULL, 3, 'ENTRADA', 45, 45, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(160, NULL, 3, 'ENTRADA', 77, 77, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(161, NULL, 3, 'ENTRADA', 44, 44, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(162, NULL, 3, 'ENTRADA', 53, 53, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(163, NULL, 3, 'ENTRADA', 25, 25, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(164, NULL, 3, 'ENTRADA', 57, 57, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(165, NULL, 3, 'ENTRADA', 32, 32, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(166, NULL, 3, 'ENTRADA', 9, 9, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(167, NULL, 3, 'ENTRADA', 69, 69, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(168, NULL, 3, 'ENTRADA', 62, 62, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(169, NULL, 3, 'ENTRADA', 53, 53, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(170, NULL, 3, 'ENTRADA', 76, 76, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(171, NULL, 3, 'ENTRADA', 29, 29, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(172, NULL, 3, 'ENTRADA', 74, 74, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(173, NULL, 3, 'ENTRADA', 11, 11, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(174, NULL, 3, 'ENTRADA', 30, 30, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(175, NULL, 3, 'ENTRADA', 48, 48, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(176, NULL, 3, 'ENTRADA', 77, 77, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(177, NULL, 3, 'ENTRADA', 26, 26, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(178, NULL, 3, 'ENTRADA', 28, 28, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(179, NULL, 3, 'ENTRADA', 11, 11, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(180, NULL, 3, 'ENTRADA', 22, 22, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(181, NULL, 3, 'ENTRADA', 73, 73, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(182, NULL, 3, 'ENTRADA', 8, 8, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(183, NULL, 3, 'ENTRADA', 55, 55, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(184, NULL, 3, 'ENTRADA', 16, 16, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(185, NULL, 3, 'ENTRADA', 55, 55, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(186, NULL, 3, 'ENTRADA', 46, 46, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(187, NULL, 3, 'ENTRADA', 35, 35, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(188, NULL, 3, 'ENTRADA', 76, 76, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(189, NULL, 3, 'ENTRADA', 27, 27, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(190, NULL, 3, 'ENTRADA', 6, 6, 'Inventario inicial', NOW() - INTERVAL 40 DAY),
(68, 1, NULL, 'VENTA', 1, 30, 'Venta PED-000001', NOW() - INTERVAL 4 DAY),
(2, 1, NULL, 'VENTA', 2, 14, 'Venta PED-000001', NOW() - INTERVAL 4 DAY),
(122, 2, NULL, 'VENTA', 1, 69, 'Venta PED-000002', NOW() - INTERVAL 1 DAY);

-- Auditoría de ejemplo

INSERT INTO auditoria (id_usuario, accion, entidad, id_entidad, detalle, ip, created_at) VALUES
(2, 'APROBAR_FORMULA', 'formulas_medicas', '1', 'Fórmula aprobada para el pedido PED-000001', '127.0.0.1', NOW() - INTERVAL 11 DAY),
(3, 'CREAR', 'promociones', '1', 'Promoción "Semana del bienestar"', '127.0.0.1', NOW() - INTERVAL 5 DAY);

COMMIT;