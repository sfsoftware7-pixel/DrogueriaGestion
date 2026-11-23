"""Inicio de sesión de la tienda y datos de Mi cuenta.

Las contraseñas están en usuarios.password_hash como Argon2id (formato PHC) y se verifican con la librería
cryptography, que ya es dependencia de la tienda. Los clientes que compraron como invitados tienen la marca
HASH_INVITADO en lugar de un hash, así que nunca pueden iniciar sesión.

Protección contra adivinar contraseñas: tras 5 intentos fallidos con el mismo correo en 10 minutos, ese correo
queda bloqueado 10 minutos. El contador vive en la memoria del servidor (se reinicia al reiniciarlo), suficiente
para este prototipo de un solo proceso.
"""
import os
import threading
import time
from collections import deque
from decimal import ROUND_HALF_UP, Decimal

from cryptography.exceptions import InvalidKey
from cryptography.hazmat.primitives.kdf.argon2 import Argon2id

from ..repositorios import cuentas as repo
from . import tienda_info
from .pedidos import ESTADOS

MAX_INTENTOS = 5
VENTANA_SEGUNDOS = 10 * 60
MENSAJE_GENERICO = 'El correo o la contraseña no son correctos.'
ENTREGAS = {'DOMICILIO': 'Domicilio', 'RETIRO': 'Retiro en sede'}

# Hash de una clave aleatoria con los mismos parámetros de seed.sql: si el correo no existe (o es de un invitado)
# se verifica contra este, para que la respuesta tarde lo mismo y no revele qué correos están registrados.
_HASH_SENUELO = Argon2id(salt=os.urandom(16), length=32, iterations=3, lanes=4,
                         memory_cost=65536).derive_phc_encoded(os.urandom(32))

_fallos = {}
_candado = threading.Lock()


class ErrorSesion(Exception):
    def __init__(self, mensaje, estado=401, errores=None):
        super().__init__(mensaje)
        self.estado = estado
        self.errores = errores or {}


def _intentos_recientes(clave, ahora):
    """Deja solo los fallos de los últimos 10 minutos y devuelve cuántos quedan (con el candado tomado)."""
    intentos = _fallos.get(clave)
    if not intentos:
        return 0
    while intentos and ahora - intentos[0] > VENTANA_SEGUNDOS:
        intentos.popleft()
    if not intentos:
        del _fallos[clave]
        return 0
    return len(intentos)


def _verificar(contrasena, hash_phc):
    try:
        Argon2id.verify_phc_encoded(contrasena.encode('utf-8'), hash_phc)
        return True
    except (InvalidKey, ValueError):
        return False


def iniciar_sesion(email, contrasena):
    """Devuelve {'id', 'nombre'} del usuario si el correo y la contraseña coinciden; si no, lanza ErrorSesion."""
    email = str(email or '').strip().lower()
    contrasena = str(contrasena or '')
    errores = {}
    if not email or len(email) > 120:
        errores['email'] = 'Escribe tu correo.'
    if not contrasena or len(contrasena) > 128:
        errores['contrasena'] = 'Escribe tu contraseña.'
    if errores:
        raise ErrorSesion('Escribe tu correo y tu contraseña.', 422, errores)

    with _candado:
        if _intentos_recientes(email, time.monotonic()) >= MAX_INTENTOS:
            raise ErrorSesion('Hubo demasiados intentos fallidos con este correo. Espera 10 minutos e intenta de nuevo.', 429)

    usuario = repo.usuario_para_sesion(email)
    hash_guardado = usuario['password_hash'] if usuario else ''
    tiene_clave = hash_guardado.startswith('$argon2id$')
    correcta = _verificar(contrasena, hash_guardado if tiene_clave else _HASH_SENUELO)
    if not (correcta and tiene_clave and usuario['activo']):
        with _candado:
            _fallos.setdefault(email, deque()).append(time.monotonic())
        raise ErrorSesion(MENSAJE_GENERICO)

    with _candado:
        _fallos.pop(email, None)
    return {'id': usuario['id_usuario'], 'nombre': usuario['nombres'].split()[0]}


def _pesos(valor):
    return int(Decimal(valor).quantize(Decimal('1'), rounding=ROUND_HALF_UP))


def datos_cuenta(id_usuario, con_pedidos=True):
    """Datos de la cuenta (y sus pedidos, del más reciente al más antiguo), o None si ya no existe o está inactiva."""
    usuario = repo.datos_usuario(id_usuario)
    if not usuario or not usuario['activo']:
        return None
    cuenta = {
        'nombres': usuario['nombres'],
        'apellidos': usuario['apellidos'],
        'email': usuario['email'],
        'telefono': usuario['telefono'],
        'tipo_documento': usuario['tipo_documento'],
        'numero_documento': usuario['numero_documento'],
        'rol': usuario['rol'],
    }
    if con_pedidos:
        cuenta['pedidos'] = [
            {
                'codigo': p['codigo'],
                'fecha_texto': tienda_info.fecha_hora_texto(p['created_at']),
                'estado_texto': ESTADOS.get(p['estado'], p['estado']),
                'entrega': ENTREGAS.get(p['tipo_entrega'], p['tipo_entrega']),
                'total': _pesos(p['total']),
            }
            for p in repo.pedidos_de_usuario(id_usuario)
        ]
    return cuenta


def pedido_es_de(codigo, id_usuario):
    return repo.pedido_es_de(codigo, id_usuario)
