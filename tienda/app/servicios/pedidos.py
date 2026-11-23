"""Compra como invitado con pago contra entrega: validación, precios desde MySQL, stock FEFO y datos del recibo.

Los precios, descuentos y el costo del domicilio se calculan siempre en el servidor (catálogo y
datos_tienda.toml); del navegador solo se toman los productos, las cantidades y los datos del cliente.
"""
import hashlib
import json
import re
import secrets
from datetime import date
from decimal import ROUND_HALF_UP, Decimal

from .. import db
from ..repositorios import pedidos as repo
from . import tienda_info

TIPOS_DOCUMENTO = ('CC', 'CE', 'TI', 'PA', 'PPT')
MAX_LINEAS = 30
MAX_FORMULA = 5 * 1024 * 1024  # 5 MB (comentario de formulas_medicas.archivo)
FIRMAS_ARCHIVO = (
    (b'\xff\xd8\xff', 'image/jpeg'),
    (b'\x89PNG\r\n\x1a\n', 'image/png'),
    (b'%PDF-', 'application/pdf'),
)
_CORREO = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')

ESTADOS = {
    'PENDIENTE_FORMULA': 'Pendiente de revisión de la fórmula',
    'CONFIRMADO': 'Confirmado',
    'EN_PREPARACION': 'En preparación',
    'EN_CAMINO': 'En camino',
    'LISTO_PARA_RETIRO': 'Listo para retirar',
    'ENTREGADO': 'Entregado',
    'CANCELADO': 'Cancelado',
}
METODOS_PAGO = {'CONTRA_ENTREGA': 'Contra entrega', 'TARJETA': 'Tarjeta', 'PSE': 'PSE'}
# Camino normal de un pedido según cómo se entrega (seguimiento)
CAMINO = {
    'DOMICILIO': ('CONFIRMADO', 'EN_PREPARACION', 'EN_CAMINO', 'ENTREGADO'),
    'RETIRO': ('CONFIRMADO', 'EN_PREPARACION', 'LISTO_PARA_RETIRO', 'ENTREGADO'),
}


class ErrorPedido(Exception):
    """Error que se muestra a la persona. errores: {campo: mensaje} para pintar junto a cada campo."""

    def __init__(self, mensaje, errores=None, estado=422):
        super().__init__(mensaje)
        self.errores = errores or {}
        self.estado = estado


def _pesos(valor):
    return int(Decimal(valor).quantize(Decimal('1'), rounding=ROUND_HALF_UP))


def _texto(datos, campo, minimo, maximo, errores, etiqueta, obligatorio=True):
    valor = ' '.join(str(datos.get(campo) or '').split())
    if not valor and not obligatorio:
        return ''
    if not minimo <= len(valor) <= maximo:
        errores[campo] = f'{etiqueta}: escribe entre {minimo} y {maximo} caracteres.'
    return valor


