"""API de categorías terapéuticas."""
from flask import Blueprint, jsonify, request

from ..db import consultar, consultar_uno, ejecutar
from ..seguridad import permiso_requerido
from ..utils import ApiError, Validador, auditar, datos_json

bp = Blueprint('categorias', __name__)


def _validar(datos):
    v = Validador(datos)
    c = {
        'nombre': v.texto('nombre', max_len=80, min_len=3),
        'descripcion': v.texto('descripcion', requerido=False, max_len=255),
    }
    v.validar()
    return c


@bp.get('/categorias')
@permiso_requerido('medicamentos.ver')
def listar():
    solo_activas = request.args.get('activas') == '1'
    filas = consultar(
        f'''SELECT c.id_categoria, c.nombre, c.descripcion, c.activo,
                   COUNT(m.id_medicamento) AS total_medicamentos,
                   COALESCE(SUM(s.stock_disponible), 0) AS unidades_disponibles
              FROM categorias c
              LEFT JOIN medicamentos m ON m.id_categoria = c.id_categoria AND m.activo = 1
              LEFT JOIN v_stock_medicamentos s ON s.id_medicamento = m.id_medicamento
             {'WHERE c.activo = 1' if solo_activas else ''}
             GROUP BY c.id_categoria
             ORDER BY c.nombre'''
    )
    return jsonify(filas)


@bp.post('/categorias')
@permiso_requerido('categorias.editar')
def crear():
    c = _validar(datos_json())
    id_nuevo, _ = ejecutar('INSERT INTO categorias (nombre, descripcion) VALUES (%s, %s)',
                           (c['nombre'], c['descripcion']))
    auditar('CREAR', 'categorias', f'Categoría {c["nombre"]}')
    return jsonify({'mensaje': 'Categoría creada', 'id_categoria': id_nuevo}), 201


@bp.put('/categorias/<int:id_categoria>')
@permiso_requerido('categorias.editar')
def actualizar(id_categoria):
    c = _validar(datos_json())
    if not consultar_uno('SELECT 1 FROM categorias WHERE id_categoria = %s', (id_categoria,)):
        raise ApiError('Categoría no encontrada', 404)
    ejecutar('UPDATE categorias SET nombre = %s, descripcion = %s WHERE id_categoria = %s',
             (c['nombre'], c['descripcion'], id_categoria))
    auditar('ACTUALIZAR', 'categorias', f'Categoría {c["nombre"]}')
    return jsonify({'mensaje': 'Categoría actualizada'})


@bp.patch('/categorias/<int:id_categoria>/estado')
@permiso_requerido('categorias.editar')
def cambiar_estado(id_categoria):
    activo = Validador(datos_json()).booleano('activo')
    categoria = consultar_uno('SELECT nombre FROM categorias WHERE id_categoria = %s', (id_categoria,))
    if not categoria:
        raise ApiError('Categoría no encontrada', 404)
    if not activo:
        en_uso = consultar_uno('SELECT COUNT(*) AS n FROM medicamentos WHERE id_categoria = %s AND activo = 1',
                               (id_categoria,))['n']
        if en_uso:
            raise ApiError(f'No se puede desactivar: tiene {en_uso} medicamento(s) activo(s)', 409)
    ejecutar('UPDATE categorias SET activo = %s WHERE id_categoria = %s', (activo, id_categoria))
    auditar('ACTIVAR' if activo else 'DESACTIVAR', 'categorias', f'Categoría {categoria["nombre"]}')
    return jsonify({'mensaje': 'Categoría activada' if activo else 'Categoría desactivada'})


@bp.delete('/categorias/<int:id_categoria>')
@permiso_requerido('categorias.editar')
def eliminar(id_categoria):
    # La llave foránea (ON DELETE RESTRICT) impide borrar categorías con medicamentos
    _, filas = ejecutar('DELETE FROM categorias WHERE id_categoria = %s', (id_categoria,))
    if not filas:
        raise ApiError('Categoría no encontrada', 404)
    auditar('ELIMINAR', 'categorias', f'Categoría #{id_categoria}')
    return jsonify({'mensaje': 'Categoría eliminada'})
