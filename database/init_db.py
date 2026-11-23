"""Instala la base de datos de DrogueriaGestión.

1. Ejecuta los scripts SQL (esquema, vistas/rutinas y datos de prueba).
2. Crea el usuario MySQL de la aplicación con privilegios mínimos.
3. Genera ventas históricas de demostración (opcional) usando las mismas
   reglas de negocio de la aplicación (FEFO, kárdex, consecutivos).

ATENCIÓN: el script 01 ejecuta DROP DATABASE. Si la base de datos ya existe,
se pide escribir su nombre para confirmar que se borrarán todos sus datos.

Uso:
    python database/init_db.py              # instalación completa con ventas demo
    python database/init_db.py --sin-demo   # solo esquema y datos base
    python database/init_db.py --bd drogueria_gestion_test   # BD de pruebas
    python database/init_db.py --forzar     # reinstala sin pedir confirmación
    python database/init_db.py --solo-mejoras   # aplica 04_mejoras.sql a la BD existente, sin recrearla
"""
import argparse
import getpass
import os
import random
import re
import sys
from datetime import datetime, time, timedelta
from decimal import Decimal

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)

import pymysql  # noqa: E402
from pymysql.cursors import DictCursor  # noqa: E402

from config import Config  # noqa: E402

SCRIPTS = ('01_esquema.sql', '02_vistas_rutinas.sql', '03_datos_prueba.sql', '04_mejoras.sql')
MEJORAS = '04_mejoras.sql'  # solo aditivo e idempotente: se puede aplicar a una BD ya instalada
IDENTIFICADOR = re.compile(r'^[A-Za-z0-9_]+$')


def dividir_sentencias(texto):
    """Divide un script SQL respetando la directiva DELIMITER (usada en triggers y rutinas)."""
    delimitador = ';'
    actual, sentencias = [], []
    for linea in texto.splitlines():
        limpia = linea.strip()
        if not actual and (not limpia or limpia.startswith('--')):
            continue
        if limpia.upper().startswith('DELIMITER '):
            delimitador = limpia.split()[1]
            continue
        actual.append(linea)
        if limpia.endswith(delimitador):
            sentencia = '\n'.join(actual).rstrip()
            sentencias.append(sentencia[: -len(delimitador)])
            actual = []
    if ''.join(actual).strip():
        sentencias.append('\n'.join(actual))
    return sentencias


def ejecutar_script(conn, ruta, nombre_bd):
    with open(ruta, encoding='utf-8') as fh:
        texto = fh.read().replace('drogueria_gestion', nombre_bd)
    sentencias = dividir_sentencias(texto)
    with conn.cursor() as cur:
        for sentencia in sentencias:
            cur.execute(sentencia)
            while cur.nextset():
                pass
    return len(sentencias)


def crear_usuario_aplicacion(conn, usuario, password, nombre_bd):
    if not IDENTIFICADOR.match(usuario):
        raise SystemExit('DB_USER solo puede contener letras, números y guion bajo')
    with conn.cursor() as cur:
        for host in ('localhost', '127.0.0.1'):
            cuenta = f"'{usuario}'@'{host}'"
            cur.execute(f'CREATE USER IF NOT EXISTS {cuenta} IDENTIFIED BY %s', (password,))
            cur.execute(f'ALTER USER {cuenta} IDENTIFIED BY %s', (password,))
            cur.execute(f'GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON `{nombre_bd}`.* TO {cuenta}')
            # Si la tienda ya existe, el panel necesita leer pedidos para mostrarlos en el dashboard.
            nombre_tienda = os.getenv('TIENDA_DB_NAME', 'drogueria_db')
            if IDENTIFICADOR.fullmatch(nombre_tienda) and nombre_tienda != nombre_bd:
                cur.execute('SELECT 1 FROM information_schema.schemata WHERE schema_name = %s', (nombre_tienda,))
                if cur.fetchone():
                    for tabla in ('pedidos', 'pedido_items', 'pedido_historial', 'productos', 'usuarios', 'sedes'):
                        cur.execute(f'GRANT SELECT ON `{nombre_tienda}`.`{tabla}` TO {cuenta}')
                    cur.execute(f'GRANT UPDATE (estado) ON `{nombre_tienda}`.`pedidos` TO {cuenta}')
                    cur.execute(f'GRANT INSERT ON `{nombre_tienda}`.`pedido_historial` TO {cuenta}')


