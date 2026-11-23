# Sanalivio — prototipo de la página de inicio

Prototipo funcional de la página de inicio de una droguería en línea en Colombia. "Sanalivio" es un nombre
inventado para el proyecto (se buscó antes de usarlo; el registro está en `.taste-skill/names.json`). Incluye:
- Un header que se queda arriba al hacer scroll y se compacta.
- Un buscador con autocompletado.
- Un banner rotativo.
- La grilla de categorías, un carrusel de productos destacados y la sección de promociones.
- Una página por categoría (`/categoria/<slug>`), que se abre desde el menú y desde la lista del inicio, con
  sus productos (y los de sus subcategorías), el precio vigente y el botón para agregar al carrito.
- **Mi cuenta** (`/cuenta`): inicio de sesión con correo y contraseña, los datos de la cuenta y sus pedidos.
- El carrito (`/carrito`) con pago contra entrega, como invitado o con la cuenta iniciada (entonces «Tus datos»
  llegan llenos y el pedido queda en Mi cuenta). Antes de pagar se revisa la cobertura del domicilio por barrio
  y, si el pedido lo necesita, se adjunta la fórmula médica.
- La confirmación del pedido (`/pedido/<código>`), con «Descargar recibo (PDF)», «Imprimir» y el seguimiento
  del estado. La página `/seguimiento` permite consultar el pedido con el código y el documento.
- Un chatbot por reglas en todas las páginas (sin IA ni servicios externos) que responde sobre horarios,
  domicilios, disponibilidad de productos y el carrito.

**Todos los datos se guardan en MySQL** (base `drogueria_db`) por medio de una API mínima en Flask. Los
horarios, las zonas de domicilio, los costos de envío y el contacto están en un solo archivo editable:
[`datos_tienda.toml`](datos_tienda.toml).

La arquitectura completa (referentes, stack, requerimientos y modelo de datos) está en
[`../docs/ARQUITECTURA.md`](../docs/ARQUITECTURA.md).

> Datos ficticios. Este prototipo **no** incluye registro de cuentas nuevas, pasarela de pago en línea ni
> panel administrativo (están documentados para fases posteriores). Quien compra como invitado queda guardado
> como cliente sin contraseña, así que no puede iniciar sesión.

## Requisitos

| Componente | Versión |
|---|---|
| Python | 3.13 |
| MySQL Server | 8.x (probado en 8.4.13 LTS; también funciona en 26.7) |
| Navegador | Chrome, Edge, Firefox o Safari recientes |

Las dependencias de Python están fijadas en [`requirements.txt`](requirements.txt): Flask 3.1.3, PyMySQL 1.2.3,
cryptography 50.0.2 y python-dotenv 1.2.4.

## Pasos

Los comandos se ejecutan desde la carpeta `DrogueriaGestion/` (la que contiene `database/` y `tienda/`), salvo
donde se indica otra cosa.

### 1. Crear la base de datos y cargar los datos de prueba

Use un usuario de MySQL que pueda crear bases de datos (por ejemplo `root`). `schema.sql` **borra y recrea
solo** la base `drogueria_db`.

En **CMD (Windows), Bash o la terminal de macOS/Linux**:

```bash
mysql -u root -p --default-character-set=utf8mb4 < database/schema.sql
mysql -u root -p --default-character-set=utf8mb4 < database/seed.sql
```

En **PowerShell** el operador `<` no existe, así que se usa `cmd /c`:

```powershell
cmd /c "mysql -u root -p --default-character-set=utf8mb4 < database\schema.sql"
cmd /c "mysql -u root -p --default-character-set=utf8mb4 < database\seed.sql"
```

Si `mysql` no se reconoce como comando, use la ruta completa. Por ejemplo:
`"C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"`.

Para comprobar la carga:

```bash
mysql -u root -p -e "SELECT COUNT(*) AS productos FROM drogueria_db.productos"
```

El resultado esperado es `42`.

### 2. Crear el usuario de la aplicación

La tienda lee el catálogo de `drogueria_db` y consulta/descuenta existencias en `drogueria_gestion` del mismo
servidor MySQL. Cambie `ClaveSegura` por una contraseña propia:

