# DrogueriaGestión — contexto para Claude Code

Sistema web para la gestión integral de una droguería. Proyecto de aula de 2.º semestre
(Tecnología en Desarrollo de Software, UNIMINUTO, asignatura **Base de datos**). El documento
del proyecto exige: **Python + Flask** en el backend, **MySQL 8** como base de datos y
**HTML, CSS y JavaScript** (sin frameworks) en el frontend. Todo el código, los nombres y
los textos de la interfaz están en **español**; mantén esa convención.

## Estado actual (actualizado 2026-11-07)

El código de todos los módulos está escrito, pero **nunca se ha ejecutado contra MySQL ni se ha
probado en el navegador**. Lo único verificado es que todos los `.py` compilan, que `create_app()`
registra las rutas y que el separador de sentencias SQL de `init_db.py` divide bien los 3 scripts.

Correcciones de la revisión del 2026-11-07 (también sin probar contra MySQL):
- `init_db.py` pide escribir el nombre de la BD antes de borrarla si ya existe (`--forzar` lo omite).
- `TestConfig` usa `DB_NAME_TEST` (por defecto `drogueria_gestion_test`), nunca la BD real.
- Con la sesión vencida, una petición que modifica datos responde 401 (redirige al login) en vez de
  un error de CSRF.
- `detalle_venta.costo_unitario` guarda el costo del lote al vender; los reportes de utilidad lo usan.
- Las ventas bloquean los lotes ordenados por id de medicamento (evita deadlocks); los errores 1213 y
  1205 de MySQL se traducen a "intente nuevamente".
- Tope de descuento para vendedores (`configuracion.descuento_maximo_vendedor`, 10 % por defecto).
- El dashboard no envía ni muestra datos de ventas a roles sin `ventas.ver` (BODEGA).
- Datos de prueba: ningún lote tiene fecha de fabricación posterior a la de su recepción.
- Activar/desactivar (usuarios, clientes, proveedores, categorías) y desbloquear usuarios responden 404
  si el registro no existe; la auditoría guarda el nombre del registro, no solo el id.
- Restablecer la contraseña de un usuario también levanta su bloqueo (`bloqueado_hasta = NULL`).
- `exportarCSV` antepone `'` a los textos que empiezan por `= + - @` (inyección de fórmulas en Excel).
- Si el costo de una entrada supera el precio de venta, la entrada se registra y la respuesta trae
  `advertencias`, que el frontend muestra para que se actualice el precio de venta.

| Área | Estado |
|---|---|
| Scripts SQL (esquema, vistas, función, triggers, procedimientos, datos de prueba) | Escritos, **sin ejecutar** |
| `database/init_db.py` (instalador + ventas de demostración) | Escrito, **sin ejecutar** |
| Backend Flask (API REST + páginas) | Escrito, sin probar |
| Frontend (16 pantallas + JS) | Escrito, sin probar |
| `README.md`, carpeta `docs/`, carpeta `tests/` | **Pendiente** (no existen o están vacías) |
| Repositorio git | No inicializado |

## Pendiente, en este orden

1. **Instalar la base de datos** (pide la contraseña de `root` de MySQL por consola):
   `python database/init_db.py`. Corrige cualquier error de SQL que aparezca. Puntos de riesgo:
   - Crear la función `fn_stock_disponible` y los triggers con el binlog activo requiere que el
     usuario tenga SUPER o `log_bin_trust_function_creators = 1`.
   - En el procedimiento `sp_dar_baja_lotes_vencidos`: `SELECT ... INTO ... FOR UPDATE`.
   - El generador de ventas demo (`generar_ventas_demo`) usa el mismo servicio que la API.
2. **Arrancar y probar cada pantalla** con `python run.py` → http://127.0.0.1:5000, con cada rol.
   Verifica especialmente:
   - El punto de venta (FEFO, exigencia de fórmula, cambio en efectivo).
   - La anulación de ventas, las entradas de mercancía con varias líneas y la baja de vencidos.
   - Los reportes y el comprobante imprimible.
   - La serialización JSON de `Decimal` y fechas.
   - Que la CSP no bloquee nada (no hay scripts en línea).
3. **README.md** con instalación, uso y cuentas de demostración.
4. **`docs/`**:
   - Modelo entidad-relación (Mermaid) y diccionario de datos.
   - Matriz de requisitos funcionales y no funcionales.
   - Manual de usuario, manual técnico y casos de prueba con evidencias.
   Estos son los anexos B, C, D, F y G del documento.
5. **`tests/`** con pytest (pruebas de la API usando el test client de Flask; idealmente contra
   una BD de prueba creada con `python database/init_db.py --bd drogueria_gestion_test`).