# ---------------------------------------------------------------------------
#  Ventas de demostración
# ---------------------------------------------------------------------------
PESOS = {1: 12, 4: 10, 21: 8, 24: 8, 28: 7, 14: 6, 19: 6, 7: 5, 22: 5, 30: 5, 2: 4, 5: 4,
         3: 4, 9: 4, 10: 3, 15: 3, 16: 3, 18: 3, 32: 3, 41: 4, 42: 3, 43: 3, 39: 0.4, 40: 0.4}
MEDICOS = ('Dra. Paula Andrea Gómez', 'Dr. Ricardo Méndez Salas', 'Dra. Carolina Ruiz Peña',
           'Dr. Felipe Castro Ríos', 'Dra. Diana Marcela Ortiz')


def generar_ventas_demo(conn, dias=60, semilla=2026):
    from app.services.ventas import anular_venta, registrar_venta
    from app.utils import ApiError

    rnd = random.Random(semilla)
    with conn.cursor() as cur:
        cur.execute('SELECT id_medicamento, requiere_formula FROM medicamentos WHERE activo = 1')
        meds = cur.fetchall()
        cur.execute('SELECT id_cliente FROM clientes WHERE activo = 1 AND id_cliente > 1')
        clientes = [c['id_cliente'] for c in cur.fetchall()]

    ids = [m['id_medicamento'] for m in meds]
    pesos = [PESOS.get(i, 2) for i in ids]
    formula = {m['id_medicamento']: m['requiere_formula'] for m in meds}
    ahora = datetime.now()
    creadas, fallidas, ids_ventas = 0, 0, []

    for atras in range(dias, -1, -1):
        dia = (ahora - timedelta(days=atras)).date()
        cantidad_ventas = rnd.randint(5, 10) + (3 if dia.weekday() >= 5 else 0)
        minutos = sorted(rnd.randint(7 * 60, 21 * 60) for _ in range(cantidad_ventas))
        for m in minutos:
            fecha = datetime.combine(dia, time(m // 60, m % 60, rnd.randint(0, 59)))
            if fecha >= ahora:
                continue
            elegidos = set()
            for _ in range(rnd.choices((1, 2, 3, 4), weights=(45, 30, 17, 8))[0]):
                elegidos.add(rnd.choices(ids, weights=pesos)[0])
            id_cliente = 1 if rnd.random() < 0.55 else rnd.choice(clientes)
            mayorista = id_cliente == 10
            items = [{'id_medicamento': i,
                      'cantidad': rnd.randint(3, 8) if mayorista else rnd.choices((1, 2, 3), weights=(70, 22, 8))[0]}
                     for i in elegidos]
            necesita_formula = any(formula[i] for i in elegidos)
            metodo = rnd.choices(('EFECTIVO', 'TARJETA_DEBITO', 'TARJETA_CREDITO', 'TRANSFERENCIA'),
                                 weights=(58, 18, 9, 15))[0]
            datos = {
                'id_cliente': id_cliente,
                'metodo_pago': metodo,
                'items': items,
                'descuento': 0,
                'formula_medica': f'RX-{rnd.randint(100000, 999999)}' if necesita_formula else None,
                'medico': rnd.choice(MEDICOS) if necesita_formula else None,
            }
            id_usuario = rnd.choices((3, 2, 1), weights=(70, 25, 5))[0]
            try:
                conn.begin()
                with conn.cursor() as cur:
                    cur.execute('SET @app_id_usuario = %s', (id_usuario,))
                    if metodo == 'EFECTIVO':
                        # El total aún no se conoce: luego se simula el billete recibido y el cambio
                        datos['monto_recibido'] = Decimal('99999999')
                    resultado = registrar_venta(cur, datos, id_usuario, fecha)
                    if metodo == 'EFECTIVO':
                        total = resultado['total']
                        recibido = (total / 5000).to_integral_value(rounding='ROUND_CEILING') * 5000
                        cur.execute('UPDATE ventas SET monto_recibido = %s, cambio = %s WHERE id_venta = %s',
                                    (recibido, recibido - total, resultado['id_venta']))
                conn.commit()
                creadas += 1
                ids_ventas.append(resultado['id_venta'])
            except ApiError:
                conn.rollback()
                fallidas += 1

    # Algunas ventas anuladas para evidenciar la trazabilidad
    candidatas = ids_ventas[:-5]
    for id_venta in rnd.sample(candidatas, k=min(3, len(candidatas))):
        conn.begin()
        with conn.cursor() as cur:
            anular_venta(cur, id_venta, 'Error en la digitación del producto (dato de demostración)', 2)
        conn.commit()

    return creadas, fallidas


def confirmar_reinstalacion(conn, nombre_bd, forzar):
    """Evita borrar por accidente una base de datos que ya existe (el script 01 hace DROP DATABASE)."""
    with conn.cursor() as cur:
        cur.execute('SELECT 1 FROM information_schema.schemata WHERE schema_name = %s', (nombre_bd,))
        existe = cur.fetchone() is not None
    if not existe or forzar:
        return
    print(f'\n  ATENCIÓN: la base de datos "{nombre_bd}" ya existe.')
    print('  Reinstalar BORRA todos sus datos (ventas, inventario, usuarios, auditoría) y no se puede deshacer.')
    respuesta = input(f'  Escriba el nombre de la base de datos ({nombre_bd}) para continuar: ').strip()
    if respuesta != nombre_bd:
        raise SystemExit('Instalación cancelada. No se modificó nada.')


def main():
    parser = argparse.ArgumentParser(description='Instala la base de datos de DrogueriaGestión')
    parser.add_argument('--sin-demo', action='store_true', help='No generar ventas de demostración')
    parser.add_argument('--bd', default=Config.DB_NAME, help='Nombre de la base de datos a crear')
    parser.add_argument('--forzar', action='store_true',
                        help='Borra y recrea la base de datos existente sin pedir confirmación')
    parser.add_argument('--solo-mejoras', action='store_true',
                        help=f'Solo aplica {MEJORAS} a la base existente (no la borra ni toca sus datos)')
    args = parser.parse_args()

    if not IDENTIFICADOR.match(args.bd):
        raise SystemExit('El nombre de la base de datos solo admite letras, números y guion bajo')

    admin_user = os.getenv('DB_ADMIN_USER', 'root')
    admin_password = os.getenv('DB_ADMIN_PASSWORD')
    if admin_password is None or admin_password == '':
        admin_password = getpass.getpass(f'Contraseña de MySQL para "{admin_user}": ')
    if not Config.DB_PASSWORD:
        raise SystemExit('Defina DB_PASSWORD en el archivo .env (contraseña del usuario de la aplicación)')

    print(f'Conectando a MySQL en {Config.DB_HOST}:{Config.DB_PORT} como {admin_user}...')
    try:
        conn = pymysql.connect(host=Config.DB_HOST, port=Config.DB_PORT, user=admin_user, password=admin_password,
                               charset='utf8mb4', cursorclass=DictCursor, autocommit=True)
    except pymysql.err.OperationalError as e:
        raise SystemExit(f'No fue posible conectarse: {e.args[1] if len(e.args) > 1 else e}')

    if args.solo_mejoras:
        with conn:
            with conn.cursor() as cur:
                cur.execute('SELECT 1 FROM information_schema.schemata WHERE schema_name = %s', (args.bd,))
                if cur.fetchone() is None:
                    raise SystemExit(f'La base de datos "{args.bd}" no existe. Instálela primero sin --solo-mejoras.')
            n = ejecutar_script(conn, os.path.join(RAIZ, 'database', MEJORAS), args.bd)
            print(f'  [OK] {MEJORAS}: {n} sentencias aplicadas a "{args.bd}" (sin recrearla)')
        return

    with conn:
        confirmar_reinstalacion(conn, args.bd, args.forzar)
        for nombre in SCRIPTS:
            n = ejecutar_script(conn, os.path.join(RAIZ, 'database', nombre), args.bd)
            print(f'  [OK] {nombre}: {n} sentencias')

        crear_usuario_aplicacion(conn, Config.DB_USER, Config.DB_PASSWORD, args.bd)
        print(f'  [OK] Usuario de aplicación "{Config.DB_USER}" con privilegios SELECT, INSERT, UPDATE, DELETE, EXECUTE')

        if not args.sin_demo:
            conn.select_db(args.bd)
            creadas, fallidas = generar_ventas_demo(conn)
            print(f'  [OK] Ventas de demostración: {creadas} registradas ({fallidas} omitidas por falta de stock)')

    print(f'\nBase de datos "{args.bd}" lista. Ejecute: python run.py')


if __name__ == '__main__':
    main()
