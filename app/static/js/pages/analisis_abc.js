import {
  $, api, exportarCSV, filaVacia, filasCargando, fechaISO, html, moneda, monedaCorta, numero, sumarDias, toastError,
} from '../core.js';
import { graficoPareto } from '../graficos.js';
import { activarVerSQL } from '../ver_sql.js';

const CLASES = { A: 'exito', B: 'alerta', C: 'info' };
let datos = null;
const hoy = new Date();
$('#abc-desde').value = fechaISO(sumarDias(hoy, -89));
$('#abc-hasta').value = fechaISO(hoy);
const rango = () => ({ desde: $('#abc-desde').value, hasta: $('#abc-hasta').value });

const porcentaje = (v) => `${Number(v).toLocaleString('es-CO', { maximumFractionDigits: 2 })} %`;
const insigniaClase = (c) => html`<span class="insignia insignia-${CLASES[c]} sin-punto abc-insignia">Clase ${c}</span>`;

function pintar(d) {
  for (const clase of ['A', 'B', 'C']) {
    const r = d.resumen[clase];
    $(`#k-${clase.toLowerCase()}`).textContent = `${numero(r.productos)} producto(s)`;
    $(`#k-${clase.toLowerCase()}-d`).textContent = `${porcentaje(r.porcentaje)} del valor · ${moneda(r.total)}`;
  }
  const c = d.control;
  $('#k-total').textContent = moneda(c.total_abc);
  $('#k-control').innerHTML = c.coincide
    ? html`<span class="exito-txt">Cuadra con sp_reporte_ventas (${moneda(c.total_sp_reporte_ventas)})</span>`
    : html`<span class="peligro-txt">No cuadra con sp_reporte_ventas (${moneda(c.total_sp_reporte_ventas)})</span>`;
  $('#k-control-icono').className = `kpi-icono ${c.coincide ? 'exito' : 'peligro'}`;

  if (!d.productos.length) {
    $('#g-pareto').innerHTML = '<div class="vacio">Sin ventas en el periodo</div>';
    $('#t-abc').innerHTML = filaVacia(8, 'Sin ventas en el periodo', 'Elija un rango con ventas completadas.');
    return;
  }
  graficoPareto($('#g-pareto'), d.productos.map((p) => ({
    etiqueta: p.nombre, valor: Number(p.total), acumulado: Number(p.porcentaje_acumulado), clase: p.clase,
  })), { formato: moneda, formatoEje: monedaCorta, umbrales: d.umbrales });

  $('#t-abc').innerHTML = html`${d.productos.map((p) => html`<tr>
    <td class="num fuerte">${p.puesto}</td>
    <td><div class="titulo-celda">${p.nombre}</div><div class="sub-celda mono">${p.codigo}</div></td>
    <td>${p.categoria}</td>
    <td class="num">${numero(p.unidades)}</td>
    <td class="num">${moneda(p.total)}</td>
    <td class="num">${porcentaje(p.porcentaje)}</td>
    <td class="num"><div class="abc-acumulado"><span>${porcentaje(p.porcentaje_acumulado)}</span>
      <div class="barra-progreso"><span style="width:${Math.min(100, Number(p.porcentaje_acumulado))}%"></span></div></div></td>
    <td>${insigniaClase(p.clase)}</td></tr>`)}`;
}

async function cargar() {
  const r = rango();
  if (!r.desde || !r.hasta) return;
  $('#t-abc').innerHTML = html`${filasCargando(8)}`;
  try {
    datos = await api.get('/api/analisis/abc', r);
    pintar(datos);
  } catch (e) { toastError(e); }
}

document.querySelectorAll('[data-rango]').forEach((b) => b.addEventListener('click', () => {
  const valor = b.dataset.rango;
  const desde = valor === 'mes' ? new Date(hoy.getFullYear(), hoy.getMonth(), 1) : sumarDias(hoy, -Number(valor));
  $('#abc-desde').value = fechaISO(desde);
  $('#abc-hasta').value = fechaISO(hoy);
  cargar();
}));
['#abc-desde', '#abc-hasta'].forEach((s) => $(s).addEventListener('change', cargar));
$('#abc-imprimir').addEventListener('click', () => window.print());
$('#abc-csv').addEventListener('click', () => datos && exportarCSV('analisis_abc', [
  { titulo: 'Puesto', valor: 'puesto' }, { titulo: 'Código', valor: 'codigo' }, { titulo: 'Medicamento', valor: 'nombre' },
  { titulo: 'Concentración', valor: 'concentracion' }, { titulo: 'Categoría', valor: 'categoria' },
  { titulo: 'Unidades', valor: 'unidades' }, { titulo: 'Total', valor: 'total' }, { titulo: '%', valor: 'porcentaje' },
  { titulo: '% acumulado', valor: 'porcentaje_acumulado' }, { titulo: 'Clase', valor: 'clase' },
], datos.productos));

activarVerSQL(rango);
cargar();
