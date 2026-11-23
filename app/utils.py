"""Utilidades comunes: errores de la API, validación de entradas y auditoría."""
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

from flask import g, request

from .db import ejecutar

EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
DOS_DECIMALES = Decimal('0.01')


class ApiError(Exception):
    """Error controlado que se devuelve al cliente como JSON."""

    def __init__(self, mensaje, status=400, errores=None):
        super().__init__(mensaje)
        self.mensaje = mensaje
        self.status = status
        self.errores = errores or {}


def redondear(valor):
    return Decimal(valor).quantize(DOS_DECIMALES, rounding=ROUND_HALF_UP)


def pesos(valor, redondeo=ROUND_HALF_UP):
    """Formato de pesos colombianos sin decimales para mensajes: Decimal('12500.4') -> '$12.500'."""
    entero = Decimal(valor).quantize(Decimal('1'), rounding=redondeo)
    return '$' + f'{entero:,}'.replace(',', '.')


class Validador:
    """Valida y normaliza los datos recibidos, acumulando errores por campo."""

    def __init__(self, datos):
        self.datos = datos if isinstance(datos, dict) else {}
        self.errores = {}

    def _crudo(self, campo):
        valor = self.datos.get(campo)
        if isinstance(valor, str):
            valor = valor.strip()
            return valor if valor != '' else None
        return valor

    def _requerido(self, campo, valor, requerido):
        if valor is None:
            if requerido:
                self.errores[campo] = 'Este campo es obligatorio'
            return False
        return True

    def texto(self, campo, requerido=True, max_len=255, min_len=1, patron=None, mensaje_patron=None):
        valor = self._crudo(campo)
        if not self._requerido(campo, valor, requerido):
            return None
        valor = str(valor)
        if len(valor) < min_len:
            self.errores[campo] = f'Debe tener al menos {min_len} caracteres'
        elif len(valor) > max_len:
            self.errores[campo] = f'Máximo {max_len} caracteres'
        elif patron and not re.fullmatch(patron, valor):
            self.errores[campo] = mensaje_patron or 'Formato no válido'
        return valor

    def email(self, campo, requerido=False):
        valor = self.texto(campo, requerido=requerido, max_len=120)
        if valor and not EMAIL_RE.match(valor):
            self.errores[campo] = 'Correo electrónico no válido'
        return valor.lower() if valor else valor

    def entero(self, campo, requerido=True, minimo=None, maximo=None):
        valor = self._crudo(campo)
        if not self._requerido(campo, valor, requerido):
            return None
        try:
            if isinstance(valor, bool) or (isinstance(valor, float) and not valor.is_integer()):
                raise ValueError
            numero = int(valor)
        except (TypeError, ValueError):
            self.errores[campo] = 'Debe ser un número entero'
            return None
        if minimo is not None and numero < minimo:
            self.errores[campo] = f'Debe ser mayor o igual a {minimo}'
        elif maximo is not None and numero > maximo:
            self.errores[campo] = f'Debe ser menor o igual a {maximo}'
        return numero

    def decimal(self, campo, requerido=True, minimo=None, maximo=None):
        valor = self._crudo(campo)
        if not self._requerido(campo, valor, requerido):
            return None
        try:
            if isinstance(valor, bool):
                raise InvalidOperation
            numero = redondear(Decimal(str(valor)))
        except (InvalidOperation, ValueError):
            self.errores[campo] = 'Debe ser un valor numérico'
            return None
        if minimo is not None and numero < Decimal(str(minimo)):
            self.errores[campo] = f'Debe ser mayor o igual a {minimo}'
        elif maximo is not None and numero > Decimal(str(maximo)):
            self.errores[campo] = f'Debe ser menor o igual a {maximo}'
        return numero

    def fecha(self, campo, requerido=True):
        valor = self._crudo(campo)
        if not self._requerido(campo, valor, requerido):
            return None
        try:
            return date.fromisoformat(str(valor)[:10])
        except ValueError:
            self.errores[campo] = 'Fecha no válida (AAAA-MM-DD)'
            return None

    def booleano(self, campo):
        valor = self.datos.get(campo)
        if isinstance(valor, str):
            return valor.lower() in ('1', 'true', 'si', 'sí', 'on')
        return bool(valor)

    def opcion(self, campo, opciones, requerido=True, defecto=None):
        valor = self._crudo(campo)
        if valor is None:
            if defecto is not None:
                return defecto
            self._requerido(campo, valor, requerido)
            return None
        if all(isinstance(o, str) for o in opciones):
            valor = str(valor)
        if valor not in opciones:
            self.errores[campo] = 'Opción no válida'
            return None
        return valor

    def lista(self, campo, minimo=1):
        valor = self.datos.get(campo)
        if not isinstance(valor, list) or len(valor) < minimo:
            self.errores[campo] = f'Debe incluir al menos {minimo} elemento(s)'
            return []
        return valor

    def error(self, campo, mensaje):
        self.errores[campo] = mensaje

    def validar(self):
        if self.errores:
            raise ApiError('Revise los datos ingresados', 422, self.errores)


def datos_json():
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        raise ApiError('Se esperaba un cuerpo JSON válido', 400)
    return datos


def parametros_paginacion(por_defecto=15, maximo=100):
    try:
        pagina = max(1, int(request.args.get('pagina', 1)))
        por_pagina = min(maximo, max(1, int(request.args.get('por_pagina', por_defecto))))
    except ValueError:
        pagina, por_pagina = 1, por_defecto
    return pagina, por_pagina


def parametro_fecha(nombre, defecto=None):
    valor = request.args.get(nombre)
    if not valor:
        return defecto
    try:
        return date.fromisoformat(valor)
    except ValueError:
        raise ApiError(f'El parámetro "{nombre}" debe tener formato AAAA-MM-DD')


def patron_busqueda(texto):
    """Escapa los comodines de LIKE para buscar el texto literal."""
    texto = texto.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
    return f'%{texto}%'


def auditar(accion, modulo, descripcion=None, id_usuario=None):
    """Registra una acción en la bitácora de auditoría."""
    usuario = g.get('usuario')
    ejecutar(
        'INSERT INTO auditoria (id_usuario, accion, modulo, descripcion, ip) VALUES (%s, %s, %s, %s, %s)',
        (id_usuario or (usuario['id_usuario'] if usuario else None), accion, modulo,
         (descripcion or '')[:255], request.remote_addr if request else None),
    )


def a_json(valor):
    """Convierte tipos de MySQL (Decimal, fechas) a tipos serializables."""
    if isinstance(valor, Decimal):
        return float(valor)
    if isinstance(valor, datetime):
        return valor.strftime('%Y-%m-%dT%H:%M:%S')
    if isinstance(valor, date):
        return valor.isoformat()
    return valor
