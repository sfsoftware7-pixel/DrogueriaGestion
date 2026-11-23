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
    fecha_nacimiento    DATE         NULL,
    autoriza_datos      TINYINT(1)   NOT NULL DEFAULT 0 COMMENT 'Autorización Ley 1581 de 2012',
    activo              TINYINT(1)   NOT NULL DEFAULT 1,
    creado_en           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_clientes_documento UNIQUE (tipo_documento, numero_documento)
) ENGINE = InnoDB COMMENT = 'Clientes de la droguería';

CREATE INDEX ix_clientes_nombres ON clientes (nombres, apellidos);

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
