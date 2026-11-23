import {
  $, abrirModal, api, cerrarModal, confirmar, debounce, exportarCSV, fecha, fechaHora, fechaISO, filaVacia,
  filasCargando, html, icono, insignia, METODOS_PAGO, moneda, numero, paginacion, puede, sumarDias, toast, toastError,
} from '../core.js';

let pagina = 1;

$('#f-desde').value = fechaISO(sumarDias(new Date(), -30));
$('#f-hasta').value = fechaISO();

const filtros = () => ({
  q: $('#f-buscar').value.trim(),
  desde: $('#f-desde').value,
  hasta: $('#f-hasta').value,
  estado: $('#f-estado').value,
  metodo_pago: $('#f-metodo').value,
});

async function cargar(p = pagina) {
  pagina = p;
  const cuerpo = $('#tabla-cuerpo');
  cuerpo.innerHTML = html`${filasCargando(9)}`;
  try {
    const r = await api.get('/api/ventas', { ...filtros(), pagina, por_pagina: 15 });
    $('#resumen-filtro').innerHTML = html`<strong>${numero(r.resumen.ventas)}</strong> ventas completadas por <strong>${moneda(r.resumen.total)}</strong>`;
    cuerpo.innerHTML = r.datos.length ? html`${r.datos.map((v) => html`
      <tr class="${v.estado === 'ANULADA' ? 'inactivo' : ''}">
        <td class="mono fuerte">${v.numero_factura}</td>
        <td class="nowrap">${fechaHora(v.fecha_venta)}</td>
        <td>${v.cliente}<div class="sub-celda">${v.tipo_documento} ${v.numero_documento}</div></td>
        <td>${v.vendedor}</td>
        <td>${METODOS_PAGO[v.metodo_pago]}</td>
        <td class="num">${numero(v.unidades)}</td>
        <td class="num fuerte">${moneda(v.total)}</td>
        <td>${insignia(v.estado)}</td>
        <td class="acciones-celda"><div class="acciones">
          <button class="btn-icono" data-accion="ver" data-id="${v.id_venta}" title="Ver detalle">${icono('ojo')}</button>
          <a class="btn-icono" href="/ventas/${v.id_venta}/comprobante" target="_blank" rel="noopener" title="Comprobante">${icono('imprimir')}</a>
          ${puede('ventas.anular') && v.estado === 'COMPLETADA'
            ? html`<button class="btn-icono peligro" data-accion="anular" data-id="${v.id_venta}" data-numero="${v.numero_factura}" title="Anular">${icono('anular')}</button>` : ''}
        </div></td>
      </tr>`)}` : filaVacia(9, 'No hay ventas en el periodo seleccionado');
    paginacion($('#paginacion'), r, cargar);
  } catch (e) {
    cuerpo.innerHTML = filaVacia(9, 'No fue posible cargar las ventas', e.message);
  }
}

async function anular(id, numeroFactura) {
  const motivo = await confirmar({
    titulo: `Anular venta ${numeroFactura}`,
    mensaje: 'Las unidades vendidas regresarán a sus lotes de origen y quedará registro en el kárdex y la auditoría. Esta acción no se puede deshacer.',
    textoBoton: 'Anular venta',
    peligro: true,
    motivo: true,
  });
  if (!motivo) return;
  try {
    const r = await api.post(`/api/ventas/${id}/anular`, { motivo });
    toast(r.mensaje);
    cerrarModal('modal-detalle');
    cargar();
  } catch (e) { toastError(e); }
}

