import { $, api, fechaISO, html, icono, sumarDias, toast, toastError } from '../core.js';
import { activarVerSQL } from '../ver_sql.js';

const ejemplosWorkbench = [
  {
    titulo: 'Consultar usuarios y roles', grupo: 'Consultas',
    descripcion: 'Lista cuentas sin contraseñas ni hashes, y roles disponibles.',
    sql: String.raw`USE drogueria_gestion;

SELECT u.id_usuario, u.usuario, u.nombres, u.apellidos, u.email,
       r.nombre AS rol, u.activo, u.ultimo_acceso
FROM usuarios AS u
JOIN roles AS r ON r.id_rol = u.id_rol
ORDER BY u.activo DESC, u.nombres, u.apellidos;

SELECT id_rol, nombre, descripcion
FROM roles
ORDER BY id_rol;`,
  },
  {
    titulo: 'Consultar medicamentos con existencias', grupo: 'Consultas',
    descripcion: 'Catálogo, categoría, precio, stock disponible y alerta.',
    sql: String.raw`USE drogueria_gestion;

SELECT codigo, nombre, principio_activo, categoria, precio_venta,
       stock_disponible, stock_minimo, estado_stock
FROM v_stock_medicamentos
WHERE activo = 1
ORDER BY nombre;`,
  },
  {
    titulo: 'Buscar un producto por nombre o código', grupo: 'Consultas',
    descripcion: 'Reemplaza texto por parte del nombre o código del medicamento.',
    sql: String.raw`USE drogueria_gestion;

SELECT codigo, nombre, concentracion, forma_farmaceutica,
       stock_disponible, estado_stock
FROM v_stock_medicamentos
WHERE nombre LIKE '%texto%'
   OR codigo LIKE '%texto%'
ORDER BY nombre;`,
  },
  {
    titulo: 'Consultar categorías de medicamentos', grupo: 'Consultas',
    descripcion: 'Muestra categorías activas para encontrar el id_categoria correcto.',
    sql: String.raw`USE drogueria_gestion;

SELECT id_categoria, nombre, descripcion
FROM categorias
WHERE activo = 1
ORDER BY nombre;`,
  },
  {
    titulo: 'Ver productos agotados o bajo mínimo', grupo: 'Consultas',
    descripcion: 'Usa el mismo semáforo de inventario que muestra el panel.',
    sql: String.raw`USE drogueria_gestion;

SELECT codigo, nombre, stock_disponible, stock_minimo, estado_stock
FROM v_stock_medicamentos
WHERE activo = 1
  AND estado_stock IN ('AGOTADO', 'BAJO')
ORDER BY stock_disponible, nombre;`,
  },
  {
    titulo: 'Revisar lotes próximos a vencer', grupo: 'Consultas',
    descripcion: 'Incluye los vencidos, críticos y próximos con su proveedor.',
    sql: String.raw`USE drogueria_gestion;

SELECT medicamento, numero_lote, proveedor, fecha_vencimiento,
       dias_para_vencer, cantidad_actual, estado_vencimiento
FROM v_lotes_vencimiento
WHERE cantidad_actual > 0
  AND estado_vencimiento IN ('VENCIDO', 'CRITICO', 'PROXIMO')
ORDER BY fecha_vencimiento;`,
  },
  {
    titulo: 'Consultar ventas recientes', grupo: 'Consultas',
    descripcion: 'Últimas 20 ventas de caja con cliente, vendedor y estado.',
    sql: String.raw`USE drogueria_gestion;

SELECT numero_factura, fecha_venta, cliente, vendedor,
       metodo_pago, total, estado
FROM v_ventas
ORDER BY fecha_venta DESC
LIMIT 20;`,
  },
  {
    titulo: 'Consultar pedidos de la tienda', grupo: 'Consultas',
    descripcion: 'Pedidos web con el estado actual y los datos de entrega.',
    sql: String.raw`USE drogueria_db;

SELECT p.codigo, p.created_at, p.estado, p.tipo_entrega,
       CONCAT_WS(' ', u.nombres, u.apellidos) AS cliente,
       p.direccion_entrega, s.nombre AS sede, p.total
FROM pedidos AS p
JOIN usuarios AS u ON u.id_usuario = p.id_usuario
JOIN sedes AS s ON s.id_sede = p.id_sede
ORDER BY p.created_at DESC
LIMIT 50;`,
  },
  {
    titulo: 'Agregar un usuario del panel', grupo: 'Operaciones',
    descripcion: 'Genera primero el hash con Python; reemplaza los datos y el hash antes de ejecutar.',
    sql: String.raw`-- Desde la carpeta del proyecto, genera un hash compatible con el inicio de sesión.
-- La terminal pedirá la contraseña sin mostrarla; copia el hash scrypt:... que imprime:
-- .venv\Scripts\python.exe -c "from getpass import getpass; from werkzeug.security import generate_password_hash; print(generate_password_hash(getpass('Nueva contraseña: ')))"
-- Copia el resultado scrypt:... en password_hash. No guardes la clave en texto plano.

USE drogueria_gestion;

INSERT INTO usuarios
    (id_rol, documento, nombres, apellidos, email, usuario, password_hash)
SELECT r.id_rol, '12345678', 'Nombres', 'Apellidos',
       'persona@correo.com', 'usuario_nuevo', 'PEGA_AQUI_EL_HASH_SCRYPT'
FROM roles AS r
WHERE r.nombre = 'VENDEDOR';`,
  },
  {
    titulo: 'Agregar un medicamento al catálogo', grupo: 'Operaciones',
    descripcion: 'Reemplaza código, categoría y datos de ejemplo. Luego registra la entrada de stock desde Gestión.',
    sql: String.raw`USE drogueria_gestion;

INSERT INTO medicamentos
    (codigo, nombre, principio_activo, forma_farmaceutica, id_categoria,
     precio_compra, precio_venta, iva_porcentaje, stock_minimo)
SELECT 'CODIGO_NUEVO', 'Nombre del medicamento', 'Principio activo', 'Tableta',
       c.id_categoria, 9000, 15000, 0, 10
FROM categorias AS c
WHERE c.nombre = 'NOMBRE_DE_CATEGORIA_EXISTENTE'
  AND c.activo = 1;`,
  },
];

