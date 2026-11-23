import {
  $, abrirModal, api, cerrarModal, conCarga, confirmar, debounce, fecha, fechaHora, filaVacia, filasCargando, html,
  icono, insignia, leerFormulario, llenarFormulario, METODOS_PAGO, moneda, numero, paginacion, puede, toast, toastError,
} from '../core.js';

const form = $('#form-cliente');
const CONSUMIDOR_FINAL = 1;
let pagina = 1;
let editando = null;
let datos = [];

async function cargar(p = pagina) {
  pagina = p;
  const cuerpo = $('#tabla-cuerpo');
  cuerpo.innerHTML = html`${filasCargando(9)}`;
  try {
    const r = await api.get('/api/clientes', { q: $('#f-buscar').value.trim(), activo: $('#f-activo').value, pagina, por_pagina: 15 });
    datos = r.datos;
    const editar = puede('clientes.editar');
    cuerpo.innerHTML = datos.length ? html`${datos.map((c) => {
      const especial = c.id_cliente === CONSUMIDOR_FINAL;
      return html`<tr class="${c.activo ? '' : 'inactivo'}">
        <td class="mono nowrap">${c.tipo_documento} ${c.numero_documento}</td>
        <td><div class="titulo-celda">${c.nombres} ${c.apellidos || ''}</div>
          ${especial ? html`<div class="sub-celda">Cliente genérico para ventas sin identificar</div>` : ''}</td>
        <td>${c.telefono || '—'}<div class="sub-celda">${c.email || ''}</div></td>
        <td>${c.ciudad || 'Sin ciudad'}<div class="sub-celda">${c.pais || 'Sin país registrado'}</div></td>
        <td class="num">${numero(c.compras)}</td>
        <td class="num">${moneda(c.total_comprado)}</td>
        <td>${c.ultima_compra ? fecha(c.ultima_compra) : '—'}</td>
        <td>${especial ? '—' : c.autoriza_datos
          ? html`<span class="insignia insignia-exito" title="Autorizó tratamiento de datos">Autorizado</span>`
          : html`<span class="insignia insignia-alerta" title="Sin autorización de tratamiento de datos">Pendiente</span>`}</td>
        <td class="acciones-celda"><div class="acciones">
          <button class="btn-icono" data-accion="ver" data-id="${c.id_cliente}" title="Historial de compras">${icono('ojo')}</button>
          ${editar && !especial ? html`
            <button class="btn-icono" data-accion="editar" data-id="${c.id_cliente}" title="Editar">${icono('editar')}</button>
            <button class="btn-icono ${c.activo ? 'peligro' : 'exito'}" data-accion="estado" data-id="${c.id_cliente}"
              title="${c.activo ? 'Desactivar' : 'Activar'}">${icono('encender')}</button>
            ${!c.ultima_compra ? html`<button class="btn-icono peligro" data-accion="eliminar" data-id="${c.id_cliente}" title="Eliminar cliente">${icono('papelera')}</button>` : ''}` : ''}
        </div></td>
      </tr>`;
    })}` : filaVacia(9);
    paginacion($('#paginacion'), r, cargar);
  } catch (e) {
    cuerpo.innerHTML = filaVacia(9, 'No fue posible cargar', e.message);
  }
}

function abrir(c = null) {
  editando = c?.id_cliente ?? null;
  form.reset();
  if (!c) $('#cl-pais').value = 'Colombia';
  $('#titulo-cliente').textContent = c ? 'Editar cliente' : 'Nuevo cliente';
  if (c) llenarFormulario(form, c);
  abrirModal('modal-cliente');
}

