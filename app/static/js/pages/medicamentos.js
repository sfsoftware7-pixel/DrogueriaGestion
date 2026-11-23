import {
  $, abrirModal, api, cerrarModal, conCarga, confirmar, debounce, exportarCSV, fecha, fechaHora, filaVacia,
  filasCargando, html, icono, insignia, insigniaActivo, leerFormulario, llenarFormulario, llenarSelect, moneda,
  numero, paginacion, puede, toast, toastError,
} from '../core.js';

const estado = { pagina: 1, editando: null, ultimos: [] };
const form = $('#form-medicamento');
const params = new URLSearchParams(window.location.search);
if (params.get('estado_stock')) $('#f-stock').value = params.get('estado_stock');

function filtros() {
  return {
    q: $('#f-buscar').value.trim(),
    categoria: $('#f-categoria').value,
    estado_stock: $('#f-stock').value,
    activo: $('#f-activo').value,
    orden: $('#f-orden').value,
  };
}

function etiquetas(m) {
  if (m.es_controlado) return html` <span class="etiqueta-rx control-esp" title="Control especial">CE</span>`;
  if (m.requiere_formula) return html` <span class="etiqueta-rx" title="Requiere fórmula médica">Rx</span>`;
  return '';
}

function fila(m) {
  const editar = puede('medicamentos.editar');
  return html`<tr class="${m.activo ? '' : 'inactivo'}">
    <td class="mono">${m.codigo}</td>
    <td>
      <div class="titulo-celda">${m.nombre}${etiquetas(m)}</div>
      <div class="sub-celda">${m.principio_activo}${m.concentracion ? ` · ${m.concentracion}` : ''} · ${m.forma_farmaceutica}</div>
    </td>
    <td>${m.categoria}</td>
    <td class="num">${moneda(m.precio_venta)}${Number(m.iva_porcentaje) ? html`<div class="sub-celda">+ IVA ${Number(m.iva_porcentaje)}%</div>` : ''}</td>
    <td class="num"><strong>${numero(m.stock_disponible)}</strong><div class="sub-celda">mín. ${m.stock_minimo}</div></td>
    <td>${m.proximo_vencimiento ? fecha(m.proximo_vencimiento) : html`<span class="tenue">—</span>`}</td>
    <td>${m.activo ? insignia(m.estado_stock) : insigniaActivo(false)}</td>
    <td class="acciones-celda"><div class="acciones">
      <button class="btn-icono" data-accion="ver" data-id="${m.id_medicamento}" title="Ver detalle">${icono('ojo')}</button>
      ${editar ? html`
        <button class="btn-icono" data-accion="editar" data-id="${m.id_medicamento}" title="Editar">${icono('editar')}</button>
        <button class="btn-icono ${m.activo ? 'peligro' : 'exito'}" data-accion="estado" data-id="${m.id_medicamento}"
          data-activo="${m.activo}" title="${m.activo ? 'Desactivar' : 'Activar'}">${icono('encender')}</button>` : ''}
    </div></td>
  </tr>`;
}

async function cargar(pagina = estado.pagina) {
  estado.pagina = pagina;
  const cuerpo = $('#tabla-cuerpo');
  cuerpo.innerHTML = html`${filasCargando(8)}`;
  try {
    const r = await api.get('/api/medicamentos', { ...filtros(), pagina, por_pagina: 15 });
    estado.ultimos = r.datos;
    cuerpo.innerHTML = r.datos.length ? html`${r.datos.map(fila)}` : filaVacia(8);
    paginacion($('#paginacion'), r, cargar);
  } catch (e) {
    cuerpo.innerHTML = filaVacia(8, 'No fue posible cargar los medicamentos', e.message);
  }
}

async function cargarCatalogos() {
  const [categorias, formas] = await Promise.all([api.get('/api/categorias', { activas: 1 }), api.get('/api/medicamentos/formas')]);
  const opciones = categorias.map((c) => ({ valor: c.id_categoria, texto: c.nombre }));
  llenarSelect($('#f-categoria'), opciones, { vacio: 'Todas las categorías' });
  llenarSelect($('#m-categoria'), opciones, { vacio: 'Seleccione…' });
  llenarSelect($('#m-forma'), formas.map((f) => ({ valor: f, texto: f })), { vacio: 'Seleccione…' });
}