async function verDetalle(id) {
  const cuerpo = $('#detalle-cuerpo');
  cuerpo.innerHTML = '<div class="esqueleto" style="height:140px"></div>';
  $('#detalle-pie').innerHTML = '';
  abrirModal('modal-detalle');
  try {
    const v = await api.get(`/api/ventas/${id}`);
    $('#titulo-detalle').textContent = `Venta ${v.numero_factura}`;
    cuerpo.innerHTML = html`
      ${v.estado === 'ANULADA' ? html`<div class="aviso peligro mb">${icono('anular')}<div><strong>Venta anulada</strong> el ${fechaHora(v.fecha_anulacion)}. Motivo: ${v.motivo_anulacion}</div></div>` : ''}
      <dl class="detalle-lista">
        <div><dt>Fecha</dt><dd>${fechaHora(v.fecha_venta)}</dd></div>
        <div><dt>Vendedor</dt><dd>${v.vendedor}</dd></div>
        <div><dt>Cliente</dt><dd>${v.cliente} (${v.tipo_documento} ${v.numero_documento})</dd></div>
        <div><dt>Método de pago</dt><dd>${METODOS_PAGO[v.metodo_pago]}${v.metodo_pago === 'EFECTIVO' ? ` · recibido ${moneda(v.monto_recibido)} · cambio ${moneda(v.cambio)}` : ''}</dd></div>
        ${v.formula_medica ? html`<div><dt>Fórmula médica</dt><dd>${v.formula_medica}${v.medico ? ` · ${v.medico}` : ''}</dd></div>` : ''}
        ${v.observaciones ? html`<div><dt>Observaciones</dt><dd>${v.observaciones}</dd></div>` : ''}
      </dl>
      <div class="tabla-contenedor mt-2">
        <table class="tabla tabla-compacta">
          <thead><tr><th>Producto</th><th>Lote</th><th>Vence</th><th class="num">Cant.</th><th class="num">Precio</th><th class="num">IVA</th><th class="num">Subtotal</th></tr></thead>
          <tbody>${v.detalle.map((d) => html`<tr>
            <td>${d.nombre}<div class="sub-celda mono">${d.codigo}</div></td>
            <td class="mono">${d.numero_lote}</td><td>${fecha(d.fecha_vencimiento)}</td>
            <td class="num">${d.cantidad}</td><td class="num">${moneda(d.precio_unitario)}</td>
            <td class="num">${moneda(d.impuesto)}</td><td class="num">${moneda(d.subtotal)}</td></tr>`)}</tbody>
          <tfoot>
            <tr><td colspan="6" class="num">Subtotal</td><td class="num">${moneda(v.subtotal)}</td></tr>
            <tr><td colspan="6" class="num">IVA</td><td class="num">${moneda(v.impuesto)}</td></tr>
            ${Number(v.descuento) ? html`<tr><td colspan="6" class="num">Descuento</td><td class="num">- ${moneda(v.descuento)}</td></tr>` : ''}
            <tr><td colspan="6" class="num">Total</td><td class="num">${moneda(v.total)}</td></tr>
          </tfoot>
        </table>
      </div>`;
    $('#detalle-pie').innerHTML = html`
      ${puede('ventas.anular') && v.estado === 'COMPLETADA' ? html`<button class="btn btn-peligro" type="button" id="detalle-anular">${icono('anular')} Anular</button><span class="crecer"></span>` : ''}
      <a class="btn btn-secundario" href="/ventas/${v.id_venta}/comprobante" target="_blank" rel="noopener">${icono('imprimir')} Comprobante</a>
      <button class="btn btn-primario" type="button" data-cerrar-modal>Cerrar</button>`;
    $('#detalle-anular')?.addEventListener('click', () => anular(v.id_venta, v.numero_factura));
  } catch (e) {
    cerrarModal('modal-detalle');
    toastError(e);
  }
}

$('#tabla-cuerpo').addEventListener('click', (e) => {
  const boton = e.target.closest('button[data-accion]');
  if (!boton) return;
  if (boton.dataset.accion === 'ver') verDetalle(Number(boton.dataset.id));
  if (boton.dataset.accion === 'anular') anular(Number(boton.dataset.id), boton.dataset.numero);
});

$('#f-buscar').addEventListener('input', debounce(() => cargar(1)));
['#f-desde', '#f-hasta', '#f-estado', '#f-metodo'].forEach((s) => $(s).addEventListener('change', () => cargar(1)));

$('#btn-exportar').addEventListener('click', async () => {
  try {
    const r = await api.get('/api/ventas', { ...filtros(), pagina: 1, por_pagina: 100 });
    exportarCSV('ventas', [
      { titulo: 'Factura', valor: 'numero_factura' }, { titulo: 'Fecha', valor: 'fecha_venta' },
      { titulo: 'Cliente', valor: 'cliente' }, { titulo: 'Documento', valor: (v) => `${v.tipo_documento} ${v.numero_documento}` },
      { titulo: 'Vendedor', valor: 'vendedor' }, { titulo: 'Método de pago', valor: (v) => METODOS_PAGO[v.metodo_pago] },
      { titulo: 'Subtotal', valor: 'subtotal' }, { titulo: 'IVA', valor: 'impuesto' }, { titulo: 'Descuento', valor: 'descuento' },
      { titulo: 'Total', valor: 'total' }, { titulo: 'Estado', valor: 'estado' },
    ], r.datos);
    if (r.total > r.datos.length) toast(`Se exportaron las ${r.datos.length} ventas más recientes de ${r.total}.`, 'info');
  } catch (e) { toastError(e); }
});

cargar(1);