function pintarBibliotecaWorkbench() {
  const ancla = $('#grupos-consultas');
  if (!ancla) return null;
  ancla.insertAdjacentHTML('beforebegin', html`
    <section class="tarjeta mb sql-biblioteca" aria-labelledby="titulo-workbench">
      <header class="tarjeta-cabecera"><div>
        <h2 id="titulo-workbench">Comandos básicos para MySQL Workbench</h2>
        <p>Copia un ejemplo de administración o una consulta real de las pantallas del sistema para abrirla en Workbench.</p>
      </div></header>
      <div id="biblioteca-workbench" class="sql-biblioteca-lista"></div>
    </section>`);
  const contenedor = $('#biblioteca-workbench');
  const grupos = new Map();
  for (const ejemplo of ejemplosWorkbench) {
    if (!grupos.has(ejemplo.grupo)) grupos.set(ejemplo.grupo, []);
    grupos.get(ejemplo.grupo).push(ejemplo);
  }
  contenedor.innerHTML = html`${[...grupos].map(([grupo, ejemplos]) => html`
    <section class="sql-workbench-grupo">
      <h3>${grupo}</h3>
      ${ejemplos.map((ejemplo, indice) => {
        const id = `wb-${grupo.toLowerCase()}-${indice}`;
        return html`<details class="sql-workbench-ejemplo">
          <summary><strong>${ejemplo.titulo}</strong><span>${ejemplo.descripcion}</span></summary>
          <div class="sql-workbench-acciones"><button class="btn btn-secundario btn-sm" type="button" data-copiar-sql="${id}">${icono('documento', 'icono-sm')} Copiar SQL</button></div>
          <pre class="sql-codigo"><code id="${id}">${ejemplo.sql}</code></pre>
        </details>`;
      })}
    </section>`)}`;
  return contenedor;
}

const hoy = new Date();
$('#c-desde').value = fechaISO(sumarDias(hoy, -29));
$('#c-hasta').value = fechaISO(hoy);
const rango = () => ({ desde: $('#c-desde').value, hasta: $('#c-hasta').value });

async function cargar() {
  try {
    const consultas = await api.get('/api/consultas');
    const grupos = new Map();
    consultas.forEach((c) => {
      if (!grupos.has(c.grupo)) grupos.set(c.grupo, []);
      grupos.get(c.grupo).push(c);
    });
    $('#grupos-consultas').innerHTML = html`${[...grupos].map(([grupo, lista]) => html`
      <section class="tarjeta mb">
        <header class="tarjeta-cabecera"><div><h2>${grupo}</h2><p>${lista.length} consulta(s)</p></div></header>
        <div class="tabla-contenedor"><table class="tabla tabla-compacta">
          <thead><tr><th>Consulta</th><th>Constante en el código</th><th></th></tr></thead>
          <tbody>${lista.map((c) => html`<tr>
            <td><div class="titulo-celda">${c.titulo}</div><div class="sub-celda">${c.descripcion}</div></td>
            <td class="mono">${c.origen}</td>
            <td class="acciones-celda"><div class="grupo-acciones">
              <button class="btn btn-secundario btn-sm" type="button" data-ver-sql="${c.clave}">
                ${icono('documento', 'icono-sm')} Ver SQL y EXPLAIN</button>
              <button class="btn btn-fantasma btn-sm" type="button" data-copiar-workbench="${c.clave}">
                ${icono('documento', 'icono-sm')} Copiar para Workbench</button>
            </div></td>
          </tr>`)}</tbody>
        </table></div>
      </section>`)}`;
  } catch (e) { toastError(e); }
}

activarVerSQL(rango);
const bibliotecaWorkbench = pintarBibliotecaWorkbench();
document.addEventListener('click', async (evento) => {
  const botonWorkbench = evento.target.closest('[data-copiar-workbench]');
  if (botonWorkbench) {
    botonWorkbench.disabled = true;
    try {
      const clave = encodeURIComponent(botonWorkbench.dataset.copiarWorkbench);
      let consulta;
      try {
        consulta = await api.get(`/api/consultas/${clave}/workbench`, rango());
      } catch (error) {
        if (error.status !== 404) throw error;
        // Compatibilidad con el servidor que ya está abierto antes de recargar Python.
        const anterior = await api.get(`/api/consultas/${clave}`, rango());
        consulta = {
          titulo: anterior.titulo,
          sql: 'USE `drogueria_gestion`;\n\n' + (anterior.sql_con_valores || anterior.sql) + ';',
        };
      }
      await navigator.clipboard.writeText(consulta.sql);
      toast(`Consulta «${consulta.titulo}» copiada para MySQL Workbench.`);
    } catch (e) {
      toastError(e);
    } finally {
      botonWorkbench.disabled = false;
    }
    return;
  }
  const boton = evento.target.closest('[data-copiar-sql]');
  if (!boton) return;
  const codigo = document.getElementById(boton.dataset.copiarSql)?.textContent;
  if (!codigo) return;
  try {
    await navigator.clipboard.writeText(codigo);
    toast('SQL copiado. Pégalo en MySQL Workbench y revisa los valores de ejemplo.');
  } catch {
    toast('No fue posible copiar automáticamente. Selecciona el bloque SQL y cópialo manualmente.', 'alerta');
  }
});
cargar();
