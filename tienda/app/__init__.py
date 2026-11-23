"""Fábrica de la aplicación Flask de la tienda en línea."""
import logging
import re
import time

import pymysql
from flask import Flask, abort, g, jsonify, redirect, render_template, request, url_for

from . import db
from .api.catalogo import bp as api_catalogo
from .api.pedidos import CODIGO, puede_ver
from .api.pedidos import bp as api_pedidos
from .api.tienda import bp as api_tienda
from .config import Config, variables_faltantes
from .servicios import catalogo as servicio_catalogo
from .servicios import pedidos as servicio_pedidos
from .servicios import tienda_info

# Política de seguridad de contenido: sin scripts ni estilos en línea; fuentes solo de Google Fonts
CSP = ("default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; "
       "font-src https://fonts.gstatic.com; img-src 'self' data:; connect-src 'self'; "
       "base-uri 'self'; form-action 'self'; frame-ancestors 'none'")


class SinConsultaEnLog(logging.Filter):
    """Quita la consulta (?q=...) de las líneas de acceso del servidor: lo que se busca puede ser un dato de salud."""

    def filter(self, registro):
        if isinstance(registro.args, tuple) and registro.args and isinstance(registro.args[0], str):
            registro.args = (re.sub(r'\?\S*', '', registro.args[0]),) + registro.args[1:]
        return True


def create_app(config=Config):
    app = Flask(__name__)
    app.config.from_object(config)
    app.json.ensure_ascii = False
    app.json.sort_keys = False
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    logging.getLogger('werkzeug').addFilter(SinConsultaEnLog())

    faltantes = variables_faltantes(app.config)
    if faltantes:
        app.logger.warning('Configuración incompleta: complete %s en tienda/.env (vea tienda/.env.example)',
                           ', '.join(faltantes))

    db.init_app(app)

    @app.context_processor
    def _marca():
        return {'marca': tienda_info.datos()['drogueria']['nombre']}

    @app.template_filter('pesos')
    def _pesos(valor):
        """22700 -> "$ 22.700" (el mismo formato es-CO que usa el JavaScript de la tienda)."""
        return '$ ' + f'{int(valor):,}'.replace(',', '.')

    app.register_blueprint(api_catalogo, url_prefix='/api')
    app.register_blueprint(api_tienda, url_prefix='/api')
    app.register_blueprint(api_pedidos, url_prefix='/api')

    @app.get('/')
    def inicio():
        try:
            banners = servicio_catalogo.banners_vigentes()
        except pymysql.MySQLError as error:
            # La página se muestra igual; las secciones dinámicas indicarán el error de la API
            app.logger.warning('No fue posible leer los banners de MySQL (código %s)', error.args[0] if error.args else '?')
            banners = []
        return render_template('index.html', banners=banners)

    @app.get('/carrito')
    def pagina_carrito():
        return render_template('carrito.html')

    @app.get('/pedido/<codigo>')
    def pagina_pedido(codigo):
        """Confirmación y seguimiento del pedido: solo para quien lo creó o lo consultó con su documento."""
        if not CODIGO.match(codigo):
            abort(404)
        if not puede_ver(codigo):
            return redirect(url_for('pagina_seguimiento', codigo=codigo))
        pedido = servicio_pedidos.detalle(codigo)
        if not pedido:
            abort(404)
        respuesta = app.make_response(render_template('pedido.html', pedido=pedido))
        respuesta.headers['Cache-Control'] = 'no-store, private'
        return respuesta

    @app.get('/seguimiento')
    def pagina_seguimiento():
        codigo = request.args.get('codigo', '')
        return render_template('seguimiento.html', codigo=codigo if CODIGO.match(codigo) else '')

    registrar_eventos(app)
    return app


def registrar_eventos(app):
    @app.before_request
    def _inicio_peticion():
        g.inicio = time.perf_counter()

    @app.after_request
    def _cabeceras(respuesta):
        respuesta.headers.setdefault('Content-Security-Policy', CSP)
        respuesta.headers.setdefault('X-Content-Type-Options', 'nosniff')
        respuesta.headers.setdefault('X-Frame-Options', 'DENY')
        respuesta.headers.setdefault('Referrer-Policy', 'strict-origin-when-cross-origin')
        respuesta.headers.setdefault('Permissions-Policy', 'camera=(), microphone=(), geolocation=()')
        if request.path.startswith('/api/'):
            duracion = (time.perf_counter() - g.get('inicio', time.perf_counter())) * 1000
            # Se registra la ruta sin la consulta (?q=...): lo que la persona busca puede ser un dato de salud
            app.logger.info('%s %s %s %.1f ms', request.method, request.path, respuesta.status_code, duracion)
        return respuesta

    @app.errorhandler(pymysql.MySQLError)
    def _error_mysql(error):
        app.logger.error('Error de MySQL en %s (código %s)', request.path, error.args[0] if error.args else '?')
        return jsonify({'error': 'No fue posible consultar la base de datos. Intente de nuevo en unos segundos.'}), 503

    @app.errorhandler(404)
    def _no_encontrado(_error):
        if request.path.startswith('/api/'):
            return jsonify({'error': 'Recurso no encontrado'}), 404
        return render_template('index.html', banners=[]), 404

    @app.errorhandler(413)
    def _demasiado_grande(_error):
        return jsonify({'error': 'El archivo es demasiado grande.', 'errores': {'formula': 'La fórmula debe pesar 5 MB o menos.'}}), 413

    @app.errorhandler(500)
    def _error_interno(_error):
        return jsonify({'error': 'Ocurrió un error inesperado'}), 500
