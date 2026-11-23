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
