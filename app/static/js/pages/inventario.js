import {
  $, abrirModal, api, cerrarModal, conCarga, confirmar, debounce, fecha, fechaHora, fechaISO, filaVacia, filasCargando,
  html, icono, insignia, leerFormulario, llenarSelect, moneda, mostrarErrores, numero, paginacion, pestanas, puede,
  sumarDias, toast, toastError,
} from '../core.js';

const TIPOS = {
  ENTRADA: ['exito', 'Entrada', '+'],
  VENTA: ['info', 'Venta', '−'],
  AJUSTE_ENTRADA: ['marca', 'Ajuste +', '+'],
  AJUSTE_SALIDA: ['alerta', 'Ajuste −', '−'],
  BAJA_VENCIMIENTO: ['peligro', 'Baja venc.', '−'],
  ANULACION_VENTA: ['neutro', 'Anulación', '+'],
};
const paginas = { lotes: 1, entradas: 1, kardex: 1 };
const cargadas = new Set();
let lotes = [];

/* ---------------------------------- Lotes ---------------------------------- */
async function cargarLotes(p = paginas.lotes) {
  paginas.lotes = p;
  const cuerpo = $('#lotes-cuerpo');
  cuerpo.innerHTML = html`${filasCargando(9)}`;
  try {
    const r = await api.get('/api/inventario/lotes', {
      q: $('#l-buscar').value.trim(), estado: $('#l-estado').value,
      con_existencia: $('#l-agotados').checked ? '0' : '1', pagina: p, por_pagina: 15,
    });
    lotes = r.datos;
    const editar = puede('inventario.editar');
    cuerpo.innerHTML = lotes.length ? html`${lotes.map((l) => html`<tr>
      <td class="mono fuerte">${l.numero_lote}</td>
      <td><div class="titulo-celda">${l.medicamento}</div><div class="sub-celda">${l.concentracion || ''} ${l.forma_farmaceutica} · ${l.categoria}</div></td>
      <td>${l.proveedor || '—'}</td>
      <td class="nowrap">${fecha(l.fecha_vencimiento)}<div class="sub-celda">${l.dias_para_vencer < 0 ? `hace ${-l.dias_para_vencer} días` : `en ${l.dias_para_vencer} días`}</div></td>
      <td class="num">${numero(l.cantidad_inicial)}</td>
      <td class="num fuerte">${numero(l.cantidad_actual)}</td>
      <td class="num">${moneda(l.valor_costo)}</td>
      <td>${insignia(l.estado_vencimiento)}</td>
      <td class="acciones-celda"><div class="acciones">
        <button class="btn-icono" data-accion="kardex" data-lote="${l.numero_lote}" title="Ver movimientos">${icono('kardex')}</button>
        ${editar ? html`<button class="btn-icono" data-accion="ajustar" data-id="${l.id_lote}" title="Ajustar existencias">${icono('ajuste')}</button>` : ''}
      </div></td>
    </tr>`)}` : filaVacia(9);
    paginacion($('#lotes-paginacion'), r, cargarLotes);
  } catch (e) {
    cuerpo.innerHTML = filaVacia(9, 'No fue posible cargar los lotes', e.message);
  }
}

$('#lotes-cuerpo').addEventListener('click', (e) => {
  const boton = e.target.closest('button[data-accion]');
  if (!boton) return;
  if (boton.dataset.accion === 'kardex') {
    $('#k-buscar').value = boton.dataset.lote;
    document.querySelector('[data-pestana="tab-kardex"]').click();
  }
  if (boton.dataset.accion === 'ajustar') abrirAjuste(lotes.find((l) => l.id_lote === Number(boton.dataset.id)));
});

/* ---------------------------------- Ajustes ---------------------------------- */
const formAjuste = $('#form-ajuste');
function abrirAjuste(lote) {
  formAjuste.reset();
  formAjuste.id_lote.value = lote.id_lote;
  $('#ajuste-info').innerHTML = html`${icono('info')}<div><strong>${lote.medicamento}</strong> · Lote ${lote.numero_lote}<br>
    Existencia actual: <strong>${numero(lote.cantidad_actual)}</strong> und. · Vence ${fecha(lote.fecha_vencimiento)}</div>`;
  abrirModal('modal-ajuste');
}
formAjuste.addEventListener('submit', async (e) => {
  e.preventDefault();
  const r = await conCarga($('#btn-guardar-ajuste'), () => api.post('/api/inventario/ajustes', leerFormulario(formAjuste)), formAjuste);
  if (r) { toast(r.mensaje); cerrarModal('modal-ajuste'); cargarLotes(); cargadas.delete('tab-kardex'); }
});

