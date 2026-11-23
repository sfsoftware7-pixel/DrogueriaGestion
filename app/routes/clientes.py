"""API de clientes (con autorización de tratamiento de datos, Ley 1581 de 2012)."""
from flask import Blueprint, jsonify, request

from ..db import consultar, consultar_uno, ejecutar, paginar
from ..seguridad import permiso_requerido
from ..utils import ApiError, Validador, auditar, datos_json, parametros_paginacion, patron_busqueda

bp = Blueprint('clientes', __name__)

TIPOS_DOCUMENTO = ('CC', 'TI', 'CE', 'PA', 'NIT', 'RC')
ID_CONSUMIDOR_FINAL = 1


def _validar(datos):
    v = Validador(datos)
    c = {
        'tipo_documento': v.opcion('tipo_documento', TIPOS_DOCUMENTO),
        'numero_documento': v.texto('numero_documento', max_len=20, min_len=3, patron=r'[0-9A-Za-z\-]+',
                                    mensaje_patron='Solo números, letras y guion'),
        'nombres': v.texto('nombres', max_len=80, min_len=2),
        'apellidos': v.texto('apellidos', requerido=False, max_len=80),
        'telefono': v.texto('telefono', requerido=False, max_len=20, patron=r'[0-9 +()\-]{7,20}',
                            mensaje_patron='Teléfono no válido'),
        'email': v.email('email'),
        'direccion': v.texto('direccion', requerido=False, max_len=150),
        'ciudad': v.texto('ciudad', max_len=50),
        'pais': v.texto('pais', max_len=50),
        'fecha_nacimiento': v.fecha('fecha_nacimiento', requerido=False),
        'autoriza_datos': v.booleano('autoriza_datos'),
    }
    v.validar()
    return c


@bp.get('/clientes')
@permiso_requerido('clientes.ver')
def listar():
    pagina, por_pagina = parametros_paginacion()
    sql = '''SELECT c.*,
                    (SELECT COUNT(*) FROM ventas v WHERE v.id_cliente = c.id_cliente AND v.estado = 'COMPLETADA') AS compras,
                    (SELECT COALESCE(SUM(v.total), 0) FROM ventas v
                      WHERE v.id_cliente = c.id_cliente AND v.estado = 'COMPLETADA') AS total_comprado,
                    (SELECT MAX(v.fecha_venta) FROM ventas v WHERE v.id_cliente = c.id_cliente) AS ultima_compra
               FROM clientes c WHERE 1 = 1'''
    params = []
    q = request.args.get('q', '').strip()
    if q:
        sql += ''' AND (c.numero_documento LIKE %s OR CONCAT_WS(' ', c.nombres, c.apellidos) LIKE %s
                        OR c.telefono LIKE %s)'''
        params += [patron_busqueda(q)] * 3
    activo = request.args.get('activo', '')
    if activo in ('0', '1'):
        sql += ' AND c.activo = %s'
        params.append(int(activo))
    return jsonify(paginar(sql, params, pagina, por_pagina, 'c.id_cliente = 1 DESC, c.nombres, c.apellidos'))


@bp.get('/clientes/buscar')
@permiso_requerido('clientes.ver')
def buscar():
    q = request.args.get('q', '').strip()
    if not q:
        return jsonify([])
    return jsonify(consultar(
        '''SELECT id_cliente, tipo_documento, numero_documento, CONCAT_WS(' ', nombres, apellidos) AS nombre, telefono
             FROM clientes
            WHERE activo = 1 AND (numero_documento LIKE %s OR CONCAT_WS(' ', nombres, apellidos) LIKE %s)
            ORDER BY numero_documento = %s DESC, nombres LIMIT 10''',
        (patron_busqueda(q), patron_busqueda(q), q),
    ))


