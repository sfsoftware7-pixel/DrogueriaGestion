import { $, api, fecha, fechaCorta, fechaHora, html, METODOS_PAGO, moneda, monedaCorta, numero, puede, toastError } from '../core.js';
import { graficoLinea } from '../graficos.js';
import { activarVerSQL } from '../ver_sql.js';

activarVerSQL(); // botones «SQL» de las tarjetas (solo aparecen con el permiso consultas.ver)

function itemVacio(texto) {
  return html`<li><div class="lista-principal"><span>${texto}</span></div></li>`;
}

function pintarKpis(d) {
  const { ventas, inventario, vencimientos } = d;
  if (ventas) pintarKpisVentas(ventas); // null para roles sin 'ventas.ver' (las tarjetas no existen)

  $('#kpi-stock').textContent = numero(inventario.stock_bajo + inventario.agotados);
  $('#kpi-stock-detalle').textContent = `${inventario.agotados} agotado(s) · ${inventario.productos_activos} productos activos`;

  $('#kpi-venc').textContent = numero(vencimientos.vencidos + vencimientos.criticos);
  $('#kpi-venc-detalle').textContent = `${vencimientos.vencidos} vencido(s) · ${vencimientos.proximos} en 31–90 días`;
}

function pintarKpisVentas(ventas) {
  $('#kpi-hoy').textContent = moneda(ventas.total_hoy);
  const ayer = Number(ventas.total_ayer);
  const variacion = ayer > 0 ? Math.round(((ventas.total_hoy - ayer) / ayer) * 100) : null;
  $('#kpi-hoy-detalle').innerHTML = html`${numero(ventas.numero_hoy)} venta(s)${variacion === null ? '' : html` ·
    <span class="${variacion >= 0 ? 'exito-txt' : 'peligro-txt'}">${variacion >= 0 ? '▲' : '▼'} ${Math.abs(variacion)}% vs. ayer</span>`}`;

  $('#kpi-mes').textContent = moneda(ventas.total_mes);
  $('#kpi-mes-detalle').textContent = `${numero(ventas.numero_mes)} venta(s) desde el día 1`;
}

function pintarTop(top) {
  const contenedor = $('#top-medicamentos');
  if (!top.length) {
    contenedor.innerHTML = html`<div class="vacio"><strong>Sin ventas recientes</strong></div>`;
    return;
  }
  const maximo = Math.max(...top.map((t) => Number(t.unidades)));
  contenedor.innerHTML = html`${top.map((t, i) => html`
    <div style="margin-bottom:14px">
      <div class="flex-entre" style="font-size:13px;margin-bottom:5px">
        <span><strong>${i + 1}.</strong> ${t.nombre}</span>
        <span class="tenue nowrap">${numero(t.unidades)} und.</span>
      </div>
      <div class="barra-progreso"><span style="width:${Math.max(4, (t.unidades / maximo) * 100)}%"></span></div>
    </div>`)}`;
}

