"""API del panel principal: indicadores, alertas y tendencias.

Las consultas son constantes del módulo: el endpoint ejecuta exactamente el mismo texto que muestra
«Ver SQL» (routes/consultas.py), con los parámetros que arman las funciones params_*.
"""
from datetime import date, timedelta

from flask import Blueprint, jsonify

from ..db import consultar, consultar_uno
from ..seguridad import login_requerido, tiene_permiso

bp = Blueprint('dashboard', __name__)

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
