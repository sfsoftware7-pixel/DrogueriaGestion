/**
 * Seguir mi pedido: con el código y el documento del comprador, el servidor autoriza ver el pedido
 * (queda en la sesión) y se abre la página del pedido con su estado y el recibo.
 */
import { enviar } from './api.js';
import { $ } from './comun.js';
import { iniciarEncabezado } from './encabezado.js';

const formulario = $('#form-consulta');
const error = $('#error-consulta');

formulario.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  error.hidden = true;
  const datos = Object.fromEntries(new FormData(formulario));
  datos.codigo = datos.codigo.trim().toUpperCase();
  if (!/^PED-\d{6,}$/.test(datos.codigo) || !datos.numero_documento.trim()) {
    error.textContent = 'Escribe el código (por ejemplo PED-000123) y el número de documento.';
    error.hidden = false;
    error.focus();
    return;
  }
  try {
    const respuesta = await enviar('/api/pedidos/consulta', datos);
    window.location.assign(respuesta.url);
  } catch (fallo) {
    error.textContent = fallo.message;
    error.hidden = false;
    error.focus();
  }
});

iniciarEncabezado();
