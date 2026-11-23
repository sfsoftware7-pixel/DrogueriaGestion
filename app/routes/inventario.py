"""API de inventario: lotes, entradas de mercancía, ajustes, kárdex y vencimientos."""
from flask import Blueprint, g, jsonify, request

from ..db import consultar, consultar_uno, get_db, paginar, transaccion
from ..seguridad import permiso_requerido
from ..services import inventario as servicio
from ..utils import (ApiError, Validador, auditar, datos_json, parametro_fecha, parametros_paginacion,
                     patron_busqueda)

bp = Blueprint('inventario', __name__)

ESTADOS_VENCIMIENTO = ('VENCIDO', 'CRITICO', 'PROXIMO', 'VIGENTE')
TIPOS_MOVIMIENTO = ('ENTRADA', 'VENTA', 'AJUSTE_ENTRADA', 'AJUSTE_SALIDA', 'BAJA_VENCIMIENTO', 'ANULACION_VENTA')


@bp.get('/inventario/lotes')
@permiso_requerido('inventario.ver')
def lotes():
    pagina, por_pagina = parametros_paginacion()
    sql = 'SELECT * FROM v_lotes_vencimiento WHERE 1 = 1'
    params = []
    q = request.args.get('q', '').strip()
    if q:
        sql += ' AND (medicamento LIKE %s OR numero_lote LIKE %s OR codigo LIKE %s)'
        params += [patron_busqueda(q)] * 3
    if request.args.get('estado') in ESTADOS_VENCIMIENTO:
        sql += ' AND estado_vencimiento = %s'
        params.append(request.args['estado'])
    if request.args.get('medicamento'):
        sql += ' AND id_medicamento = %s'
        params.append(request.args['medicamento'])
    if request.args.get('con_existencia', '1') == '1':
        sql += ' AND cantidad_actual > 0'
    return jsonify(paginar(sql, params, pagina, por_pagina, 'fecha_vencimiento ASC, medicamento ASC'))


@bp.get('/inventario/vencimientos/resumen')
@permiso_requerido('inventario.ver')
def resumen_vencimientos():
    filas = consultar(
        '''SELECT estado_vencimiento AS estado, COUNT(*) AS lotes, SUM(cantidad_actual) AS unidades,
                  SUM(valor_costo) AS valor
             FROM v_lotes_vencimiento WHERE cantidad_actual > 0
            GROUP BY estado_vencimiento'''
    )
    resumen = {e: {'estado': e, 'lotes': 0, 'unidades': 0, 'valor': 0} for e in ESTADOS_VENCIMIENTO}
    for f in filas:
        resumen[f['estado']] = f
    return jsonify(list(resumen.values()))


@bp.post('/inventario/vencimientos/baja')
@permiso_requerido('inventario.editar')
def dar_baja_vencidos():
    """Ejecuta el procedimiento almacenado sp_dar_baja_lotes_vencidos."""
    with get_db().cursor() as cur:
        cur.execute('CALL sp_dar_baja_lotes_vencidos(%s)', (g.usuario['id_usuario'],))
        resultado = cur.fetchone()
        while cur.nextset():
            pass
    auditar('BAJA_VENCIDOS', 'inventario',
            f'{resultado["lotes_afectados"]} lote(s), {resultado["unidades_retiradas"]} unidad(es) retiradas')
    if not resultado['lotes_afectados']:
        return jsonify({'mensaje': 'No hay lotes vencidos con existencias', **resultado})
    return jsonify({'mensaje': f'Se dieron de baja {resultado["lotes_afectados"]} lote(s) con '
                               f'{resultado["unidades_retiradas"]} unidad(es)', **resultado})


@bp.get('/inventario/entradas')
@permiso_requerido('inventario.ver')
def entradas():
    pagina, por_pagina = parametros_paginacion()
    sql = '''SELECT e.id_entrada, e.numero_factura, e.fecha_entrada, e.total, e.observaciones,
                    p.razon_social AS proveedor, CONCAT_WS(' ', u.nombres, u.apellidos) AS usuario,
                    (SELECT COUNT(*) FROM detalle_entrada d WHERE d.id_entrada = e.id_entrada) AS productos,
                    (SELECT SUM(d.cantidad) FROM detalle_entrada d WHERE d.id_entrada = e.id_entrada) AS unidades
               FROM entradas e
               JOIN proveedores p ON p.id_proveedor = e.id_proveedor
               JOIN usuarios u ON u.id_usuario = e.id_usuario
              WHERE 1 = 1'''
    params = []
    q = request.args.get('q', '').strip()
    if q:
        sql += ' AND (e.numero_factura LIKE %s OR p.razon_social LIKE %s)'
        params += [patron_busqueda(q)] * 2
    desde, hasta = parametro_fecha('desde'), parametro_fecha('hasta')
    if desde:
        sql += ' AND e.fecha_entrada >= %s'
        params.append(desde)
    if hasta:
        sql += ' AND e.fecha_entrada < %s + INTERVAL 1 DAY'
        params.append(hasta)
    return jsonify(paginar(sql, params, pagina, por_pagina, 'e.fecha_entrada DESC'))


