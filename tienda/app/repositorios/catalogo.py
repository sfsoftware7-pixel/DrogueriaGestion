"""Consultas SQL del catálogo. Todas usan parámetros %s: ningún dato del usuario se concatena al SQL."""
from ..db import consultar

# Expresión del descuento por unidad de una promoción (pesos colombianos, sin decimales)
_DESCUENTO = """CASE pr.tipo_descuento
                    WHEN 'PORCENTAJE' THEN ROUND(p2.precio * pr.valor_descuento / 100, 0)
                    ELSE LEAST(pr.valor_descuento, p2.precio)
                END"""

# Mejor promoción vigente de cada producto (una fila por producto)
_MEJOR_PROMOCION = f"""
    SELECT id_producto, descuento, promocion FROM (
        SELECT pp.id_producto,
               {_DESCUENTO} AS descuento,
               pr.nombre AS promocion,
               ROW_NUMBER() OVER (PARTITION BY pp.id_producto ORDER BY {_DESCUENTO} DESC, pr.id_promocion) AS puesto
          FROM promocion_producto pp
          JOIN promociones pr ON pr.id_promocion = pp.id_promocion
          JOIN productos p2   ON p2.id_producto = pp.id_producto
         WHERE pr.activo = 1 AND NOW() BETWEEN pr.fecha_inicio AND pr.fecha_fin
    ) candidatas
    WHERE puesto = 1"""

# Existencias vendibles: lotes sin vencer de las sedes activas (la misma regla que aplica el pedido)
STOCK_PRODUCTO = """COALESCE((
        SELECT SUM(i.cantidad)
          FROM inventario i
          JOIN lotes lo ON lo.id_lote = i.id_lote
          JOIN sedes s  ON s.id_sede = i.id_sede
         WHERE lo.id_producto = p.id_producto AND lo.fecha_vencimiento >= CURDATE() AND s.activo = 1
    ), 0)"""

_COLUMNAS_PRODUCTO = f"""
    p.id_producto, p.nombre, p.slug, p.presentacion, p.precio, p.requiere_formula,
    c.nombre AS categoria, l.nombre AS laboratorio,
    COALESCE(mp.descuento, 0) AS descuento, mp.promocion,
    {STOCK_PRODUCTO} AS stock"""

_FROM_PRODUCTO = f"""
      FROM productos p
      JOIN categorias c   ON c.id_categoria = p.id_categoria
      JOIN laboratorios l ON l.id_laboratorio = p.id_laboratorio
      LEFT JOIN ({_MEJOR_PROMOCION}) mp ON mp.id_producto = p.id_producto"""


def categorias_principales():
    """Categorías activas de primer nivel con el número de productos activos (incluye subcategorías)."""
    return consultar(
        """SELECT c.id_categoria, c.nombre, c.slug, c.descripcion, c.icono,
                  (SELECT COUNT(*)
                     FROM productos p
                     JOIN categorias h ON h.id_categoria = p.id_categoria
                    WHERE p.activo = 1
                      AND (h.id_categoria = c.id_categoria OR h.id_categoria_padre = c.id_categoria)
                  ) AS total_productos
             FROM categorias c
            WHERE c.activo = 1 AND c.id_categoria_padre IS NULL
            ORDER BY c.orden, c.nombre"""
    )


def productos_destacados(limite):
    """Productos marcados como destacados o con una promoción vigente."""
    return consultar(
        f"""SELECT {_COLUMNAS_PRODUCTO}
            {_FROM_PRODUCTO}
            WHERE p.activo = 1 AND (p.destacado = 1 OR mp.id_producto IS NOT NULL)
            ORDER BY p.destacado DESC, descuento DESC, p.nombre
            LIMIT %s""",
        (limite,),
    )


def productos_en_promocion(limite):
    """Solo productos con una promoción vigente, del mayor al menor descuento relativo."""
    return consultar(
        f"""SELECT {_COLUMNAS_PRODUCTO}
            {_FROM_PRODUCTO}
            WHERE p.activo = 1 AND mp.id_producto IS NOT NULL
            ORDER BY mp.descuento / p.precio DESC, p.nombre
            LIMIT %s""",
        (limite,),
    )


