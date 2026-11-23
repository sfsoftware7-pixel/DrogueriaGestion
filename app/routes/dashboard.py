"""API del panel principal: indicadores, alertas, tendencias y pedidos web recientes."""
from datetime import date, timedelta
import logging
import re

import pymysql
from flask import Blueprint, current_app, jsonify

from ..db import consultar, consultar_uno
from ..seguridad import login_requerido, permiso_requerido, tiene_permiso

bp = Blueprint('dashboard', __name__)
log = logging.getLogger(__name__)

ESTADOS_PEDIDO_TIENDA = {
    'PENDIENTE_FORMULA': 'Pendiente de fórmula',
    'CONFIRMADO': 'Confirmado',
    'EN_PREPARACION': 'En preparación',
    'EN_CAMINO': 'En camino',
    'LISTO_PARA_RETIRO': 'Listo para retirar',
    'ENTREGADO': 'Entregado',
    'CANCELADO': 'Cancelado',
}


def _pedidos_tienda():
    """Pedidos activos y entregas de hoy desde el esquema separado de la tienda."""
    nombre_bd = current_app.config.get('TIENDA_DB_NAME', 'drogueria_db')
    if not re.fullmatch(r'[A-Za-z0-9_]+', nombre_bd or ''):
        log.error('TIENDA_DB_NAME debe contener solo letras, números y guion bajo')
        return [], False
    tabla_pedidos = f'`{nombre_bd}`.`pedidos`'
    tabla_usuarios = f'`{nombre_bd}`.`usuarios`'
    tabla_items = f'`{nombre_bd}`.`pedido_items`'
    tabla_historial = f'`{nombre_bd}`.`pedido_historial`'
    tabla_productos = f'`{nombre_bd}`.`productos`'
    try:
        filas = consultar(f'''SELECT pe.codigo, pe.estado, pe.tipo_entrega,
                    COALESCE(MAX(CASE WHEN ph.estado = pe.estado THEN ph.created_at END), pe.created_at)
                        AS actualizado_en,
                    CONCAT_WS(' ', u.nombres, u.apellidos) AS cliente,
                    items.productos
               FROM {tabla_pedidos} pe
               JOIN {tabla_usuarios} u ON u.id_usuario = pe.id_usuario
               JOIN (SELECT pi.id_pedido,
                            GROUP_CONCAT(CONCAT(pr.nombre, ' × ', pi.cantidad)
                                         ORDER BY pr.nombre SEPARATOR ', ') AS productos
                       FROM {tabla_items} pi
                       JOIN {tabla_productos} pr ON pr.id_producto = pi.id_producto
                      GROUP BY pi.id_pedido) items ON items.id_pedido = pe.id_pedido
               LEFT JOIN {tabla_historial} ph ON ph.id_pedido = pe.id_pedido
              WHERE pe.estado <> 'CANCELADO'
              GROUP BY pe.id_pedido, pe.codigo, pe.estado, pe.tipo_entrega, pe.created_at,
                       u.nombres, u.apellidos, items.productos
              HAVING pe.estado <> 'ENTREGADO' OR actualizado_en >= CURDATE()
              ORDER BY (pe.estado = 'ENTREGADO') ASC, actualizado_en DESC
              LIMIT 12''')
    except pymysql.err.MySQLError:
        log.warning('No se pudieron leer los pedidos de la tienda; revise el esquema y el permiso SELECT',
                    exc_info=True)
        return [], False
    for fila in filas:
        fila['estado_texto'] = ESTADOS_PEDIDO_TIENDA.get(fila['estado'], fila['estado'])
        fila['tipo_entrega_texto'] = 'Domicilio' if fila['tipo_entrega'] == 'DOMICILIO' else 'Retiro en sede'
        fila['updated_at'] = fila.pop('actualizado_en')
    return filas, True

# Parámetros: (inicio_mes, inicio_mes, inicio_mes) — ver params_indicadores()
SQL_INDICADORES_VENTAS = '''SELECT
              COALESCE(SUM(CASE WHEN DATE(fecha_venta) = CURDATE() THEN total END), 0) AS total_hoy,
              COUNT(CASE WHEN DATE(fecha_venta) = CURDATE() THEN 1 END) AS numero_hoy,
              COALESCE(SUM(CASE WHEN DATE(fecha_venta) = CURDATE() - INTERVAL 1 DAY THEN total END), 0) AS total_ayer,
              COALESCE(SUM(CASE WHEN fecha_venta >= %s THEN total END), 0) AS total_mes,
              COUNT(CASE WHEN fecha_venta >= %s THEN 1 END) AS numero_mes
             FROM ventas
            WHERE estado = 'COMPLETADA' AND fecha_venta >= LEAST(%s, CURDATE() - INTERVAL 1 DAY)'''