@bp.get('/inventario/entradas/<int:id_entrada>')
@permiso_requerido('inventario.ver')
def entrada(id_entrada):
    e = consultar_uno(
        '''SELECT e.*, p.razon_social AS proveedor, p.nit, CONCAT_WS(' ', u.nombres, u.apellidos) AS usuario
             FROM entradas e
             JOIN proveedores p ON p.id_proveedor = e.id_proveedor
             JOIN usuarios u ON u.id_usuario = e.id_usuario
            WHERE e.id_entrada = %s''',
        (id_entrada,),
    )
    if not e:
        raise ApiError('Entrada no encontrada', 404)
    e['detalle'] = consultar(
        '''SELECT d.cantidad, d.costo_unitario, d.subtotal, l.numero_lote, l.fecha_vencimiento,
                  m.codigo, m.nombre, m.concentracion
             FROM detalle_entrada d
             JOIN lotes l ON l.id_lote = d.id_lote
             JOIN medicamentos m ON m.id_medicamento = l.id_medicamento
            WHERE d.id_entrada = %s ORDER BY d.id_detalle_entrada''',
        (id_entrada,),
    )
    return jsonify(e)


@bp.post('/inventario/entradas')
@permiso_requerido('inventario.editar')
def registrar_entrada():
    v = Validador(datos_json())
    id_proveedor = v.entero('id_proveedor', minimo=1)
    numero_factura = v.texto('numero_factura', max_len=40, patron=r'[A-Za-z0-9\-/.]+',
                             mensaje_patron='Use letras, números, guion o punto')
    observaciones = v.texto('observaciones', requerido=False, max_len=255)
    items = v.lista('items')
    v.validar()
    items = servicio.validar_items_entrada(items)

    with transaccion() as cur:
        resultado = servicio.registrar_entrada(cur, id_proveedor, numero_factura.upper(), items,
                                               g.usuario['id_usuario'], observaciones)
    auditar('CREAR', 'inventario', f'Entrada #{resultado["id_entrada"]} factura {numero_factura} '
                                   f'({len(items)} producto(s))')
    return jsonify({'mensaje': 'Entrada de mercancía registrada', **resultado}), 201


@bp.post('/inventario/ajustes')
@permiso_requerido('inventario.editar')
def registrar_ajuste():
    v = Validador(datos_json())
    id_lote = v.entero('id_lote', minimo=1)
    tipo = v.opcion('tipo', servicio.TIPOS_AJUSTE)
    cantidad = v.entero('cantidad', minimo=1, maximo=100000)
    motivo = v.texto('motivo', max_len=255, min_len=5)
    v.validar()
    with transaccion() as cur:
        resultado = servicio.registrar_ajuste(cur, id_lote, tipo, cantidad, motivo, g.usuario['id_usuario'])
    auditar('AJUSTE', 'inventario', f'{tipo} de {cantidad} und. en lote {resultado["numero_lote"]}: {motivo}')
    return jsonify({'mensaje': f'Ajuste registrado. Nuevo saldo del lote: {resultado["saldo"]}', **resultado})


@bp.get('/inventario/movimientos')
@permiso_requerido('inventario.ver')
def movimientos():
    pagina, por_pagina = parametros_paginacion(por_defecto=20)
    sql = '''SELECT mv.id_movimiento, mv.fecha, mv.tipo, mv.cantidad, mv.saldo_lote, mv.motivo,
                    mv.id_venta, mv.id_entrada, l.numero_lote, m.codigo, m.nombre AS medicamento,
                    CONCAT_WS(' ', u.nombres, u.apellidos) AS usuario
               FROM movimientos_inventario mv
               JOIN lotes l ON l.id_lote = mv.id_lote
               JOIN medicamentos m ON m.id_medicamento = mv.id_medicamento
               LEFT JOIN usuarios u ON u.id_usuario = mv.id_usuario
              WHERE 1 = 1'''
    params = []
    if request.args.get('medicamento'):
        sql += ' AND mv.id_medicamento = %s'
        params.append(request.args['medicamento'])
    if request.args.get('tipo') in TIPOS_MOVIMIENTO:
        sql += ' AND mv.tipo = %s'
        params.append(request.args['tipo'])
    q = request.args.get('q', '').strip()
    if q:
        sql += ' AND (m.nombre LIKE %s OR l.numero_lote LIKE %s OR mv.motivo LIKE %s)'
        params += [patron_busqueda(q)] * 3
    desde, hasta = parametro_fecha('desde'), parametro_fecha('hasta')
    if desde:
        sql += ' AND mv.fecha >= %s'
        params.append(desde)
    if hasta:
        sql += ' AND mv.fecha < %s + INTERVAL 1 DAY'
        params.append(hasta)
    return jsonify(paginar(sql, params, pagina, por_pagina, 'mv.fecha DESC, mv.id_movimiento DESC'))
