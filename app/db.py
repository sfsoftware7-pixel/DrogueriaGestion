"""Acceso a MySQL con PyMySQL: una conexión por petición y consultas parametrizadas."""
from contextlib import contextmanager

import pymysql
from flask import current_app, g
from pymysql.cursors import DictCursor


def conectar(config, database=True):
    """Abre una conexión nueva usando la configuración indicada."""
    return pymysql.connect(
        host=config['DB_HOST'],
        port=config['DB_PORT'],
        user=config['DB_USER'],
        password=config['DB_PASSWORD'],
        database=config['DB_NAME'] if database else None,
        charset='utf8mb4',
        cursorclass=DictCursor,
        autocommit=True,
    )


def get_db():
    """Devuelve la conexión de la petición actual (la crea si no existe)."""
    if 'db' not in g:
        g.db = conectar(current_app.config)
        usuario = g.get('usuario')
        if usuario:
            asignar_usuario_sesion(g.db, usuario['id_usuario'])
    return g.db


def asignar_usuario_sesion(conn, id_usuario):
    """Variable de sesión MySQL que usan los triggers para saber quién hizo el cambio."""
    with conn.cursor() as cur:
        cur.execute('SET @app_id_usuario = %s', (id_usuario,))


def cerrar_db(_exc=None):
    conn = g.pop('db', None)
    if conn is not None:
        conn.close()


def init_app(app):
    app.teardown_appcontext(cerrar_db)


def consultar(sql, params=None):
    """Ejecuta un SELECT y devuelve todas las filas como diccionarios."""
    with get_db().cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def consultar_uno(sql, params=None):
    """Ejecuta un SELECT y devuelve la primera fila (o None)."""
    with get_db().cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def ejecutar(sql, params=None):
    """Ejecuta INSERT/UPDATE/DELETE. Devuelve (lastrowid, filas_afectadas)."""
    with get_db().cursor() as cur:
        filas = cur.execute(sql, params)
        return cur.lastrowid, filas


@contextmanager
def transaccion():
    """Agrupa varias sentencias en una transacción: todo se confirma o nada."""
    conn = get_db()
    conn.begin()
    try:
        with conn.cursor() as cur:
            yield cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise


def paginar(sql, params, pagina, por_pagina, orden):
    """Ejecuta una consulta paginada. `sql` no debe incluir ORDER BY ni LIMIT."""
    total = consultar_uno(f'SELECT COUNT(*) AS total FROM ({sql}) AS t', params)['total']
    offset = (pagina - 1) * por_pagina
    filas = consultar(f'{sql} ORDER BY {orden} LIMIT %s OFFSET %s', (*params, por_pagina, offset))
    return {
        'datos': filas,
        'total': total,
        'pagina': pagina,
        'por_pagina': por_pagina,
        'paginas': max(1, -(-total // por_pagina)),
    }
