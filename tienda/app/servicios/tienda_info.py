"""Datos editables de la droguería (tienda/datos_tienda.toml): horario, zonas de domicilio, pago y contacto.

El archivo se relee cuando cambia su fecha de modificación, así una edición se aplica sin reiniciar.
"""
import os
import re
import threading
import tomllib
import unicodedata
from datetime import datetime, timedelta, timezone

from ..config import CARPETA_TIENDA

RUTA = os.path.join(CARPETA_TIENDA, 'datos_tienda.toml')

DIAS = ('lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo')
NOMBRE_DIA = {'lunes': 'Lunes', 'martes': 'Martes', 'miercoles': 'Miércoles', 'jueves': 'Jueves',
              'viernes': 'Viernes', 'sabado': 'Sábado', 'domingo': 'Domingo'}
MESES = ('enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre',
         'octubre', 'noviembre', 'diciembre')

_bloqueo = threading.Lock()
_cache = {'mtime': None, 'datos': None}


def datos():
    """Contenido del TOML (se relee solo si el archivo cambió)."""
    mtime = os.path.getmtime(RUTA)
    with _bloqueo:
        if _cache['mtime'] != mtime:
            with open(RUTA, 'rb') as archivo:
                _cache['datos'] = tomllib.load(archivo)
            _cache['mtime'] = mtime
        return _cache['datos']


# ---------------------------------------------------------------- hora de Colombia
def zona_horaria():
    """America/Bogota. En Windows sin el paquete tzdata, ZoneInfo no la encuentra: Colombia usa UTC-5 fijo
    (sin horario de verano desde 1993), así que el respaldo da la misma hora."""
    nombre = datos()['drogueria'].get('zona_horaria', 'America/Bogota')
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo(nombre)
    except Exception:  # ZoneInfoNotFoundError o módulo sin base de zonas
        return timezone(timedelta(hours=-5), nombre)


def ahora():
    return datetime.now(zona_horaria())


def hora_texto(hhmm):
    """"21:00" -> "9:00 p. m." (formato de Colombia)."""
    hora, minuto = (int(x) for x in hhmm.split(':'))
    sufijo = 'a. m.' if hora < 12 else 'p. m.'
    return f'{(hora % 12) or 12}:{minuto:02d} {sufijo}'


def fecha_hora_texto(momento):
    """datetime -> "21 de noviembre de 2026, 3:05 p. m."."""
    return f'{momento.day} de {MESES[momento.month - 1]} de {momento.year}, {hora_texto(momento.strftime("%H:%M"))}'


def estado_horario(momento=None):
    """Horario de cada día y si la droguería está abierta en este momento (hora de Colombia)."""
    momento = momento or ahora()
    horario = datos()['horario']
    dias = []
    for dia in DIAS:
        franja = horario.get(dia, {})
        if franja.get('cerrado'):
            dias.append({'dia': NOMBRE_DIA[dia], 'abre': None, 'cierra': None, 'texto': 'Cerrado'})
        else:
            dias.append({'dia': NOMBRE_DIA[dia], 'abre': franja['abre'], 'cierra': franja['cierra'],
                         'texto': f"{hora_texto(franja['abre'])} a {hora_texto(franja['cierra'])}"})

    hoy = dias[momento.weekday()]
    actual = momento.strftime('%H:%M')
    abierto = bool(hoy['abre']) and hoy['abre'] <= actual < hoy['cierra']
    # Las horas terminan en "a. m." o "p. m.": las frases no agregan otro punto final
    if abierto:
        resumen = f"Estamos abiertos: hoy atendemos hasta las {hora_texto(hoy['cierra'])}"
    elif hoy['abre'] and actual < hoy['abre']:
        resumen = f"Ahora estamos cerrados. Hoy abrimos a las {hora_texto(hoy['abre'])}"
    else:
        resumen = 'Ahora estamos cerrados.'
        for desplazamiento in range(1, 8):
            siguiente = dias[(momento.weekday() + desplazamiento) % 7]
            if siguiente['abre']:
                cuando = 'mañana' if desplazamiento == 1 else f"el {siguiente['dia'].lower()}"
                resumen += f" Abrimos {cuando} a las {hora_texto(siguiente['abre'])}"
                break
    return {'abierto': abierto, 'resumen': resumen, 'hoy': hoy['dia'], 'hora_actual': hora_texto(actual), 'dias': dias}


