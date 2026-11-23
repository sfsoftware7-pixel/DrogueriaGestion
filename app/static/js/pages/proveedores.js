import {
  $, abrirModal, api, cerrarModal, conCarga, confirmar, debounce, fecha, fechaHora, filaVacia, filasCargando, html,
  icono, insigniaActivo, leerFormulario, llenarFormulario, moneda, numero, paginacion, puede, toast, toastError,
} from '../core.js';

const form = $('#form-proveedor');
let pagina = 1;
let editando = null;
let datos = [];

async function cargar(p = pagina) {
  pagina = p;
  const cuerpo = $('#tabla-cuerpo');
  cuerpo.innerHTML = html`${filasCargando(7)}`;
  try {
    const r = await api.get('/api/proveedores', { q: $('#f-buscar').value.trim(), activo: $('#f-activo').value, pagina, por_pagina: 15 });
    datos = r.datos;
    const editar = puede('proveedores.editar');
    cuerpo.innerHTML = datos.length ? html`${datos.map((p) => html`
      <tr class="${p.activo ? '' : 'inactivo'}">
        <td><div class="titulo-celda">${p.razon_social}</div><div class="sub-celda mono">NIT ${p.nit}</div></td>
        <td>${p.nombre_contacto || '—'}<div class="sub-celda">${[p.telefono, p.email].filter(Boolean).join(' · ')}</div></td>
        <td>${p.ciudad || '—'}</td>
        <td class="num">${numero(p.total_entradas)}</td>
        <td>${p.ultima_entrada ? fecha(p.ultima_entrada) : '—'}</td>
        <td>${insigniaActivo(p.activo)}</td>
        <td class="acciones-celda"><div class="acciones">
          <button class="btn-icono" data-accion="ver" data-id="${p.id_proveedor}" title="Ver entradas">${icono('ojo')}</button>
          ${editar ? html`
            <button class="btn-icono" data-accion="editar" data-id="${p.id_proveedor}" title="Editar">${icono('editar')}</button>
            <button class="btn-icono ${p.activo ? 'peligro' : 'exito'}" data-accion="estado" data-id="${p.id_proveedor}"
              title="${p.activo ? 'Desactivar' : 'Activar'}">${icono('encender')}</button>` : ''}
        </div></td>
      </tr>`)}` : filaVacia(7);
    paginacion($('#paginacion'), r, cargar);
  } catch (e) {
    cuerpo.innerHTML = filaVacia(7, 'No fue posible cargar', e.message);
  }
}

function abrir(p = null) {
  editando = p?.id_proveedor ?? null;
  form.reset();
  $('#titulo-proveedor').textContent = p ? 'Editar proveedor' : 'Nuevo proveedor';
  if (p) llenarFormulario(form, p);
  abrirModal('modal-proveedor');
}

async function verDetalle(id) {
  const cuerpo = $('#detalle-cuerpo');
  cuerpo.innerHTML = '<div class="esqueleto" style="height:100px"></div>';
  abrirModal('modal-detalle');
  try {
    const p = await api.get(`/api/proveedores/${id}`);
    $('#titulo-detalle').textContent = p.razon_social;
    cuerpo.innerHTML = html`
      <dl class="detalle-lista">
        <div><dt>NIT</dt><dd class="mono">${p.nit}</dd></div>
        <div><dt>Ciudad</dt><dd>${p.ciudad || '—'}</dd></div>
        <div><dt>Contacto</dt><dd>${p.nombre_contacto || '—'}</dd></div>
        <div><dt>Teléfono</dt><dd>${p.telefono || '—'}</dd></div>
        <div><dt>Correo</dt><dd>${p.email || '—'}</dd></div>
        <div><dt>Dirección</dt><dd>${p.direccion || '—'}</dd></div>
      </dl>
      <h3 class="mt-3" style="font-size:14px">Últimas entradas de mercancía</h3>
      <table class="tabla tabla-compacta mt-1">
        <thead><tr><th>Factura</th><th>Fecha</th><th class="num">Productos</th><th class="num">Total</th></tr></thead>
        <tbody>${p.entradas.length ? p.entradas.map((e) => html`<tr><td class="mono">${e.numero_factura}</td>
          <td>${fechaHora(e.fecha_entrada)}</td><td class="num">${e.productos}</td><td class="num">${moneda(e.total)}</td></tr>`)
          : filaVacia(4, 'Sin entradas registradas', '')}</tbody>
      </table>`;
  } catch (e) {
    cerrarModal('modal-detalle');
    toastError(e);
  }
}

$('#tabla-cuerpo').addEventListener('click', async (e) => {
  const boton = e.target.closest('button[data-accion]');
  if (!boton) return;
  const p = datos.find((x) => x.id_proveedor === Number(boton.dataset.id));
  if (boton.dataset.accion === 'ver') return verDetalle(p.id_proveedor);
  if (boton.dataset.accion === 'editar') return abrir(p);
  if (boton.dataset.accion === 'estado') {
    if (p.activo) {
      const ok = await confirmar({ titulo: 'Desactivar proveedor', mensaje: 'No podrá seleccionarse en nuevas entradas de mercancía.', textoBoton: 'Desactivar', peligro: true });
      if (!ok) return;
    }
    try {
      const r = await api.patch(`/api/proveedores/${p.id_proveedor}/estado`, { activo: !p.activo });
      toast(r.mensaje);
      cargar();
    } catch (err) { toastError(err); }
  }
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const valores = leerFormulario(form);
  const r = await conCarga($('#btn-guardar'), () => (editando ? api.put(`/api/proveedores/${editando}`, valores) : api.post('/api/proveedores', valores)), form);
  if (r) { toast(r.mensaje); cerrarModal('modal-proveedor'); cargar(); }
});

$('#btn-nuevo')?.addEventListener('click', () => abrir());
$('#f-buscar').addEventListener('input', debounce(() => cargar(1)));
$('#f-activo').addEventListener('change', () => cargar(1));
cargar(1);