```sql
CREATE USER 'tienda_app'@'localhost' IDENTIFIED BY 'ClaveSegura';
CREATE USER 'tienda_app'@'127.0.0.1' IDENTIFIED BY 'ClaveSegura';
GRANT SELECT ON drogueria_db.* TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
-- Compra como invitado: cliente, dirección, fórmula, pedido, sus productos, lotes despachados e historial
GRANT INSERT ON drogueria_db.usuarios TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
GRANT INSERT ON drogueria_db.direcciones TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
GRANT INSERT ON drogueria_db.formulas_medicas TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
GRANT INSERT, UPDATE (codigo) ON drogueria_db.pedidos TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
GRANT INSERT ON drogueria_db.pedido_items TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
GRANT INSERT ON drogueria_db.pedido_item_lotes_gestion TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
GRANT INSERT ON drogueria_db.pedido_historial TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
-- Integración con el inventario del panel administrativo
GRANT SELECT ON drogueria_gestion.medicamentos TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
GRANT SELECT, UPDATE ON drogueria_gestion.lotes TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
GRANT INSERT ON drogueria_gestion.movimientos_inventario TO 'tienda_app'@'localhost', 'tienda_app'@'127.0.0.1';
```

Sin los permisos de escritura, todo funciona salvo confirmar un pedido.

### 3. Configurar las variables de entorno

Desde la carpeta `tienda/`, copie el ejemplo:

```bash
cd tienda
copy .env.example .env        # Windows (CMD o PowerShell)
cp .env.example .env          # macOS o Linux
```

Después edite `tienda/.env` y complete estas variables:

| Variable | Valor |
|---|---|
| `SECRET_KEY` | Una cadena aleatoria: `python -c "import secrets; print(secrets.token_hex(32))"` |
| `DB_HOST` / `DB_PORT` | Dirección y puerto de MySQL (por defecto `127.0.0.1` y `3306`) |
| `DB_NAME` | `drogueria_db` |
| `DB_GESTION_NAME` | `drogueria_gestion`, la base que usa el panel administrativo en el mismo servidor MySQL |
| `DB_USER` / `DB_PASSWORD` | El usuario del paso 2 |

El archivo `.env` está en `.gitignore`: las credenciales nunca se suben al repositorio.

### 4. Instalar las dependencias

Dentro de `tienda/`:

```bash
python -m venv .venv
.venv\Scripts\activate        # Windows
source .venv/bin/activate     # macOS o Linux
pip install -r requirements.txt
```

### 5. Arrancar el servidor

```bash
python run.py
```

Abra **http://127.0.0.1:5050**. Si falta alguna variable en `.env`, la consola lo avisa al arrancar
("Configuración incompleta: complete DB_USER…"). La página se abre igual y muestra un aviso de error con el botón
"Reintentar" en cada sección.

## API

Todas las rutas responden JSON y usan consultas parametrizadas. Los productos incluyen `stock`: las unidades de
lotes sin vencer en las sedes activas, la misma cuenta que usa el pedido al descontar.

