"""Autenticación, autorización por roles, protección CSRF y control de sesiones."""
import hmac
import secrets
import time
from functools import wraps

from flask import abort, current_app, g, redirect, request, session, url_for

from .db import consultar_uno
from .utils import ApiError

ADMIN, REGENTE, VENDEDOR, BODEGA = 'ADMINISTRADOR', 'REGENTE', 'VENDEDOR', 'BODEGA'
TODOS = {ADMIN, REGENTE, VENDEDOR, BODEGA}

# Matriz de permisos: qué roles pueden realizar cada acción
PERMISOS = {
    'dashboard.ver': TODOS,
    'medicamentos.ver': TODOS,
    'medicamentos.editar': {ADMIN, REGENTE},
    'categorias.editar': {ADMIN, REGENTE},
    'inventario.ver': {ADMIN, REGENTE, BODEGA},
    'inventario.editar': {ADMIN, REGENTE, BODEGA},
    'proveedores.ver': {ADMIN, REGENTE, BODEGA},
    'proveedores.editar': {ADMIN, REGENTE, BODEGA},
    'clientes.ver': {ADMIN, REGENTE, VENDEDOR},
    'clientes.editar': {ADMIN, REGENTE, VENDEDOR},
    'ventas.ver': {ADMIN, REGENTE, VENDEDOR},
    'ventas.crear': {ADMIN, REGENTE, VENDEDOR},
    'ventas.anular': {ADMIN, REGENTE},
    'pedidos.gestionar': {ADMIN, REGENTE},
    'ventas.descuento_libre': {ADMIN, REGENTE},  # los demás roles tienen el tope 'descuento_maximo_vendedor'
    'reportes.ver': {ADMIN, REGENTE},
    'analisis_abc.ver': {ADMIN, REGENTE},   # análisis ABC (Pareto) de productos vendidos
    'consultas.ver': {ADMIN, REGENTE},      # «Ver SQL»: consulta y EXPLAIN de los reportes y el panel
    'modelo.ver': {ADMIN},                  # modelo de datos en vivo (information_schema)
    'usuarios.administrar': {ADMIN},
    'auditoria.ver': {ADMIN},
    'configuracion.editar': {ADMIN},
}

METODOS_SEGUROS = {'GET', 'HEAD', 'OPTIONS'}


def tiene_permiso(permiso, usuario=None):
    usuario = usuario or g.get('usuario')
    return bool(usuario) and usuario['rol'] in PERMISOS.get(permiso, set())


def permisos_de(rol):
    return sorted(p for p, roles in PERMISOS.items() if rol in roles)


def es_api():
    return request.path.startswith('/api/')


def login_requerido(vista):
    @wraps(vista)
    def envoltura(*args, **kwargs):
        if not g.get('usuario'):
            if es_api():
                raise ApiError('Su sesión ha expirado. Inicie sesión nuevamente.', 401)
            return redirect(url_for('paginas.login', siguiente=request.path))
        return vista(*args, **kwargs)
    return envoltura


def permiso_requerido(permiso):
    def decorador(vista):
        @wraps(vista)
        @login_requerido
        def envoltura(*args, **kwargs):
            if not tiene_permiso(permiso):
                if es_api():
                    raise ApiError('No tiene permisos para realizar esta acción', 403)
                abort(403)
            return vista(*args, **kwargs)
        return envoltura
    return decorador


def token_csrf():
    if '_csrf' not in session:
        session['_csrf'] = secrets.token_urlsafe(32)
    return session['_csrf']


def iniciar_sesion(usuario):
    """Regenera la sesión para evitar fijación de sesión y guarda el usuario."""
    session.clear()
    session.permanent = True
    session['id_usuario'] = usuario['id_usuario']
    session['ultimo_uso'] = int(time.time())
    token_csrf()


def cargar_usuario():
    """Antes de cada petición: valida inactividad y recarga el usuario desde la BD."""
    g.usuario = None
    id_usuario = session.get('id_usuario')
    if not id_usuario or request.endpoint == 'static':
        return
    ahora = int(time.time())
    limite = current_app.config['MINUTOS_INACTIVIDAD'] * 60
    if ahora - session.get('ultimo_uso', 0) > limite:
        session.clear()
        return
    usuario = consultar_uno(
        '''SELECT u.id_usuario, u.usuario, u.nombres, u.apellidos, u.email, u.activo, r.nombre AS rol
             FROM usuarios u JOIN roles r ON r.id_rol = u.id_rol
            WHERE u.id_usuario = %s''',
        (id_usuario,),
    )
    if not usuario or not usuario['activo']:
        session.clear()
        return
    session['ultimo_uso'] = ahora
    g.usuario = usuario
    # La conexión ya existe: se asigna la variable usada por los triggers.
    from .db import asignar_usuario_sesion, get_db
    asignar_usuario_sesion(get_db(), usuario['id_usuario'])


def verificar_csrf():
    if request.method in METODOS_SEGUROS or not es_api():
        return
    enviado = request.headers.get('X-CSRF-Token', '')
    esperado = session.get('_csrf', '')
    if not esperado and request.endpoint != 'auth.login':
        # La sesión venció (inactividad o cookie expirada) y con ella el token: se responde 401
        # para que el frontend redirija al inicio de sesión en lugar de mostrar un error de CSRF.
        raise ApiError('Su sesión ha expirado. Inicie sesión nuevamente.', 401)
    if not esperado or not hmac.compare_digest(enviado, esperado):
        raise ApiError('Token de seguridad inválido. Recargue la página.', 403)


def cabeceras_seguridad(respuesta):
    respuesta.headers.setdefault('X-Content-Type-Options', 'nosniff')
    respuesta.headers.setdefault('X-Frame-Options', 'DENY')
    respuesta.headers.setdefault('Referrer-Policy', 'same-origin')
    respuesta.headers.setdefault(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; font-src 'self'; frame-ancestors 'none'; form-action 'self'",
    )
    if es_api():
        respuesta.headers.setdefault('Cache-Control', 'no-store')
    return respuesta


def init_app(app):
    app.before_request(cargar_usuario)
    app.before_request(verificar_csrf)
    app.after_request(cabeceras_seguridad)

    @app.context_processor
    def contexto_plantillas():
        usuario = g.get('usuario')
        return {
            'usuario_actual': usuario,
            'puede': tiene_permiso,
            'permisos_usuario': permisos_de(usuario['rol']) if usuario else [],
            'csrf_token': token_csrf,
        }