/* ---------------------------------- Entradas ---------------------------------- */
async function cargarEntradas(p = paginas.entradas) {
  paginas.entradas = p;
  const cuerpo = $('#entradas-cuerpo');
  cuerpo.innerHTML = html`${filasCargando(8)}`;
  try {
    const r = await api.get('/api/inventario/entradas', { q: $('#e-buscar').value.trim(), desde: $('#e-desde').value, hasta: $('#e-hasta').value, pagina: p });
    cuerpo.innerHTML = r.datos.length ? html`${r.datos.map((e) => html`<tr>
      <td class="mono fuerte">${e.numero_factura}</td>
      <td class="nowrap">${fechaHora(e.fecha_entrada)}</td>
      <td>${e.proveedor}</td>
      <td class="num">${numero(e.productos)}</td>
      <td class="num">${numero(e.unidades)}</td>
      <td class="num fuerte">${moneda(e.total)}</td>
      <td>${e.usuario}</td>
      <td class="acciones-celda"><button class="btn-icono" data-id="${e.id_entrada}" title="Ver detalle">${icono('ojo')}</button></td>
    </tr>`)}` : filaVacia(8);
    paginacion($('#entradas-paginacion'), r, cargarEntradas);
  } catch (e) {
    cuerpo.innerHTML = filaVacia(8, 'No fue posible cargar las entradas', e.message);
  }
}

$('#entradas-cuerpo').addEventListener('click', async (e) => {
  const boton = e.target.closest('button[data-id]');
  if (!boton) return;
  const cuerpo = $('#detalle-entrada-cuerpo');
  cuerpo.innerHTML = '<div class="esqueleto" style="height:100px"></div>';
  abrirModal('modal-detalle-entrada');
  try {
    const d = await api.get(`/api/inventario/entradas/${boton.dataset.id}`);
    $('#titulo-detalle-entrada').textContent = `Factura ${d.numero_factura}`;
    cuerpo.innerHTML = html`
      <dl class="detalle-lista">
        <div><dt>Proveedor</dt><dd>${d.proveedor} (NIT ${d.nit})</dd></div>
        <div><dt>Fecha</dt><dd>${fechaHora(d.fecha_entrada)}</dd></div>
        <div><dt>Registró</dt><dd>${d.usuario}</dd></div>
        <div><dt>Observaciones</dt><dd>${d.observaciones || '—'}</dd></div>
      </dl>
      <table class="tabla tabla-compacta mt-2">
        <thead><tr><th>Medicamento</th><th>Lote</th><th>Vence</th><th class="num">Cantidad</th><th class="num">Costo</th><th class="num">Subtotal</th></tr></thead>
        <tbody>${d.detalle.map((x) => html`<tr><td>${x.nombre}<div class="sub-celda mono">${x.codigo}</div></td>
          <td class="mono">${x.numero_lote}</td><td>${fecha(x.fecha_vencimiento)}</td><td class="num">${numero(x.cantidad)}</td>
          <td class="num">${moneda(x.costo_unitario)}</td><td class="num">${moneda(x.subtotal)}</td></tr>`)}</tbody>
        <tfoot><tr><td colspan="5" class="num">Total</td><td class="num">${moneda(d.total)}</td></tr></tfoot>
      </table>`;
  } catch (err) {
    cerrarModal('modal-detalle-entrada');
    toastError(err);
  }
});

/* ---------------------------------- Kárdex ---------------------------------- */
async function cargarKardex(p = paginas.kardex) {
  paginas.kardex = p;
  const cuerpo = $('#kardex-cuerpo');
  cuerpo.innerHTML = html`${filasCargando(8)}`;
  try {
    const r = await api.get('/api/inventario/movimientos', {
      q: $('#k-buscar').value.trim(), tipo: $('#k-tipo').value, desde: $('#k-desde').value, hasta: $('#k-hasta').value, pagina: p,
    });
    cuerpo.innerHTML = r.datos.length ? html`${r.datos.map((m) => {
      const [tipo, texto, signo] = TIPOS[m.tipo];
      return html`<tr>
        <td class="nowrap">${fechaHora(m.fecha)}</td>
        <td><span class="insignia insignia-${tipo}">${texto}</span></td>
        <td>${m.medicamento}<div class="sub-celda mono">${m.codigo}</div></td>
        <td class="mono">${m.numero_lote}</td>
        <td class="num fuerte ${signo === '+' ? 'exito-txt' : 'peligro-txt'}">${signo}${numero(m.cantidad)}</td>
        <td class="num">${numero(m.saldo_lote)}</td>
        <td class="texto-2">${m.id_venta ? html`<a href="/ventas/${m.id_venta}/comprobante" target="_blank" rel="noopener">${m.motivo}</a>` : m.motivo || '—'}</td>
        <td>${m.usuario || '—'}</td>
      </tr>`;
    })}` : filaVacia(8);
    paginacion($('#kardex-paginacion'), r, cargarKardex);
  } catch (e) {
    cuerpo.innerHTML = filaVacia(8, 'No fue posible cargar el kárdex', e.message);
  }
}

