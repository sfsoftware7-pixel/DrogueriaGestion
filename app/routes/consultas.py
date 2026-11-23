"""«Ver SQL»: muestra la consulta exacta de un reporte o del panel y su plan de ejecución (EXPLAIN).

Solo se aceptan claves de la lista blanca CONSULTAS. Cada entrada apunta a la MISMA constante y a los MISMOS
parámetros que usa su endpoint; del cliente solo llegan la clave y el rango de fechas (validado). Nunca se
ejecuta SQL escrito por el usuario.
"""
import re

import pymysql
from flask import Blueprint, current_app, jsonify

from ..db import get_db
from ..seguridad import permiso_requerido
from ..utils import ApiError
from . import analisis_abc, dashboard, reportes

bp = Blueprint('consultas', __name__)


def _rango():
    return reportes._rango()


def _top():
    desde, hasta = reportes._rango()
    return (desde, hasta, reportes.limite_top(15))


def _sin_parametros():
    return ()


# clave -> (grupo, título, descripción, constante, nombre de la constante, función de parámetros)
CONSULTAS = {
    'reportes.diario': ('Reportes', 'Ventas por día', 'Serie diaria del procedimiento almacenado sp_reporte_ventas.',
                        reportes.SQL_VENTAS_DIARIO, 'reportes.SQL_VENTAS_DIARIO', _rango),
    'reportes.totales': ('Reportes', 'Totales del periodo', 'Total vendido, IVA, descuentos y ticket promedio.',
                         reportes.SQL_VENTAS_TOTALES, 'reportes.SQL_VENTAS_TOTALES', _rango),
    'reportes.costo': ('Reportes', 'Costo y utilidad bruta', 'Costo de los lotes vendidos y unidades del periodo.',
                        reportes.SQL_COSTO_VENTAS, 'reportes.SQL_COSTO_VENTAS', _rango),
    'reportes.anuladas': ('Reportes', 'Ventas anuladas', 'Cantidad y valor de ventas anuladas en el periodo.',
                          reportes.SQL_VENTAS_ANULADAS, 'reportes.SQL_VENTAS_ANULADAS', _rango),
    'reportes.por_metodo': ('Reportes', 'Métodos de pago', 'Ventas agrupadas por método de pago.',
                            reportes.SQL_VENTAS_POR_METODO, 'reportes.SQL_VENTAS_POR_METODO', _rango),
    'reportes.por_categoria': ('Reportes', 'Ventas por categoría', 'Unidades y total vendido por categoría.',
                               reportes.SQL_VENTAS_POR_CATEGORIA, 'reportes.SQL_VENTAS_POR_CATEGORIA', _rango),
    'reportes.por_vendedor': ('Reportes', 'Ventas por vendedor', 'Número de ventas y total por usuario.',
                              reportes.SQL_VENTAS_POR_VENDEDOR, 'reportes.SQL_VENTAS_POR_VENDEDOR', _rango),
    'reportes.top': ('Reportes', 'Medicamentos más vendidos', 'Top 15 del periodo por unidades, con la utilidad.',
                     reportes.SQL_TOP_MEDICAMENTOS, 'reportes.SQL_TOP_MEDICAMENTOS', _top),
    'reportes.inventario': ('Reportes', 'Inventario valorizado', 'Existencias vigentes por categoría a costo y a precio de venta.',
                            reportes.SQL_INVENTARIO_POR_CATEGORIA, 'reportes.SQL_INVENTARIO_POR_CATEGORIA', _sin_parametros),
    'reportes.stock_bajo': ('Reportes', 'Sugerido de compra', 'Productos agotados o bajo el mínimo (vista v_stock_medicamentos).',
                            reportes.SQL_STOCK_BAJO, 'reportes.SQL_STOCK_BAJO', _sin_parametros),
    'panel.ventas': ('Panel principal', 'Ventas de hoy y del mes', 'Indicadores de la parte superior del panel.',
                     dashboard.SQL_INDICADORES_VENTAS, 'dashboard.SQL_INDICADORES_VENTAS', dashboard.params_indicadores),
    'panel.tendencia': ('Panel principal', 'Ventas de los últimos 14 días', 'Lee la vista v_ventas_diarias.',
                        dashboard.SQL_TENDENCIA, 'dashboard.SQL_TENDENCIA', dashboard.params_tendencia),
    'panel.top': ('Panel principal', 'Más vendidos (30 días)', 'Cinco medicamentos con más unidades en 30 días.',
                  dashboard.SQL_TOP_30_DIAS, 'dashboard.SQL_TOP_30_DIAS', _sin_parametros),
    'panel.ultimas_ventas': ('Panel principal', 'Últimas ventas', 'Las seis ventas más recientes que aparecen en el panel.',
                             dashboard.SQL_ULTIMAS_VENTAS, 'dashboard.SQL_ULTIMAS_VENTAS', _sin_parametros),
    'panel.inventario': ('Panel principal', 'Resumen de inventario', 'Conteo de productos activos, agotados y con stock bajo.',
                         dashboard.SQL_RESUMEN_INVENTARIO, 'dashboard.SQL_RESUMEN_INVENTARIO', _sin_parametros),
    'panel.vencimientos': ('Panel principal', 'Resumen de vencimientos', 'Conteo de lotes vencidos, críticos y próximos.',
                           dashboard.SQL_RESUMEN_VENCIMIENTOS, 'dashboard.SQL_RESUMEN_VENCIMIENTOS', _sin_parametros),
    'panel.alertas_stock': ('Panel principal', 'Alertas de inventario', 'Lee la vista v_stock_medicamentos.',
                            dashboard.SQL_ALERTAS_STOCK, 'dashboard.SQL_ALERTAS_STOCK', _sin_parametros),
    'panel.alertas_vencimiento': ('Panel principal', 'Próximos vencimientos', 'Lee la vista v_lotes_vencimiento.',
                                  dashboard.SQL_ALERTAS_VENCIMIENTO, 'dashboard.SQL_ALERTAS_VENCIMIENTO', _sin_parametros),
    'analisis.abc': ('Análisis ABC', 'Clasificación ABC (Pareto)', 'CTE y funciones de ventana: RANK() y SUM() OVER.',
                     analisis_abc.SQL_ANALISIS_ABC, 'analisis_abc.SQL_ANALISIS_ABC', _rango),
}