6. Avisar al equipo de que el documento del proyecto menciona "administración de mesas" y "mesas"
   (residuo de una plantilla de restaurante). **No se implementó**; hay que corregir el documento.

## Cómo ejecutar

```bash
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
copy .env.example .env          # luego editar SECRET_KEY y DB_PASSWORD
python database/init_db.py      # crea BD, usuario MySQL de la app y datos demo
python database/init_db.py --sin-demo   # alternativa: sin ventas históricas
python run.py                   # http://127.0.0.1:5000
```

- No copiar `.venv/` ni `.env` de otro computador: se recrean (están en `.gitignore`).
  **Al comprimir el proyecto para entregarlo o compartirlo, excluir `.venv/`, `.env` y `__pycache__/`**
  (el `.env` contiene la `SECRET_KEY` y la contraseña de MySQL).
- `init_db.py` borra y recrea la BD (`DROP DATABASE`). Si ya existe, pide escribir su nombre para
  confirmar; `--forzar` omite la confirmación. Para las pruebas: `--bd drogueria_gestion_test`.
- `init_db.py` se conecta como `DB_ADMIN_USER` (root). Si `DB_ADMIN_PASSWORD` está vacío, la pide
  con `getpass`. Luego crea el usuario `DB_USER` (`drogueria_app`) para `localhost` y `127.0.0.1`
  con solo `SELECT, INSERT, UPDATE, DELETE, EXECUTE`. La app nunca usa root.
- **Cuentas de demostración** (definidas en `03_datos_prueba.sql`, guardadas con hash scrypt):

  | Usuario | Contraseña |
  |---|---|
  | `admin` | `Admin2026*` |
  | `regente` | `Regente2026*` |
  | `vendedor` | `Vendedor2026*` |
  | `bodega` | `Bodega2026*` |

## Estructura

```
config.py            Configuración desde .env (Config, TestConfig)
run.py               Servidor de desarrollo
database/
  01_esquema.sql         16 tablas InnoDB con PK/FK, UNIQUE, CHECK e índices
  02_vistas_rutinas.sql  Vistas, función, triggers y procedimientos (usa DELIMITER $$)
  03_datos_prueba.sql    Datos ficticios con fechas relativas a CURDATE()/NOW()
  init_db.py             Instalador: ejecuta los scripts, crea usuario de la app y ventas demo
app/
  __init__.py      create_app(): JSON provider (Decimal→float, fechas ISO), blueprints, manejo de errores MySQL
  db.py            PyMySQL, una conexión por petición: consultar, consultar_uno, ejecutar, transaccion(), paginar()
  seguridad.py     Matriz PERMISOS por rol, decoradores, CSRF, inactividad, cabeceras CSP
  utils.py         ApiError, Validador (validación por campo → 422), auditar(), patron_busqueda()
  services/        Lógica de negocio transaccional (recibe un cursor):
    ventas.py        registrar_venta (FEFO + consecutivo FV-000001), anular_venta
    inventario.py    registrar_entrada, registrar_ajuste
  routes/          paginas.py (HTML) + un blueprint JSON por módulo bajo /api
  templates/       base.html (layout), _macros.html, _iconos.html (sprite SVG), una plantilla por página
  static/css/styles.css   Diseño completo con variables CSS y tema oscuro ([data-tema="oscuro"])
  static/js/core.js       api(), html`` (escapa todo, anti-XSS), formatos COP, toasts, modales <dialog>, paginación, CSV
  static/js/graficos.js   Gráficos SVG propios (barras, línea, dona), sin librerías
  static/js/pages/*.js    Un módulo ES por página
```

## Modelo de datos (resumen)

- **Tablas**:
  - Seguridad y configuración: `roles`, `usuarios`, `auditoria`, `configuracion`, `consecutivos`.
  - Catálogo: `categorias`, `proveedores`, `medicamentos`, `historial_precios`, `clientes`.
  - Inventario: `entradas`, `detalle_entrada`, `lotes`, `movimientos_inventario` (kárdex).
  - Ventas: `ventas`, `detalle_venta`.
- **El stock no se guarda en `medicamentos`**: se calcula sumando `lotes.cantidad_actual` de los
  lotes no vencidos. Toda alteración de existencias deja una fila en `movimientos_inventario` con
  `saldo_lote`.
- **Vistas**:
  - `v_stock_medicamentos`: estado AGOTADO, BAJO o NORMAL.
  - `v_lotes_vencimiento`: semáforo VENCIDO, CRITICO (≤30 días), PROXIMO (≤90 días) o VIGENTE.
  - `v_ventas` y `v_ventas_diarias`.
- **Función** `fn_stock_disponible(id)`.
- **Triggers**:
  - `trg_medicamentos_precio_au`: historial de precios; usa la variable `@app_id_usuario` que asigna `db.py`.
  - `trg_detalle_venta_bi`: impide vender un lote vencido, de otro medicamento o sin stock.
  - `trg_ventas_bu`: una venta anulada no se puede modificar.
