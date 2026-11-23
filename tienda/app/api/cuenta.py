"""API de la cuenta: iniciar y cerrar sesión.

La sesión de Flask es una cookie firmada con SECRET_KEY (HttpOnly, SameSite=Lax). Al iniciar sesión se
reemplaza todo su contenido y solo se conservan los pedidos que esa persona ya podía ver; al cerrarla se borra.
"""
from flask import Blueprint, current_app, jsonify, request, session, url_for

from ..servicios import cuentas as servicio

bp = Blueprint('api_cuenta', __name__)


def usuario_en_sesion():
    """{'id', 'nombre'} de quien inició sesión, o None."""
    usuario = session.get('usuario')
    return usuario if isinstance(usuario, dict) and isinstance(usuario.get('id'), int) else None


@bp.before_request
def _solo_desde_la_tienda():
    """Los POST deben llevar la cabecera que pone api.js (la misma protección de la API de pedidos)."""
    if request.method == 'POST' and request.headers.get('X-Requested-With') != 'tienda':
        return jsonify({'error': 'Solicitud no permitida'}), 403


@bp.errorhandler(servicio.ErrorSesion)
def _error_sesion(error):
    return jsonify({'error': str(error), 'errores': error.errores}), error.estado


@bp.post('/sesion')
def iniciar():
    datos = request.get_json(silent=True) or {}
    usuario = servicio.iniciar_sesion(datos.get('email'), datos.get('contrasena'))
    pedidos = session.get('pedidos', [])
    session.clear()
    if pedidos:
        session['pedidos'] = pedidos
    session['usuario'] = usuario
    current_app.logger.info('Inicio de sesión del usuario %s', usuario['id'])
    return jsonify({'nombre': usuario['nombre'], 'url': url_for('pagina_cuenta')})


@bp.post('/sesion/salir')
def cerrar():
    session.clear()
    return jsonify({'url': url_for('inicio')})