def buscar_productos(termino_fulltext, prefijo_like, contiene_like, limite):
    """Búsqueda para el autocompletado.

    Une cuatro fuentes: FULLTEXT en nombre y descripción, prefijo del nombre (ix_productos_nombre), el nombre
    que contiene el texto (para nombres incompletos: "minofen") y el nombre del principio activo. La
    intercalación utf8mb4_unicode_ci ignora tildes y mayúsculas ("acetaminofen" encuentra "Acetaminofén").
    Si el término FULLTEXT está vacío (palabras de menos de 3 letras, el mínimo de InnoDB), esa rama se omite.
    """
    ramas, params = [], []
    if termino_fulltext:
        ramas.append("""SELECT id_producto, 1 + MATCH(nombre, descripcion) AGAINST (%s IN BOOLEAN MODE) AS puntaje
                          FROM productos
                         WHERE MATCH(nombre, descripcion) AGAINST (%s IN BOOLEAN MODE)""")
        params += [termino_fulltext, termino_fulltext]
    ramas.append("SELECT id_producto, 3 AS puntaje FROM productos WHERE nombre LIKE %s")
    params.append(prefijo_like)
    ramas.append("SELECT id_producto, 0.8 AS puntaje FROM productos WHERE nombre LIKE %s")
    params.append(contiene_like)
    ramas.append("""SELECT ppa.id_producto, 0.5 AS puntaje
                      FROM producto_principio_activo ppa
                      JOIN principios_activos pa ON pa.id_principio_activo = ppa.id_principio_activo
                     WHERE pa.nombre LIKE %s""")
    params.append(contiene_like)

    return consultar(
        f"""SELECT {_COLUMNAS_PRODUCTO}
            {_FROM_PRODUCTO}
            JOIN (SELECT id_producto, MAX(puntaje) AS puntaje
                    FROM ({' UNION ALL '.join(ramas)}) coincidencias
                   GROUP BY id_producto) r ON r.id_producto = p.id_producto
            WHERE p.activo = 1
            ORDER BY r.puntaje DESC, p.nombre
            LIMIT %s""",
        (*params, limite),
    )


def productos_por_ids(ids):
    """Productos activos con su precio vigente y existencias (página del carrito y chatbot)."""
    marcadores = ', '.join(['%s'] * len(ids))
    return consultar(
        f"""SELECT {_COLUMNAS_PRODUCTO}
            {_FROM_PRODUCTO}
            WHERE p.activo = 1 AND p.id_producto IN ({marcadores})
            ORDER BY p.nombre""",
        tuple(ids),
    )


def stock_por_sede(ids):
    """Existencias vendibles de cada producto en cada sede activa (las sedes sin unidades no aparecen)."""
    marcadores = ', '.join(['%s'] * len(ids))
    return consultar(
        f"""SELECT lo.id_producto, i.id_sede, SUM(i.cantidad) AS stock
              FROM inventario i
              JOIN lotes lo ON lo.id_lote = i.id_lote
              JOIN sedes s  ON s.id_sede = i.id_sede
             WHERE lo.id_producto IN ({marcadores}) AND lo.fecha_vencimiento >= CURDATE() AND s.activo = 1
             GROUP BY lo.id_producto, i.id_sede""",
        tuple(ids),
    )


def sedes_activas():
    return consultar(
        """SELECT s.id_sede, s.nombre, s.direccion, s.permite_retiro, c.nombre AS ciudad
             FROM sedes s
             JOIN ciudades c ON c.id_ciudad = s.id_ciudad
            WHERE s.activo = 1
            ORDER BY s.id_sede"""
    )


def banners_vigentes(limite=5):
    """Promociones vigentes marcadas para el banner rotativo de inicio."""
    return consultar(
        """SELECT id_promocion, titulo_banner, subtitulo_banner, tipo_descuento, valor_descuento
             FROM promociones
            WHERE activo = 1 AND mostrar_en_banner = 1 AND NOW() BETWEEN fecha_inicio AND fecha_fin
            ORDER BY fecha_inicio DESC, id_promocion
            LIMIT %s""",
        (limite,),
    )
