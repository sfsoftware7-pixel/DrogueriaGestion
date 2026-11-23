"""Reglas de negocio de ventas y dispensación.

La dispensación sigue el criterio FEFO (First Expired, First Out): para cada
medicamento se descuenta primero el lote que vence antes, sin usar lotes vencidos.
Todas las funciones reciben un cursor dentro de una transacción abierta.
"""
from decimal import ROUND_DOWN, Decimal

from ..utils import ApiError, pesos, redondear

METODOS_PAGO = ('EFECTIVO', 'TARJETA_DEBITO', 'TARJETA_CREDITO', 'TRANSFERENCIA')
# Tope de descuento (%) para roles sin 'ventas.descuento_libre' si no está en la tabla configuracion
DESCUENTO_MAXIMO_VENDEDOR_DEFECTO = Decimal('10')


def _siguiente_factura(cur):
    """Obtiene el siguiente consecutivo de forma atómica (patrón LAST_INSERT_ID)."""
    cur.execute(
        "UPDATE consecutivos SET ultimo_numero = LAST_INSERT_ID(ultimo_numero + 1) WHERE tipo = 'VENTA'"
    )
    cur.execute("SELECT LAST_INSERT_ID() AS numero, prefijo FROM consecutivos WHERE tipo = 'VENTA'")
    fila = cur.fetchone()
    return f"{fila['prefijo']}-{int(fila['numero']):06d}"


def _agrupar_items(items):
    """Suma las cantidades si el mismo medicamento aparece varias veces."""
    cantidades = {}
    for item in items:
        try:
            id_medicamento = int(item.get('id_medicamento'))
            cantidad = int(item.get('cantidad'))
        except (TypeError, ValueError, AttributeError):
            raise ApiError('Hay productos con datos inválidos en la venta')
        if cantidad <= 0:
            raise ApiError('Las cantidades deben ser mayores a cero')
        cantidades[id_medicamento] = cantidades.get(id_medicamento, 0) + cantidad
    return cantidades


def porcentaje_txt(valor):
    """Decimal('10.00') -> '10'; Decimal('7.50') -> '7.5'."""
    return format(Decimal(valor).normalize(), 'f')


