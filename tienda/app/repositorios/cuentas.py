"""Consultas SQL de las cuentas de la tienda (inicio de sesión y Mi cuenta). Solo lectura, con parámetros %s:
el usuario de MySQL de la tienda (tienda_app) ya tiene SELECT sobre drogueria_db y no necesita más permisos."""
from ..db import consultar


def usuario_para_sesion(email):
    filas = consultar(
        'SELECT id_usuario, nombres, password_hash, activo FROM usuarios WHERE email = %s',
        (email,),
    )
    return filas[0] if filas else None


def datos_usuario(id_usuario):
    filas = consultar(
        """SELECT u.id_usuario, u.tipo_documento, u.numero_documento, u.nombres, u.apellidos, u.email, u.telefono,
                  u.activo, r.nombre AS rol
             FROM usuarios u
             JOIN roles r ON r.id_rol = u.id_rol
            WHERE u.id_usuario = %s""",
        (id_usuario,),
    )
    return filas[0] if filas else None


def pedidos_de_usuario(id_usuario, limite=50):
    return consultar(
        """SELECT codigo, created_at, estado, tipo_entrega, total
             FROM pedidos
            WHERE id_usuario = %s
            ORDER BY created_at DESC, id_pedido DESC
            LIMIT %s""",
        (id_usuario, limite),
    )


def pedido_es_de(codigo, id_usuario):
    return bool(consultar('SELECT 1 FROM pedidos WHERE codigo = %s AND id_usuario = %s', (codigo, id_usuario)))
