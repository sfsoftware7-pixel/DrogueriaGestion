import {
  $, api, exportarCSV, fecha, fechaCorta, fechaISO, filaVacia, html, insignia, METODOS_PAGO, moneda, monedaCorta,
  numero, sumarDias, toastError,
} from '../core.js';
import { graficoBarras, graficoDona } from '../graficos.js';
import { activarVerSQL } from '../ver_sql.js';

const datos = { ventas: null, top: [], inventario: null };
const hoy = new Date();
$('#r-desde').value = fechaISO(sumarDias(hoy, -29));
$('#r-hasta').value = fechaISO(hoy);

function rango() {
  return { desde: $('#r-desde').value, hasta: $('#r-hasta').value };
}

/** Completa con ceros los días sin ventas para que la serie sea continua. */
function serieCompleta(diario, desde, hasta) {
  const porFecha = new Map(diario.map((d) => [d.fecha, d]));
  const serie = [];
  for (let d = new Date(desde + 'T00:00:00'); fechaISO(d) <= hasta; d = sumarDias(d, 1)) {
    const clave = fechaISO(d);
    const fila = porFecha.get(clave);
    serie.push({ fecha: clave, numero_ventas: fila?.numero_ventas || 0, total_ventas: Number(fila?.total_ventas || 0) });
  }
  return serie;
}

function pintarVentas(v) {
  const t = v.totales;
  $('#k-total').textContent = moneda(t.total);
  $('#k-total-d').textContent = `IVA ${moneda(t.impuestos)} · descuentos ${moneda(t.descuentos)}`;
  $('#k-ventas').textContent = numero(t.numero_ventas);
  $('#k-ventas-d').textContent = `Ticket promedio ${moneda(t.ticket_promedio)} · ${v.anuladas.n} anulada(s)`;
  const margen = Number(t.subtotal) ? (Number(t.utilidad_bruta) / (Number(t.subtotal) - Number(t.descuentos))) * 100 : 0;
  $('#k-utilidad').textContent = moneda(t.utilidad_bruta);
  $('#k-utilidad-d').textContent = `Margen ${margen.toFixed(1)} % · costo ${moneda(t.costo_ventas)}`;
  $('#k-unidades').textContent = numero(t.unidades);
  $('#k-unidades-d').textContent = `${fecha(v.desde)} – ${fecha(v.hasta)}`;

  const serie = serieCompleta(v.diario, v.desde, v.hasta);
  graficoBarras($('#g-diario'), serie.map((d) => ({
    etiqueta: fechaCorta(d.fecha), valor: d.total_ventas, detalle: `${fecha(d.fecha)} · ${d.numero_ventas} venta(s)`,
  })), { formato: moneda, formatoEje: monedaCorta });

  if (v.por_metodo.length) {
    graficoDona($('#g-metodos'), v.por_metodo.map((m) => ({ etiqueta: METODOS_PAGO[m.metodo_pago], valor: m.total })),
      { formato: moneda, centro: monedaCorta(t.total), etiquetaCentro: 'Total' });
  } else {
    $('#g-metodos').innerHTML = '<div class="vacio">Sin ventas en el periodo</div>';
  }

  const maxCat = Math.max(1, ...v.por_categoria.map((c) => Number(c.total)));
  $('#t-categorias').innerHTML = v.por_categoria.length ? html`${v.por_categoria.map((c) => html`<tr>
    <td>${c.categoria}</td><td class="num">${numero(c.unidades)}</td><td class="num">${moneda(c.total)}</td>
    <td><div class="barra-progreso"><span style="width:${(Number(c.total) / maxCat) * 100}%"></span></div></td></tr>`)}`
    : filaVacia(4, 'Sin ventas', '');

  $('#t-vendedores').innerHTML = v.por_vendedor.length ? html`${v.por_vendedor.map((u) => html`<tr>
    <td>${u.vendedor}</td><td class="num">${numero(u.ventas)}</td><td class="num">${moneda(u.total)}</td>
    <td class="num">${moneda(Number(u.total) / Number(u.ventas))}</td></tr>`)}`
    : filaVacia(4, 'Sin ventas', '');
}

function pintarTop(top) {
  $('#t-top').innerHTML = top.length ? html`${top.map((m, i) => html`<tr>
    <td class="fuerte">${i + 1}</td>
    <td><div class="titulo-celda">${m.nombre}</div><div class="sub-celda mono">${m.codigo}</div></td>
    <td>${m.categoria}</td><td class="num fuerte">${numero(m.unidades)}</td><td class="num">${numero(m.ventas)}</td>
    <td class="num">${moneda(m.total)}</td><td class="num exito-txt">${moneda(m.utilidad)}</td></tr>`)}`
    : filaVacia(7, 'Sin ventas en el periodo', '');
}