function actualizarMargen() {
  const compra = Number(form.precio_compra.value);
  const venta = Number(form.precio_venta.value);
  const ayuda = $('#m-margen');
  if (compra > 0 && venta > 0) {
    const margen = ((venta - compra) / venta) * 100;
    ayuda.textContent = `Margen: ${margen.toFixed(1)} %`;
    ayuda.className = `ayuda ${margen < 0 ? 'peligro-txt' : margen < 15 ? 'alerta-txt' : 'exito-txt'}`;
  } else {
    ayuda.innerHTML = '&nbsp;';
  }
}

function abrirFormulario(med = null) {
  estado.editando = med?.id_medicamento ?? null;
  form.reset();
  $('#titulo-medicamento').textContent = med ? `Editar: ${med.nombre}` : 'Nuevo medicamento';
  if (med) llenarFormulario(form, { ...med, iva_porcentaje: String(Number(med.iva_porcentaje)) });
  actualizarMargen();
  abrirModal('modal-medicamento');
}

async function verDetalle(id) {
  const cuerpo = $('#detalle-cuerpo');
  cuerpo.innerHTML = '<div class="esqueleto" style="height:120px"></div>';
  abrirModal('modal-detalle');
  try {
    const m = await api.get(`/api/medicamentos/${id}`);
    $('#titulo-detalle').textContent = m.nombre;
    cuerpo.innerHTML = html`
      <dl class="detalle-lista">
        <div><dt>Código</dt><dd class="mono">${m.codigo}</dd></div>
        <div><dt>Categoría</dt><dd>${m.categoria}</dd></div>
        <div><dt>Principio activo</dt><dd>${m.principio_activo} ${m.concentracion || ''}</dd></div>
        <div><dt>Forma / presentación</dt><dd>${m.forma_farmaceutica}${m.presentacion ? ` · ${m.presentacion}` : ''}</dd></div>
        <div><dt>Laboratorio</dt><dd>${m.laboratorio || '—'}</dd></div>
        <div><dt>Registro INVIMA</dt><dd>${m.registro_invima || '—'}</dd></div>
        <div><dt>Precio de venta</dt><dd>${moneda(m.precio_venta)} ${Number(m.iva_porcentaje) ? `+ IVA ${Number(m.iva_porcentaje)}%` : '(excluido de IVA)'}</dd></div>
        ${m.precio_compra !== undefined ? html`<div><dt>Último costo</dt><dd>${moneda(m.precio_compra)}</dd></div>` : ''}
        <div><dt>Existencia disponible</dt><dd><strong>${numero(m.stock_disponible)}</strong> und. ${insignia(m.estado_stock)}
          <span class="tenue" title="Calculado con la función almacenada fn_stock_disponible">(fn: ${m.stock_funcion})</span></dd></div>
        <div><dt>Ubicación</dt><dd>${m.ubicacion || '—'}</dd></div>
        <div><dt>Dispensación</dt><dd>${m.es_controlado ? 'Control especial (fórmula obligatoria)' : m.requiere_formula ? 'Bajo fórmula médica' : 'Venta libre'}</dd></div>
        <div><dt>Unidades vencidas sin dar de baja</dt><dd>${numero(m.stock_vencido)}</dd></div>
      </dl>
      <h3 class="mt-3" style="font-size:14px">Lotes con existencias (orden FEFO)</h3>
      <div class="tabla-contenedor mt-1">
        <table class="tabla tabla-compacta">
          <thead><tr><th>Lote</th><th>Proveedor</th><th>Vence</th><th class="num">Existencia</th><th>Estado</th></tr></thead>
          <tbody>${m.lotes.length ? m.lotes.map((l) => html`<tr>
            <td class="mono">${l.numero_lote}</td><td>${l.proveedor || '—'}</td><td>${fecha(l.fecha_vencimiento)}</td>
            <td class="num">${numero(l.cantidad_actual)}</td><td>${insignia(l.estado_vencimiento)}</td></tr>`)
            : filaVacia(5, 'Sin lotes con existencias', 'Registre una entrada de mercancía.')}</tbody>
        </table>
      </div>
      ${m.historial_precios.length ? html`
        <h3 class="mt-3" style="font-size:14px">Historial de precios <span class="tenue" style="font-weight:400">(registrado por trigger)</span></h3>
        <table class="tabla tabla-compacta mt-1">
          <thead><tr><th>Fecha</th><th class="num">Anterior</th><th class="num">Nuevo</th><th>Usuario</th></tr></thead>
          <tbody>${m.historial_precios.map((h) => html`<tr><td>${fechaHora(h.fecha)}</td>
            <td class="num">${moneda(h.precio_venta_anterior)}</td><td class="num">${moneda(h.precio_venta_nuevo)}</td>
            <td>${h.usuario || '—'}</td></tr>`)}</tbody>
        </table>` : ''}`;
  } catch (e) {
    cerrarModal('modal-detalle');
    toastError(e);
  }
}

