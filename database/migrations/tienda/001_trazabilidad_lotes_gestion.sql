-- Ejecutar una sola vez sobre la base drogueria_db ya instalada.
-- Para instalaciones nuevas, esta tabla ya forma parte de database/schema.sql.
CREATE TABLE IF NOT EXISTS pedido_item_lotes_gestion (
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
