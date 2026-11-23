/**
 * Confirmación del pedido: «Descargar recibo (PDF)» e «Imprimir».
 * Los datos salen del pedido ya confirmado que el servidor insertó en la página (#datos-pedido), no del carrito.
 */
import { $ } from './comun.js';
import { iniciarEncabezado } from './encabezado.js';
import { generarRecibo, nombreArchivo } from './recibo.js';

const pedido = JSON.parse($('#datos-pedido').textContent);
const aviso = $('#aviso-recibo');
const botonPDF = $('#descargar-recibo');

async function actualizarSeguimiento() {
  try {
    const respuesta = await fetch(`/api/pedidos/${encodeURIComponent(pedido.codigo)}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
      cache: 'no-store',
    });
    if (!respuesta.ok) return;
    const actualizado = await respuesta.json();
    $('#estado-actual').textContent = actualizado.estado_texto;
    const titulo = {
      PENDIENTE_FORMULA: 'Recibimos tu pedido: falta aprobar la fórmula',
      ENTREGADO: 'Tu pedido fue entregado',
      CANCELADO: 'Pedido cancelado',
    }[actualizado.estado] || 'Recibimos tu pedido';
    $('#titulo-pedido').textContent = titulo;
    for (const fila of document.querySelectorAll('[data-estado]')) {
      const paso = actualizado.pasos.find((p) => p.estado === fila.dataset.estado);
      if (!paso) continue;
      fila.classList.toggle('paso--hecho', paso.hecho);
      fila.classList.toggle('paso--actual', paso.actual);
      if (paso.actual) fila.setAttribute('aria-current', 'step');
      else fila.removeAttribute('aria-current');
      fila.querySelector('[data-paso-fecha]').textContent = paso.fecha_texto || (paso.hecho ? '' : 'Pendiente');
    }
  } catch {
    // El seguimiento inicial ya se muestra desde el servidor; la próxima consulta vuelve a intentar.
  }
}

async function descargar() {
  if (!window.jspdf) {
    aviso.textContent = 'El generador del PDF aún no termina de cargar. Intenta de nuevo en un momento.';
    return;
  }
  botonPDF.disabled = true;
  aviso.textContent = 'Generando el recibo…';
  try {
    const doc = await generarRecibo(pedido);
    doc.save(nombreArchivo(pedido));
    aviso.textContent = `Descargamos ${nombreArchivo(pedido)}.`;
  } catch (error) {
    aviso.textContent = `No pudimos generar el PDF (${error.message}). Puedes usar «Imprimir».`;
  } finally {
    botonPDF.disabled = false;
  }
}

iniciarEncabezado();
botonPDF.addEventListener('click', descargar);
$('#imprimir-recibo').addEventListener('click', () => window.print());
window.setInterval(() => { if (!document.hidden) actualizarSeguimiento(); }, 15000);
