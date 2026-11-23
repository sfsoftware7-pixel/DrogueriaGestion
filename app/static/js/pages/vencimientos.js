import {
  $, $$, api, confirmar, exportarCSV, fecha, filaVacia, filasCargando, html, insignia, moneda, numero, paginacion,
  toast, toastError,
} from '../core.js';

const TITULOS = {
  '': 'Lotes vencidos y por vencer',
  VENCIDO: 'Lotes vencidos con existencias',
  CRITICO: 'Lotes que vencen en los próximos 30 días',
  PROXIMO: 'Lotes que vencen entre 31 y 90 días',
  VIGENTE: 'Lotes vigentes (más de 90 días)',
};
let estadoFiltro = '';
let pagina = 1;

async function cargarResumen() {
  try {
    const resumen = await api.get('/api/inventario/vencimientos/resumen');
    for (const r of resumen) {
      $(`[data-valor="${r.estado}"]`).textContent = numero(r.lotes);
      $(`[data-detalle="${r.estado}"]`).textContent = `${numero(r.unidades)} und. · ${moneda(r.valor)}`;
    }
    const vencidos = resumen.find((r) => r.estado === 'VENCIDO');
    const boton = $('#btn-baja');
    if (boton) boton.disabled = !Number(vencidos?.lotes);
  } catch (e) { toastError(e); }
}

async function consultar(p, porPagina) {
  // Sin filtro se muestran vencidos, críticos y próximos (lo que requiere atención)
  if (estadoFiltro) return api.get('/api/inventario/lotes', { estado: estadoFiltro, pagina: p, por_pagina: porPagina });
  const partes = await Promise.all(['VENCIDO', 'CRITICO', 'PROXIMO'].map((e) => api.get('/api/inventario/lotes', { estado: e, pagina: 1, por_pagina: 100 })));
  const datos = partes.flatMap((r) => r.datos).sort((a, b) => a.fecha_vencimiento.localeCompare(b.fecha_vencimiento));
  const total = datos.length;
  return { datos: datos.slice((p - 1) * porPagina, p * porPagina), total, pagina: p, por_pagina: porPagina, paginas: Math.max(1, Math.ceil(total / porPagina)) };
}

async function cargar(p = pagina) {
  pagina = p;
  $('#titulo-lista').textContent = TITULOS[estadoFiltro];
  $$('.semaforo-item').forEach((b) => b.classList.toggle('activo', b.dataset.estado === estadoFiltro));
  const cuerpo = $('#tabla-cuerpo');
  cuerpo.innerHTML = html`${filasCargando(8)}`;
  try {
    const r = await consultar(p, 15);
    cuerpo.innerHTML = r.datos.length ? html`${r.datos.map((l) => html`<tr>
      <td><div class="titulo-celda">${l.medicamento}</div><div class="sub-celda">${l.concentracion || ''} ${l.forma_farmaceutica}</div></td>
      <td class="mono">${l.numero_lote}</td>
      <td>${l.proveedor || '—'}</td>
      <td class="nowrap">${fecha(l.fecha_vencimiento)}</td>
      <td class="num fuerte ${l.dias_para_vencer < 0 ? 'peligro-txt' : l.dias_para_vencer <= 30 ? 'alerta-txt' : ''}">${l.dias_para_vencer}</td>
      <td class="num">${numero(l.cantidad_actual)}</td>
      <td class="num">${moneda(l.valor_costo)}</td>
      <td>${insignia(l.estado_vencimiento)}</td>
    </tr>`)}` : filaVacia(8, 'No hay lotes en este estado', '¡Excelente! No se requiere acción.');
    paginacion($('#paginacion'), r, cargar);
  } catch (e) {
    cuerpo.innerHTML = filaVacia(8, 'No fue posible cargar', e.message);
  }
}

$('#semaforo').addEventListener('click', (e) => {
  const item = e.target.closest('.semaforo-item');
  if (!item) return;
  estadoFiltro = estadoFiltro === item.dataset.estado ? '' : item.dataset.estado;
  cargar(1);
});

$('#btn-baja')?.addEventListener('click', async () => {
  const ok = await confirmar({
    titulo: 'Dar de baja lotes vencidos',
    mensaje: 'Todas las existencias de lotes vencidos pasarán a cero y se registrará un movimiento de BAJA en el kárdex (procedimiento almacenado sp_dar_baja_lotes_vencidos). Realice la destrucción o devolución según la normativa vigente.',
    textoBoton: 'Dar de baja',
    peligro: true,
  });
  if (!ok) return;
  try {
    const r = await api.post('/api/inventario/vencimientos/baja');
    toast(r.mensaje, r.lotes_afectados ? 'exito' : 'info');
    cargarResumen();
    cargar(1);
  } catch (e) { toastError(e); }
});

$('#btn-exportar').addEventListener('click', async () => {
  try {
    const r = await consultar(1, 1000);
    exportarCSV('vencimientos', [
      { titulo: 'Medicamento', valor: 'medicamento' }, { titulo: 'Código', valor: 'codigo' },
      { titulo: 'Lote', valor: 'numero_lote' }, { titulo: 'Proveedor', valor: 'proveedor' },
      { titulo: 'Vencimiento', valor: 'fecha_vencimiento' }, { titulo: 'Días para vencer', valor: 'dias_para_vencer' },
      { titulo: 'Existencia', valor: 'cantidad_actual' }, { titulo: 'Valor costo', valor: 'valor_costo' },
      { titulo: 'Estado', valor: 'estado_vencimiento' },
    ], r.datos);
  } catch (e) { toastError(e); }
});

cargarResumen();
cargar(1);