$('#tabla-cuerpo').addEventListener('click', async (e) => {
  const boton = e.target.closest('button[data-accion]');
  if (!boton) return;
  const id = Number(boton.dataset.id);
  if (boton.dataset.accion === 'ver') return verDetalle(id);
  if (boton.dataset.accion === 'editar') {
    try { abrirFormulario(await api.get(`/api/medicamentos/${id}`)); } catch (err) { toastError(err); }
    return;
  }
  if (boton.dataset.accion === 'estado') {
    const activar = boton.dataset.activo === '0';
    const ok = await confirmar({
      titulo: activar ? 'Activar medicamento' : 'Desactivar medicamento',
      mensaje: activar ? 'El medicamento volverá a estar disponible para la venta.'
        : 'El medicamento no aparecerá en el punto de venta. Su historial se conserva.',
      textoBoton: activar ? 'Activar' : 'Desactivar',
      peligro: !activar,
    });
    if (!ok) return;
    try {
      const r = await api.patch(`/api/medicamentos/${id}/estado`, { activo: activar });
      toast(r.mensaje);
      cargar();
    } catch (err) { toastError(err); }
  }
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const datos = leerFormulario(form);
  const r = await conCarga($('#btn-guardar'), () => (estado.editando
    ? api.put(`/api/medicamentos/${estado.editando}`, datos)
    : api.post('/api/medicamentos', datos)), form);
  if (r) {
    toast(r.mensaje);
    cerrarModal('modal-medicamento');
    cargar();
  }
});

form.es_controlado.addEventListener('change', () => { if (form.es_controlado.checked) form.requiere_formula.checked = true; });
form.precio_compra.addEventListener('input', actualizarMargen);
form.precio_venta.addEventListener('input', actualizarMargen);
$('#btn-nuevo')?.addEventListener('click', () => abrirFormulario());
$('#f-buscar').addEventListener('input', debounce(() => cargar(1)));
['#f-categoria', '#f-stock', '#f-activo', '#f-orden'].forEach((s) => $(s).addEventListener('change', () => cargar(1)));

$('#btn-exportar').addEventListener('click', async () => {
  try {
    const r = await api.get('/api/medicamentos', { ...filtros(), pagina: 1, por_pagina: 100 });
    exportarCSV('medicamentos', [
      { titulo: 'Código', valor: 'codigo' }, { titulo: 'Nombre', valor: 'nombre' },
      { titulo: 'Principio activo', valor: 'principio_activo' }, { titulo: 'Concentración', valor: 'concentracion' },
      { titulo: 'Forma', valor: 'forma_farmaceutica' }, { titulo: 'Categoría', valor: 'categoria' },
      { titulo: 'Laboratorio', valor: 'laboratorio' }, { titulo: 'Precio venta', valor: 'precio_venta' },
      { titulo: 'IVA %', valor: 'iva_porcentaje' }, { titulo: 'Disponible', valor: 'stock_disponible' },
      { titulo: 'Stock mínimo', valor: 'stock_minimo' }, { titulo: 'Estado', valor: 'estado_stock' },
      { titulo: 'Próximo vencimiento', valor: 'proximo_vencimiento' },
    ], r.datos);
    if (r.total > r.datos.length) toast(`Se exportaron los primeros ${r.datos.length} de ${r.total}. Use filtros para acotar.`, 'info');
  } catch (err) { toastError(err); }
});

cargarCatalogos().catch(toastError).finally(() => {
  if (params.get('categoria')) $('#f-categoria').value = params.get('categoria');
  cargar(1);
});
