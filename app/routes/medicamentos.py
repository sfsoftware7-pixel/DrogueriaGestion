"""API de medicamentos (catálogo con existencias calculadas por lote)."""
from flask import Blueprint, jsonify, request

from ..db import consultar, consultar_uno, ejecutar, paginar
from ..seguridad import permiso_requerido, tiene_permiso
from ..utils import ApiError, Validador, auditar, datos_json, parametros_paginacion, patron_busqueda

bp = Blueprint('medicamentos', __name__)

FORMAS = ('Tableta', 'Tableta masticable', 'Cápsula', 'Jarabe', 'Suspensión', 'Polvo para suspensión',
          'Solución', 'Gotas', 'Crema', 'Gel', 'Ungüento', 'Inhalador', 'Inyectable', 'Óvulo',
          'Supositorio', 'Sobre', 'Material de curación', 'Otro')
IVA_PERMITIDOS = ('0', '5', '19')
ORDENES = {
    'nombre': 'nombre ASC',
    'stock': 'stock_disponible ASC, nombre ASC',
    'precio': 'precio_venta DESC, nombre ASC',
    'vencimiento': 'proximo_vencimiento IS NULL, proximo_vencimiento ASC',
    'codigo': 'codigo ASC',
}


def _validar(datos):
    v = Validador(datos)
    m = {
        'codigo': v.texto('codigo', max_len=30, patron=r'[A-Za-z0-9\-]+', mensaje_patron='Solo letras, números y guion'),
        'nombre': v.texto('nombre', max_len=120, min_len=2),
        'principio_activo': v.texto('principio_activo', max_len=150, min_len=2),
        'concentracion': v.texto('concentracion', requerido=False, max_len=50),
        'forma_farmaceutica': v.opcion('forma_farmaceutica', FORMAS),
        'presentacion': v.texto('presentacion', requerido=False, max_len=80),
        'laboratorio': v.texto('laboratorio', requerido=False, max_len=100),
        'registro_invima': v.texto('registro_invima', requerido=False, max_len=40),
        'id_categoria': v.entero('id_categoria', minimo=1),
        'requiere_formula': v.booleano('requiere_formula'),
        'es_controlado': v.booleano('es_controlado'),
        'precio_compra': v.decimal('precio_compra', minimo=0, maximo=100000000),
        'precio_venta': v.decimal('precio_venta', minimo=1, maximo=100000000),
        'iva_porcentaje': v.opcion('iva_porcentaje', IVA_PERMITIDOS, defecto='0'),
        'stock_minimo': v.entero('stock_minimo', minimo=0, maximo=100000),
        'ubicacion': v.texto('ubicacion', requerido=False, max_len=40),
    }
    if m['precio_compra'] is not None and m['precio_venta'] is not None and m['precio_venta'] < m['precio_compra']:
        v.error('precio_venta', 'No puede ser menor que el precio de compra (último costo de entrada)')
    if m['id_categoria'] and not consultar_uno('SELECT 1 FROM categorias WHERE id_categoria = %s AND activo = 1',
                                               (m['id_categoria'],)):
        v.error('id_categoria', 'Categoría no válida')
    v.validar()
    if m['es_controlado']:
        m['requiere_formula'] = True  # Todo medicamento de control especial exige fórmula
    m['codigo'] = m['codigo'].upper()
    return m


@bp.get('/medicamentos')
@permiso_requerido('medicamentos.ver')
def listar():
    pagina, por_pagina = parametros_paginacion()
    sql = 'SELECT * FROM v_stock_medicamentos WHERE 1 = 1'
    params = []
    q = request.args.get('q', '').strip()
    if q:
        sql += ' AND (nombre LIKE %s OR principio_activo LIKE %s OR codigo LIKE %s OR laboratorio LIKE %s)'
        params += [patron_busqueda(q)] * 4
    if request.args.get('categoria'):
        sql += ' AND id_categoria = %s'
        params.append(request.args['categoria'])
    if request.args.get('estado_stock') in ('AGOTADO', 'BAJO', 'NORMAL'):
        sql += ' AND estado_stock = %s'
        params.append(request.args['estado_stock'])
    activo = request.args.get('activo', '1')
    if activo in ('0', '1'):
        sql += ' AND activo = %s'
        params.append(int(activo))
    if request.args.get('formula') == '1':
        sql += ' AND requiere_formula = 1'
    orden = ORDENES.get(request.args.get('orden'), ORDENES['nombre'])
    return jsonify(paginar(sql, params, pagina, por_pagina, orden))


