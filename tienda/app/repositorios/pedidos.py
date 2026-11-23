"""Consultas SQL de los pedidos de la tienda en línea. Todas con parámetros %s.

Las funciones que escriben reciben el cursor de una transacción abierta (db.transaccion) para que el pedido,
sus productos, los lotes despachados, el kárdex y el historial se guarden todos o ninguno.
"""
from ..db import consultar
from flask import current_app
from .catalogo import _MEJOR_PROMOCION

# Marca de contraseña de un cliente que compró como invitado: no es un hash Argon2 válido, así que esa
# cuenta nunca puede iniciar sesión (servicios/cuentas.py la rechaza).
HASH_INVITADO = '!invitado-sin-acceso'


def _marcadores(valores):
    return ', '.join(['%s'] * len(valores))


def _bd_gestion():
    """El nombre de esquema solo puede venir de configuración validada al iniciar Flask."""
    import re
    nombre = current_app.config.get('DB_GESTION_NAME', 'drogueria_gestion')
    if not re.fullmatch(r'[A-Za-z0-9_]+', nombre):
        raise RuntimeError('DB_GESTION_NAME no es válido')
    return f'`{nombre}`'


# ---------------------------------------------------------------- lectura previa (sin bloqueo)
def precios_vigentes(cur, ids):
    """Precio vigente solo para productos vinculados a un medicamento por SKU=código exacto."""
    bd = _bd_gestion()
    cur.execute(
        f"""SELECT p.id_producto, p.nombre, p.presentacion, p.precio, p.requiere_formula, p.activo,
                   m.id_medicamento,
                   COALESCE(mp.descuento, 0) AS descuento
              FROM productos p
              JOIN {bd}.medicamentos m ON m.codigo = p.sku AND m.activo = 1
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
    """Lotes vigentes del inventario administrativo compartido, bloqueados en orden FEFO.

    Todas las sedes de la tienda consumen esta bolsa de stock porque gestión todavía no separa lotes por sede.
    Ambas bases deben estar en el mismo servidor MySQL para que el bloqueo abarque la transacción del pedido.
    """
    bd = _bd_gestion()
    cur.execute(
        f"""SELECT p.id_producto, lo.id_lote, lo.id_medicamento, lo.cantidad_actual AS cantidad,
                   lo.fecha_vencimiento
              FROM productos p
              JOIN {bd}.medicamentos m ON m.codigo = p.sku AND m.activo = 1
              JOIN {bd}.lotes lo ON lo.id_medicamento = m.id_medicamento
             WHERE p.id_producto IN ({_marcadores(ids)})
               AND lo.fecha_vencimiento >= CURDATE() AND lo.cantidad_actual > 0
             ORDER BY p.id_producto, lo.fecha_vencimiento, lo.id_lote
             FOR UPDATE OF lo""",
        tuple(ids),
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
    """Descuenta el lote fuente de gestión y conserva el enlace de trazabilidad en el pedido web."""
    bd = _bd_gestion()
    cur.execute(
        f"""UPDATE {bd}.lotes SET cantidad_actual = cantidad_actual - %s
             WHERE id_lote = %s AND cantidad_actual >= %s""",
        (asignacion['cantidad'], asignacion['id_lote'], asignacion['cantidad']),
    )
    if cur.rowcount != 1:
        raise RuntimeError('El lote administrativo cambió durante el pedido')
    cur.execute(
        """INSERT INTO pedido_item_lotes_gestion (id_pedido_item, id_lote_gestion, cantidad)
           VALUES (%s, %s, %s)""",
        (id_pedido_item, asignacion['id_lote'], asignacion['cantidad']),
    )
    cur.execute(
        f"""INSERT INTO {bd}.movimientos_inventario
               (id_lote, id_medicamento, tipo, cantidad, saldo_lote, motivo, fecha)
           VALUES (%s, %s, 'VENTA', %s, %s, %s, NOW())""",
        (asignacion['id_lote'], asignacion['id_medicamento'], asignacion['cantidad'],
         asignacion['saldo'], motivo),
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
