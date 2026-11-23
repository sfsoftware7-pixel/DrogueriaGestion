"""Lectura y avance controlado de estados de pedidos creados en la tienda en línea."""
import re

from flask import Blueprint, current_app, g, jsonify, request

from ..db import paginar, transaccion
from ..seguridad import permiso_requerido
from ..utils import ApiError, Validador, auditar, datos_json, parametros_paginacion, patron_busqueda

bp = Blueprint('pedidos_tienda', __name__)

ESTADOS = {
    'PENDIENTE_FORMULA': 'Pendiente de fórmula',
    'CONFIRMADO': 'Confirmado',
    'EN_PREPARACION': 'En preparación',
    'EN_CAMINO': 'En camino',
    'LISTO_PARA_RETIRO': 'Listo para retirar',
    'ENTREGADO': 'Entregado',
    'CANCELADO': 'Cancelado',
}


def esquema_tienda():
    nombre = current_app.config.get('TIENDA_DB_NAME', 'drogueria_db')
    if not re.fullmatch(r'[A-Za-z0-9_]+', nombre or ''):
        raise ApiError('El nombre de la base de pedidos no es válido.', 503)
    return f'`{nombre}`'


def siguiente_estado(estado, tipo_entrega):
    """Solo permite avanzar el flujo normal; no cancela pedidos con stock ya descontado."""
    if estado == 'CONFIRMADO':
        return 'EN_PREPARACION'
    if estado == 'EN_PREPARACION':
        return 'EN_CAMINO' if tipo_entrega == 'DOMICILIO' else 'LISTO_PARA_RETIRO'
    if estado in ('EN_CAMINO', 'LISTO_PARA_RETIRO'):
        return 'ENTREGADO'
    return None


@bp.get('/pedidos-tienda')
@permiso_requerido('ventas.ver')
def listar():
    bd = esquema_tienda()
    sql = f'''SELECT pe.id_pedido, pe.codigo, pe.estado, pe.tipo_entrega, pe.created_at,
                     COALESCE(h.actualizado_en, pe.created_at) AS actualizado_en,
                     pe.direccion_entrega, pe.total, u.nombres, u.apellidos, u.telefono,
                     s.nombre AS sede, s.direccion AS sede_direccion, items.productos
                FROM {bd}.pedidos pe
                JOIN {bd}.usuarios u ON u.id_usuario = pe.id_usuario
                JOIN {bd}.sedes s ON s.id_sede = pe.id_sede
                JOIN (SELECT pi.id_pedido,
                             GROUP_CONCAT(CONCAT(p.nombre, ' × ', pi.cantidad)
                                          ORDER BY p.nombre SEPARATOR ', ') AS productos
                        FROM {bd}.pedido_items pi
                        JOIN {bd}.productos p ON p.id_producto = pi.id_producto
                       GROUP BY pi.id_pedido) items ON items.id_pedido = pe.id_pedido
                LEFT JOIN (SELECT id_pedido, estado, MAX(created_at) AS actualizado_en
                             FROM {bd}.pedido_historial GROUP BY id_pedido, estado) h
                  ON h.id_pedido = pe.id_pedido AND h.estado = pe.estado
               WHERE 1 = 1'''
    params = []
    q = request.args.get('q', '').strip()
    if q:
        patron = patron_busqueda(q)
        sql += ' AND (pe.codigo LIKE %s OR u.nombres LIKE %s OR u.apellidos LIKE %s OR u.telefono LIKE %s)'
        params.extend([patron] * 4)
    estado = request.args.get('estado', '')
    if estado in ESTADOS:
        sql += ' AND pe.estado = %s'
        params.append(estado)
    pagina, por_pagina = parametros_paginacion()
    resultado = paginar(sql, params, pagina, por_pagina, 'actualizado_en DESC')
    for pedido in resultado['datos']:
        pedido['cliente'] = f"{pedido.pop('nombres')} {pedido.pop('apellidos')}"
        pedido['estado_texto'] = ESTADOS[pedido['estado']]
        pedido['siguiente_estado'] = siguiente_estado(pedido['estado'], pedido['tipo_entrega'])
        pedido['siguiente_estado_texto'] = ESTADOS.get(pedido['siguiente_estado'])
        pedido['entrega_texto'] = (pedido['direccion_entrega'] if pedido['tipo_entrega'] == 'DOMICILIO'
                                   else f"Retiro en {pedido['sede']} · {pedido['sede_direccion']}")
    return jsonify(resultado)


@bp.post('/pedidos-tienda/<codigo>/estado')
@permiso_requerido('pedidos.gestionar')
def actualizar_estado(codigo):
    if not re.fullmatch(r'PED-\d{6,}', codigo or ''):
        raise ApiError('Código de pedido no válido.', 400)
    bd = esquema_tienda()
    with transaccion() as cur:
        cur.execute(f'''SELECT id_pedido, estado, tipo_entrega
                          FROM {bd}.pedidos WHERE codigo = %s FOR UPDATE''', (codigo,))
        pedido = cur.fetchone()
        if not pedido:
            raise ApiError('No se encontró el pedido.', 404)
        siguiente = siguiente_estado(pedido['estado'], pedido['tipo_entrega'])
        if not siguiente:
            if pedido['estado'] == 'PENDIENTE_FORMULA':
                raise ApiError('El pedido debe esperar la revisión de la fórmula antes de prepararse.', 409)
            raise ApiError('El pedido ya está cerrado y no admite más cambios.', 409)

        v = Validador(datos_json())
        estado = v.opcion('estado', (siguiente,))
        v.validar()
        cur.execute(f'''UPDATE {bd}.pedidos SET estado = %s
                         WHERE id_pedido = %s AND estado = %s''',
                    (estado, pedido['id_pedido'], pedido['estado']))
        if cur.rowcount != 1:
            raise ApiError('El estado del pedido cambió en otra sesión. Recargue e intente de nuevo.', 409)
        cur.execute(f'''INSERT INTO {bd}.pedido_historial (id_pedido, id_usuario, estado, comentario)
                        VALUES (%s, NULL, %s, %s)''',
                    (pedido['id_pedido'], estado, 'Estado actualizado desde el panel administrativo'))

    auditar('ACTUALIZAR_ESTADO', 'pedidos_tienda',
            f"{codigo}: {pedido['estado']} → {estado} por {g.usuario['usuario']}")
    return jsonify({'mensaje': f'Pedido {codigo}: {ESTADOS[estado]}', 'estado': estado,
                    'estado_texto': ESTADOS[estado]})
