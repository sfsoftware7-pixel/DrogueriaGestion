-- =====================================================================
--  DrogueriaGestión · 04_mejoras.sql
--  Mejoras SOLO aditivas sobre la base existente (no borra ni altera tablas,
--  columnas, triggers ni rutinas de los scripts 01 a 03).
--  Se puede ejecutar varias veces seguidas: cada objeto se crea solo si falta
--  o se reemplaza a sí mismo.
--
--  Aplicar a una base ya instalada (sin recrearla):
--      python database/init_db.py --solo-mejoras
--  o con el cliente de MySQL:
--      mysql -u root -p drogueria_gestion < database/04_mejoras.sql
--
--  Contenido:
--    1. ix_ventas_estado_fecha_valores: índice de cobertura para el análisis ABC
--       y los totales de los reportes.
--    2. sp_modelo_objetos(): triggers, rutinas y vistas con su definición,
--       para la pantalla «Modelo de datos».
-- =====================================================================

USE drogueria_gestion;

DELIMITER $$

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
