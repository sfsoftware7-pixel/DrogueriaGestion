"""Acceso a MySQL con PyMySQL: una conexión por petición y consultas siempre parametrizadas."""
from contextlib import contextmanager

import pymysql
from flask import current_app, g
from pymysql.cursors import DictCursor


def obtener_conexion():
    """Devuelve la conexión de la petición actual (la abre la primera vez)."""
    if 'db' not in g:
        cfg = current_app.config
        g.db = pymysql.connect(
            host=cfg['DB_HOST'],
            port=cfg['DB_PORT'],
            user=cfg['DB_USER'],
            password=cfg['DB_PASSWORD'],
            database=cfg['DB_NAME'],
            charset='utf8mb4',
            cursorclass=DictCursor,
            autocommit=True,
            connect_timeout=5,
            read_timeout=10,
        )
    return g.db


def consultar(sql, params=()):
    """Ejecuta un SELECT con parámetros %s y devuelve las filas como diccionarios."""
    with obtener_conexion().cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


@contextmanager
def transaccion():
    """Bloque con varias escrituras: confirma todo al salir o deshace todo si hay un error."""
    conexion = obtener_conexion()
    conexion.begin()
    try:
        with conexion.cursor() as cur:
            yield cur
        conexion.commit()
    except BaseException:
        conexion.rollback()
        raise


def cerrar_conexion(_error=None):
    conexion = g.pop('db', None)
    if conexion is not None:
        conexion.close()


def init_app(app):
    app.teardown_appcontext(cerrar_conexion)
