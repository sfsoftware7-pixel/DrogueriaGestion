"""API del análisis ABC (Pareto) de los medicamentos vendidos en un rango de fechas.

Todo el cálculo ocurre en MySQL con expresiones de tabla comunes (CTE) y funciones de ventana:
  - RANK() OVER (ORDER BY total DESC) ordena los medicamentos por valor vendido.
  - SUM(total) OVER () da el total general sin agrupar las filas.
  - SUM(total) OVER (ORDER BY total DESC ROWS UNBOUNDED PRECEDING) acumula el valor (curva de Pareto).
Clase A: lo que acumula el primer 80 % del valor; B: hasta el 95 %; C: el resto.

El valor de cada línea descuenta la parte proporcional del descuento de su venta, así la suma del
análisis coincide con ventas.total, que es lo que suma sp_reporte_ventas para el mismo rango.
"""
from decimal import Decimal

from flask import Blueprint, jsonify

from ..db import consultar, get_db
from ..seguridad import permiso_requerido
from .reportes import SQL_VENTAS_DIARIO, _rango

bp = Blueprint('analisis_abc', __name__)

UMBRAL_A = 80
UMBRAL_B = 95

# Parámetros: (desde, hasta). Los umbrales son constantes del código, no datos del usuario.
SQL_ANALISIS_ABC = f'''WITH ventas_rango AS (
    SELECT v.id_venta,
           v.total / NULLIF(v.subtotal + v.impuesto, 0) AS factor_descuento
      FROM ventas v
     WHERE v.estado = 'COMPLETADA' AND v.fecha_venta >= %s AND v.fecha_venta < %s + INTERVAL 1 DAY
),
por_medicamento AS (
    SELECT d.id_medicamento,
           SUM(d.cantidad) AS unidades,
           SUM((d.subtotal + d.impuesto) * vr.factor_descuento) AS total
      FROM ventas_rango vr
      JOIN detalle_venta d ON d.id_venta = vr.id_venta
     GROUP BY d.id_medicamento
),
clasificado AS (
    SELECT pm.id_medicamento, pm.unidades, pm.total,
           RANK() OVER (ORDER BY pm.total DESC) AS puesto,
           SUM(pm.total) OVER () AS total_general,
           SUM(pm.total) OVER (ORDER BY pm.total DESC, pm.id_medicamento
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS acumulado
      FROM por_medicamento pm
)
SELECT c.puesto, m.id_medicamento, m.codigo, m.nombre, m.concentracion, cat.nombre AS categoria,
       c.unidades,
       ROUND(c.total, 2) AS total,
       ROUND(100 * c.total / c.total_general, 2) AS porcentaje,
       ROUND(100 * c.acumulado / c.total_general, 2) AS porcentaje_acumulado,
       CASE WHEN c.acumulado - c.total < {UMBRAL_A / 100} * c.total_general THEN 'A'
            WHEN c.acumulado - c.total < {UMBRAL_B / 100} * c.total_general THEN 'B'
            ELSE 'C' END AS clase,
       c.total_general
  FROM clasificado c
  JOIN medicamentos m ON m.id_medicamento = c.id_medicamento
  JOIN categorias cat ON cat.id_categoria = m.id_categoria
 ORDER BY c.puesto, m.nombre'''


def total_sp_reporte_ventas(desde, hasta):
    """Suma de total_ventas que devuelve sp_reporte_ventas para el mismo rango (control cruzado)."""
    with get_db().cursor() as cur:
        cur.execute(SQL_VENTAS_DIARIO, (desde, hasta))
        filas = cur.fetchall()
        while cur.nextset():
            pass
    return sum((Decimal(f['total_ventas']) for f in filas), Decimal('0'))


@bp.get('/analisis/abc')
@permiso_requerido('analisis_abc.ver')
def analisis():
    desde, hasta = _rango()
    filas = consultar(SQL_ANALISIS_ABC, (desde, hasta))
    total_abc = Decimal(filas[0]['total_general']) if filas else Decimal('0')
    total_sp = total_sp_reporte_ventas(desde, hasta)

    resumen = {clase: {'productos': 0, 'total': Decimal('0'), 'unidades': 0} for clase in 'ABC'}
    for fila in filas:
        fila.pop('total_general', None)
        grupo = resumen[fila['clase']]
        grupo['productos'] += 1
        grupo['total'] += Decimal(fila['total'])
        grupo['unidades'] += int(fila['unidades'])
    for grupo in resumen.values():
        grupo['porcentaje'] = round(grupo['total'] * 100 / total_abc, 1) if total_abc else 0

    return jsonify({
        'desde': desde,
        'hasta': hasta,
        'umbrales': {'A': UMBRAL_A, 'B': UMBRAL_B},
        'productos': filas,
        'resumen': resumen,
        'control': {
            'total_abc': round(total_abc, 2),
            'total_sp_reporte_ventas': total_sp,
            # La división del descuento proporcional deja decimales: se compara al peso
            'coincide': abs(total_abc - total_sp) < 1,
        },
    })
