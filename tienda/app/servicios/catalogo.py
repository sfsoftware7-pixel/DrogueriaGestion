"""Reglas del catálogo: precio con la mejor promoción vigente y preparación de la búsqueda."""
import re
from decimal import ROUND_HALF_UP, Decimal

from ..repositorios import catalogo as repo

# Para el término FULLTEXT solo se toman palabras alfanuméricas (letras con tilde incluidas): así ningún
# operador del modo booleano (+ - < > ( ) ~ * " @) ni signo suelto llega a MySQL desde el texto del usuario.
_PALABRA = re.compile(r'\w+')
MIN_TOKEN_FULLTEXT = 3  # innodb_ft_min_token_size por defecto


def _pesos(valor):
    """DECIMAL de MySQL -> entero en pesos colombianos (los precios no llevan centavos)."""
    return int(Decimal(valor).quantize(Decimal('1'), rounding=ROUND_HALF_UP))


def _producto(fila):
    precio = _pesos(fila['precio'])
    descuento = _pesos(fila['descuento'])
    tiene_oferta = 0 < descuento < precio
    return {
        'id': fila['id_producto'],
        'nombre': fila['nombre'],
        'slug': fila['slug'],
        'presentacion': fila['presentacion'],
        'categoria': fila['categoria'],
        'laboratorio': fila['laboratorio'],
        'requiere_formula': bool(fila['requiere_formula']),
        'precio': precio,
        'precio_oferta': precio - descuento if tiene_oferta else None,
        'descuento_porcentaje': round(descuento * 100 / precio) if tiene_oferta else None,
        'promocion': fila['promocion'] if tiene_oferta else None,
        'stock': int(fila['stock']),
    }


def listar_categorias():
    return [
        {
            'id': c['id_categoria'],
            'nombre': c['nombre'],
            'slug': c['slug'],
            'descripcion': c['descripcion'],
            'icono': c['icono'],
            'total_productos': int(c['total_productos']),
        }
        for c in repo.categorias_principales()
    ]


def categoria(slug):
    """Datos de una categoría activa para su página (sin productos), o None si no existe."""
    fila = repo.categoria_por_slug(slug)
    if not fila:
        return None
    return {
        'id': fila['id_categoria'],
        'nombre': fila['nombre'],
        'slug': fila['slug'],
        'descripcion': fila['descripcion'],
        'padre': {'nombre': fila['padre_nombre'], 'slug': fila['padre_slug']} if fila['padre_slug'] else None,
    }


def detalle_categoria(slug):
    """La categoría con sus productos (incluye los de sus subcategorías), o None si no existe."""
    datos = categoria(slug)
    if not datos:
        return None
    datos['productos'] = [_producto(f) for f in repo.productos_de_categoria(datos.pop('id'))]
    return datos


def listar_destacados(tipo, limite):
    filas = repo.productos_en_promocion(limite) if tipo == 'promocion' else repo.productos_destacados(limite)
    return [_producto(f) for f in filas]


def _escapar_like(texto):
    return texto.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')


def preparar_busqueda(texto):
    """Devuelve (término FULLTEXT booleano, prefijo LIKE, contiene LIKE) a partir del texto del usuario."""
    limpio = ' '.join(texto.split())
    palabras = [p for p in _PALABRA.findall(limpio) if len(p) >= MIN_TOKEN_FULLTEXT]
    # Cada palabra es obligatoria (+) y admite terminaciones (*): "acet" -> "+acet*"
    termino = ' '.join(f'+{p}*' for p in palabras)
    escapado = _escapar_like(limpio)
    return termino, f'{escapado}%', f'%{escapado}%'


def buscar(texto, limite):
    termino, prefijo, contiene = preparar_busqueda(texto)
    return [_producto(f) for f in repo.buscar_productos(termino, prefijo, contiene, limite)]


def productos_por_ids(ids):
    return [_producto(f) for f in repo.productos_por_ids(ids)]


def sedes():
    return [{'id': s['id_sede'], 'nombre': s['nombre'], 'direccion': s['direccion'], 'ciudad': s['ciudad'],
             'permite_retiro': bool(s['permite_retiro'])} for s in repo.sedes_activas()]


def disponibilidad(texto, limite=5):
    """Búsqueda del catálogo (la misma del autocompletado) con las existencias de cada sede activa."""
    productos = buscar(texto, limite)
    if not productos:
        return []
    por_sede = {(f['id_producto'], f['id_sede']): int(f['stock']) for f in repo.stock_por_sede([p['id'] for p in productos])}
    lista_sedes = sedes()
    for producto in productos:
        producto['sedes'] = [{'nombre': s['nombre'], 'ciudad': s['ciudad'], 'stock': por_sede.get((producto['id'], s['id']), 0)}
                             for s in lista_sedes]
    return productos


def _texto_descuento(fila):
    valor = Decimal(fila['valor_descuento'])
    if fila['tipo_descuento'] == 'PORCENTAJE':
        return f'-{_pesos(valor)} %'
    return '-$' + f'{_pesos(valor):,}'.replace(',', '.')


def banners_vigentes():
    return [
        {
            'id': b['id_promocion'],
            'titulo': b['titulo_banner'],
            'subtitulo': b['subtitulo_banner'],
            'etiqueta': _texto_descuento(b),
        }
        for b in repo.banners_vigentes()
    ]