| Método | Ruta | Parámetros | Respuesta |
|---|---|---|---|
| GET | `/api/categorias` | — | Categorías principales activas, con el número de productos |
| GET | `/api/categorias/<slug>` | — | Una categoría con sus productos y los de sus subcategorías (primero los que tienen existencias); `404` si no existe |
| GET | `/api/productos/destacados` | `tipo` = `destacados` (por defecto) o `promocion`; `limite` de 1 a 24 (12 por defecto) | Productos destacados o en promoción, con `precio`, `precio_oferta`, `requiere_formula` y `stock` |
| GET | `/api/productos/buscar` | `q` de 2 a 60 caracteres; `limite` de 1 a 10 (8 por defecto) | Sugerencias para el autocompletado. Busca por nombre (completo o incompleto, sin importar tildes ni mayúsculas), descripción (FULLTEXT) y principio activo |
| GET | `/api/productos/disponibilidad` | `q` de 2 a 60 caracteres | Para el chatbot: la misma búsqueda, con las unidades de cada sede y sin caché |
| GET | `/api/productos` | `ids` (hasta 50, separados por comas) | Productos del carrito con precio y existencias actuales, sin caché |
| GET | `/api/tienda` | — | Datos de `datos_tienda.toml`: horario de cada día y si está abierto ahora (hora de Colombia), zonas de domicilio, pago, contacto y sedes |
| GET | `/api/domicilios/cobertura` | `barrio`; `ciudad` (código DANE, opcional) | Si hay domicilio al barrio, con costo y tiempo; si no, sugerencias de barrios parecidos |
| POST | `/api/pedidos` | Formulario de pago (`multipart/form-data`, con la fórmula si aplica) | Crea el pedido y responde `201` con el código y la URL de la confirmación |
| GET | `/api/pedidos/<código>` | — | El pedido confirmado; solo para la sesión que lo creó o lo consultó, o para su dueño con la sesión iniciada |
| POST | `/api/pedidos/consulta` | `codigo`, `tipo_documento`, `numero_documento` (JSON) | Autoriza ver el pedido en esta sesión si el documento coincide |
| POST | `/api/sesion` | `email`, `contrasena` (JSON) | Inicia sesión y responde con la URL de Mi cuenta. Datos errados: **401** con el mismo mensaje para el correo y la contraseña |
| POST | `/api/sesion/salir` | — | Cierra la sesión |

Respuestas de error:
- Parámetros inválidos: **422**, con el detalle por campo.
- Correo o documento de otra cuenta, o sin unidades suficientes: **409**.
- Cinco intentos fallidos de inicio de sesión con el mismo correo en 10 minutos: **429** durante 10 minutos.
- POST sin la cabecera `X-Requested-With: tienda` (la pone `api.js`): **403**, como protección contra envíos
  desde otros sitios.
- Base de datos no disponible: **503**, con un mensaje genérico.

### Sincronización con el inventario administrativo

La tienda conserva su catálogo y sus pedidos en `drogueria_db`; las existencias vendibles se consultan y descuentan
directamente de `drogueria_gestion.lotes`. El cruce es exacto: `productos.sku` debe ser igual a
`medicamentos.codigo`. Los productos sin coincidencia no se pueden comprar y muestran stock cero. La tienda guarda
el ID del lote administrativo en `pedido_item_lotes_gestion` y registra un movimiento `VENTA` en el kárdex del
panel. La misma transacción cubre ambas bases, por lo que deben estar en el mismo servidor MySQL.

En una tienda ya instalada, ejecute una vez `database/migrations/tienda/001_trazabilidad_lotes_gestion.sql` sobre
`drogueria_db`. Después vincule cada SKU con el código del medicamento correspondiente (no use un código de otro
producto). Configure `DB_GESTION_NAME` en `tienda/.env` y conceda al usuario de tienda los permisos indicados
arriba. Gestión maneja un inventario global, sin cantidades por sede; por eso los pedidos de todas las sedes de la
tienda comparten el mismo stock administrativo.

### Cómo se guarda un pedido

Todo ocurre en una sola transacción (`db.transaccion()`), así que se guarda completo o no se guarda nada:

1. Se valida el formulario. Los precios y descuentos se recalculan desde MySQL, y el costo del domicilio desde
   `datos_tienda.toml`; del navegador solo se toman los productos y las cantidades.
2. Se bloquean los lotes de la sede (`SELECT … FOR UPDATE`) y las unidades se reparten FEFO: primero el lote que
   vence antes.
3. Con la sesión iniciada, el pedido queda a nombre de esa cuenta; si no, se crea o reutiliza el cliente
   invitado. Se guardan la dirección y la fórmula, y luego el pedido
   (`PED-000123`), sus productos con el precio congelado, los lotes despachados, el movimiento `VENTA` del kárdex
   y la primera línea del historial.
4. Si algún producto requiere fórmula, el pedido queda `PENDIENTE_FORMULA` hasta que un farmacéutico la apruebe;
   si no, queda `CONFIRMADO`.

## Cómo está construido

