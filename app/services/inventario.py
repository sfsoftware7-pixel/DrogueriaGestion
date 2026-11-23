"""Reglas de negocio del inventario: entradas de mercancía y ajustes por lote.

Todas las funciones reciben un cursor dentro de una transacción abierta.
"""
from datetime import date
from decimal import Decimal

from ..utils import ApiError, Validador, pesos, redondear

TIPOS_AJUSTE = ('AJUSTE_ENTRADA', 'AJUSTE_SALIDA')


def validar_items_entrada(items):
    """Valida cada línea de la entrada y devuelve la lista normalizada."""
    normalizados, errores = [], {}
    for i, item in enumerate(items):
        v = Validador(item)
        linea = {
            'id_medicamento': v.entero('id_medicamento', minimo=1),
            'numero_lote': v.texto('numero_lote', max_len=40, patron=r'[A-Za-z0-9\-/.]+',
                                   mensaje_patron='Use letras, números, guion o punto'),
            'fecha_fabricacion': v.fecha('fecha_fabricacion', requerido=False),
            'fecha_vencimiento': v.fecha('fecha_vencimiento'),
            'cantidad': v.entero('cantidad', minimo=1, maximo=100000),
            'costo_unitario': v.decimal('costo_unitario', minimo=0, maximo=100000000),
        }
        if linea['fecha_vencimiento'] and linea['fecha_vencimiento'] <= date.today():
            v.error('fecha_vencimiento', 'No se pueden ingresar lotes vencidos')
        if (linea['fecha_fabricacion'] and linea['fecha_vencimiento']
                and linea['fecha_fabricacion'] >= linea['fecha_vencimiento']):
            v.error('fecha_fabricacion', 'Debe ser anterior a la fecha de vencimiento')
        for campo, mensaje in v.errores.items():
            errores[f'items.{i}.{campo}'] = mensaje
        normalizados.append(linea)
    if errores:
        raise ApiError('Revise los productos de la entrada', 422, errores)
    return normalizados


