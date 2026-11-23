"""Consultas SQL de los pedidos de la tienda en línea. Todas con parámetros %s.

Las funciones que escriben reciben el cursor de una transacción abierta (db.transaccion) para que el pedido,
sus productos, los lotes despachados, el kárdex y el historial se guarden todos o ninguno.
"""
from ..db import consultar
from .catalogo import _MEJOR_PROMOCION

# Marca de contraseña de un cliente que compró como invitado: no es un hash Argon2 válido, así que esa
# cuenta nunca puede iniciar sesión (servicios/cuentas.py la rechaza).
HASH_INVITADO = '!invitado-sin-acceso'


def _marcadores(valores):
    return ', '.join(['%s'] * len(valores))


# ---------------------------------------------------------------- lectura previa (sin bloqueo)
def precios_vigentes(cur, ids):
    """Precio de lista y descuento por unidad de la mejor promoción vigente (la misma regla del catálogo)."""
    cur.execute(
        f"""SELECT p.id_producto, p.nombre, p.presentacion, p.precio, p.requiere_formula, p.activo,
                   COALESCE(mp.descuento, 0) AS descuento
              FROM productos p
              LEFT JOIN ({_MEJOR_PROMOCION}) mp ON mp.id_producto = p.id_producto
             WHERE p.id_producto IN ({_marcadores(ids)})""",
        tuple(ids),
    )
    return cur.fetchall()


def sede_para_pedido(cur, id_sede):
    cur.execute(
        """SELECT s.id_sede, s.nombre, s.direccion, s.permite_retiro, s.activo, c.nombre AS ciudad
             FROM sedes s JOIN ciudades c ON c.id_ciudad = s.id_ciudad
            WHERE s.id_sede = %s""",
        (id_sede,),
    )
    return cur.fetchone()


def ciudad_por_dane(cur, codigo_dane):
    cur.execute('SELECT id_ciudad, nombre, tiene_cobertura FROM ciudades WHERE codigo_dane = %s', (codigo_dane,))
    return cur.fetchone()


def id_rol_cliente(cur):
    cur.execute("SELECT id_rol FROM roles WHERE codigo = 'CLIENTE'")
    fila = cur.fetchone()
    return fila['id_rol'] if fila else None


def usuarios_con_datos(cur, email, tipo_documento, numero_documento):
    cur.execute(
        """SELECT id_usuario, email, tipo_documento, numero_documento, password_hash
             FROM usuarios
            WHERE email = %s OR (tipo_documento = %s AND numero_documento = %s)""",
        (email, tipo_documento, numero_documento),
    )
    return cur.fetchall()


# ---------------------------------------------------------------- existencias (con bloqueo)
def bloquear_existencias(cur, id_sede, ids):
    """Lotes sin vencer de la sede con unidades, en orden FEFO (primero el que vence antes).

    FOR UPDATE OF i bloquea solo las filas de inventario hasta el final de la transacción: dos compras
    simultáneas del mismo producto no pueden vender la misma unidad. El orden fijo (producto, vencimiento,
    lote) evita bloqueos cruzados entre pedidos.
    """
    cur.execute(
        f"""SELECT i.id_inventario, i.id_lote, i.cantidad, lo.id_producto
              FROM inventario i
              JOIN lotes lo ON lo.id_lote = i.id_lote
             WHERE i.id_sede = %s AND lo.id_producto IN ({_marcadores(ids)})
               AND lo.fecha_vencimiento >= CURDATE() AND i.cantidad > 0
             ORDER BY lo.id_producto, lo.fecha_vencimiento, lo.id_lote
             FOR UPDATE OF i""",
        (id_sede, *ids),
    )
    return cur.fetchall()


# ---------------------------------------------------------------- escrituras
def insertar_usuario_invitado(cur, id_rol, cliente):
    cur.execute(
        """INSERT INTO usuarios (id_rol, tipo_documento, numero_documento, nombres, apellidos, email, telefono,
                                 password_hash, acepta_tratamiento_datos, fecha_autorizacion_datos)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 1, NOW())""",
        (id_rol, cliente['tipo_documento'], cliente['numero_documento'], cliente['nombres'], cliente['apellidos'],
         cliente['email'], cliente['telefono'], HASH_INVITADO),
    )
    return cur.lastrowid


def insertar_direccion(cur, id_usuario, id_ciudad, entrega):
    cur.execute(
        """INSERT INTO direcciones (id_usuario, id_ciudad, alias, direccion, barrio, indicaciones)
           VALUES (%s, %s, 'Entrega', %s, %s, %s)""",
        (id_usuario, id_ciudad, entrega['direccion'], entrega['barrio'], entrega['indicaciones'] or None),
    )
    return cur.lastrowid


