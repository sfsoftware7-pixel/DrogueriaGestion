import {
  $, api, confirmar, debounce, fechaHora, html, moneda, numero, paginacion, puede, toast, toastError,
} from '../core.js';

let pagina = 1;
let cargando = false;

function filtros() {
  return { q: $('#f-pedidos-buscar').value.trim(), estado: $('#f-pedidos-estado').value };
}

function insigniaEstado(estado, texto) {
  const tipo = estado === 'ENTREGADO' ? 'exito'
    : ['EN_CAMINO', 'LISTO_PARA_RETIRO'].includes(estado) ? 'info'
      : estado === 'CANCELADO' ? 'peligro' : 'alerta';
  return html`<span class="insignia insignia-${tipo}">${texto}</span>`;
}

async function cargar(p = pagina, silencioso = false) {
  if (cargando) return;
  cargando = true;
  pagina = p;
  const cuerpo = $('#pedidos-cuerpo');
  if (!silencioso) cuerpo.innerHTML = html`<tr><td colspan="7"><div class="esqueleto"></div></td></tr>`;
  try {
    const r = await api.get('/api/pedidos-tienda', { ...filtros(), pagina, por_pagina: 15 });
    $('#pedidos-resumen').textContent = `${numero(r.total)} pedido(s)`;
    cuerpo.innerHTML = r.datos.length ? html`${r.datos.map((p) => html`<tr>
      <td class="mono fuerte">${p.codigo}<div class="sub-celda">${fechaHora(p.created_at)}</div></td>
      <td>${p.cliente}<div class="sub-celda">${p.telefono || 'Sin teléfono'}</div></td>
      <td>${p.productos}</td>
      <td>${p.entrega_texto}</td>
      <td class="num fuerte">${moneda(p.total)}</td>
      <td>${insigniaEstado(p.estado, p.estado_texto)}<div class="sub-celda">Actualizado ${fechaHora(p.actualizado_en)}</div></td>
      <td>${puede('pedidos.gestionar') && p.siguiente_estado
        ? html`<button class="btn btn-secundario btn-sm" data-codigo="${p.codigo}" data-estado="${p.siguiente_estado}" data-texto="${p.siguiente_estado_texto}">Marcar: ${p.siguiente_estado_texto}</button>`
        : p.estado === 'PENDIENTE_FORMULA' ? html`<span class="sub-celda">Esperando revisión de fórmula</span>`
          : html`<span class="sub-celda">Sin acciones pendientes</span>`}</td>
    </tr>`)}` : html`<tr><td colspan="7" class="vacio"><strong>No hay pedidos con esos filtros.</strong></td></tr>`;
    paginacion($('#pedidos-paginacion'), r, cargar);
    $('#pedidos-actualizados').textContent = `Última actualización: ${fechaHora(new Date())}.`;
  } catch (e) {
    cuerpo.innerHTML = html`<tr><td colspan="7">No fue posible cargar los pedidos: ${e.message}</td></tr>`;
    toastError(e);
  } finally {
    cargando = false;
  }
}

async function avanzar(codigo, estado, texto) {
  const acepta = await confirmar({
    titulo: `Actualizar pedido ${codigo}`,
    mensaje: `El estado cambiará a «${texto}» y el cliente podrá verlo en el seguimiento de su compra.`,
    textoBoton: `Marcar ${texto}`,
  });
  if (!acepta) return;
  try {
    const r = await api.post(`/api/pedidos-tienda/${encodeURIComponent(codigo)}/estado`, { estado });
    toast(r.mensaje);
    await cargar(pagina);
  } catch (e) { toastError(e); }
}

$('#pedidos-cuerpo').addEventListener('click', (e) => {
  const boton = e.target.closest('button[data-codigo]');
  if (boton) avanzar(boton.dataset.codigo, boton.dataset.estado, boton.dataset.texto);
});
$('#f-pedidos-buscar').addEventListener('input', debounce(() => cargar(1), 250));
$('#f-pedidos-estado').addEventListener('change', () => cargar(1));

cargar(1);
window.setInterval(() => { if (!document.hidden) cargar(pagina, true); }, 15000);
