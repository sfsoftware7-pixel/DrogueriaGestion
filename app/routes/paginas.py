"""Rutas que entregan las páginas HTML. Los datos se cargan desde JavaScript vía /api."""
from flask import Blueprint, abort, g, redirect, render_template, request, url_for

from ..db import consultar, consultar_uno
from ..seguridad import login_requerido, permiso_requerido

bp = Blueprint('paginas', __name__)


@bp.get('/login')
def login():
    if g.get('usuario'):
        return redirect(url_for('paginas.inicio'))
    siguiente = request.args.get('siguiente', '')
    # Solo se permiten redirecciones internas para evitar redirecciones abiertas
    if not siguiente.startswith('/') or siguiente.startswith('//'):
        siguiente = ''
    return render_template('login.html', siguiente=siguiente)


@bp.get('/')
@login_requerido
def inicio():
    return render_template('dashboard.html', pagina='dashboard')


@bp.get('/medicamentos')
@permiso_requerido('medicamentos.ver')
def medicamentos():
    return render_template('medicamentos.html', pagina='medicamentos')


@bp.get('/categorias')
@permiso_requerido('medicamentos.ver')
def categorias():
    return render_template('categorias.html', pagina='categorias')


@bp.get('/inventario')
@permiso_requerido('inventario.ver')
def inventario():
    return render_template('inventario.html', pagina='inventario')


@bp.get('/vencimientos')
@permiso_requerido('inventario.ver')
def vencimientos():
    return render_template('vencimientos.html', pagina='vencimientos')


@bp.get('/proveedores')
@permiso_requerido('proveedores.ver')
def proveedores():
    return render_template('proveedores.html', pagina='proveedores')


@bp.get('/clientes')
@permiso_requerido('clientes.ver')
def clientes():
    return render_template('clientes.html', pagina='clientes')


@bp.get('/clientes/reporte-pais')
@permiso_requerido('clientes.ver')
def reporte_clientes_pais():
    filas = consultar(
        '''SELECT id_cliente, tipo_documento, numero_documento, nombres, apellidos, ciudad,
                  COALESCE(NULLIF(TRIM(pais), ''), 'Sin especificar') AS pais
             FROM clientes
            WHERE id_cliente <> %s
            ORDER BY pais, nombres, apellidos, id_cliente''',
        (1,),
    )
    grupos = {}
    for cliente in filas:
        grupos.setdefault(cliente['pais'], []).append(cliente)
    return render_template('clientes_reporte_pais.html', grupos=grupos, total=len(filas))


@bp.get('/ventas/nueva')
@permiso_requerido('ventas.crear')
def nueva_venta():
    return render_template('pos.html', pagina='pos')


@bp.get('/ventas')
@permiso_requerido('ventas.ver')
def ventas():
    return render_template('ventas.html', pagina='ventas')


@bp.get('/pedidos')
@permiso_requerido('ventas.ver')
def pedidos_tienda():
    return render_template('pedidos_tienda.html', pagina='pedidos_tienda')


@bp.get('/ventas/<int:id_venta>/comprobante')
@permiso_requerido('ventas.ver')
def comprobante(id_venta):
    venta = consultar_uno('SELECT * FROM v_ventas WHERE id_venta = %s', (id_venta,))
    if not venta:
        abort(404)
    detalle = consultar(
        '''SELECT d.cantidad, d.precio_unitario, d.iva_porcentaje, d.subtotal, d.impuesto,
                  m.nombre, m.concentracion, l.numero_lote, l.fecha_vencimiento
             FROM detalle_venta d
             JOIN medicamentos m ON m.id_medicamento = d.id_medicamento
             JOIN lotes l ON l.id_lote = d.id_lote
            WHERE d.id_venta = %s ORDER BY d.id_detalle_venta''',
        (id_venta,),
    )
    config = {f['clave']: f['valor'] for f in consultar('SELECT clave, valor FROM configuracion')}
    return render_template('comprobante.html', venta=venta, detalle=detalle, config=config)


@bp.get('/reportes')
@permiso_requerido('reportes.ver')
def reportes():
    return render_template('reportes.html', pagina='reportes')


@bp.get('/analisis-abc')
@permiso_requerido('analisis_abc.ver')
def analisis_abc():
    return render_template('analisis_abc.html', pagina='analisis_abc')


@bp.get('/consultas-sql')
@permiso_requerido('consultas.ver')
def consultas_sql():
    return render_template('consultas.html', pagina='consultas')


@bp.get('/modelo-datos')
@permiso_requerido('modelo.ver')
def modelo_datos():
    return render_template('modelo.html', pagina='modelo')


@bp.get('/usuarios')
@permiso_requerido('usuarios.administrar')
def usuarios():
    return render_template('usuarios.html', pagina='usuarios')


@bp.get('/auditoria')
@permiso_requerido('auditoria.ver')
def auditoria():
    return render_template('auditoria.html', pagina='auditoria')


@bp.get('/configuracion')
@permiso_requerido('configuracion.editar')
def configuracion():
    return render_template('configuracion.html', pagina='configuracion')


@bp.get('/perfil')
@login_requerido
def perfil():
    return render_template('perfil.html', pagina='perfil')