/* ---------------------------- Formulario de entrada ---------------------------- */
const formEntrada = $('#form-entrada');
let lineas = [];
let encontrados = [];

function pintarLineas() {
  const cuerpo = $('#e-lineas');
  if (!lineas.length) {
    cuerpo.innerHTML = html`<tr><td colspan="8"><div class="vacio" style="padding:24px">Agregue los medicamentos recibidos con el buscador.</div></td></tr>`;
  } else {
    cuerpo.innerHTML = html`${lineas.map((l, i) => html`<tr>
      <td><div class="titulo-celda">${l.nombre}</div><div class="sub-celda mono">${l.codigo}</div></td>
      <td><div class="campo"><input class="control" name="items.${i}.numero_lote" data-i="${i}" data-campo="numero_lote" value="${l.numero_lote}" maxlength="40" style="height:34px;min-width:110px;text-transform:uppercase"></div></td>
      <td><div class="campo"><input class="control" type="date" name="items.${i}.fecha_fabricacion" data-i="${i}" data-campo="fecha_fabricacion" value="${l.fecha_fabricacion}" style="height:34px"></div></td>
      <td><div class="campo"><input class="control" type="date" name="items.${i}.fecha_vencimiento" data-i="${i}" data-campo="fecha_vencimiento" value="${l.fecha_vencimiento}" min="${fechaISO(sumarDias(new Date(), 1))}" style="height:34px"></div></td>
      <td><div class="campo"><input class="control num" type="number" min="1" step="1" name="items.${i}.cantidad" data-i="${i}" data-campo="cantidad" value="${l.cantidad}" style="height:34px;width:90px"></div></td>
      <td><div class="campo"><input class="control num" type="number" min="0" step="50" name="items.${i}.costo_unitario" data-i="${i}" data-campo="costo_unitario" value="${l.costo_unitario}" style="height:34px;width:110px"></div></td>
      <td class="num fuerte" data-subtotal="${i}">${moneda(l.cantidad * l.costo_unitario)}</td>
      <td><button type="button" class="btn-icono peligro" data-quitar="${i}" title="Quitar">${icono('x')}</button></td>
    </tr>`)}`;
  }
  actualizarTotalEntrada();
}

function actualizarTotalEntrada() {
  $('#e-total').textContent = moneda(lineas.reduce((s, l) => s + (Number(l.cantidad) || 0) * (Number(l.costo_unitario) || 0), 0));
}

$('#e-lineas').addEventListener('input', (e) => {
  const el = e.target;
  if (el.dataset.i === undefined) return;
  const linea = lineas[Number(el.dataset.i)];
  linea[el.dataset.campo] = el.dataset.campo === 'numero_lote' ? el.value.toUpperCase() : el.value;
  const celda = $(`[data-subtotal="${el.dataset.i}"]`);
  if (celda) celda.textContent = moneda((Number(linea.cantidad) || 0) * (Number(linea.costo_unitario) || 0));
  actualizarTotalEntrada();
});
$('#e-lineas').addEventListener('click', (e) => {
  const boton = e.target.closest('[data-quitar]');
  if (!boton) return;
  lineas.splice(Number(boton.dataset.quitar), 1);
  pintarLineas();
});

