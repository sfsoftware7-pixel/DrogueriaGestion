"""API de la bitácora de auditoría (solo administrador)."""
from flask import Blueprint, jsonify, request

from ..db import consultar, paginar
from ..seguridad import permiso_requerido
from ..utils import parametro_fecha, parametros_paginacion, patron_busqueda

bp = Blueprint('auditoria', __name__)


@bp.get('/auditoria')
@permiso_requerido('auditoria.ver')
def listar():
    pagina, por_pagina = parametros_paginacion(por_defecto=25)
    sql = '''SELECT a.id_auditoria, a.fecha, a.accion, a.modulo, a.descripcion, a.ip,
                    u.usuario, CONCAT_WS(' ', u.nombres, u.apellidos) AS nombre_usuario
               FROM auditoria a LEFT JOIN usuarios u ON u.id_usuario = a.id_usuario
              WHERE 1 = 1'''
    params = []
    if request.args.get('modulo'):
        sql += ' AND a.modulo = %s'
        params.append(request.args['modulo'])
    if request.args.get('accion'):
        sql += ' AND a.accion = %s'
        params.append(request.args['accion'])
    q = request.args.get('q', '').strip()
    if q:
        sql += ' AND (a.descripcion LIKE %s OR u.usuario LIKE %s)'
        params += [patron_busqueda(q)] * 2
    desde, hasta = parametro_fecha('desde'), parametro_fecha('hasta')
    if desde:
        sql += ' AND a.fecha >= %s'
        params.append(desde)
    if hasta:
        sql += ' AND a.fecha < %s + INTERVAL 1 DAY'
        params.append(hasta)
    return jsonify(paginar(sql, params, pagina, por_pagina, 'a.fecha DESC, a.id_auditoria DESC'))


@bp.get('/auditoria/filtros')
@permiso_requerido('auditoria.ver')
def filtros():
    return jsonify({
        'modulos': [f['modulo'] for f in consultar('SELECT DISTINCT modulo FROM auditoria ORDER BY modulo')],
        'acciones': [f['accion'] for f in consultar('SELECT DISTINCT accion FROM auditoria ORDER BY accion')],
    })