- **Procedimientos**:
  - `sp_dar_baja_lotes_vencidos(id_usuario)`: lo llama `POST /api/inventario/vencimientos/baja`.
  - `sp_reporte_ventas(desde, hasta)`: lo llama `GET /api/reportes/ventas`.
- El cliente con `id_cliente = 1` es "Consumidor final" y no se puede editar ni desactivar.
- El consecutivo de las facturas usa `UPDATE consecutivos SET ultimo_numero = LAST_INSERT_ID(ultimo_numero + 1)`.

## Reglas de negocio clave

- **Roles**:
  - ADMINISTRADOR: todo.
  - REGENTE: catálogo, inventario, ventas, anulaciones y reportes.
  - VENDEDOR: ventas, clientes y consulta del catálogo.
  - BODEGA: inventario, vencimientos y proveedores.
  - La matriz está en `seguridad.PERMISOS`. Las plantillas usan `puede('permiso')` y el JS usa `puede()` de `core.js`. **El servidor siempre valida.**
- **Ventas**:
  - FEFO: se despacha primero el lote que vence antes, con `SELECT ... FOR UPDATE` dentro de una transacción.
  - Los productos con `requiere_formula` exigen `formula_medica`. `es_controlado` implica `requiere_formula` (también hay un CHECK en la BD).
  - `precio_venta` es sin IVA; el IVA (0, 5 o 19 %) se suma por línea.
  - Cada línea de `detalle_venta` guarda el `costo_unitario` del lote en ese momento; los reportes de
    utilidad usan ese valor, no el costo actual del lote (que cambia con nuevas entradas).
  - Los lotes se bloquean en orden de `id_medicamento` para evitar deadlocks entre cajas.
  - Descuento: ADMINISTRADOR y REGENTE (`ventas.descuento_libre`) sin tope; los demás roles, hasta
    `configuracion.descuento_maximo_vendedor` % del total con IVA (10 % si no está configurado).
    El servidor lo valida en `registrar_venta(..., descuento_maximo_pct)`.
- **Anulación**: devuelve las unidades al mismo lote, con movimiento `ANULACION_VENTA` y motivo obligatorio.
- **Entradas de mercancía**:
  - Cada línea crea un lote o incrementa uno existente (mismo medicamento y número de lote, con la misma fecha de vencimiento).
  - El último costo pasa a ser el `precio_compra`. Si supera el `precio_venta`, se avisa en
    `advertencias` (el medicamento no se puede editar hasta subir su precio de venta).
  - No se reciben lotes vencidos.
  - La pareja proveedor + número de factura es única.
- **Login**:
  - Mensaje genérico ante usuario o contraseña incorrectos.
  - Bloqueo de 10 minutos tras 5 intentos fallidos.
  - La sesión se regenera al iniciar.
  - Hay 60 minutos de inactividad máxima.
  - Todo se registra en `auditoria`.
- **Datos personales**: los clientes tienen `autoriza_datos` (Ley 1581 de 2012).

## Convenciones de código

- **SQL**: siempre parametrizado (`%s`). Los únicos fragmentos interpolados con f-string son nombres
  de columnas y órdenes que salen de listas blancas del propio código.
- **Escrituras**: las de varias sentencias van en `with transaccion() as cur:`; las simples, con `ejecutar()`.
- **Validación**: con `Validador`. `v.validar()` lanza `ApiError(..., 422, errores)`, cuyas claves
  coinciden con el `name` de los inputs y el frontend las pinta con `mostrarErrores(form, errores)`.
- **Errores de MySQL**: el manejador global de `app/__init__.py` traduce los códigos 1062, 1451,
  1452, 3819, 1213/1205 (deadlock / espera de bloqueo) y 1644 (SIGNAL).
- **Sesión y CSRF**: si una petición que modifica datos llega sin token CSRF en la sesión (sesión
  vencida), `verificar_csrf` responde 401 para que `core.js` redirija al login; el login responde 403.
- **Frontend**:
  - Renderiza siempre con la plantilla etiquetada `html`…`` de `core.js`, que escapa todo; `crudo()` solo para HTML de confianza.
  - Nada de scripts en línea, porque la CSP es `script-src 'self'`.
  - Los modales son `<dialog>` nativos y los cierra cualquier botón con `data-cerrar-modal`.
- **Peticiones**: usa `api.get/post/put/patch/del` de `core.js`, que envía el `X-CSRF-Token`
  (tomado de `<meta name="csrf-token">`) y redirige al login ante un 401.
- **Formato colombiano**: `moneda()` en COP sin decimales, fechas `es-CO` y CSV separado por `;` con BOM para Excel.