- `app/api/` contiene la API: `catalogo.py`, `tienda.py`, `pedidos.py` y `cuenta.py`.
- `app/servicios/` contiene las reglas de negocio:
  - `catalogo.py`: precio con la mejor promoción vigente y los productos de cada categoría.
  - `pedidos.py`: validación, FEFO y datos del recibo.
  - `cuentas.py`: inicio de sesión (Argon2id con la librería `cryptography`, límite de intentos) y datos de Mi cuenta.
  - `tienda_info.py`: lee `datos_tienda.toml`, calcula el horario en hora de Colombia y revisa la cobertura.
- `app/repositorios/` contiene el SQL.
- `app/templates/`:
  - Las páginas: `index.html`, `categoria.html`, `carrito.html`, `cuenta.html`, `pedido.html` y `seguimiento.html`.
  - `base.html`, la base de las páginas de compra.
  - Las partes compartidas: `_encabezado.html`, `_pie.html` y `_chat.html`.
- `app/static/` tiene los estilos y el JavaScript, sin frameworks:

| Archivo | Para qué |
|---|---|
| `css/estilos.css` | Todo el diseño: paleta, tipografía, retícula de 12 columnas, header, tarjetas, formularios, recibo, chatbot e impresión |
| `js/arranque.js` | Se carga en `<head>` antes de pintar: prepara la entrada del hero (la CSP no permite scripts en línea) |
| `js/comun.js` | Utilidades compartidas: elementos del DOM, formato de pesos, avisos y el carrito guardado en el navegador |
| `js/encabezado.js` | Encabezado de todas las páginas: menú, buscador y contador del carrito |
| `js/inicio.js` | Página de inicio: banner, carrusel y carga de categorías y productos |
| `js/productos.js` | Tarjetas de producto que comparten el inicio y las páginas de categoría |
| `js/categoria.js` | Página de una categoría: carga sus productos con estados de carga, vacío y error |
| `js/cuenta.js` | Mi cuenta: formulario de inicio de sesión y botón para cerrarla |
| `js/carrito.js` | Carrito y pago: cantidades, cobertura por barrio, fórmula médica y envío del pedido |
| `js/pedido.js` y `js/recibo.js` | Confirmación: «Descargar recibo (PDF)» (jsPDF) e «Imprimir» |
| `js/seguimiento.js` | Consulta del pedido con código y documento |
| `js/chat.js` | Chatbot por reglas |
| `vendor/jspdf/` | jsPDF 4.2.1 (licencia MIT), copia local para que funcione con la CSP; genera el recibo en el navegador |
| `vendor/taste/` | Capa de movimiento (hover, entrada del hero) y el momento "word-highlight" de la sección de fórmula médica. Copias sin modificar de la skill de diseño *tasteskill*; no usan `eval`, así que funcionan con la CSP |
| `img/fotos/` | Fotografías de reemplazo (ver abajo) en 500, 960 y 1280 px de ancho |
| `img/logo.svg` | El logo (un arco) |
| `creditos.html` | Autor, licencia y fuente de cada fotografía; el pie de la página enlaza aquí |

### Diseño

- Fuente Figtree. Paleta de tinta azul oscura sobre un fondo claro cálido, con verde para las acciones.
- Las tarjetas de producto no muestran una foto de otro producto: llevan una etiqueta tipográfica con el
  laboratorio, la cantidad de la presentación ("30 tabletas") y la categoría. Cuando la base de datos tenga la
  foto de cada producto, esa etiqueta se reemplaza por la imagen.
- **Las 5 fotografías son de reemplazo**, tomadas de Wikimedia Commons con licencias libres (CC BY-SA 4.0,
  CC BY 2.0, CC0 y dominio público). Muestran droguerías de otros países. Hay que cambiarlas por fotos propias
  de la droguería y actualizar `app/static/creditos.html`.
- La carpeta `.taste-skill/` guarda capturas y registros de la revisión de diseño. No la usa la aplicación y
  se puede borrar o excluir al entregar el proyecto.

### Datos de la droguería (`datos_tienda.toml`)