# ---------------------------------------------------------------- validación
def validar(formulario, archivo):
    """Convierte el formulario de pago en un pedido limpio o lanza ErrorPedido con los errores por campo."""
    errores = {}
    try:
        lineas = json.loads(formulario.get('items') or '[]')
    except ValueError:
        lineas = None
    items = {}
    if not isinstance(lineas, list) or not lineas:
        errores['items'] = 'Tu carrito está vacío.'
    else:
        for linea in lineas[:MAX_LINEAS]:
            try:
                id_producto, cantidad = int(linea['id']), int(linea['cantidad'])
            except (KeyError, TypeError, ValueError):
                errores['items'] = 'El carrito tiene un producto no válido. Recarga la página.'
                break
            if id_producto > 0 and 1 <= cantidad <= 99:
                items[id_producto] = min(items.get(id_producto, 0) + cantidad, 99)
            else:
                errores['items'] = 'Cada producto debe tener entre 1 y 99 unidades.'
        if len(lineas) > MAX_LINEAS:
            errores['items'] = f'El pedido admite hasta {MAX_LINEAS} productos distintos.'

    cliente = {
        'tipo_documento': formulario.get('tipo_documento', ''),
        'numero_documento': re.sub(r'[\s.]', '', formulario.get('numero_documento', '')),
        'nombres': _texto(formulario, 'nombres', 2, 80, errores, 'Nombres'),
        'apellidos': _texto(formulario, 'apellidos', 2, 80, errores, 'Apellidos'),
        'email': formulario.get('email', '').strip().lower(),
        'telefono': re.sub(r'[\s()-]', '', formulario.get('telefono', '')),
    }
    if cliente['tipo_documento'] not in TIPOS_DOCUMENTO:
        errores['tipo_documento'] = 'Elige el tipo de documento.'
    if not re.fullmatch(r'[A-Za-z0-9]{5,20}', cliente['numero_documento']):
        errores['numero_documento'] = 'Escribe el número de documento (5 a 20 letras o números).'
    if not (_CORREO.match(cliente['email']) and len(cliente['email']) <= 120):
        errores['email'] = 'Escribe un correo válido, por ejemplo nombre@correo.com.'
    if not re.fullmatch(r'\+?\d{7,15}', cliente['telefono']):
        errores['telefono'] = 'Escribe un celular o teléfono de 7 a 15 dígitos.'

    tipo_entrega = formulario.get('tipo_entrega', '')
    entrega = {'tipo': tipo_entrega}
    if tipo_entrega == 'DOMICILIO':
        entrega['barrio'] = _texto(formulario, 'barrio', 3, 80, errores, 'Barrio')
        entrega['direccion'] = _texto(formulario, 'direccion', 5, 150, errores, 'Dirección')
        entrega['indicaciones'] = _texto(formulario, 'indicaciones', 0, 255, errores, 'Indicaciones', obligatorio=False)
        ciudad_dane = formulario.get('ciudad', '')
        if 'barrio' not in errores:
            cobertura = tienda_info.buscar_cobertura(entrega['barrio'], ciudad_dane)
            if not cobertura['cobertura']:
                errores['barrio'] = 'Aún no tenemos domicilio en ese barrio. Puedes elegir retiro en sede.'
            else:
                entrega['zona'] = cobertura['coincidencias'][0]
    elif tipo_entrega == 'RETIRO':
        try:
            entrega['id_sede'] = int(formulario.get('sede', ''))
        except ValueError:
            errores['sede'] = 'Elige la sede donde vas a retirar el pedido.'
    else:
        errores['tipo_entrega'] = 'Elige domicilio o retiro en sede.'

    metodo = tienda_info.datos()['pago']['metodo']
    if formulario.get('metodo_pago') != metodo:
        errores['metodo_pago'] = 'Elige el método de pago.'
    if formulario.get('acepta_datos') != 'si':
        errores['acepta_datos'] = 'Para despachar el pedido necesitamos tu autorización de tratamiento de datos.'

    formula = None
    if archivo and archivo.filename:
        contenido = archivo.read(MAX_FORMULA + 1)
        mime = next((tipo for firma, tipo in FIRMAS_ARCHIVO if contenido.startswith(firma)), None)
        if len(contenido) > MAX_FORMULA:
            errores['formula'] = 'La fórmula debe pesar 5 MB o menos.'
        elif not mime:
            errores['formula'] = 'Sube la fórmula como foto (JPG o PNG) o como PDF.'
        try:
            fecha = date.fromisoformat(formulario.get('fecha_formula', ''))
            if fecha > tienda_info.ahora().date():
                errores['fecha_formula'] = 'La fecha de la fórmula no puede ser posterior a hoy.'
        except ValueError:
            fecha = None
            errores['fecha_formula'] = 'Escribe la fecha en que el médico emitió la fórmula.'
        formula = {'contenido': contenido, 'mime': mime, 'sha256': hashlib.sha256(contenido).hexdigest(),
                   'fecha_emision': fecha,
                   'medico': _texto(formulario, 'medico', 0, 120, errores, 'Médico', obligatorio=False)}

    if errores:
        raise ErrorPedido('Revisa los datos marcados.', errores)
    return {'items': items, 'cliente': cliente, 'entrega': entrega, 'metodo_pago': metodo, 'formula': formula}


# ---------------------------------------------------------------- creación
def _usuario(cur, cliente):
    """Reutiliza al invitado que ya compró con el mismo correo y documento; si no existe, lo crea."""
    filas = repo.usuarios_con_datos(cur, cliente['email'], cliente['tipo_documento'], cliente['numero_documento'])
    if not filas:
        id_rol = repo.id_rol_cliente(cur)
        if id_rol is None:
            raise ErrorPedido('La tienda no tiene configurado el rol de cliente.', estado=503)
        return repo.insertar_usuario_invitado(cur, id_rol, cliente)
    mismo = [f for f in filas if f['email'].lower() == cliente['email'] and f['tipo_documento'] == cliente['tipo_documento']
             and f['numero_documento'] == cliente['numero_documento'] and f['password_hash'] == repo.HASH_INVITADO]
    if len(filas) == 1 and mismo:
        return mismo[0]['id_usuario']
    # Sin inicio de sesión no se puede comprar a nombre de una cuenta ajena: no se dice cuál dato coincide
    raise ErrorPedido('Ese correo o documento ya está registrado con otros datos. Revisa lo que escribiste o escríbenos.',
                      {'email': 'Revisa el correo.', 'numero_documento': 'Revisa el documento.'}, estado=409)


