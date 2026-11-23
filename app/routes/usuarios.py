"""API de administración de usuarios y roles (solo administrador)."""
from flask import Blueprint, g, jsonify, request
from werkzeug.security import generate_password_hash

from ..db import consultar, consultar_uno, ejecutar
from ..seguridad import permiso_requerido
from ..utils import ApiError, Validador, auditar, datos_json, patron_busqueda
from .auth import MENSAJE_PASSWORD, PATRON_PASSWORD

bp = Blueprint('usuarios', __name__)


def _validar(datos, nuevo):
    v = Validador(datos)
    u = {
        'id_rol': v.entero('id_rol', minimo=1),
        'documento': v.texto('documento', max_len=20, min_len=5, patron=r'[0-9]+', mensaje_patron='Solo números'),
        'nombres': v.texto('nombres', max_len=80, min_len=2),
        'apellidos': v.texto('apellidos', max_len=80, min_len=2),
        'email': v.email('email', requerido=True),
        'usuario': v.texto('usuario', max_len=40, min_len=4, patron=r'[a-zA-Z0-9_.]+',
                           mensaje_patron='Solo letras, números, punto y guion bajo'),
    }
    password = v.texto('password', requerido=nuevo, max_len=64, patron=PATRON_PASSWORD,
                       mensaje_patron=MENSAJE_PASSWORD)
    if u['id_rol'] and not consultar_uno('SELECT 1 FROM roles WHERE id_rol = %s', (u['id_rol'],)):
        v.error('id_rol', 'Rol no válido')
    v.validar()
    u['usuario'] = u['usuario'].lower()
    return u, password


@bp.get('/usuarios')
@permiso_requerido('usuarios.administrar')
def listar():
    sql = '''SELECT u.id_usuario, u.documento, u.nombres, u.apellidos, u.email, u.usuario, u.activo,
                    u.ultimo_acceso, u.creado_en, u.bloqueado_hasta > NOW() AS bloqueado,
                    r.id_rol, r.nombre AS rol
               FROM usuarios u JOIN roles r ON r.id_rol = u.id_rol WHERE 1 = 1'''
    params = []
    q = request.args.get('q', '').strip()
    if q:
        sql += " AND (CONCAT_WS(' ', u.nombres, u.apellidos) LIKE %s OR u.usuario LIKE %s OR u.documento LIKE %s)"
        params += [patron_busqueda(q)] * 3
    return jsonify(consultar(sql + ' ORDER BY u.activo DESC, u.nombres', params))


@bp.get('/roles')
@permiso_requerido('usuarios.administrar')
def roles():
    return jsonify(consultar(
        '''SELECT r.id_rol, r.nombre, r.descripcion, COUNT(u.id_usuario) AS usuarios
             FROM roles r LEFT JOIN usuarios u ON u.id_rol = r.id_rol AND u.activo = 1
            GROUP BY r.id_rol ORDER BY r.id_rol'''))


@bp.post('/usuarios')
@permiso_requerido('usuarios.administrar')
def crear():
    u, password = _validar(datos_json(), nuevo=True)
    id_nuevo, _ = ejecutar(
        '''INSERT INTO usuarios (id_rol, documento, nombres, apellidos, email, usuario, password_hash)
           VALUES (%s, %s, %s, %s, %s, %s, %s)''',
        (u['id_rol'], u['documento'], u['nombres'], u['apellidos'], u['email'], u['usuario'],
         generate_password_hash(password)),
    )
    auditar('CREAR', 'usuarios', f'Usuario {u["usuario"]}')
    return jsonify({'mensaje': 'Usuario creado', 'id_usuario': id_nuevo}), 201


@bp.put('/usuarios/<int:id_usuario>')
@permiso_requerido('usuarios.administrar')
def actualizar(id_usuario):
    actual = consultar_uno('SELECT id_rol FROM usuarios WHERE id_usuario = %s', (id_usuario,))
    if not actual:
        raise ApiError('Usuario no encontrado', 404)
    u, password = _validar(datos_json(), nuevo=False)
    if id_usuario == g.usuario['id_usuario'] and u['id_rol'] != actual['id_rol']:
        raise ApiError('No puede cambiar su propio rol', 409, {'id_rol': 'No puede cambiar su propio rol'})

    campos = dict(u)
    if password:
        campos['password_hash'] = generate_password_hash(password)
        # Restablecer la contraseña también levanta el bloqueo por intentos fallidos
        campos['intentos_fallidos'] = 0
        campos['bloqueado_hasta'] = None
    ejecutar(f'UPDATE usuarios SET {", ".join(f"{c} = %s" for c in campos)} WHERE id_usuario = %s',
             (*campos.values(), id_usuario))
    auditar('ACTUALIZAR', 'usuarios', f'Usuario {u["usuario"]}' + (' (restableció contraseña)' if password else ''))
    return jsonify({'mensaje': 'Usuario actualizado'})


@bp.patch('/usuarios/<int:id_usuario>/estado')
@permiso_requerido('usuarios.administrar')
def cambiar_estado(id_usuario):
    activo = Validador(datos_json()).booleano('activo')
    if id_usuario == g.usuario['id_usuario'] and not activo:
        raise ApiError('No puede desactivar su propio usuario', 409)
    usuario = _obtener_o_404(id_usuario)
    ejecutar('UPDATE usuarios SET activo = %s WHERE id_usuario = %s', (activo, id_usuario))
    auditar('ACTIVAR' if activo else 'DESACTIVAR', 'usuarios', f'Usuario {usuario["usuario"]}')
    return jsonify({'mensaje': 'Usuario activado' if activo else 'Usuario desactivado'})


@bp.post('/usuarios/<int:id_usuario>/desbloquear')
@permiso_requerido('usuarios.administrar')
def desbloquear(id_usuario):
    usuario = _obtener_o_404(id_usuario)
    ejecutar('UPDATE usuarios SET intentos_fallidos = 0, bloqueado_hasta = NULL WHERE id_usuario = %s', (id_usuario,))
    auditar('DESBLOQUEAR', 'usuarios', f'Usuario {usuario["usuario"]}')
    return jsonify({'mensaje': 'Usuario desbloqueado'})


def _obtener_o_404(id_usuario):
    usuario = consultar_uno('SELECT usuario FROM usuarios WHERE id_usuario = %s', (id_usuario,))
    if not usuario:
        raise ApiError('Usuario no encontrado', 404)
    return usuario
