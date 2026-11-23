"""Configuración de la aplicación, leída desde variables de entorno (.env)."""
import os
import secrets
from datetime import timedelta

from dotenv import load_dotenv

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))


class Config:
    APP_NAME = 'DrogueriaGestión'
    APP_VERSION = '1.0.0'

    # Si no se define SECRET_KEY se genera una temporal (las sesiones se pierden al reiniciar).
    SECRET_KEY = os.getenv('SECRET_KEY') or secrets.token_hex(32)

    # Conexión MySQL del usuario de la aplicación (privilegios mínimos)
    DB_HOST = os.getenv('DB_HOST', '127.0.0.1')
    DB_PORT = int(os.getenv('DB_PORT', '3306'))
    DB_USER = os.getenv('DB_USER', 'drogueria_app')
    DB_PASSWORD = os.getenv('DB_PASSWORD', '')
    DB_NAME = os.getenv('DB_NAME', 'drogueria_gestion')
    # Esquema de pedidos de tienda (se consulta con permisos de solo lectura).
    TIENDA_DB_NAME = os.getenv('TIENDA_DB_NAME', 'drogueria_db')

    # Sesiones
    SESSION_COOKIE_NAME = 'drogueria_session'
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'
    SESSION_COOKIE_SECURE = os.getenv('SESSION_COOKIE_SECURE', '0') == '1'
    PERMANENT_SESSION_LIFETIME = timedelta(hours=8)
    MINUTOS_INACTIVIDAD = int(os.getenv('MINUTOS_INACTIVIDAD', '60'))

    # Protección contra fuerza bruta en el inicio de sesión
    MAX_INTENTOS_LOGIN = 5
    MINUTOS_BLOQUEO = 10

    JSON_SORT_KEYS = False
    MAX_CONTENT_LENGTH = 1 * 1024 * 1024


class TestConfig(Config):
    TESTING = True
    # Las pruebas escriben datos: nunca deben usar la BD real. Créela con:
    #   python database/init_db.py --bd drogueria_gestion_test
    DB_NAME = os.getenv('DB_NAME_TEST', 'drogueria_gestion_test')
    TIENDA_DB_NAME = os.getenv('TIENDA_DB_NAME_TEST', 'drogueria_db_test')