def _asignar_fefo(lotes, cantidad):
    """Reparte la cantidad entre los lotes de un producto, del que vence antes al que vence después."""
    asignaciones, faltan = [], cantidad
    for lote in lotes:
        if faltan == 0:
            break
        tomar = min(lote['cantidad'], faltan)
        asignaciones.append({'id_inventario': lote['id_inventario'], 'id_lote': lote['id_lote'],
                             'cantidad': tomar, 'saldo': lote['cantidad'] - tomar})
        faltan -= tomar
    return asignaciones if faltan == 0 else None


def crear(pedido):
    """Guarda el pedido completo en una transacción y devuelve su código (PED-000123)."""
    ids = sorted(pedido['items'])
    entrega = pedido['entrega']
    with db.transaccion() as cur:
        productos = {p['id_producto']: p for p in repo.precios_vigentes(cur, ids)}
        faltantes = [i for i in ids if i not in productos or not productos[i]['activo']]
        if faltantes:
            raise ErrorPedido('Algunos productos del carrito ya no están disponibles. Recarga el carrito.',
                              {'items': 'Quita los productos que ya no se venden.'})
        requiere_formula = any(productos[i]['requiere_formula'] for i in ids)
        if requiere_formula and not pedido['formula']:
            raise ErrorPedido('Tu pedido incluye productos con fórmula médica.',
                              {'formula': 'Adjunta la fórmula médica (foto o PDF).'})

        if entrega['tipo'] == 'DOMICILIO':
            zona = entrega['zona']
            id_sede, costo_envio = zona['sede_id'], zona['costo']
            ciudad = repo.ciudad_por_dane(cur, zona['ciudad_dane'])
            if not ciudad or not ciudad['tiene_cobertura']:
                raise ErrorPedido('Aún no tenemos domicilio en esa ciudad.', {'barrio': 'Elige retiro en sede.'})
        else:
            id_sede, costo_envio, ciudad = entrega['id_sede'], 0, None
        sede = repo.sede_para_pedido(cur, id_sede)
        if not sede or not sede['activo'] or (entrega['tipo'] == 'RETIRO' and not sede['permite_retiro']):
            raise ErrorPedido('Esa sede no está disponible.', {'sede': 'Elige otra sede.'})

        lotes_por_producto = {}
        for lote in repo.bloquear_existencias(cur, id_sede, ids):
            lotes_por_producto.setdefault(lote['id_producto'], []).append(lote)
        asignaciones, sin_stock = {}, []
        for id_producto in ids:
            reparto = _asignar_fefo(lotes_por_producto.get(id_producto, []), pedido['items'][id_producto])
            if reparto is None:
                disponibles = sum(l['cantidad'] for l in lotes_por_producto.get(id_producto, []))
                sin_stock.append(f"{productos[id_producto]['nombre']} (quedan {disponibles})")
            asignaciones[id_producto] = reparto
        if sin_stock:
            raise ErrorPedido(f"No hay unidades suficientes en {sede['nombre']}: {'; '.join(sin_stock)}.",
                              {'items': 'Ajusta las cantidades.'}, estado=409)

        lineas = [{'id_producto': i, 'cantidad': pedido['items'][i], 'precio': _pesos(productos[i]['precio']),
                   'descuento': min(_pesos(productos[i]['descuento']), _pesos(productos[i]['precio']))} for i in ids]
        subtotal = sum(l['precio'] * l['cantidad'] for l in lineas)
        descuento = sum(l['descuento'] * l['cantidad'] for l in lineas)

        id_usuario = _usuario(cur, pedido['cliente'])
        id_direccion = direccion_texto = None
        if entrega['tipo'] == 'DOMICILIO':
            id_direccion = repo.insertar_direccion(cur, id_usuario, ciudad['id_ciudad'], entrega)
            direccion_texto = f"{entrega['direccion']}, {entrega['barrio']}, {ciudad['nombre']}"
            if entrega['indicaciones']:
                direccion_texto += f" ({entrega['indicaciones']})"
        id_formula = repo.insertar_formula(cur, id_usuario, pedido['formula']) if requiere_formula else None

        estado = 'PENDIENTE_FORMULA' if requiere_formula else 'CONFIRMADO'
        id_pedido, codigo = repo.insertar_pedido(cur, {
            'codigo_temporal': 'TMP-' + secrets.token_hex(8), 'id_usuario': id_usuario, 'id_sede': id_sede,
            'id_direccion': id_direccion, 'tipo_entrega': entrega['tipo'], 'direccion_entrega': direccion_texto,
            'estado': estado, 'metodo_pago': pedido['metodo_pago'], 'subtotal': subtotal, 'descuento': descuento,
            'costo_envio': costo_envio, 'total': subtotal - descuento + costo_envio,
        })
        for linea in lineas:
            rx = productos[linea['id_producto']]['requiere_formula']
            id_item = repo.insertar_item(cur, id_pedido, linea, id_formula if rx else None)
            for asignacion in asignaciones[linea['id_producto']]:
                repo.descontar_lote(cur, id_pedido, id_item, asignacion, f'Pedido {codigo} (tienda en línea)')
        repo.insertar_historial(cur, id_pedido, estado,
                                'Pedido creado; un farmacéutico debe aprobar la fórmula médica' if requiere_formula
                                else 'Pedido creado en la tienda en línea')
    return codigo