function pintarAlertas(d) {
  $('#alertas-stock').innerHTML = d.alertas_stock.length
    ? html`${d.alertas_stock.map((a) => html`<li>
        <span class="punto ${a.estado_stock === 'AGOTADO' ? 'peligro' : 'alerta'}"></span>
        <div class="lista-principal"><strong>${a.nombre}</strong><span>Mínimo: ${a.stock_minimo} und.</span></div>
        <span class="insignia ${a.estado_stock === 'AGOTADO' ? 'insignia-peligro' : 'insignia-alerta'} sin-punto">${numero(a.stock_disponible)} und.</span>
      </li>`)}`
    : itemVacio('Todo el inventario está sobre el mínimo.');

  $('#alertas-vencimiento').innerHTML = d.alertas_vencimiento.length
    ? html`${d.alertas_vencimiento.map((a) => {
        const vencido = a.dias_para_vencer < 0;
        const tipo = vencido || a.estado_vencimiento === 'CRITICO' ? 'peligro' : 'alerta';
        return html`<li>
          <span class="punto ${tipo}"></span>
          <div class="lista-principal"><strong>${a.medicamento}</strong><span>Lote ${a.numero_lote} · ${numero(a.cantidad_actual)} und. · ${fecha(a.fecha_vencimiento)}</span></div>
          <span class="insignia insignia-${tipo} sin-punto">${vencido ? 'Vencido' : `${a.dias_para_vencer} días`}</span>
        </li>`;
      })}`
    : itemVacio('No hay lotes próximos a vencer.');

  if (!puede('ventas.ver')) return; // la tarjeta de últimas ventas no se renderiza para este rol
  $('#ultimas-ventas').innerHTML = d.ultimas_ventas.length
    ? html`${d.ultimas_ventas.map((v) => html`<li>
        <span class="punto ${v.estado === 'ANULADA' ? 'peligro' : 'exito'}"></span>
        <div class="lista-principal">
          <strong><a href="/ventas/${v.id_venta}/comprobante">${v.numero_factura}</a> · ${v.cliente}</strong>
          <span>${fechaHora(v.fecha_venta)} · ${METODOS_PAGO[v.metodo_pago]}</span>
        </div>
        <strong class="num ${v.estado === 'ANULADA' ? 'peligro-txt' : ''}">${moneda(v.total)}</strong>
      </li>`)}`
    : itemVacio('Aún no hay ventas registradas.');
}

async function cargar() {
  try {
    const d = await api.get('/api/dashboard');
    pintarKpis(d);
    pintarAlertas(d);
    if (!d.ventas) return; // rol sin acceso a ventas: no hay tendencia ni más vendidos
    pintarTop(d.top_medicamentos);
    graficoLinea(
      $('#grafico-tendencia'),
      d.tendencia.map((t) => ({ etiqueta: fechaCorta(t.fecha), valor: t.total, detalle: `${fecha(t.fecha)} · ${t.ventas} venta(s)` })),
      { formato: moneda, formatoEje: monedaCorta }
    );
  } catch (e) {
    toastError(e);
  }
}

function claseEstadoPedido(estado) {
  if (estado === 'ENTREGADO') return 'insignia-exito';
  if (estado === 'EN_CAMINO' || estado === 'LISTO_PARA_RETIRO') return 'insignia-info';
  if (estado === 'CANCELADO') return 'insignia-peligro';
  return 'insignia-alerta';
}

async function cargarPedidosTienda() {
  const cuerpo = $('#pedidos-tienda');
  try {
    const d = await api.get('/api/dashboard/pedidos-tienda');
    if (!d.disponible) {
      cuerpo.innerHTML = html`<tr><td colspan="6">No se pudo conectar con los pedidos de la tienda. Revise TIENDA_DB_NAME y el permiso SELECT de DB_USER.</td></tr>`;
      return;
    }
    cuerpo.innerHTML = d.pedidos.length
      ? html`${d.pedidos.map((p) => html`<tr>
        <td class="titulo-celda">${p.codigo}</td>
        <td>${p.cliente}</td>
        <td class="sub-celda">${p.productos}</td>
        <td>${p.tipo_entrega_texto}</td>
        <td><span class="insignia ${claseEstadoPedido(p.estado)}">${p.estado_texto}</span></td>
        <td class="nowrap">${fechaHora(p.updated_at)}</td>
        </tr>`)}`
      : html`<tr><td colspan="6">No hay pedidos activos o entregados hoy.</td></tr>`;
    $('#pedidos-tienda-actualizado').textContent = `Actualizado ${fechaHora(new Date())} · se renueva cada 15 segundos`;
  } catch (e) {
    cuerpo.innerHTML = html`<tr><td colspan="6">No se pudieron actualizar los pedidos. ${e.message}</td></tr>`;
  }
}

cargar();
if ($('#pedidos-tienda')) {
  cargarPedidosTienda();
  window.setInterval(() => { if (!document.hidden) cargarPedidosTienda(); }, 15000);
}