# ---------------------------------------------------------------- domicilios
def normalizar(texto):
    """Minúsculas, sin tildes ni signos y con espacios simples: "  Quinta  CAMACHO!" -> "quinta camacho"."""
    sin_tildes = ''.join(c for c in unicodedata.normalize('NFD', texto or '') if unicodedata.category(c) != 'Mn')
    return ' '.join(re.sub(r'[^a-z0-9 ]', ' ', sin_tildes.lower()).split())


def zonas():
    return datos()['domicilio']['zonas']


def ciudades_con_cobertura():
    vistas, ciudades = set(), []
    for zona in zonas():
        if zona['ciudad_dane'] not in vistas:
            vistas.add(zona['ciudad_dane'])
            ciudades.append({'nombre': zona['ciudad'], 'dane': zona['ciudad_dane']})
    return ciudades


def _coincidencia(zona, barrio):
    return {'barrio': barrio, 'zona': zona['nombre'], 'ciudad': zona['ciudad'], 'ciudad_dane': zona['ciudad_dane'],
            'sede_id': zona['sede_id'], 'costo': int(zona['costo']), 'tiempo': zona['tiempo']}


def buscar_cobertura(barrio, ciudad_dane=None):
    """¿Hay domicilio al barrio? Compara sin tildes ni mayúsculas.

    Devuelve las coincidencias exactas (barrio o nombre de zona) y, si no hay, sugerencias de barrios que
    contienen el texto escrito (por ejemplo "chapi" -> Chapinero Central, Chapinero Alto).
    """
    buscado = normalizar(barrio)
    if buscado.startswith('barrio '):
        buscado = buscado[len('barrio '):]
    candidatas = [z for z in zonas() if not ciudad_dane or z['ciudad_dane'] == ciudad_dane]
    exactas, sugerencias = [], []
    for zona in candidatas:
        for nombre in zona['barrios']:
            normal = normalizar(nombre)
            if normal == buscado:
                exactas.append(_coincidencia(zona, nombre))
            elif len(buscado) >= 3 and buscado in normal:
                sugerencias.append(_coincidencia(zona, nombre))
        if not any(c['zona'] == zona['nombre'] for c in exactas) and normalizar(zona['nombre']) == buscado:
            exactas.append(_coincidencia(zona, zona['nombre']))
    return {'barrio': barrio.strip(), 'cobertura': bool(exactas), 'coincidencias': exactas,
            'sugerencias': [] if exactas else sugerencias[:6]}


# ---------------------------------------------------------------- datos públicos (chatbot, pago, recibo)
def datos_drogueria():
    d = datos()
    return {
        'nombre': d['drogueria']['nombre'],
        'razon_social': d['drogueria'].get('razon_social', ''),
        'nit': d['drogueria'].get('nit', ''),
        'direccion': d['drogueria'].get('direccion', ''),
        'telefono': d['contacto'].get('telefono', ''),
        'correo': d['contacto'].get('correo', ''),
    }


def info_publica(sedes):
    d = datos()
    return {
        'drogueria': datos_drogueria(),
        'contacto': {'telefono': d['contacto'].get('telefono', ''), 'correo': d['contacto'].get('correo', ''),
                     'atiende': d['contacto'].get('atiende', 'un farmacéutico')},
        'horario': estado_horario(),
        'pago': {'metodo': d['pago']['metodo'], 'nombre': d['pago']['nombre'], 'descripcion': d['pago']['descripcion']},
        'domicilio': {
            'ciudades': ciudades_con_cobertura(),
            'zonas': [{'ciudad': z['ciudad'], 'ciudad_dane': z['ciudad_dane'], 'nombre': z['nombre'],
                       'barrios': z['barrios'], 'costo': int(z['costo']), 'tiempo': z['tiempo']} for z in zonas()],
        },
        'sedes': sedes,
    }