@bp.get('/clientes/<int:id_cliente>')
@permiso_requerido('clientes.ver')
def obtener(id_cliente):
    c = consultar_uno('SELECT * FROM clientes WHERE id_cliente = %s', (id_cliente,))
    if not c:
        raise ApiError('Cliente no encontrado', 404)
    c['compras'] = consultar(
        '''SELECT id_venta, numero_factura, fecha_venta, total, metodo_pago, estado, unidades
             FROM v_ventas WHERE id_cliente = %s ORDER BY fecha_venta DESC LIMIT 15''',
        (id_cliente,),
    )
    return jsonify(c)


@bp.post('/clientes')
@permiso_requerido('clientes.editar')
def crear():
    c = _validar(datos_json())
    id_nuevo, _ = ejecutar(
        f'INSERT INTO clientes ({", ".join(c)}) VALUES ({", ".join(["%s"] * len(c))})', tuple(c.values()))
    auditar('CREAR', 'clientes', f'Cliente {c["tipo_documento"]} {c["numero_documento"]}')
    nombre = f'{c["nombres"]} {c["apellidos"] or ""}'.strip()
    return jsonify({'mensaje': 'Cliente registrado', 'id_cliente': id_nuevo, 'nombre': nombre,
                    'tipo_documento': c['tipo_documento'], 'numero_documento': c['numero_documento']}), 201


@bp.put('/clientes/<int:id_cliente>')
@permiso_requerido('clientes.editar')
def actualizar(id_cliente):
    if id_cliente == ID_CONSUMIDOR_FINAL:
        raise ApiError('El cliente "Consumidor final" no se puede modificar', 409)
    c = _validar(datos_json())
    if not consultar_uno('SELECT 1 FROM clientes WHERE id_cliente = %s', (id_cliente,)):
        raise ApiError('Cliente no encontrado', 404)
    ejecutar(f'UPDATE clientes SET {", ".join(f"{k} = %s" for k in c)} WHERE id_cliente = %s',
             (*c.values(), id_cliente))
    auditar('ACTUALIZAR', 'clientes', f'Cliente {c["tipo_documento"]} {c["numero_documento"]}')
    return jsonify({'mensaje': 'Cliente actualizado'})


@bp.patch('/clientes/<int:id_cliente>/estado')
@permiso_requerido('clientes.editar')
def cambiar_estado(id_cliente):
    if id_cliente == ID_CONSUMIDOR_FINAL:
        raise ApiError('El cliente "Consumidor final" no se puede desactivar', 409)
    activo = Validador(datos_json()).booleano('activo')
    cliente = consultar_uno('SELECT tipo_documento, numero_documento FROM clientes WHERE id_cliente = %s',
                            (id_cliente,))
    if not cliente:
        raise ApiError('Cliente no encontrado', 404)
    ejecutar('UPDATE clientes SET activo = %s WHERE id_cliente = %s', (activo, id_cliente))
    auditar('ACTIVAR' if activo else 'DESACTIVAR', 'clientes',
            f'Cliente {cliente["tipo_documento"]} {cliente["numero_documento"]}')
    return jsonify({'mensaje': 'Cliente activado' if activo else 'Cliente desactivado'})


@bp.delete('/clientes/<int:id_cliente>')
@permiso_requerido('clientes.editar')
def eliminar(id_cliente):
    if id_cliente == ID_CONSUMIDOR_FINAL:
        raise ApiError('El cliente "Consumidor final" no se puede eliminar', 409)
    cliente = consultar_uno(
        'SELECT tipo_documento, numero_documento FROM clientes WHERE id_cliente = %s', (id_cliente,))
    if not cliente:
        raise ApiError('Cliente no encontrado', 404)
    if consultar_uno('SELECT 1 FROM ventas WHERE id_cliente = %s LIMIT 1', (id_cliente,)):
        raise ApiError('El cliente tiene facturas vinculadas; desactívelo para conservar el historial', 409)
    auditar('ELIMINAR', 'clientes', f'Cliente {cliente["tipo_documento"]} {cliente["numero_documento"]}')
    ejecutar('DELETE FROM clientes WHERE id_cliente = %s', (id_cliente,))
    return jsonify({'mensaje': 'Cliente eliminado'})
