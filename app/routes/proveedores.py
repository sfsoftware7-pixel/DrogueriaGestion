"""API de proveedores."""
from flask import Blueprint, jsonify, request

from ..db import consultar, consultar_uno, ejecutar, paginar
from ..seguridad import permiso_requerido
from ..utils import ApiError, Validador, auditar, datos_json, parametros_paginacion, patron_busqueda

bp = Blueprint('proveedores', __name__)


def _validar(datos):
    v = Validador(datos)
    p = {
        'nit': v.texto('nit', max_len=20, min_len=5, patron=r'[0-9]{5,15}(-[0-9])?',
                       mensaje_patron='Formato NIT: 900123456-1'),
        'razon_social': v.texto('razon_social', max_len=150, min_len=3),
        'nombre_contacto': v.texto('nombre_contacto', requerido=False, max_len=100),
        'telefono': v.texto('telefono', requerido=False, max_len=20, patron=r'[0-9 +()\-]{7,20}',
                            mensaje_patron='Teléfono no válido'),
        'email': v.email('email'),
        'direccion': v.texto('direccion', requerido=False, max_len=150),
        'ciudad': v.texto('ciudad', requerido=False, max_len=60),
    }
    v.validar()
    return p


@bp.get('/proveedores')
@permiso_requerido('proveedores.ver')
def listar():
    pagina, por_pagina = parametros_paginacion()
    sql = '''SELECT p.*,
                    (SELECT COUNT(*) FROM entradas e WHERE e.id_proveedor = p.id_proveedor) AS total_entradas,
                    (SELECT MAX(e.fecha_entrada) FROM entradas e WHERE e.id_proveedor = p.id_proveedor) AS ultima_entrada
               FROM proveedores p WHERE 1 = 1'''
    params = []
    q = request.args.get('q', '').strip()
    if q:
        sql += ' AND (p.razon_social LIKE %s OR p.nit LIKE %s OR p.nombre_contacto LIKE %s OR p.ciudad LIKE %s)'
        params += [patron_busqueda(q)] * 4
    activo = request.args.get('activo', '')
    if activo in ('0', '1'):
        sql += ' AND p.activo = %s'
        params.append(int(activo))
    return jsonify(paginar(sql, params, pagina, por_pagina, 'razon_social'))


@bp.get('/proveedores/opciones')
@permiso_requerido('proveedores.ver')
def opciones():
    return jsonify(consultar('SELECT id_proveedor, razon_social, nit FROM proveedores WHERE activo = 1 '
                             'ORDER BY razon_social'))


@bp.get('/proveedores/<int:id_proveedor>')
@permiso_requerido('proveedores.ver')
def obtener(id_proveedor):
    p = consultar_uno('SELECT * FROM proveedores WHERE id_proveedor = %s', (id_proveedor,))
    if not p:
        raise ApiError('Proveedor no encontrado', 404)
    p['entradas'] = consultar(
        '''SELECT id_entrada, numero_factura, fecha_entrada, total,
                  (SELECT COUNT(*) FROM detalle_entrada d WHERE d.id_entrada = e.id_entrada) AS productos
             FROM entradas e WHERE id_proveedor = %s ORDER BY fecha_entrada DESC LIMIT 10''',
        (id_proveedor,),
    )
    return jsonify(p)


@bp.post('/proveedores')
@permiso_requerido('proveedores.editar')
def crear():
    p = _validar(datos_json())
    id_nuevo, _ = ejecutar(
        f'INSERT INTO proveedores ({", ".join(p)}) VALUES ({", ".join(["%s"] * len(p))})', tuple(p.values()))
    auditar('CREAR', 'proveedores', f'Proveedor {p["nit"]} - {p["razon_social"]}')
    return jsonify({'mensaje': 'Proveedor registrado', 'id_proveedor': id_nuevo}), 201


@bp.put('/proveedores/<int:id_proveedor>')
@permiso_requerido('proveedores.editar')
def actualizar(id_proveedor):
    p = _validar(datos_json())
    if not consultar_uno('SELECT 1 FROM proveedores WHERE id_proveedor = %s', (id_proveedor,)):
        raise ApiError('Proveedor no encontrado', 404)
    ejecutar(f'UPDATE proveedores SET {", ".join(f"{c} = %s" for c in p)} WHERE id_proveedor = %s',
             (*p.values(), id_proveedor))
    auditar('ACTUALIZAR', 'proveedores', f'Proveedor {p["nit"]} - {p["razon_social"]}')
    return jsonify({'mensaje': 'Proveedor actualizado'})


@bp.patch('/proveedores/<int:id_proveedor>/estado')
@permiso_requerido('proveedores.editar')
def cambiar_estado(id_proveedor):
    activo = Validador(datos_json()).booleano('activo')
    proveedor = consultar_uno('SELECT nit, razon_social FROM proveedores WHERE id_proveedor = %s', (id_proveedor,))
    if not proveedor:
        raise ApiError('Proveedor no encontrado', 404)
    ejecutar('UPDATE proveedores SET activo = %s WHERE id_proveedor = %s', (activo, id_proveedor))
    auditar('ACTIVAR' if activo else 'DESACTIVAR', 'proveedores',
            f'Proveedor {proveedor["nit"]} - {proveedor["razon_social"]}')
    return jsonify({'mensaje': 'Proveedor activado' if activo else 'Proveedor desactivado'})
