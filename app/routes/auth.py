"""API de autenticación: inicio/cierre de sesión y cambio de contraseña."""
from datetime import datetime, timedelta

from flask import Blueprint, current_app, g, jsonify, session
from werkzeug.security import check_password_hash, generate_password_hash

from ..db import consultar_uno, ejecutar
from ..seguridad import iniciar_sesion, login_requerido, permisos_de, token_csrf
from ..utils import ApiError, Validador, auditar, datos_json

bp = Blueprint('auth', __name__)

# Política de contraseñas: mínimo 8 caracteres con mayúscula, minúscula, número y símbolo
PATRON_PASSWORD = r'(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,64}'
MENSAJE_PASSWORD = 'Mínimo 8 caracteres con mayúscula, minúscula, número y símbolo'


@bp.post('/auth/login')
def login():
    v = Validador(datos_json())
    usuario_txt = v.texto('usuario', max_len=40)
    password = v.texto('password', max_len=128)
    v.validar()

    usuario = consultar_uno(
        '''SELECT u.id_usuario, u.password_hash, u.activo, u.intentos_fallidos, u.bloqueado_hasta, r.nombre AS rol
             FROM usuarios u JOIN roles r ON r.id_rol = u.id_rol
            WHERE u.usuario = %s''',
        (usuario_txt,),
    )
    mensaje_generico = 'Usuario o contraseña incorrectos'
    if not usuario:
        auditar('LOGIN_FALLIDO', 'auth', f'Usuario inexistente: {usuario_txt}')
        raise ApiError(mensaje_generico, 401)

    ahora = datetime.now()
    if usuario['bloqueado_hasta'] and usuario['bloqueado_hasta'] > ahora:
        minutos = int((usuario['bloqueado_hasta'] - ahora).total_seconds() // 60) + 1
        raise ApiError(f'Cuenta bloqueada temporalmente por intentos fallidos. Intente en {minutos} min.', 423)

    if not check_password_hash(usuario['password_hash'], password):
        intentos = usuario['intentos_fallidos'] + 1
        maximo = current_app.config['MAX_INTENTOS_LOGIN']
        bloqueo = None
        if intentos >= maximo:
            bloqueo = ahora + timedelta(minutes=current_app.config['MINUTOS_BLOQUEO'])
            intentos = 0
        ejecutar('UPDATE usuarios SET intentos_fallidos = %s, bloqueado_hasta = %s WHERE id_usuario = %s',
                 (intentos, bloqueo, usuario['id_usuario']))
        auditar('LOGIN_FALLIDO', 'auth', 'Contraseña incorrecta', id_usuario=usuario['id_usuario'])
        if bloqueo:
            raise ApiError('Demasiados intentos fallidos. La cuenta se bloqueó por '
                           f'{current_app.config["MINUTOS_BLOQUEO"]} minutos.', 423)
        raise ApiError(mensaje_generico, 401)

    if not usuario['activo']:
        raise ApiError('El usuario está inactivo. Contacte al administrador.', 403)

    ejecutar('''UPDATE usuarios SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_acceso = NOW()
                 WHERE id_usuario = %s''', (usuario['id_usuario'],))
    iniciar_sesion(usuario)
    auditar('LOGIN', 'auth', 'Inicio de sesión exitoso', id_usuario=usuario['id_usuario'])
    return jsonify({'mensaje': 'Bienvenido', 'csrf': token_csrf(), 'rol': usuario['rol']})


@bp.post('/auth/logout')
def logout():
    if g.get('usuario'):
        auditar('LOGOUT', 'auth', 'Cierre de sesión')
    session.clear()
    return jsonify({'mensaje': 'Sesión cerrada'})


@bp.get('/auth/yo')
@login_requerido
def yo():
    u = g.usuario
    return jsonify({**u, 'permisos': permisos_de(u['rol'])})


@bp.post('/auth/cambiar-password')
@login_requerido
def cambiar_password():
    v = Validador(datos_json())
    actual = v.texto('actual', max_len=128)
    nueva = v.texto('nueva', max_len=64, patron=PATRON_PASSWORD, mensaje_patron=MENSAJE_PASSWORD)
    confirmacion = v.texto('confirmacion', max_len=64)
    if nueva and confirmacion and nueva != confirmacion:
        v.error('confirmacion', 'Las contraseñas no coinciden')
    if nueva and actual and nueva == actual:
        v.error('nueva', 'Debe ser diferente a la contraseña actual')
    v.validar()

    fila = consultar_uno('SELECT password_hash FROM usuarios WHERE id_usuario = %s', (g.usuario['id_usuario'],))
    if not check_password_hash(fila['password_hash'], actual):
        raise ApiError('La contraseña actual no es correcta', 422, {'actual': 'Contraseña incorrecta'})

    ejecutar('UPDATE usuarios SET password_hash = %s WHERE id_usuario = %s',
             (generate_password_hash(nueva), g.usuario['id_usuario']))
    auditar('CAMBIO_PASSWORD', 'auth', 'El usuario cambió su contraseña')
    return jsonify({'mensaje': 'Contraseña actualizada correctamente'})