def registrar_venta(cur, datos, id_usuario, fecha=None, descuento_maximo_pct=None):
    """Registra una venta completa y descuenta el inventario por lotes (FEFO).

    `datos` contiene: id_cliente, metodo_pago, items[{id_medicamento, cantidad}],
    y opcionalmente descuento, monto_recibido, formula_medica, medico, observaciones.
    `fecha` permite registrar ventas históricas (datos de demostración).
    `descuento_maximo_pct` limita el descuento (en % del total con IVA); None = sin límite.
    """
    cantidades = _agrupar_items(datos['items'])

    cur.execute('SELECT id_cliente, activo FROM clientes WHERE id_cliente = %s', (datos['id_cliente'],))
    cliente = cur.fetchone()
    if not cliente or not cliente['activo']:
        raise ApiError('El cliente seleccionado no existe o está inactivo')

    lineas = []
    requiere_formula = []
    # Los lotes se bloquean siempre en el mismo orden (por id de medicamento) para que dos ventas
    # simultáneas con los mismos productos en distinto orden no queden en bloqueo mutuo (deadlock).
    for id_medicamento, cantidad in sorted(cantidades.items()):
        cur.execute(
            '''SELECT id_medicamento, nombre, precio_venta, iva_porcentaje, requiere_formula, activo
                 FROM medicamentos WHERE id_medicamento = %s''',
            (id_medicamento,),
        )
        med = cur.fetchone()
        if not med or not med['activo']:
            raise ApiError('Uno de los medicamentos no existe o está inactivo')
        if med['requiere_formula']:
            requiere_formula.append(med['nombre'])

        # Bloquea los lotes disponibles para evitar ventas simultáneas del mismo stock
        cur.execute(
            '''SELECT id_lote, cantidad_actual, costo_unitario FROM lotes
                WHERE id_medicamento = %s AND cantidad_actual > 0 AND fecha_vencimiento >= CURDATE()
                ORDER BY fecha_vencimiento, id_lote
                FOR UPDATE''',
            (id_medicamento,),
        )
        lotes = cur.fetchall()
        disponible = sum(l['cantidad_actual'] for l in lotes)
        if disponible < cantidad:
            raise ApiError(f'Existencias insuficientes de "{med["nombre"]}": disponibles {disponible}, '
                           f'solicitadas {cantidad}', 409)

        pendiente = cantidad
        for lote in lotes:
            if pendiente == 0:
                break
            tomar = min(pendiente, lote['cantidad_actual'])
            subtotal = redondear(med['precio_venta'] * tomar)
            impuesto = redondear(subtotal * med['iva_porcentaje'] / 100)
            lineas.append({
                'id_medicamento': id_medicamento,
                'id_lote': lote['id_lote'],
                'cantidad': tomar,
                'precio_unitario': med['precio_venta'],
                'iva_porcentaje': med['iva_porcentaje'],
                'subtotal': subtotal,
                'impuesto': impuesto,
                # Se guarda el costo vigente: los reportes de utilidad no cambian si el lote se recosta después
                'costo_unitario': lote['costo_unitario'],
                'saldo_lote': lote['cantidad_actual'] - tomar,
            })
            pendiente -= tomar

    formula = (datos.get('formula_medica') or '').strip() or None
    if requiere_formula and not formula:
        raise ApiError('Los siguientes productos requieren fórmula médica: ' + ', '.join(requiere_formula), 422,
                       {'formula_medica': 'Ingrese el número de la fórmula médica'})

    subtotal = sum((l['subtotal'] for l in lineas), Decimal('0'))
    impuesto = sum((l['impuesto'] for l in lineas), Decimal('0'))
    descuento = redondear(datos.get('descuento') or 0)
    if descuento < 0 or descuento > subtotal + impuesto:
        raise ApiError('El descuento no puede superar el valor de la venta', 422, {'descuento': 'Descuento no válido'})
    if descuento_maximo_pct is not None:
        tope = redondear((subtotal + impuesto) * Decimal(descuento_maximo_pct) / 100)
        if descuento > tope:
            pct = porcentaje_txt(descuento_maximo_pct)
            tope_txt = pesos(tope, ROUND_DOWN)  # hacia abajo: el valor mostrado siempre es aceptado
            raise ApiError(f'Su rol permite un descuento máximo del {pct} % ({tope_txt} en esta venta). '
                           'Para un descuento mayor, la venta debe registrarla un regente o el administrador.',
                           422, {'descuento': f'Máximo {pct} % ({tope_txt})'})
    total = subtotal + impuesto - descuento

    metodo = datos.get('metodo_pago', 'EFECTIVO')
    if metodo not in METODOS_PAGO:
        raise ApiError('Método de pago no válido')
    if metodo == 'EFECTIVO':
        recibido = redondear(datos.get('monto_recibido') or total)
        if recibido < total:
            raise ApiError('El dinero recibido es menor que el total a pagar', 422,
                           {'monto_recibido': 'Valor insuficiente'})
    else:
        recibido = total
    cambio = recibido - total

    numero = _siguiente_factura(cur)
    cur.execute(
        '''INSERT INTO ventas (numero_factura, id_cliente, id_usuario, fecha_venta, subtotal, descuento, impuesto,
                               total, metodo_pago, monto_recibido, cambio, formula_medica, medico, observaciones)
           VALUES (%s, %s, %s, COALESCE(%s, NOW()), %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)''',
        (numero, datos['id_cliente'], id_usuario, fecha, subtotal, descuento, impuesto, total, metodo,
         recibido, cambio, formula, (datos.get('medico') or '').strip() or None,
         (datos.get('observaciones') or '').strip()[:255] or None),
    )
    id_venta = cur.lastrowid

    for l in lineas:
        # El trigger trg_detalle_venta_bi valida lote, vencimiento y existencias
        cur.execute(
            '''INSERT INTO detalle_venta (id_venta, id_medicamento, id_lote, cantidad, precio_unitario,
                                          iva_porcentaje, subtotal, impuesto, costo_unitario)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)''',
            (id_venta, l['id_medicamento'], l['id_lote'], l['cantidad'], l['precio_unitario'],
             l['iva_porcentaje'], l['subtotal'], l['impuesto'], l['costo_unitario']),
        )
        cur.execute('UPDATE lotes SET cantidad_actual = cantidad_actual - %s WHERE id_lote = %s',
                    (l['cantidad'], l['id_lote']))
        cur.execute(
            '''INSERT INTO movimientos_inventario (id_lote, id_medicamento, tipo, cantidad, saldo_lote, motivo,
                                                   id_venta, id_usuario, fecha)
               VALUES (%s, %s, 'VENTA', %s, %s, %s, %s, %s, COALESCE(%s, NOW()))''',
            (l['id_lote'], l['id_medicamento'], l['cantidad'], l['saldo_lote'], f'Venta {numero}',
             id_venta, id_usuario, fecha),
        )

    return {'id_venta': id_venta, 'numero_factura': numero, 'total': total, 'cambio': cambio}


def anular_venta(cur, id_venta, motivo, id_usuario):
    """Anula una venta y devuelve las unidades a los mismos lotes de donde salieron."""
    cur.execute('SELECT id_venta, numero_factura, estado FROM ventas WHERE id_venta = %s FOR UPDATE', (id_venta,))
    venta = cur.fetchone()
    if not venta:
        raise ApiError('La venta no existe', 404)
    if venta['estado'] == 'ANULADA':
        raise ApiError('La venta ya se encuentra anulada', 409)

    cur.execute('SELECT id_lote, id_medicamento, cantidad FROM detalle_venta WHERE id_venta = %s', (id_venta,))
    for d in cur.fetchall():
        cur.execute('SELECT cantidad_actual FROM lotes WHERE id_lote = %s FOR UPDATE', (d['id_lote'],))
        saldo = cur.fetchone()['cantidad_actual'] + d['cantidad']
        cur.execute('UPDATE lotes SET cantidad_actual = %s WHERE id_lote = %s', (saldo, d['id_lote']))
        cur.execute(
            '''INSERT INTO movimientos_inventario (id_lote, id_medicamento, tipo, cantidad, saldo_lote, motivo,
                                                   id_venta, id_usuario)
               VALUES (%s, %s, 'ANULACION_VENTA', %s, %s, %s, %s, %s)''',
            (d['id_lote'], d['id_medicamento'], d['cantidad'], saldo,
             f'Anulación {venta["numero_factura"]}', id_venta, id_usuario),
        )

    cur.execute(
        '''UPDATE ventas SET estado = 'ANULADA', motivo_anulacion = %s, anulada_por = %s, fecha_anulacion = NOW()
            WHERE id_venta = %s''',
        (motivo, id_usuario, id_venta),
    )
    return venta['numero_factura']