# Parámetros: (desde,) — ver params_tendencia()
SQL_TENDENCIA = 'SELECT fecha, numero_ventas, total_ventas FROM v_ventas_diarias WHERE fecha >= %s ORDER BY fecha'

SQL_TOP_30_DIAS = '''SELECT m.nombre, SUM(d.cantidad) AS unidades, SUM(d.subtotal + d.impuesto) AS total
             FROM detalle_venta d
             JOIN ventas v ON v.id_venta = d.id_venta
             JOIN medicamentos m ON m.id_medicamento = d.id_medicamento
            WHERE v.estado = 'COMPLETADA' AND v.fecha_venta >= CURDATE() - INTERVAL 30 DAY
            GROUP BY m.id_medicamento, m.nombre
            ORDER BY unidades DESC LIMIT 5'''

SQL_ULTIMAS_VENTAS = '''SELECT id_venta, numero_factura, fecha_venta, cliente, total, metodo_pago, estado
             FROM v_ventas ORDER BY fecha_venta DESC LIMIT 6'''

SQL_RESUMEN_INVENTARIO = '''SELECT COUNT(*) AS productos_activos,
                  SUM(estado_stock = 'AGOTADO') AS agotados,
                  SUM(estado_stock = 'BAJO') AS stock_bajo
             FROM v_stock_medicamentos WHERE activo = 1'''

SQL_RESUMEN_VENCIMIENTOS = '''SELECT SUM(estado_vencimiento = 'VENCIDO') AS vencidos,
                  SUM(estado_vencimiento = 'CRITICO') AS criticos,
                  SUM(estado_vencimiento = 'PROXIMO') AS proximos
             FROM v_lotes_vencimiento WHERE cantidad_actual > 0'''

SQL_ALERTAS_STOCK = '''SELECT id_medicamento, nombre, concentracion, stock_disponible, stock_minimo, estado_stock
             FROM v_stock_medicamentos
            WHERE activo = 1 AND estado_stock IN ('AGOTADO', 'BAJO')
            ORDER BY stock_disponible, nombre LIMIT 8'''

SQL_ALERTAS_VENCIMIENTO = '''SELECT id_lote, medicamento, numero_lote, fecha_vencimiento, dias_para_vencer, cantidad_actual,
                  estado_vencimiento
             FROM v_lotes_vencimiento
            WHERE cantidad_actual > 0 AND estado_vencimiento IN ('VENCIDO', 'CRITICO', 'PROXIMO')
            ORDER BY fecha_vencimiento LIMIT 8'''


def params_indicadores():
    inicio_mes = date.today().replace(day=1)
    return (inicio_mes, inicio_mes, inicio_mes)


def params_tendencia():
    return (date.today() - timedelta(days=13),)


def _indicadores_ventas():
    """Totales de ventas, tendencia de 14 días, más vendidos y últimas ventas (requiere 'ventas.ver')."""
    ventas = consultar_uno(SQL_INDICADORES_VENTAS, params_indicadores())

    (desde,) = params_tendencia()
    filas = consultar(SQL_TENDENCIA, (desde,))
    por_dia = {f['fecha']: f for f in filas}
    tendencia = []
    for i in range(14):
        dia = desde + timedelta(days=i)
        fila = por_dia.get(dia)
        tendencia.append({
            'fecha': dia,
            'total': fila['total_ventas'] if fila else 0,
            'ventas': fila['numero_ventas'] if fila else 0,
        })

    top = consultar(SQL_TOP_30_DIAS)
    ultimas = consultar(SQL_ULTIMAS_VENTAS)
    return ventas, tendencia, top, ultimas


@bp.get('/dashboard')
@login_requerido
def resumen():
    inventario = consultar_uno(SQL_RESUMEN_INVENTARIO)
    vencimientos = consultar_uno(SQL_RESUMEN_VENCIMIENTOS)
    alertas_stock = consultar(SQL_ALERTAS_STOCK)
    alertas_vencimiento = consultar(SQL_ALERTAS_VENCIMIENTO)

    # Los datos de ventas solo se envían a los roles que pueden verlas (BODEGA no)
    ventas, tendencia, top, ultimas = None, [], [], []
    if tiene_permiso('ventas.ver'):
        ventas, tendencia, top, ultimas = _indicadores_ventas()

    return jsonify({
        'ventas': ventas,
        'inventario': {k: int(v or 0) for k, v in inventario.items()},
        'vencimientos': {k: int(v or 0) for k, v in vencimientos.items()},
        'tendencia': tendencia,
        'top_medicamentos': top,
        'alertas_stock': alertas_stock,
        'alertas_vencimiento': alertas_vencimiento,
        'ultimas_ventas': ultimas,
    })


@bp.get('/dashboard/pedidos-tienda')
@permiso_requerido('ventas.ver')
def pedidos_tienda():
    pedidos, disponible = _pedidos_tienda()
    return jsonify({'pedidos': pedidos, 'disponible': disponible})
