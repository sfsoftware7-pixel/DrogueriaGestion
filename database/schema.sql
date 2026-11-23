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
