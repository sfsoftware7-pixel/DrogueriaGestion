"""API REST del catálogo (solo lectura): categorías, destacados/promociones, búsqueda, productos del carrito
y disponibilidad por sede."""
from flask import Blueprint, jsonify, request

from ..servicios import catalogo as servicio

bp = Blueprint('api_catalogo', __name__)

TIPOS_LISTADO = ('destacados', 'promocion')


class ErrorValidacion(Exception):
    def __init__(self, errores):
        super().__init__('Parámetros no válidos')
        self.errores = errores


def _entero(nombre, defecto, minimo, maximo):
    valor = request.args.get(nombre, '').strip()
    if not valor:
        return defecto
    if not valor.isdigit() or not minimo <= int(valor) <= maximo:
        raise ErrorValidacion({nombre: f'Debe ser un número entero entre {minimo} y {maximo}'})
    return int(valor)


def _respuesta(datos, segundos_cache=60):
    respuesta = jsonify(datos)
    respuesta.headers['Cache-Control'] = f'public, max-age={segundos_cache}'
    return respuesta


@bp.errorhandler(ErrorValidacion)
def _error_validacion(error):
    return jsonify({'error': 'Revise los parámetros de la consulta', 'errores': error.errores}), 422


@bp.get('/categorias')
def categorias():
    return _respuesta(servicio.listar_categorias())


@bp.get('/productos/destacados')
def destacados():
    tipo = request.args.get('tipo', 'destacados')
    if tipo not in TIPOS_LISTADO:
        raise ErrorValidacion({'tipo': f'Valores permitidos: {", ".join(TIPOS_LISTADO)}'})
    limite = _entero('limite', 12, 1, 24)
    return _respuesta(servicio.listar_destacados(tipo, limite))


@bp.get('/productos/buscar')
def buscar():
    texto = ' '.join(request.args.get('q', '').split())
    if not 2 <= len(texto) <= 60:
        raise ErrorValidacion({'q': 'Escriba entre 2 y 60 caracteres'})
    limite = _entero('limite', 8, 1, 10)
    return _respuesta(servicio.buscar(texto, limite))


@bp.get('/productos/disponibilidad')
def disponibilidad():
    """Para el chatbot: existencias al momento (sin caché), por sede."""
    texto = ' '.join(request.args.get('q', '').split())
    if not 2 <= len(texto) <= 60:
        raise ErrorValidacion({'q': 'Escriba entre 2 y 60 caracteres'})
    respuesta = jsonify(servicio.disponibilidad(texto))
    respuesta.headers['Cache-Control'] = 'no-store'
    return respuesta


@bp.get('/productos')
def productos():
    """Productos del carrito: ?ids=3,8,15 (hasta 50) con su precio vigente y existencias, sin caché."""
    partes = [p for p in request.args.get('ids', '').split(',') if p.strip()]
    if not partes or len(partes) > 50 or not all(p.strip().isdigit() for p in partes):
        raise ErrorValidacion({'ids': 'Envíe de 1 a 50 identificadores numéricos separados por comas'})
    respuesta = jsonify(servicio.productos_por_ids(sorted({int(p) for p in partes})))
    respuesta.headers['Cache-Control'] = 'no-store'
    return respuesta