function pintarInventario(inv) {
  $('#t-inventario').innerHTML = html`${inv.por_categoria.map((c) => html`<tr>
    <td>${c.categoria}<div class="sub-celda">${c.productos} producto(s)</div></td><td class="num">${numero(c.unidades)}</td>
    <td class="num">${moneda(c.valor_costo)}</td><td class="num">${moneda(c.valor_venta)}</td></tr>`)}`;
  $('#t-inventario-total').innerHTML = html`<tr><td>Total</td><td class="num">${numero(inv.totales.unidades)}</td>
    <td class="num">${moneda(inv.totales.valor_costo)}</td><td class="num">${moneda(inv.totales.valor_venta)}</td></tr>`;
  $('#t-pedido').innerHTML = inv.stock_bajo.length ? html`${inv.stock_bajo.map((m) => html`<tr>
    <td><div class="titulo-celda">${m.nombre}</div><div class="sub-celda">${m.categoria}</div></td>
    <td class="num">${insignia(m.estado_stock, numero(m.stock_disponible))}</td><td class="num">${numero(m.stock_minimo)}</td>
    <td class="num fuerte">${numero(m.sugerido_pedir)}</td></tr>`)}`
    : filaVacia(4, 'Inventario suficiente', 'Ningún producto está bajo el mínimo.');
}

async function cargar() {
  const r = rango();
  if (!r.desde || !r.hasta) return;
  try {
    const [ventas, top] = await Promise.all([
      api.get('/api/reportes/ventas', r),
      api.get('/api/reportes/top-medicamentos', { ...r, limite: 15 }),
    ]);
    Object.assign(datos, { ventas, top });
    pintarVentas(ventas);
    pintarTop(top);
  } catch (e) { toastError(e); }
}

async function cargarInventario() {
  try {
    datos.inventario = await api.get('/api/reportes/inventario');
    pintarInventario(datos.inventario);
  } catch (e) { toastError(e); }
}

document.querySelectorAll('[data-rango]').forEach((b) => b.addEventListener('click', () => {
  const valor = b.dataset.rango;
  const desde = valor === 'mes' ? new Date(hoy.getFullYear(), hoy.getMonth(), 1) : sumarDias(hoy, -Number(valor));
  $('#r-desde').value = fechaISO(desde);
  $('#r-hasta').value = fechaISO(hoy);
  cargar();
}));
['#r-desde', '#r-hasta'].forEach((s) => $(s).addEventListener('change', cargar));
$('#btn-imprimir').addEventListener('click', () => window.print());

$('#exp-diario').addEventListener('click', () => {
  if (!datos.ventas) return;
  exportarCSV('ventas_diarias', [
    { titulo: 'Fecha', valor: 'fecha' }, { titulo: 'Ventas', valor: 'numero_ventas' }, { titulo: 'Subtotal', valor: 'subtotal' },
    { titulo: 'Descuentos', valor: 'descuentos' }, { titulo: 'IVA', valor: 'impuestos' }, { titulo: 'Total', valor: 'total_ventas' },
    { titulo: 'Ticket promedio', valor: 'ticket_promedio' },
  ], datos.ventas.diario);
});
$('#exp-top').addEventListener('click', () => exportarCSV('medicamentos_mas_vendidos', [
  { titulo: 'Código', valor: 'codigo' }, { titulo: 'Medicamento', valor: 'nombre' }, { titulo: 'Categoría', valor: 'categoria' },
  { titulo: 'Unidades', valor: 'unidades' }, { titulo: 'Ventas', valor: 'ventas' }, { titulo: 'Total', valor: 'total' },
  { titulo: 'Utilidad', valor: 'utilidad' },
], datos.top));
$('#exp-pedido').addEventListener('click', () => datos.inventario && exportarCSV('sugerido_compra', [
  { titulo: 'Código', valor: 'codigo' }, { titulo: 'Medicamento', valor: 'nombre' }, { titulo: 'Categoría', valor: 'categoria' },
  { titulo: 'Disponible', valor: 'stock_disponible' }, { titulo: 'Mínimo', valor: 'stock_minimo' }, { titulo: 'Sugerido', valor: 'sugerido_pedir' },
], datos.inventario.stock_bajo));

activarVerSQL(rango); // «Ver SQL» usa el mismo periodo de la página

cargar();
cargarInventario();
