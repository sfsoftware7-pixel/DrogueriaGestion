"""API del modelo de datos en vivo: lee information_schema de la base actual.

Devuelve tablas (agrupadas por área), columnas, llaves primarias y foráneas, índices, restricciones CHECK,
número de filas y los objetos programados (vistas, función, triggers y procedimientos).
Las filas se cuentan con COUNT(*) solo sobre nombres que vienen de information_schema, entre backticks.
"""
import re

import pymysql
from flask import Blueprint, jsonify

from ..db import consultar, get_db
from ..seguridad import permiso_requerido

bp = Blueprint('modelo', __name__)

# Áreas del modelo (CLAUDE.md, «Modelo de datos»). Una tabla nueva que no esté aquí aparece en «Otras».
AREAS = (
    ('Seguridad', ('roles', 'usuarios', 'configuracion', 'consecutivos', 'auditoria')),
    ('Catálogo', ('categorias', 'proveedores', 'medicamentos', 'historial_precios', 'clientes')),
    ('Inventario', ('entradas', 'lotes', 'detalle_entrada', 'movimientos_inventario')),
    ('Ventas', ('ventas', 'detalle_venta')),
)
NOMBRE_SEGURO = re.compile(r'^[A-Za-z0-9_$]+$')

SQL_TABLAS = '''SELECT TABLE_NAME AS nombre, TABLE_TYPE AS tipo, ENGINE AS motor, TABLE_COMMENT AS comentario
                  FROM information_schema.TABLES
                 WHERE TABLE_SCHEMA = DATABASE()
                 ORDER BY TABLE_NAME'''

SQL_COLUMNAS = '''SELECT TABLE_NAME AS tabla, COLUMN_NAME AS nombre, COLUMN_TYPE AS tipo, IS_NULLABLE AS nulo,
                         COLUMN_KEY AS clave, COLUMN_DEFAULT AS predeterminado, EXTRA AS extra,
                         COLUMN_COMMENT AS comentario
                    FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE()
                   ORDER BY TABLE_NAME, ORDINAL_POSITION'''

SQL_LLAVES_FORANEAS = '''SELECT k.TABLE_NAME AS tabla, k.COLUMN_NAME AS columna, k.CONSTRAINT_NAME AS nombre,
                                k.REFERENCED_TABLE_NAME AS tabla_referida, k.REFERENCED_COLUMN_NAME AS columna_referida,
                                r.UPDATE_RULE AS al_actualizar, r.DELETE_RULE AS al_borrar
                           FROM information_schema.KEY_COLUMN_USAGE k
                           JOIN information_schema.REFERENTIAL_CONSTRAINTS r
                             ON r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME
                          WHERE k.TABLE_SCHEMA = DATABASE() AND k.REFERENCED_TABLE_NAME IS NOT NULL
                          ORDER BY k.TABLE_NAME, k.CONSTRAINT_NAME, k.ORDINAL_POSITION'''

SQL_INDICES = '''SELECT TABLE_NAME AS tabla, INDEX_NAME AS nombre, NON_UNIQUE AS no_unico, INDEX_TYPE AS tipo,
                        GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ', ') AS columnas
                   FROM information_schema.STATISTICS
                  WHERE TABLE_SCHEMA = DATABASE()
                  GROUP BY TABLE_NAME, INDEX_NAME, NON_UNIQUE, INDEX_TYPE
                  ORDER BY TABLE_NAME, INDEX_NAME = 'PRIMARY' DESC, INDEX_NAME'''

SQL_CHECKS = '''SELECT t.TABLE_NAME AS tabla, c.CONSTRAINT_NAME AS nombre, c.CHECK_CLAUSE AS condicion
                  FROM information_schema.CHECK_CONSTRAINTS c
                  JOIN information_schema.TABLE_CONSTRAINTS t
                    ON t.CONSTRAINT_SCHEMA = c.CONSTRAINT_SCHEMA AND t.CONSTRAINT_NAME = c.CONSTRAINT_NAME
                   AND t.CONSTRAINT_TYPE = 'CHECK'
                 WHERE c.CONSTRAINT_SCHEMA = DATABASE()
                 ORDER BY t.TABLE_NAME, c.CONSTRAINT_NAME'''

# Lo que el usuario de la aplicación ve directamente (sin el procedimiento de 04_mejoras.sql)
SQL_RUTINAS_VISIBLES = '''SELECT ROUTINE_NAME AS nombre, ROUTINE_TYPE AS tipo, DTD_IDENTIFIER AS retorna,
                                 SECURITY_TYPE AS seguridad, ROUTINE_COMMENT AS comentario, NULL AS definicion
                            FROM information_schema.ROUTINES
                           WHERE ROUTINE_SCHEMA = DATABASE()
                           ORDER BY ROUTINE_TYPE, ROUTINE_NAME'''
