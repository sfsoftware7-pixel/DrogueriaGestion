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
