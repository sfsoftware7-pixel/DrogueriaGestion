"""Fábrica de la aplicación Flask DrogueriaGestión."""
import logging

import pymysql
from flask import Flask, jsonify, render_template, request
from flask.json.provider import DefaultJSONProvider

from config import Config

from . import db, seguridad
from .utils import ApiError, a_json

log = logging.getLogger(__name__)

# Códigos de error de MySQL traducidos a mensajes comprensibles
ERRORES_MYSQL = {
    1062: (409, 'Ya existe un registro con esos datos (valor duplicado).'),
    1451: (409, 'No se puede eliminar porque tiene registros relacionados.'),
    1452: (400, 'Uno de los registros relacionados no existe.'),
    3819: (400, 'Los datos no cumplen las reglas de validación de la base de datos.'),
    # Dos operaciones simultáneas compitieron por los mismos registros; MySQL canceló una de ellas
    1213: (409, 'Otra operación estaba usando los mismos productos. Intente nuevamente.'),
    1205: (409, 'Otra operación estaba usando los mismos productos. Intente nuevamente.'),
}


class ProveedorJSON(DefaultJSONProvider):
    """Serializa Decimal como número y fechas en formato ISO 8601."""
    ensure_ascii = False
    sort_keys = False

    @staticmethod
    def default(o):
        convertido = a_json(o)
        if convertido is not o:
            return convertido
        return DefaultJSONProvider.default(o)


def create_app(config_object=Config):
    app = Flask(__name__)
    app.config.from_object(config_object)
    app.json = ProveedorJSON(app)

    db.init_app(app)
    seguridad.init_app(app)
    registrar_blueprints(app)
    registrar_manejadores_error(app)
    return app


def registrar_blueprints(app):
    from .routes import (analisis_abc, auditoria, auth, categorias, clientes, configuracion, consultas, dashboard,
                         inventario, medicamentos, modelo, paginas, proveedores, reportes, usuarios, ventas)

    app.register_blueprint(paginas.bp)
    for modulo in (auth, dashboard, medicamentos, categorias, proveedores, clientes, inventario,
                   ventas, reportes, usuarios, auditoria, configuracion, analisis_abc, consultas, modelo):
        app.register_blueprint(modulo.bp, url_prefix='/api')


def registrar_manejadores_error(app):
    def respuesta_error(mensaje, status, errores=None):
        cuerpo = {'error': mensaje}
        if errores:
            cuerpo['errores'] = errores
        return jsonify(cuerpo), status

    @app.errorhandler(ApiError)
    def api_error(e):
        return respuesta_error(e.mensaje, e.status, e.errores)

    @app.errorhandler(pymysql.err.MySQLError)
    def mysql_error(e):
        codigo = e.args[0] if e.args else None
        if codigo == 1644:  # SIGNAL lanzado por un trigger o procedimiento
            return respuesta_error(e.args[1], 400)
        if codigo in ERRORES_MYSQL:
            status, mensaje = ERRORES_MYSQL[codigo]
            return respuesta_error(mensaje, status)
        log.exception('Error de base de datos')
        if codigo in (2003, 1045, 1049):
            return respuesta_error('No fue posible conectarse a la base de datos.', 503)
        return respuesta_error('Ocurrió un error en la base de datos.', 500)

    def pagina_o_json(status, titulo, mensaje):
        if request.path.startswith('/api/'):
            return respuesta_error(mensaje, status)
        return render_template('error.html', codigo=status, titulo=titulo, mensaje=mensaje), status

    @app.errorhandler(403)
    def prohibido(_e):
        return pagina_o_json(403, 'Acceso restringido', 'Su rol no tiene permisos para ver esta sección.')

    @app.errorhandler(404)
    def no_encontrado(_e):
        return pagina_o_json(404, 'Página no encontrada', 'El recurso solicitado no existe.')

    @app.errorhandler(405)
    def metodo_no_permitido(_e):
        return pagina_o_json(405, 'Método no permitido', 'La operación solicitada no está permitida.')

    @app.errorhandler(500)
    def error_interno(_e):
        return pagina_o_json(500, 'Error interno', 'Ocurrió un error inesperado. Intente nuevamente.')
