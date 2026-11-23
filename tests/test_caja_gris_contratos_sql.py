"""Pruebas de caja gris: verifican puntos de código conocidos frente al contrato DDL."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def leer(ruta):
    return (ROOT / ruta).read_text(encoding='utf-8').lower()


def test_esquema_gestion_define_integridad_relacional_y_valores():
    sql = leer('database/01_esquema.sql')

    assert 'foreign key' in sql
    assert 'uq_lotes_medicamento_lote' in sql
    assert 'ck_detalle_venta_cantidad check (cantidad > 0)' in sql
    assert 'ck_ventas_descuento check (descuento <= subtotal + impuesto)' in sql


def test_trigger_de_venta_valida_lote_vigencia_y_stock():
    sql = leer('database/02_vistas_rutinas.sql')
    trigger = sql.split('create trigger trg_detalle_venta_bi', 1)[1].split('end$$', 1)[0]

    assert 'v_id_medicamento <> new.id_medicamento' in trigger
    assert 'v_vencimiento < curdate()' in trigger
    assert 'new.cantidad > v_existencia' in trigger


def test_servicio_venta_bloquea_stock_y_registra_kardex():
    codigo = leer('app/services/ventas.py')

    assert 'for update' in codigo
    assert 'fecha_vencimiento >= curdate()' in codigo
    assert 'insert into movimientos_inventario' in codigo


def test_esquema_tienda_impone_total_y_producto_unico_por_pedido():
    sql = leer('database/schema.sql')

    assert 'ck_pedidos_total check (total = subtotal - descuento + costo_envio)' in sql
    assert 'uq_pedido_items_producto unique (id_pedido, id_producto)' in sql
    assert 'foreign key (id_inventario)' in sql