# ---------------------------------------------------------------- lectura para la confirmación y el recibo
def _pasos(tipo_entrega, estado, historial):
    """Línea de tiempo del seguimiento: cada paso del camino, si ya ocurrió y cuándo (según pedido_historial)."""
    fechas = {}
    for evento in historial:
        fechas.setdefault(evento['estado'], evento['fecha_texto'])
    camino = list(CAMINO[tipo_entrega])
    if 'PENDIENTE_FORMULA' in fechas or estado == 'PENDIENTE_FORMULA':
        camino.insert(0, 'PENDIENTE_FORMULA')
    if estado == 'CANCELADO':
        camino = [e for e in camino if e in fechas] + ['CANCELADO']
    actual = camino.index(estado) if estado in camino else -1
    return [{'estado': e, 'texto': ESTADOS[e], 'hecho': i <= actual, 'actual': i == actual,
             'fecha_texto': fechas.get(e)} for i, e in enumerate(camino)]


def detalle(codigo):
    """Pedido ya confirmado, tal como quedó guardado en MySQL (nunca desde el carrito)."""
    fila = repo.pedido_por_codigo(codigo)
    if not fila:
        return None
    items = []
    for item in repo.items_de_pedido(fila['id_pedido']):
        precio, descuento = _pesos(item['precio_unitario']), _pesos(item['descuento_unitario'])
        items.append({'nombre': item['nombre'], 'presentacion': item['presentacion'],
                      'requiere_formula': bool(item['requiere_formula']), 'cantidad': item['cantidad'],
                      'precio_unitario': precio, 'descuento_unitario': descuento,
                      'subtotal': precio * item['cantidad']})
    historial = [{'estado': h['estado'], 'estado_texto': ESTADOS.get(h['estado'], h['estado']),
                  'comentario': h['comentario'], 'fecha_texto': tienda_info.fecha_hora_texto(h['created_at'])}
                 for h in repo.historial_de_pedido(fila['id_pedido'])]
    return {
        'pasos': _pasos(fila['tipo_entrega'], fila['estado'], historial),
        'codigo': fila['codigo'],
        'fecha_texto': tienda_info.fecha_hora_texto(fila['created_at']),
        'estado': fila['estado'],
        'estado_texto': ESTADOS.get(fila['estado'], fila['estado']),
        'cliente': {'nombre': f"{fila['nombres']} {fila['apellidos']}",
                    'documento': f"{fila['tipo_documento']} {fila['numero_documento']}"},
        'tipo_entrega': fila['tipo_entrega'],
        'direccion_entrega': fila['direccion_entrega'],
        'sede': {'nombre': fila['sede'], 'direccion': fila['sede_direccion']},
        'metodo_pago': METODOS_PAGO.get(fila['metodo_pago'], fila['metodo_pago']),
        'items': items,
        'subtotal': _pesos(fila['subtotal']),
        'descuento': _pesos(fila['descuento']),
        'costo_envio': _pesos(fila['costo_envio']),
        'total': _pesos(fila['total']),
        'historial': historial,
        'drogueria': tienda_info.datos_drogueria(),
    }


def documento_coincide(codigo, tipo_documento, numero_documento):
    numero = re.sub(r'[\s.]', '', numero_documento or '')
    return tipo_documento in TIPOS_DOCUMENTO and bool(numero) and repo.documento_coincide(codigo, tipo_documento, numero)