const buscadorMed = $('#e-buscar-med');
const resultadosMed = $('#e-resultados');
buscadorMed.addEventListener('input', debounce(async () => {
  const q = buscadorMed.value.trim();
  if (q.length < 2) { resultadosMed.hidden = true; return; }
  try {
    encontrados = await api.get('/api/medicamentos/buscar', { q });
    resultadosMed.innerHTML = encontrados.length ? html`${encontrados.map((m, i) => html`
      <button type="button" class="resultado" data-i="${i}">
        <div class="resultado-info"><strong>${m.nombre}</strong><span>${m.principio_activo} · ${m.presentacion || m.forma_farmaceutica} · <span class="mono">${m.codigo}</span></span></div>
        <div class="resultado-precio"><strong>${moneda(m.precio_compra)}</strong><span>${numero(m.stock_disponible)} en stock</span></div>
      </button>`)}` : html`<div class="vacio" style="padding:16px">Sin coincidencias</div>`;
    resultadosMed.hidden = false;
  } catch (err) { toastError(err); }
}, 250));
resultadosMed.addEventListener('click', (e) => {
  const opcion = e.target.closest('.resultado');
  if (!opcion) return;
  const m = encontrados[Number(opcion.dataset.i)];
  lineas.push({
    id_medicamento: m.id_medicamento, nombre: m.nombre, codigo: m.codigo, numero_lote: '',
    fecha_fabricacion: '', fecha_vencimiento: '', cantidad: 1, costo_unitario: Number(m.precio_compra),
  });
  buscadorMed.value = '';
  resultadosMed.hidden = true;
  pintarLineas();
  $(`[name="items.${lineas.length - 1}.numero_lote"]`)?.focus();
});

async function abrirEntrada() {
  formEntrada.reset();
  lineas = [];
  pintarLineas();
  try {
    const proveedores = await api.get('/api/proveedores/opciones');
    llenarSelect($('#e-proveedor'), proveedores.map((p) => ({ valor: p.id_proveedor, texto: p.razon_social })), { vacio: 'Seleccione…' });
  } catch (e) { toastError(e); }
  abrirModal('modal-entrada');
}

formEntrada.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!lineas.length) return toast('Agregue al menos un medicamento a la entrada', 'alerta');
  const limite = fechaISO(sumarDias(new Date(), 90));
  const cortas = lineas.filter((l) => l.fecha_vencimiento && l.fecha_vencimiento <= limite);
  if (cortas.length && !(await confirmar({
    titulo: 'Vencimiento corto',
    mensaje: `${cortas.length} lote(s) vencen en menos de 90 días. ¿Desea recibirlos de todas formas?`,
    textoBoton: 'Sí, recibir',
  }))) return;

  const cabecera = leerFormulario(formEntrada);
  const datos = {
    id_proveedor: cabecera.id_proveedor,
    numero_factura: cabecera.numero_factura,
    observaciones: cabecera.observaciones,
    items: lineas.map(({ id_medicamento, numero_lote, fecha_fabricacion, fecha_vencimiento, cantidad, costo_unitario }) => ({
      id_medicamento, numero_lote, fecha_fabricacion, fecha_vencimiento, cantidad, costo_unitario,
    })),
  };
  const boton = $('#btn-guardar-entrada');
  boton.classList.add('cargando');
  boton.disabled = true;
  try {
    const r = await api.post('/api/inventario/entradas', datos);
    toast(`${r.mensaje} por ${moneda(r.total)}`);
    // Costos que superan el precio de venta: la entrada se guardó, pero hay que revisar el precio
    (r.advertencias || []).forEach((aviso) => toast(aviso, 'alerta', 10000));
    cerrarModal('modal-entrada');
    cargadas.clear();
    document.querySelector('.pestana.activa').click();
  } catch (err) {
    if (err.errores) mostrarErrores(formEntrada, err.errores);
    toastError(err);
  } finally {
    boton.classList.remove('cargando');
    boton.disabled = false;
  }
});

/* ---------------------------------- Inicio ---------------------------------- */
const CARGADORES = { 'tab-lotes': () => cargarLotes(1), 'tab-entradas': () => cargarEntradas(1), 'tab-kardex': () => cargarKardex(1) };
pestanas(document, (id) => {
  if (id === 'tab-kardex' || !cargadas.has(id)) { cargadas.add(id); CARGADORES[id](); }
});

$('#l-buscar').addEventListener('input', debounce(() => cargarLotes(1)));
$('#l-estado').addEventListener('change', () => cargarLotes(1));
$('#l-agotados').addEventListener('change', () => cargarLotes(1));
$('#e-buscar').addEventListener('input', debounce(() => cargarEntradas(1)));
['#e-desde', '#e-hasta'].forEach((s) => $(s).addEventListener('change', () => cargarEntradas(1)));
$('#k-buscar').addEventListener('input', debounce(() => cargarKardex(1)));
['#k-tipo', '#k-desde', '#k-hasta'].forEach((s) => $(s).addEventListener('change', () => cargarKardex(1)));
$('#btn-entrada')?.addEventListener('click', abrirEntrada);
document.addEventListener('click', (e) => { if (!e.target.closest('.pos-buscador')) resultadosMed.hidden = true; });

cargadas.add('tab-lotes');
cargarLotes(1);
if (window.location.hash === '#entrada' && puede('inventario.editar')) abrirEntrada();