Un solo archivo con el nombre, la razón social, el NIT y la dirección (que salen en el recibo), el contacto, el
horario de cada día, el método de pago y las zonas de domicilio:
- Cada zona tiene su lista de barrios, el costo, el tiempo estimado y la sede que despacha.
- Los valores marcados `# EJEMPLO` son ficticios y hay que reemplazarlos.
- El servidor relee el archivo cuando cambia, sin reiniciar.

### Chatbot

- Responde cuatro tipos de pregunta: horarios, domicilios (con revisión de cobertura por barrio), disponibilidad
  de productos y navegación del carrito.
- El stock sale de la misma consulta del catálogo en MySQL. Ante preguntas sobre dosis, síntomas o qué tomar,
  no recomienda nada: remite al farmacéutico o al médico y muestra el contacto.
- Se usa con el teclado: Escape cierra el panel y devuelve el foco al botón. Los mensajes nuevos se anuncian con
  `aria-live`.

### Header que acompaña el scroll

- `position: sticky; top: 0`.
- Cuando la barra promocional sale de la pantalla (lo detecta un `IntersectionObserver`), el header recibe la
  clase `compacto`. Entonces reduce su altura y gana sombra, con transiciones de 200 ms.
- El espacio que ocupa el header no cambia, así que el contenido no salta.
- En escritorio, las categorías que no caben en la fila del menú se ocultan enteras y el enlace
  "Todas las categorías" lleva a la lista completa.
- Por debajo de 768 px, las categorías pasan a un menú hamburguesa y el buscador sigue visible.

### Accesibilidad y lectura

- Texto de 16 px con interlineado de 26 px. El texto principal es tinta sobre fondo claro, con contraste
  mayor a 7:1. Los textos secundarios superan 4,5:1.
- Foco visible y navegación completa con teclado: enlace para saltar al contenido, autocompletado con flechas,
  Enter y Escape, menú con Escape y banner con botón de pausa.
- Respeta `prefers-reduced-motion`: sin entrada animada, sin rotación automática del banner.

### Seguridad

- Política de seguridad de contenido (CSP) sin scripts en línea, más las cabeceras `nosniff`, `X-Frame-Options`
  y `Referrer-Policy`.
- El usuario de MySQL lee todo, pero solo puede insertar en las tablas de una compra y actualizar existencias y
  el código del pedido.
- Los logs no registran lo que la persona busca.
- Un pedido solo se muestra a la sesión que lo creó, a quien lo consulta con el documento del comprador o a su
  dueño con la sesión iniciada. El mensaje de error es el mismo si el pedido no existe o si el documento no
  coincide.
- Inicio de sesión: la contraseña se verifica contra el hash Argon2id de MySQL; el mensaje es el mismo si el
  correo no existe o si la contraseña está mal, y la respuesta tarda lo mismo en los dos casos. Tras 5 intentos
  fallidos el correo se bloquea 10 minutos (contador en memoria: se reinicia con el servidor). Al iniciar y al
  cerrar sesión se reemplaza la cookie de sesión. Las páginas de Mi cuenta y del carrito no se guardan en caché.
- La fórmula médica se valida por su contenido (JPG, PNG o PDF de hasta 5 MB) y se guarda con su huella SHA-256.

## Usuarios de prueba

`database/seed.sql` crea 3 usuarios con contraseñas hasheadas con Argon2id. Con ellos se entra en **Mi cuenta**
(`/cuenta`); la cuenta del cliente ya tiene 2 pedidos de ejemplo. Son solo para los datos de prueba: no las use
en una instalación real.

| Correo | Contraseña | Rol |
|---|---|---|
| `cliente@tienda-demo.co` | `Cliente2026*` | Cliente |
| `farmaceutico@tienda-demo.co` | `Farmacia2026*` | Farmacéutico |
| `admin@tienda-demo.co` | `Admin2026*` | Administrador |

## Solución de problemas

| Síntoma | Causa probable |
|---|---|
| Las secciones muestran "No pudimos cargar…" y la API responde 503 | MySQL no está encendido o hay credenciales incorrectas en `tienda/.env` |
| `Access denied for user` al cargar los scripts | El usuario del paso 1 no tiene permiso para crear bases de datos |
| `Unknown database 'drogueria_db'` | Falta ejecutar `database/schema.sql` antes que `database/seed.sql` |
