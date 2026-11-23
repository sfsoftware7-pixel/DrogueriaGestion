"""API de reportes gerenciales: ventas, productos de mayor rotación e inventario valorizado.

Las consultas son constantes del módulo: el endpoint ejecuta exactamente el mismo texto que muestra
«Ver SQL» (routes/consultas.py), junto con su EXPLAIN.
"""
from datetime import date, timedelta

from flask import Blueprint, jsonify, request

from ..db import consultar, consultar_uno, get_db
from ..seguridad import permiso_requerido
from ..utils import ApiError, parametro_fecha

bp = Blueprint('reportes', __name__)

# Ventas completadas del rango [desde, hasta] (ambos días incluidos); parámetros: (desde, hasta)
FILTRO_VENTAS = "v.estado = 'COMPLETADA' AND v.fecha_venta >= %s AND v.fecha_venta < %s + INTERVAL 1 DAY"

# Serie diaria obtenida con el procedimiento almacenado sp_reporte_ventas
SQL_VENTAS_DIARIO = 'CALL sp_reporte_ventas(%s, %s)'

SQL_VENTAS_TOTALES = f'''SELECT COUNT(*) AS numero_ventas, COALESCE(SUM(v.subtotal), 0) AS subtotal,
                   COALESCE(SUM(v.descuento), 0) AS descuentos, COALESCE(SUM(v.impuesto), 0) AS impuestos,
                   COALESCE(SUM(v.total), 0) AS total, COALESCE(AVG(v.total), 0) AS ticket_promedio
              FROM ventas v WHERE {FILTRO_VENTAS}'''

# El costo se toma de detalle_venta (costo del lote en el momento de la venta), no del lote actual
SQL_COSTO_VENTAS = f'''SELECT COALESCE(SUM(d.cantidad * d.costo_unitario), 0) AS costo, COALESCE(SUM(d.cantidad), 0) AS unidades
              FROM detalle_venta d
              JOIN ventas v ON v.id_venta = d.id_venta
             WHERE {FILTRO_VENTAS}'''

SQL_VENTAS_ANULADAS = '''SELECT COUNT(*) AS n, COALESCE(SUM(total), 0) AS total FROM ventas
            WHERE estado = 'ANULADA' AND fecha_venta >= %s AND fecha_venta < %s + INTERVAL 1 DAY'''

SQL_VENTAS_POR_METODO = f'''SELECT v.metodo_pago, COUNT(*) AS ventas, SUM(v.total) AS total
              FROM ventas v WHERE {FILTRO_VENTAS} GROUP BY v.metodo_pago ORDER BY total DESC'''

SQL_VENTAS_POR_VENDEDOR = f'''SELECT CONCAT_WS(' ', u.nombres, u.apellidos) AS vendedor, COUNT(*) AS ventas, SUM(v.total) AS total
              FROM ventas v JOIN usuarios u ON u.id_usuario = v.id_usuario
             WHERE {FILTRO_VENTAS} GROUP BY u.id_usuario ORDER BY total DESC'''

SQL_VENTAS_POR_CATEGORIA = f'''SELECT c.nombre AS categoria, SUM(d.cantidad) AS unidades, SUM(d.subtotal + d.impuesto) AS total
              FROM detalle_venta d
              JOIN ventas v ON v.id_venta = d.id_venta
              JOIN medicamentos m ON m.id_medicamento = d.id_medicamento
              JOIN categorias c ON c.id_categoria = m.id_categoria
             WHERE {FILTRO_VENTAS} GROUP BY c.id_categoria ORDER BY total DESC'''

# Parámetros: (desde, hasta, limite)
SQL_TOP_MEDICAMENTOS = '''SELECT m.codigo, m.nombre, m.concentracion, c.nombre AS categoria,
                  SUM(d.cantidad) AS unidades, COUNT(DISTINCT d.id_venta) AS ventas,
                  SUM(d.subtotal + d.impuesto) AS total,
                  SUM(d.subtotal) - SUM(d.cantidad * d.costo_unitario) AS utilidad
             FROM detalle_venta d
             JOIN ventas v ON v.id_venta = d.id_venta
             JOIN medicamentos m ON m.id_medicamento = d.id_medicamento
             JOIN categorias c ON c.id_categoria = m.id_categoria
            WHERE v.estado = 'COMPLETADA' AND v.fecha_venta >= %s AND v.fecha_venta < %s + INTERVAL 1 DAY
            GROUP BY m.id_medicamento, c.nombre
            ORDER BY unidades DESC, total DESC
            LIMIT %s'''

