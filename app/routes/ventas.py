"""API de ventas y dispensación."""
from decimal import Decimal, InvalidOperation

from flask import Blueprint, g, jsonify, request

from ..db import consultar, consultar_uno, paginar, transaccion
from ..seguridad import permiso_requerido, tiene_permiso
from ..services import ventas as servicio
from ..utils import (ApiError, Validador, auditar, datos_json, parametro_fecha, parametros_paginacion,
                     patron_busqueda)

bp = Blueprint('ventas', __name__)


def descuento_maximo_usuario():
    """Tope de descuento (%) del usuario actual, o None si su rol puede aplicar cualquier descuento."""
    if tiene_permiso('ventas.descuento_libre'):
        return None
    fila = consultar_uno("SELECT valor FROM configuracion WHERE clave = 'descuento_maximo_vendedor'")
    try:
        pct = Decimal(fila['valor']) if fila else servicio.DESCUENTO_MAXIMO_VENDEDOR_DEFECTO
    except InvalidOperation:
        pct = servicio.DESCUENTO_MAXIMO_VENDEDOR_DEFECTO
    if not pct.is_finite():
        pct = servicio.DESCUENTO_MAXIMO_VENDEDOR_DEFECTO
    return min(max(pct, Decimal('0')), Decimal('100'))


@bp.get('/ventas')
@permiso_requerido('ventas.ver')
def listar():
    pagina, por_pagina = parametros_paginacion()
    sql = 'SELECT * FROM v_ventas WHERE 1 = 1'
    params = []
    q = request.args.get('q', '').strip()
    if q:
        sql += ' AND (numero_factura LIKE %s OR cliente LIKE %s OR numero_documento LIKE %s)'
        params += [patron_busqueda(q)] * 3
    desde, hasta = parametro_fecha('desde'), parametro_fecha('hasta')
    if desde:
        sql += ' AND fecha_venta >= %s'
        params.append(desde)
    if hasta:
        sql += ' AND fecha_venta < %s + INTERVAL 1 DAY'
        params.append(hasta)
    if request.args.get('estado') in ('COMPLETADA', 'ANULADA'):
        sql += ' AND estado = %s'
        params.append(request.args['estado'])
    if request.args.get('metodo_pago') in servicio.METODOS_PAGO:
        sql += ' AND metodo_pago = %s'
        params.append(request.args['metodo_pago'])
    resultado = paginar(sql, params, pagina, por_pagina, 'fecha_venta DESC')
    resultado['resumen'] = consultar_uno(
        f'''SELECT COUNT(*) AS ventas, COALESCE(SUM(total), 0) AS total
              FROM ({sql}) t WHERE estado = 'COMPLETADA' ''', params)
    return jsonify(resultado)


@bp.get('/ventas/<int:id_venta>')
@permiso_requerido('ventas.ver')
def obtener(id_venta):
    venta = consultar_uno('SELECT * FROM v_ventas WHERE id_venta = %s', (id_venta,))
    if not venta:
        raise ApiError('Venta no encontrada', 404)
    venta['detalle'] = consultar(
        '''SELECT d.id_detalle_venta, d.cantidad, d.precio_unitario, d.iva_porcentaje, d.subtotal, d.impuesto,
                  m.codigo, m.nombre, m.concentracion, m.forma_farmaceutica,
                  l.numero_lote, l.fecha_vencimiento
             FROM detalle_venta d
             JOIN medicamentos m ON m.id_medicamento = d.id_medicamento
             JOIN lotes l ON l.id_lote = d.id_lote
            WHERE d.id_venta = %s ORDER BY d.id_detalle_venta''',
        (id_venta,),
    )
    return jsonify(venta)


@bp.post('/ventas')
@permiso_requerido('ventas.crear')
def crear():
    datos = datos_json()
    v = Validador(datos)
    venta = {
        'id_cliente': v.entero('id_cliente', minimo=1),
        'metodo_pago': v.opcion('metodo_pago', servicio.METODOS_PAGO),
        'descuento': v.decimal('descuento', requerido=False, minimo=0) or 0,
        'monto_recibido': v.decimal('monto_recibido', requerido=False, minimo=0),
        'formula_medica': v.texto('formula_medica', requerido=False, max_len=60),
        'medico': v.texto('medico', requerido=False, max_len=120),
        'observaciones': v.texto('observaciones', requerido=False, max_len=255),
        'items': v.lista('items'),
    }
    if len(venta['items']) > 100:
        v.error('items', 'Máximo 100 productos por venta')
    v.validar()

    tope = descuento_maximo_usuario()
    with transaccion() as cur:
        resultado = servicio.registrar_venta(cur, venta, g.usuario['id_usuario'], descuento_maximo_pct=tope)
    detalle_descuento = f' con descuento de ${venta["descuento"]:,.0f}' if venta['descuento'] else ''
    auditar('VENTA', 'ventas',
            f'Venta {resultado["numero_factura"]} por ${resultado["total"]:,.0f}{detalle_descuento}')
    return jsonify({'mensaje': f'Venta {resultado["numero_factura"]} registrada', **resultado}), 201


@bp.post('/ventas/<int:id_venta>/anular')
@permiso_requerido('ventas.anular')
def anular(id_venta):
    v = Validador(datos_json())
    motivo = v.texto('motivo', max_len=255, min_len=10)
    v.validar()
    with transaccion() as cur:
        numero = servicio.anular_venta(cur, id_venta, motivo, g.usuario['id_usuario'])
    auditar('ANULAR', 'ventas', f'Venta {numero}: {motivo}')
    return jsonify({'mensaje': f'La venta {numero} fue anulada y el inventario restituido'})
