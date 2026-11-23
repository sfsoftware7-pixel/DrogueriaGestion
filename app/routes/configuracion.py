"""API de parámetros generales de la droguería (solo administrador)."""
from flask import Blueprint, jsonify

from ..db import consultar, transaccion
from ..seguridad import login_requerido, permiso_requerido
from ..services.ventas import DESCUENTO_MAXIMO_VENDEDOR_DEFECTO, porcentaje_txt
from ..utils import Validador, auditar, datos_json

bp = Blueprint('configuracion', __name__)

CAMPOS = {
    'nombre_drogueria': (True, 100),
    'nit': (True, 30),
    'direccion': (True, 150),
    'telefono': (False, 30),
    'email': (False, 120),
    'mensaje_factura': (False, 200),
}


@bp.get('/configuracion')
@login_requerido
def obtener():
    datos = {f['clave']: f['valor'] for f in consultar('SELECT clave, valor FROM configuracion')}
    datos.setdefault('descuento_maximo_vendedor', porcentaje_txt(DESCUENTO_MAXIMO_VENDEDOR_DEFECTO))
    return jsonify(datos)


@bp.put('/configuracion')
@permiso_requerido('configuracion.editar')
def actualizar():
    v = Validador(datos_json())
    valores = {}
    for clave, (requerido, max_len) in CAMPOS.items():
        valores[clave] = (v.email(clave) if clave == 'email' else
                          v.texto(clave, requerido=requerido, max_len=max_len)) or ''
    descuento = v.decimal('descuento_maximo_vendedor', minimo=0, maximo=100)
    v.validar()
    valores['descuento_maximo_vendedor'] = porcentaje_txt(descuento)
    with transaccion() as cur:
        for clave, valor in valores.items():
            # Alias de fila (MySQL 8.0.19+): reemplaza a VALUES(valor), que está obsoleto
            cur.execute(
                '''INSERT INTO configuracion (clave, valor) VALUES (%s, %s) AS nuevo
                   ON DUPLICATE KEY UPDATE valor = nuevo.valor''',
                (clave, valor),
            )
    auditar('ACTUALIZAR', 'configuracion',
            f'Datos generales de la droguería (descuento máximo vendedor: {valores["descuento_maximo_vendedor"]} %)')
    return jsonify({'mensaje': 'Configuración guardada'})