@bp.get('/medicamentos/buscar')
@permiso_requerido('medicamentos.ver')
def buscar():
    """Búsqueda rápida para el punto de venta y las entradas de mercancía."""
    q = request.args.get('q', '').strip()
    if not q:
        return jsonify([])
    solo_stock = request.args.get('con_stock') == '1'
    filas = consultar(
        f'''SELECT id_medicamento, codigo, nombre, principio_activo, concentracion, forma_farmaceutica,
                   presentacion, laboratorio, precio_compra, precio_venta, iva_porcentaje, requiere_formula,
                   es_controlado, stock_disponible, proximo_vencimiento, estado_stock
              FROM v_stock_medicamentos
             WHERE activo = 1 {'AND stock_disponible > 0' if solo_stock else ''}
               AND (codigo = %s OR nombre LIKE %s OR principio_activo LIKE %s)
             ORDER BY codigo = %s DESC, nombre
             LIMIT 12''',
        (q, patron_busqueda(q), patron_busqueda(q), q),
    )
    return jsonify(filas)


@bp.get('/medicamentos/formas')
@permiso_requerido('medicamentos.ver')
def formas():
    return jsonify(FORMAS)


@bp.get('/medicamentos/<int:id_medicamento>')
@permiso_requerido('medicamentos.ver')
def obtener(id_medicamento):
    med = consultar_uno('SELECT * FROM v_stock_medicamentos WHERE id_medicamento = %s', (id_medicamento,))
    if not med:
        raise ApiError('Medicamento no encontrado', 404)
    med['lotes'] = consultar(
        '''SELECT id_lote, numero_lote, proveedor, fecha_vencimiento, cantidad_actual, cantidad_inicial,
                  dias_para_vencer, estado_vencimiento
             FROM v_lotes_vencimiento WHERE id_medicamento = %s AND cantidad_actual > 0
            ORDER BY fecha_vencimiento''',
        (id_medicamento,),
    )
    med['historial_precios'] = consultar(
        '''SELECT h.fecha, h.precio_venta_anterior, h.precio_venta_nuevo,
                  CONCAT_WS(' ', u.nombres, u.apellidos) AS usuario
             FROM historial_precios h LEFT JOIN usuarios u ON u.id_usuario = h.id_usuario
            WHERE h.id_medicamento = %s ORDER BY h.fecha DESC LIMIT 10''',
        (id_medicamento,),
    )
    # Ejemplo de uso de la función almacenada fn_stock_disponible
    med['stock_funcion'] = consultar_uno('SELECT fn_stock_disponible(%s) AS stock', (id_medicamento,))['stock']
    if not tiene_permiso('inventario.ver'):
        med.pop('precio_compra', None)
    return jsonify(med)


@bp.post('/medicamentos')
@permiso_requerido('medicamentos.editar')
def crear():
    m = _validar(datos_json())
    id_nuevo, _ = ejecutar(
        f'''INSERT INTO medicamentos ({', '.join(m.keys())})
            VALUES ({', '.join(['%s'] * len(m))})''',
        tuple(m.values()),
    )
    auditar('CREAR', 'medicamentos', f'Medicamento {m["codigo"]} - {m["nombre"]}')
    return jsonify({'mensaje': 'Medicamento registrado', 'id_medicamento': id_nuevo}), 201


@bp.put('/medicamentos/<int:id_medicamento>')
@permiso_requerido('medicamentos.editar')
def actualizar(id_medicamento):
    if not consultar_uno('SELECT 1 FROM medicamentos WHERE id_medicamento = %s', (id_medicamento,)):
        raise ApiError('Medicamento no encontrado', 404)
    m = _validar(datos_json())
    asignaciones = ', '.join(f'{campo} = %s' for campo in m)
    ejecutar(f'UPDATE medicamentos SET {asignaciones} WHERE id_medicamento = %s', (*m.values(), id_medicamento))
    auditar('ACTUALIZAR', 'medicamentos', f'Medicamento {m["codigo"]} - {m["nombre"]}')
    return jsonify({'mensaje': 'Medicamento actualizado'})


@bp.patch('/medicamentos/<int:id_medicamento>/estado')
@permiso_requerido('medicamentos.editar')
def cambiar_estado(id_medicamento):
    activo = Validador(datos_json()).booleano('activo')
    _, filas = ejecutar('UPDATE medicamentos SET activo = %s WHERE id_medicamento = %s', (activo, id_medicamento))
    if not filas and not consultar_uno('SELECT 1 FROM medicamentos WHERE id_medicamento = %s', (id_medicamento,)):
        raise ApiError('Medicamento no encontrado', 404)
    auditar('ACTIVAR' if activo else 'DESACTIVAR', 'medicamentos', f'Medicamento #{id_medicamento}')
    return jsonify({'mensaje': 'Medicamento activado' if activo else 'Medicamento desactivado'})
