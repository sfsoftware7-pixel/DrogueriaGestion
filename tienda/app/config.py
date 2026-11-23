"""Configuración leída desde tienda/.env (las credenciales nunca van en el código)."""
import os
import secrets

from dotenv import load_dotenv

CARPETA_TIENDA = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(CARPETA_TIENDA, '.env'))


class Config:
    # Si falta, se genera una clave temporal (las sesiones se pierden al reiniciar).
    SECRET_KEY = os.getenv('SECRET_KEY') or secrets.token_hex(32)

    DB_HOST = os.getenv('DB_HOST', '127.0.0.1')
    DB_PORT = int(os.getenv('DB_PORT', '3306'))
    DB_NAME = os.getenv('DB_NAME', 'drogueria_db')
    DB_USER = os.getenv('DB_USER', '')
    DB_PASSWORD = os.getenv('DB_PASSWORD', '')

    # La fórmula médica admite hasta 5 MB; el resto del formulario de pago es pequeño
    MAX_CONTENT_LENGTH = 6 * 1024 * 1024
    # La sesión solo guarda los códigos de los pedidos que esta persona puede ver
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'


def variables_faltantes(config):
    """Variables de .env sin valor que impiden conectarse a MySQL."""
    return [nombre for nombre in ('DB_HOST', 'DB_NAME', 'DB_USER') if not config.get(nombre)]
