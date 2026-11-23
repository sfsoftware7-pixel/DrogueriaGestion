"""API de pedidos: compra como invitado (contra entrega), detalle del pedido confirmado y consulta para seguimiento.

Acceso al detalle: el código del pedido queda en la sesión (cookie firmada con SECRET_KEY) de quien lo creó o
de quien lo consultó con el número de documento del comprador. Sin eso, el pedido no se muestra.
"""
import re

import pymysql
from flask import Blueprint, current_app, jsonify, request, session, url_for

from ..servicios import pedidos as servicio

bp = Blueprint('api_pedidos', __name__)

CODIGO = re.compile(r'^PED-\d{6,}$')
MAX_PEDIDOS_SESION = 20


def autorizar_en_sesion(codigo):
    codigos = [c for c in session.get('pedidos', []) if c != codigo]
    session['pedidos'] = (codigos + [codigo])[-MAX_PEDIDOS_SESION:]


def puede_ver(codigo):
    return codigo in session.get('pedidos', [])


@bp.before_request
def _solo_desde_la_tienda():
    """Los POST deben llevar la cabecera que pone api.js: un formulario de otro sitio no puede enviarla sin
    una verificación previa (CORS) que este servidor no autoriza."""
    if request.method == 'POST' and request.headers.get('X-Requested-With') != 'tienda':
        return jsonify({'error': 'Solicitud no permitida'}), 403


@bp.errorhandler(servicio.ErrorPedido)
def _error_pedido(error):
    return jsonify({'error': str(error), 'errores': error.errores}), error.estado


@bp.post('/pedidos')
def crear():
    pedido = servicio.validar(request.form, request.files.get('formula'))
    try:
        codigo = servicio.crear(pedido)
    except pymysql.err.OperationalError as error:
        if error.args and error.args[0] in (1205, 1213):  # espera de bloqueo o interbloqueo con otra compra
            return jsonify({'error': 'Otra compra estaba usando estas unidades. Intenta de nuevo.'}), 409
        raise
    autorizar_en_sesion(codigo)
    current_app.logger.info('Pedido %s creado', codigo)
    return jsonify({'codigo': codigo, 'url': url_for('pagina_pedido', codigo=codigo)}), 201


@bp.get('/pedidos/<codigo>')
def detalle(codigo):
    pedido = servicio.detalle(codigo) if CODIGO.match(codigo) and puede_ver(codigo) else None
    if not pedido:
        return jsonify({'error': 'Pedido no encontrado'}), 404
    respuesta = jsonify(pedido)
    respuesta.headers['Cache-Control'] = 'no-store, private'
    return respuesta


@bp.post('/pedidos/consulta')
def consulta():
    datos = request.get_json(silent=True) or {}
    codigo = str(datos.get('codigo', '')).strip().upper()
    if not CODIGO.match(codigo) or not servicio.documento_coincide(codigo, datos.get('tipo_documento'), datos.get('numero_documento')):
        # Mismo mensaje si el pedido no existe o el documento no coincide: no se revela cuál de los dos falló
        return jsonify({'error': 'No encontramos un pedido con ese código y ese documento.'}), 404
    autorizar_en_sesion(codigo)
    return jsonify({'codigo': codigo, 'url': url_for('pagina_pedido', codigo=codigo)})