def registrar_entrada(cur, id_proveedor, numero_factura, items, id_usuario, observaciones=None):
    """Registra la recepción de mercancía: crea o incrementa lotes y deja el kárdex."""
    cur.execute('SELECT activo FROM proveedores WHERE id_proveedor = %s', (id_proveedor,))
    proveedor = cur.fetchone()
    if not proveedor or not proveedor['activo']:
        raise ApiError('El proveedor no existe o está inactivo', 422, {'id_proveedor': 'Proveedor no válido'})

    cur.execute('SELECT 1 FROM entradas WHERE id_proveedor = %s AND numero_factura = %s',
                (id_proveedor, numero_factura))
    if cur.fetchone():
        raise ApiError('Esta factura del proveedor ya fue registrada', 409,
                       {'numero_factura': 'Factura duplicada para este proveedor'})

    cur.execute(
        'INSERT INTO entradas (id_proveedor, numero_factura, observaciones, id_usuario) VALUES (%s, %s, %s, %s)',
        (id_proveedor, numero_factura, observaciones, id_usuario),
    )
    id_entrada = cur.lastrowid
    total = Decimal('0')
    advertencias = {}  # id_medicamento -> mensaje (una sola vez por medicamento)

    for item in items:
        cur.execute('SELECT nombre, activo, precio_venta FROM medicamentos WHERE id_medicamento = %s',
                    (item['id_medicamento'],))
        med = cur.fetchone()
        if not med or not med['activo']:
            raise ApiError('Uno de los medicamentos no existe o está inactivo')
        # La compra se registra igual (ya ocurrió), pero se avisa: el costo pasa a ser el precio de compra
        # y el medicamento no se podrá editar hasta que su precio de venta lo iguale o supere.
        if item['costo_unitario'] > med['precio_venta']:
            advertencias[item['id_medicamento']] = (
                f'"{med["nombre"]}": el costo de compra ({pesos(item["costo_unitario"])}) supera el precio de '
                f'venta ({pesos(med["precio_venta"])}). Actualice el precio de venta en Medicamentos.')

        cur.execute(
            '''SELECT id_lote, fecha_vencimiento, cantidad_actual FROM lotes
                WHERE id_medicamento = %s AND numero_lote = %s FOR UPDATE''',
            (item['id_medicamento'], item['numero_lote']),
        )
        lote = cur.fetchone()
        if lote:
            if lote['fecha_vencimiento'] != item['fecha_vencimiento']:
                raise ApiError(f'El lote {item["numero_lote"]} de "{med["nombre"]}" ya existe con otra fecha '
                               f'de vencimiento ({lote["fecha_vencimiento"]:%Y-%m-%d})', 409)
            id_lote = lote['id_lote']
            saldo = lote['cantidad_actual'] + item['cantidad']
            cur.execute(
                '''UPDATE lotes SET cantidad_actual = %s, cantidad_inicial = cantidad_inicial + %s,
                                    costo_unitario = %s WHERE id_lote = %s''',
                (saldo, item['cantidad'], item['costo_unitario'], id_lote),
            )
        else:
            saldo = item['cantidad']
            cur.execute(
                '''INSERT INTO lotes (id_medicamento, id_proveedor, numero_lote, fecha_fabricacion, fecha_vencimiento,
                                      cantidad_inicial, cantidad_actual, costo_unitario)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s)''',
                (item['id_medicamento'], id_proveedor, item['numero_lote'], item['fecha_fabricacion'],
                 item['fecha_vencimiento'], item['cantidad'], item['cantidad'], item['costo_unitario']),
            )
            id_lote = cur.lastrowid

        subtotal = redondear(item['costo_unitario'] * item['cantidad'])
        total += subtotal
        cur.execute(
            '''INSERT INTO detalle_entrada (id_entrada, id_lote, cantidad, costo_unitario, subtotal)
               VALUES (%s, %s, %s, %s, %s)''',
            (id_entrada, id_lote, item['cantidad'], item['costo_unitario'], subtotal),
        )
        cur.execute(
            '''INSERT INTO movimientos_inventario (id_lote, id_medicamento, tipo, cantidad, saldo_lote, motivo,
                                                   id_entrada, id_usuario)
               VALUES (%s, %s, 'ENTRADA', %s, %s, %s, %s, %s)''',
            (id_lote, item['id_medicamento'], item['cantidad'], saldo, f'Entrada factura {numero_factura}',
             id_entrada, id_usuario),
        )
        # El último costo de compra se convierte en el precio de compra de referencia
        cur.execute('UPDATE medicamentos SET precio_compra = %s WHERE id_medicamento = %s',
                    (item['costo_unitario'], item['id_medicamento']))

    cur.execute('UPDATE entradas SET total = %s WHERE id_entrada = %s', (total, id_entrada))
    return {'id_entrada': id_entrada, 'total': total, 'advertencias': list(advertencias.values())}


def registrar_ajuste(cur, id_lote, tipo, cantidad, motivo, id_usuario):
    """Corrige las existencias de un lote (conteo físico, avería, pérdida, etc.)."""
    if tipo not in TIPOS_AJUSTE:
        raise ApiError('Tipo de ajuste no válido')
    cur.execute('SELECT id_lote, id_medicamento, numero_lote, cantidad_actual FROM lotes WHERE id_lote = %s FOR UPDATE',
                (id_lote,))
    lote = cur.fetchone()
    if not lote:
        raise ApiError('El lote no existe', 404)
    if tipo == 'AJUSTE_SALIDA' and cantidad > lote['cantidad_actual']:
        raise ApiError(f'El lote solo tiene {lote["cantidad_actual"]} unidades', 422,
                       {'cantidad': 'Supera la existencia del lote'})

    saldo = lote['cantidad_actual'] + (cantidad if tipo == 'AJUSTE_ENTRADA' else -cantidad)
    cur.execute('UPDATE lotes SET cantidad_actual = %s WHERE id_lote = %s', (saldo, id_lote))
    cur.execute(
        '''INSERT INTO movimientos_inventario (id_lote, id_medicamento, tipo, cantidad, saldo_lote, motivo, id_usuario)
           VALUES (%s, %s, %s, %s, %s, %s, %s)''',
        (id_lote, lote['id_medicamento'], tipo, cantidad, saldo, motivo, id_usuario),
    )
    return {'id_lote': id_lote, 'numero_lote': lote['numero_lote'], 'saldo': saldo}