def insertar_formula(cur, id_usuario, formula):
    cur.execute(
        """INSERT INTO formulas_medicas (id_usuario, archivo, archivo_mime, archivo_sha256, medico_nombre, fecha_emision)
           VALUES (%s, %s, %s, %s, %s, %s)""",
        (id_usuario, formula['contenido'], formula['mime'], formula['sha256'], formula['medico'] or None,
         formula['fecha_emision']),
    )
    return cur.lastrowid


def insertar_pedido(cur, pedido):
    """Inserta el encabezado con un código temporal y lo reemplaza por PED-000123 a partir del id."""
    cur.execute(
        """INSERT INTO pedidos (codigo, id_usuario, id_sede, id_direccion, tipo_entrega, direccion_entrega, estado,
                                metodo_pago, subtotal, descuento, costo_envio, total)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
        (pedido['codigo_temporal'], pedido['id_usuario'], pedido['id_sede'], pedido['id_direccion'],
         pedido['tipo_entrega'], pedido['direccion_entrega'], pedido['estado'], pedido['metodo_pago'],
         pedido['subtotal'], pedido['descuento'], pedido['costo_envio'], pedido['total']),
    )
    id_pedido = cur.lastrowid
    cur.execute("UPDATE pedidos SET codigo = CONCAT('PED-', LPAD(id_pedido, 6, '0')) WHERE id_pedido = %s", (id_pedido,))
    cur.execute('SELECT codigo FROM pedidos WHERE id_pedido = %s', (id_pedido,))
    return id_pedido, cur.fetchone()['codigo']


def insertar_item(cur, id_pedido, item, id_formula):
    cur.execute(
        """INSERT INTO pedido_items (id_pedido, id_producto, id_formula, cantidad, precio_unitario, descuento_unitario)
           VALUES (%s, %s, %s, %s, %s, %s)""",
        (id_pedido, item['id_producto'], id_formula, item['cantidad'], item['precio'], item['descuento']),
    )
    return cur.lastrowid


def descontar_lote(cur, id_pedido, id_pedido_item, asignacion, motivo):
    """Saca unidades de un lote: ítem-lote (trazabilidad), inventario y movimiento VENTA del kárdex."""
    cur.execute('INSERT INTO pedido_item_lotes (id_pedido_item, id_lote, cantidad) VALUES (%s, %s, %s)',
                (id_pedido_item, asignacion['id_lote'], asignacion['cantidad']))
    cur.execute('UPDATE inventario SET cantidad = cantidad - %s WHERE id_inventario = %s',
                (asignacion['cantidad'], asignacion['id_inventario']))
    cur.execute(
        """INSERT INTO movimientos_inventario (id_inventario, id_pedido, tipo, cantidad, saldo, motivo)
           VALUES (%s, %s, 'VENTA', %s, %s, %s)""",
        (asignacion['id_inventario'], id_pedido, asignacion['cantidad'], asignacion['saldo'], motivo),
    )


def insertar_historial(cur, id_pedido, estado, comentario):
    cur.execute('INSERT INTO pedido_historial (id_pedido, estado, comentario) VALUES (%s, %s, %s)',
                (id_pedido, estado, comentario))


# ---------------------------------------------------------------- lectura del pedido confirmado
def pedido_por_codigo(codigo):
    filas = consultar(
        """SELECT pe.id_pedido, pe.codigo, pe.tipo_entrega, pe.direccion_entrega, pe.estado, pe.metodo_pago,
                  pe.subtotal, pe.descuento, pe.costo_envio, pe.total, pe.created_at,
                  u.nombres, u.apellidos, u.tipo_documento, u.numero_documento,
                  s.nombre AS sede, s.direccion AS sede_direccion
             FROM pedidos pe
             JOIN usuarios u ON u.id_usuario = pe.id_usuario
             JOIN sedes s    ON s.id_sede = pe.id_sede
            WHERE pe.codigo = %s""",
        (codigo,),
    )
    return filas[0] if filas else None


def items_de_pedido(id_pedido):
    return consultar(
        """SELECT pi.id_producto, p.nombre, p.presentacion, p.requiere_formula, pi.cantidad,
                  pi.precio_unitario, pi.descuento_unitario
             FROM pedido_items pi
             JOIN productos p ON p.id_producto = pi.id_producto
            WHERE pi.id_pedido = %s
            ORDER BY pi.id_pedido_item""",
        (id_pedido,),
    )


def historial_de_pedido(id_pedido):
    return consultar(
        """SELECT estado, comentario, created_at
             FROM pedido_historial
            WHERE id_pedido = %s
            ORDER BY created_at, id_historial""",
        (id_pedido,),
    )


def documento_coincide(codigo, tipo_documento, numero_documento):
    filas = consultar(
        """SELECT 1
             FROM pedidos pe JOIN usuarios u ON u.id_usuario = pe.id_usuario
            WHERE pe.codigo = %s AND u.tipo_documento = %s AND u.numero_documento = %s""",
        (codigo, tipo_documento, numero_documento),
    )
    return bool(filas)