async function verDetalle(id) {
  const cuerpo = $('#detalle-cuerpo');
  cuerpo.innerHTML = '<div class="esqueleto" style="height:100px"></div>';
  abrirModal('modal-detalle');
  try {
    const c = await api.get(`/api/clientes/${id}`);
    $('#titulo-detalle').textContent = `${c.nombres} ${c.apellidos || ''}`;
    cuerpo.innerHTML = html`
      <dl class="detalle-lista">
        <div><dt>Documento</dt><dd>${c.tipo_documento} ${c.numero_documento}</dd></div>
        <div><dt>Teléfono</dt><dd>${c.telefono || '—'}</dd></div>
        <div><dt>Correo</dt><dd>${c.email || '—'}</dd></div>
        <div><dt>Dirección</dt><dd>${c.direccion || '—'}</dd></div>
        <div><dt>Ciudad</dt><dd>${c.ciudad || '—'}</dd></div>
        <div><dt>País / nacionalidad</dt><dd>${c.pais || 'Sin especificar'}</dd></div>
        <div><dt>Fecha de registro</dt><dd>${fechaHora(c.creado_en)}</dd></div>
        <div><dt>Fecha de nacimiento</dt><dd>${c.fecha_nacimiento ? fecha(c.fecha_nacimiento) : '—'}</dd></div>
        <div><dt>Tratamiento de datos</dt><dd>${c.autoriza_datos ? 'Autorizado' : 'No autorizado'}</dd></div>
      </dl>
      <h3 class="mt-3" style="font-size:14px">Últimas compras</h3>
      <table class="tabla tabla-compacta mt-1">
        <thead><tr><th>Factura</th><th>Fecha</th><th>Pago</th><th class="num">Unidades</th><th class="num">Total</th><th>Estado</th></tr></thead>
        <tbody>${c.compras.length ? c.compras.map((v) => html`<tr>
          <td><a href="/ventas/${v.id_venta}/comprobante" class="mono">${v.numero_factura}</a></td>
          <td>${fechaHora(v.fecha_venta)}</td><td>${METODOS_PAGO[v.metodo_pago]}</td>
          <td class="num">${v.unidades}</td><td class="num">${moneda(v.total)}</td><td>${insignia(v.estado)}</td></tr>`)
          : filaVacia(6, 'Sin compras registradas', '')}</tbody>
      </table>`;
  } catch (e) {
    cerrarModal('modal-detalle');
    toastError(e);
  }
}

$('#tabla-cuerpo').addEventListener('click', async (e) => {
  const boton = e.target.closest('button[data-accion]');
  if (!boton) return;
  const c = datos.find((x) => x.id_cliente === Number(boton.dataset.id));
  if (boton.dataset.accion === 'ver') return verDetalle(c.id_cliente);
  if (boton.dataset.accion === 'editar') return abrir(c);
  if (boton.dataset.accion === 'eliminar') {
    const ok = await confirmar({ titulo: 'Eliminar cliente', mensaje: 'Esta acción es permanente. Solo se permite si el cliente no tiene facturas asociadas.', textoBoton: 'Eliminar', peligro: true });
    if (!ok) return;
    try {
      toast((await api.del(`/api/clientes/${c.id_cliente}`)).mensaje);
      cargar();
    } catch (err) { toastError(err); }
    return;
  }
  if (boton.dataset.accion === 'estado') {
    if (c.activo) {
      const ok = await confirmar({ titulo: 'Desactivar cliente', mensaje: 'El cliente no aparecerá en el punto de venta. Su historial se conserva.', textoBoton: 'Desactivar', peligro: true });
      if (!ok) return;
    }
    try {
      const r = await api.patch(`/api/clientes/${c.id_cliente}/estado`, { activo: !c.activo });
      toast(r.mensaje);
      cargar();
    } catch (err) { toastError(err); }
  }
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const valores = leerFormulario(form);
  const r = await conCarga($('#btn-guardar-cliente'), () => (editando ? api.put(`/api/clientes/${editando}`, valores) : api.post('/api/clientes', valores)), form);
  if (r) { toast(r.mensaje); cerrarModal('modal-cliente'); cargar(); }
});

$('#btn-nuevo')?.addEventListener('click', () => abrir());
$('#f-buscar').addEventListener('input', debounce(() => cargar(1)));
$('#f-activo').addEventListener('change', () => cargar(1));
cargar(1);