CODIGO_FALTA_SHOW_VIEW = 1345  # EXPLAIN sobre una vista exige el privilegio SHOW VIEW


def _a_texto(valor):
    return valor.isoformat() if hasattr(valor, 'isoformat') else valor


def _definicion_procedimiento(nombre):
    try:
        with get_db().cursor() as cur:
            cur.execute('CALL sp_modelo_objetos()')
            cur.nextset()
            rutinas = cur.fetchall()
            while cur.nextset():
                pass
    except pymysql.err.MySQLError:
        return None
    return next((r['definicion'] for r in rutinas if r['nombre'] == nombre), None)


def _explicar(sql, params):
    """EXPLAIN tabular (tipo de acceso, índice, filas estimadas) y el plan en árbol."""
    with get_db().cursor() as cur:
        cur.execute(f'EXPLAIN FORMAT=TRADITIONAL {sql}', params)
        filas = cur.fetchall()
        cur.execute(f'EXPLAIN FORMAT=TREE {sql}', params)
        plan = cur.fetchone()
    return filas, (next(iter(plan.values())) if plan else None)


def _analizar(filas):
    resumen = []
    for f in filas:
        extra = f.get('Extra') or ''
        resumen.append({
            'tabla': f.get('table'),
            'acceso': f.get('type'),
            'indice': f.get('key'),
            'filas': f.get('rows'),
            'usa_indice': bool(f.get('key')),
            'cobertura': 'Using index' in extra,
            'recorrido_completo': f.get('type') == 'ALL',
        })
    return resumen


@bp.get('/consultas')
@permiso_requerido('consultas.ver')
def lista():
    return jsonify([{'clave': clave, 'grupo': c[0], 'titulo': c[1], 'descripcion': c[2], 'origen': c[4]}
                    for clave, c in CONSULTAS.items()])


@bp.get('/consultas/<clave>')
@permiso_requerido('consultas.ver')
def detalle(clave):
    if clave not in CONSULTAS:
        raise ApiError('La consulta solicitada no está en la lista permitida', 404)
    grupo, titulo, descripcion, sql, origen, armar_parametros = CONSULTAS[clave]
    params = armar_parametros()
    with get_db().cursor() as cur:
        sql_con_valores = cur.mogrify(sql, params) if params else sql

    respuesta = {
        'clave': clave, 'grupo': grupo, 'titulo': titulo, 'descripcion': descripcion, 'origen': origen,
        'sql': sql, 'parametros': [_a_texto(p) for p in params], 'sql_con_valores': sql_con_valores,
        'explain': None, 'plan': None, 'analisis': [], 'nota': None, 'procedimiento': None,
    }
    if sql.lstrip().upper().startswith('CALL '):
        nombre = sql.split()[1].split('(')[0]
        respuesta['procedimiento'] = {'nombre': nombre, 'definicion': _definicion_procedimiento(nombre)}
        respuesta['nota'] = ('EXPLAIN no se aplica a CALL. El procedimiento lee la vista v_ventas_diarias; '
                             'abajo está su definición, tomada de information_schema.')
        return jsonify(respuesta)

    try:
        filas, plan = _explicar(sql, params)
    except pymysql.err.MySQLError as error:
        if error.args and error.args[0] == CODIGO_FALTA_SHOW_VIEW:
            respuesta['nota'] = ('La consulta usa una vista y MySQL solo muestra el EXPLAIN de una vista a quien tiene '
                                 'el privilegio SHOW VIEW, que el usuario de la aplicación no tiene (privilegios mínimos).')
            return jsonify(respuesta)
        raise
    respuesta.update(explain=filas, plan=plan, analisis=_analizar(filas))
    return jsonify(respuesta)


@bp.get('/consultas/<clave>/workbench')
@permiso_requerido('consultas.ver')
def workbench(clave):
    """Devuelve la consulta permitida con parámetros reales para pegar en MySQL Workbench."""
    if clave not in CONSULTAS:
        raise ApiError('La consulta solicitada no está en la lista permitida', 404)
    nombre_bd = current_app.config.get('DB_NAME', 'drogueria_gestion')
    if not re.fullmatch(r'[A-Za-z0-9_]+', nombre_bd or ''):
        raise ApiError('El nombre configurado de la base de datos no es válido', 500)
    _, titulo, _, sql, _, armar_parametros = CONSULTAS[clave]
    params = armar_parametros()
    with get_db().cursor() as cur:
        consulta = cur.mogrify(sql, params) if params else sql
    return jsonify({'titulo': titulo, 'sql': f'USE `{nombre_bd}`;\n\n{consulta};'})