SQL_TRIGGERS_VISIBLES = '''SELECT TRIGGER_NAME AS nombre, EVENT_OBJECT_TABLE AS tabla, ACTION_TIMING AS momento,
                                  EVENT_MANIPULATION AS evento, NULL AS definicion
                             FROM information_schema.TRIGGERS
                            WHERE TRIGGER_SCHEMA = DATABASE()
                            ORDER BY EVENT_OBJECT_TABLE, TRIGGER_NAME'''
SQL_VISTAS_VISIBLES = '''SELECT TABLE_NAME AS nombre, NULL AS definicion
                           FROM information_schema.VIEWS
                          WHERE TABLE_SCHEMA = DATABASE()
                          ORDER BY TABLE_NAME'''


def area_de(tabla):
    for area, tablas in AREAS:
        if tabla in tablas:
            return area
    return 'Otras'


def contar_filas(nombres):
    """COUNT(*) por tabla. Los nombres salen de information_schema y además se validan antes de usarlos."""
    conteos = {}
    with get_db().cursor() as cur:
        for nombre in nombres:
            if not NOMBRE_SEGURO.match(nombre):
                continue
            cur.execute(f'SELECT COUNT(*) AS filas FROM `{nombre}`')
            conteos[nombre] = cur.fetchone()['filas']
    return conteos


def objetos_programados():
    """Triggers, rutinas y vistas. Con sp_modelo_objetos (SQL SECURITY DEFINER, de 04_mejoras.sql) llegan con
    su definición; sin él, solo lo que information_schema le muestra al usuario de la aplicación."""
    visibles = {'triggers': len(consultar(SQL_TRIGGERS_VISIBLES))}
    try:
        with get_db().cursor() as cur:
            cur.execute('CALL sp_modelo_objetos()')
            triggers = cur.fetchall()
            cur.nextset()
            rutinas = cur.fetchall()
            cur.nextset()
            vistas = cur.fetchall()
            while cur.nextset():
                pass
        fuente = 'sp_modelo_objetos'
    except pymysql.err.MySQLError as error:
        if not error.args or error.args[0] != 1305:  # 1305: el procedimiento no existe (falta 04_mejoras.sql)
            raise
        triggers = consultar(SQL_TRIGGERS_VISIBLES)
        rutinas = consultar(SQL_RUTINAS_VISIBLES)
        vistas = consultar(SQL_VISTAS_VISIBLES)
        fuente = 'information_schema'
    return {'fuente': fuente, 'visibles_sin_procedimiento': visibles,
            'triggers': triggers, 'rutinas': rutinas, 'vistas': vistas}


@bp.get('/modelo')
@permiso_requerido('modelo.ver')
def modelo():
    tablas = consultar(SQL_TABLAS)
    columnas = consultar(SQL_COLUMNAS)
    foraneas = consultar(SQL_LLAVES_FORANEAS)
    indices = consultar(SQL_INDICES)
    checks = consultar(SQL_CHECKS)
    base = [t for t in tablas if t['tipo'] == 'BASE TABLE']
    filas = contar_filas([t['nombre'] for t in base])

    def de(lista, tabla):
        return [{k: v for k, v in fila.items() if k != 'tabla'} for fila in lista if fila['tabla'] == tabla]

    resultado = []
    for t in base:
        nombre = t['nombre']
        resultado.append({
            'nombre': nombre,
            'area': area_de(nombre),
            'motor': t['motor'],
            'comentario': t['comentario'],
            'filas': filas.get(nombre),
            'columnas': de(columnas, nombre),
            'llaves_foraneas': de(foraneas, nombre),
            'referida_por': [{'tabla': f['tabla'], 'columna': f['columna'], 'columna_referida': f['columna_referida']}
                             for f in foraneas if f['tabla_referida'] == nombre],
            'indices': [{**i, 'unico': not i['no_unico']} for i in de(indices, nombre)],
            'checks': de(checks, nombre),
        })

    orden_areas = [a for a, _ in AREAS] + ['Otras']
    posicion = {tabla: i for _, tablas in AREAS for i, tabla in enumerate(tablas)}
    resultado.sort(key=lambda t: (orden_areas.index(t['area']), posicion.get(t['nombre'], 99), t['nombre']))

    return jsonify({
        'base_datos': get_db().db.decode() if isinstance(get_db().db, bytes) else get_db().db,
        'areas': orden_areas,
        'tablas': resultado,
        'relaciones': foraneas,
        'objetos': objetos_programados(),
    })