SQL_INVENTARIO_POR_CATEGORIA = '''SELECT c.nombre AS categoria,
                  COUNT(DISTINCT m.id_medicamento) AS productos,
                  COALESCE(SUM(l.cantidad_actual), 0) AS unidades,
                  COALESCE(SUM(l.cantidad_actual * l.costo_unitario), 0) AS valor_costo,
                  COALESCE(SUM(l.cantidad_actual * m.precio_venta), 0) AS valor_venta
             FROM categorias c
             JOIN medicamentos m ON m.id_categoria = c.id_categoria AND m.activo = 1
             LEFT JOIN lotes l ON l.id_medicamento = m.id_medicamento
                              AND l.cantidad_actual > 0 AND l.fecha_vencimiento >= CURDATE()
            GROUP BY c.id_categoria
            ORDER BY valor_costo DESC'''

SQL_STOCK_BAJO = '''SELECT codigo, nombre, concentracion, categoria, stock_disponible, stock_minimo, estado_stock,
                  GREATEST(stock_minimo * 2 - stock_disponible, 0) AS sugerido_pedir
             FROM v_stock_medicamentos
            WHERE activo = 1 AND estado_stock IN ('AGOTADO', 'BAJO')
            ORDER BY stock_disponible, nombre'''


def _rango():
    hasta = parametro_fecha('hasta', date.today())
    desde = parametro_fecha('desde', hasta - timedelta(days=29))
    if desde > hasta:
        raise ApiError('La fecha inicial no puede ser mayor que la final')
    if (hasta - desde).days > 366:
        raise ApiError('El rango máximo de consulta es de un año')
    return desde, hasta


def limite_top(defecto=10):
    return min(50, max(1, request.args.get('limite', defecto, type=int)))


@bp.get('/reportes/ventas')
@permiso_requerido('reportes.ver')
def ventas():
    desde, hasta = _rango()
    rango = (desde, hasta)

    with get_db().cursor() as cur:
        cur.execute(SQL_VENTAS_DIARIO, rango)
        diario = cur.fetchall()
        while cur.nextset():
            pass

    totales = consultar_uno(SQL_VENTAS_TOTALES, rango)
    costo = consultar_uno(SQL_COSTO_VENTAS, rango)
    totales['costo_ventas'] = costo['costo']
    totales['unidades'] = costo['unidades']
    totales['utilidad_bruta'] = totales['subtotal'] - totales['descuentos'] - costo['costo']
    anuladas = consultar_uno(SQL_VENTAS_ANULADAS, rango)

    por_metodo = consultar(SQL_VENTAS_POR_METODO, rango)
    por_vendedor = consultar(SQL_VENTAS_POR_VENDEDOR, rango)
    por_categoria = consultar(SQL_VENTAS_POR_CATEGORIA, rango)

    return jsonify({
        'desde': desde, 'hasta': hasta,
        'totales': totales,
        'anuladas': anuladas,
        'diario': diario,
        'por_metodo': por_metodo,
        'por_vendedor': por_vendedor,
        'por_categoria': por_categoria,
    })


@bp.get('/reportes/top-medicamentos')
@permiso_requerido('reportes.ver')
def top_medicamentos():
    desde, hasta = _rango()
    filas = consultar(SQL_TOP_MEDICAMENTOS, (desde, hasta, limite_top()))
    return jsonify(filas)


@bp.get('/reportes/inventario')
@permiso_requerido('reportes.ver')
def inventario():
    por_categoria = consultar(SQL_INVENTARIO_POR_CATEGORIA)
    stock_bajo = consultar(SQL_STOCK_BAJO)
    totales = {
        'productos': sum(int(f['productos']) for f in por_categoria),
        'unidades': sum(int(f['unidades']) for f in por_categoria),
        'valor_costo': sum(f['valor_costo'] for f in por_categoria),
        'valor_venta': sum(f['valor_venta'] for f in por_categoria),
    }
    return jsonify({'por_categoria': por_categoria, 'stock_bajo': stock_bajo, 'totales': totales})
