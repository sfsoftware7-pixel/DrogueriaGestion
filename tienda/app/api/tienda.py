"""API de los datos de la droguería (datos_tienda.toml): horario, domicilios, pago, contacto y sedes."""
from flask import Blueprint, jsonify, request

from ..servicios import catalogo as servicio_catalogo
from ..servicios import tienda_info
from .catalogo import ErrorValidacion

bp = Blueprint('api_tienda', __name__)


@bp.errorhandler(ErrorValidacion)
def _error_validacion(error):
    return jsonify({'error': 'Revise los parámetros de la consulta', 'errores': error.errores}), 422


def _sin_cache(datos):
    respuesta = jsonify(datos)
    respuesta.headers['Cache-Control'] = 'no-store'  # "abierto ahora" cambia con la hora
    return respuesta


@bp.get('/tienda')
def info():
    return _sin_cache(tienda_info.info_publica(servicio_catalogo.sedes()))


@bp.get('/domicilios/cobertura')
def cobertura():
    barrio = ' '.join(request.args.get('barrio', '').split())
    if not 2 <= len(barrio) <= 80:
        raise ErrorValidacion({'barrio': 'Escriba entre 2 y 80 caracteres'})
    ciudad = request.args.get('ciudad') or None
    return _sin_cache(tienda_info.buscar_cobertura(barrio, ciudad))
