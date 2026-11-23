/**
 * Carrito y pago (compra como invitado, contra entrega).
 * Precios y existencias se piden a la API cada vez (nunca se confía en lo guardado en el navegador); el
 * servidor vuelve a calcular todo al confirmar. La cobertura del domicilio se revisa por barrio antes de pagar.
 */
import { enviar, obtenerJSON } from './api.js';
import {
  $, avisar, carritoActual, el, fijarCantidad, mostrarError, pesos, quitarDelCarrito, vaciarCarrito,
} from './comun.js';
import { iniciarEncabezado } from './encabezado.js';

const lista = $('#carrito-lista');
const estado = $('#estado-carrito');
const formulario = $('#form-pago');
const resumen = $('#resumen');

let productos = new Map(); // id (texto) -> producto de la API
let tienda = null;         // /api/tienda: zonas, sedes, pago
let zona = null;           // cobertura confirmada del barrio escrito
let enviando = false;

const tipoEntrega = () => formulario.elements.tipo_entrega.value;
const precioFinal = (p) => p.precio_oferta ?? p.precio;

/* ------------------------------------------------------------------ productos del carrito */
async function cargarProductos() {
  const ids = Object.keys(carritoActual());
  if (!ids.length) { pintarVacio(); return; }
  lista.setAttribute('aria-busy', 'true');
  try {
    const encontrados = await obtenerJSON(`/api/productos?ids=${ids.join(',')}`);
    productos = new Map(encontrados.map((p) => [String(p.id), p]));
    const retirados = ids.filter((id) => !productos.has(id));
    retirados.forEach(quitarDelCarrito);
    if (retirados.length) avisar('Quitamos del carrito productos que ya no se venden.');
    // Ninguna cantidad puede superar las existencias actuales
    for (const [id, cantidad] of Object.entries(carritoActual())) {
      const disponible = productos.get(id)?.stock ?? 0;
      if (disponible === 0) { quitarDelCarrito(id); avisar(`${productos.get(id).nombre} se agotó y salió del carrito.`); }
      else if (cantidad > disponible) { fijarCantidad(id, disponible); avisar(`Ajustamos ${productos.get(id).nombre} a las ${disponible} unidades disponibles.`); }
    }
    estado.replaceChildren();
    pintar();
  } catch (error) {
    lista.replaceChildren();
    mostrarError(estado, 'No pudimos cargar tu carrito.', error, cargarProductos);
  } finally {
    lista.setAttribute('aria-busy', 'false');
  }
}

function pintarVacio() {
  lista.replaceChildren();
  formulario.hidden = true;
  resumen.hidden = true;
  estado.replaceChildren(el('div', { clase: 'estado' },
    el('p', { texto: 'Tu carrito está vacío. Busca un producto arriba o mira las promociones.' }),
    el('a', { clase: 'btn btn--secondary', href: '/#promociones' }, 'Ver promociones')));
}

function filaProducto(id, cantidad) {
  const p = productos.get(id);
  const tope = Math.min(99, p.stock);
  const precio = precioFinal(p);
  const cambiar = (valor) => fijarCantidad(id, Math.max(1, Math.min(tope, valor)));
  return el('li', { clase: 'carrito-item' },
    el('div', { clase: 'carrito-item__info' },
      el('p', { clase: 'carrito-item__nombre', texto: p.nombre }),
      el('p', { clase: 'carrito-item__detalle' }, p.presentacion,
        p.requiere_formula ? el('span', { clase: 'insignia-formula', texto: 'Requiere fórmula médica' }) : null),
      el('p', { clase: 'carrito-item__precio' }, pesos(precio), ' c/u',
        p.precio_oferta !== null ? el('del', { clase: 'precio-anterior' }, el('span', { clase: 'solo-lectores', texto: 'Precio anterior: ' }), pesos(p.precio)) : null)),
    el('div', { clase: 'cantidad' },
      el('button', {
        type: 'button', clase: 'boton-icono boton-borde', 'data-foco': `menos-${id}`, disabled: cantidad <= 1,
        'aria-label': `Quitar una unidad de ${p.nombre}`, onclick: () => cambiar(cantidad - 1),
      }, '−'),
      el('input', {
        type: 'number', min: 1, max: tope, value: cantidad, inputmode: 'numeric', 'data-foco': `cantidad-${id}`,
        'aria-label': `Cantidad de ${p.nombre}`,
        onchange: (evento) => cambiar(Number(evento.target.value) || 1),
      }),
      el('button', {
        type: 'button', clase: 'boton-icono boton-borde', 'data-foco': `mas-${id}`, disabled: cantidad >= tope,
        'aria-label': `Agregar una unidad de ${p.nombre}`, onclick: () => cambiar(cantidad + 1),
      }, '+')),
    el('p', { clase: 'carrito-item__subtotal' },
      el('span', { clase: 'solo-lectores', texto: 'Subtotal: ' }), pesos(precio * cantidad),
      cantidad >= tope ? el('span', { clase: 'carrito-item__tope', texto: `Máximo disponible: ${tope}` }) : null),
    el('button', {
      type: 'button', clase: 'enlace carrito-item__quitar', 'data-foco': `quitar-${id}`,
      'aria-label': `Quitar ${p.nombre} del carrito`,
      onclick: () => { quitarDelCarrito(id); avisar(`Quitaste ${p.nombre} del carrito.`); },
    }, 'Quitar'));
}

function pintar() {
  const carrito = carritoActual();
  const ids = Object.keys(carrito).filter((id) => productos.has(id));
  if (!ids.length) { pintarVacio(); return; }
  const foco = document.activeElement?.dataset?.foco; // conserva el foco al volver a pintar
  lista.replaceChildren(...ids.map((id) => filaProducto(id, carrito[id])));
  if (foco) (lista.querySelector(`[data-foco="${foco}"]:not([disabled])`) || $('#titulo-carrito'))?.focus?.();
  formulario.hidden = false;
  resumen.hidden = false;
  $('#grupo-formula').hidden = !ids.some((id) => productos.get(id).requiere_formula);
  pintarResumen();
}

function pintarResumen() {
  const carrito = carritoActual();
  let subtotal = 0;
  let descuento = 0;
  for (const [id, cantidad] of Object.entries(carrito)) {
    const p = productos.get(id);
    if (!p) continue;
    subtotal += p.precio * cantidad;
    descuento += (p.precio - precioFinal(p)) * cantidad;
  }
  let envio = 0;
  let textoEnvio = 'Según tu barrio';
  if (tipoEntrega() === 'RETIRO') textoEnvio = 'Sin costo';
  else if (zona) { envio = zona.costo; textoEnvio = pesos(envio); }
  $('#resumen-subtotal').textContent = pesos(subtotal);
  $('#resumen-descuento').textContent = descuento ? `-${pesos(descuento)}` : pesos(0);
  $('#resumen-envio').textContent = textoEnvio;
  $('#resumen-total').textContent = pesos(subtotal - descuento + envio);
}

/* ------------------------------------------------------------------ entrega y cobertura por barrio */
function pintarBarrios() {
  const dane = $('#ciudad').value;
  const barrios = tienda.domicilio.zonas.filter((z) => z.ciudad_dane === dane).flatMap((z) => z.barrios);
  $('#lista-barrios').replaceChildren(...barrios.map((b) => el('option', { value: b })));
}

async function cargarTienda() {
  try {
    tienda = await obtenerJSON('/api/tienda');
  } catch (error) {
    mostrarError(estado, 'No pudimos cargar las opciones de entrega.', error, cargarTienda);
    return;
  }
  $('#ciudad').replaceChildren(...tienda.domicilio.ciudades.map((c) => el('option', { value: c.dane, texto: c.nombre })));
  pintarBarrios();
  $('#sede').replaceChildren(...tienda.sedes.filter((s) => s.permite_retiro)
    .map((s) => el('option', { value: s.id, texto: `${s.nombre} · ${s.direccion}` })));
  $('#metodo-pago').value = tienda.pago.metodo;
  $('#metodo-pago-nombre').textContent = tienda.pago.nombre;
  $('#pago-descripcion').textContent = tienda.pago.descripcion;
}

async function revisarCobertura() {
  const barrio = $('#barrio').value.trim();
  const salida = $('#cobertura');
  zona = null;
  pintarResumen();
  if (barrio.length < 2) {
    salida.className = 'cobertura';
    salida.textContent = 'Escribe tu barrio para ver el costo y el tiempo del domicilio.';
    return false;
  }
  salida.className = 'cobertura';
  salida.textContent = 'Revisando cobertura…';
  try {
    const r = await obtenerJSON(`/api/domicilios/cobertura?barrio=${encodeURIComponent(barrio)}&ciudad=${encodeURIComponent($('#ciudad').value)}`);
    if (r.cobertura) {
      zona = r.coincidencias[0];
      salida.className = 'cobertura cobertura--si';
      salida.textContent = `Sí llegamos a ${zona.barrio} (zona ${zona.zona}): domicilio de ${pesos(zona.costo)}, entrega en ${zona.tiempo}.`;
    } else {
      salida.className = 'cobertura cobertura--no';
      salida.replaceChildren(`Aún no llegamos a «${barrio}» (${$('#ciudad').selectedOptions[0]?.textContent || 'esa ciudad'}). Puedes elegir retiro gratis en sede.`);
      if (r.sugerencias.length) {
        salida.append(' ¿Quisiste decir ', ...r.sugerencias.flatMap((s, i) => [i ? ', ' : '', el('button', {
          type: 'button', clase: 'enlace',
          onclick: () => { $('#barrio').value = s.barrio; revisarCobertura(); },
        }, s.barrio)]), '?');
      }
    }
    pintarResumen();
    return Boolean(zona);
  } catch (error) {
    salida.className = 'cobertura cobertura--no';
    salida.textContent = `No pudimos revisar la cobertura: ${error.message}`;
    return false;
  }
}

function alternarEntrega() {
  const domicilio = tipoEntrega() === 'DOMICILIO';
  $('#bloque-domicilio').hidden = !domicilio;
  $('#bloque-retiro').hidden = domicilio;
  pintarResumen();
}

/* ------------------------------------------------------------------ envío del pedido */
function limpiarErrores() {
  formulario.querySelectorAll('.campo-error').forEach((p) => { p.hidden = true; p.textContent = ''; });
  formulario.querySelectorAll('[aria-invalid]').forEach((campo) => campo.removeAttribute('aria-invalid'));
  $('#errores-pago').hidden = true;
}

function mostrarErrores(mensaje, errores = {}) {
  const resumenErrores = $('#errores-pago');
  const enlaces = [];
  for (const [campo, texto] of Object.entries(errores)) {
    const destino = $(`#error-${campo}`);
    if (destino) { destino.textContent = texto; destino.hidden = false; }
    const control = formulario.elements[campo];
    const primero = control instanceof RadioNodeList ? control[0] : control;
    if (primero?.setAttribute) {
      primero.setAttribute('aria-invalid', 'true');
      enlaces.push(el('li', {}, el('a', { href: `#${primero.id || campo}`, texto })));
    } else {
      enlaces.push(el('li', { texto }));
    }
  }
  resumenErrores.replaceChildren(el('p', {}, el('strong', { texto: mensaje })), enlaces.length ? el('ul', {}, enlaces) : null);
  resumenErrores.hidden = false;
  resumenErrores.focus();
}

async function confirmar(evento) {
  evento.preventDefault();
  if (enviando) return;
  limpiarErrores();
  if (tipoEntrega() === 'DOMICILIO' && !zona && !(await revisarCobertura())) {
    mostrarErrores('Revisa la entrega.', { barrio: 'Escribe un barrio con cobertura o elige retiro en sede.' });
    return;
  }
  const datos = new FormData(formulario);
  datos.set('items', JSON.stringify(Object.entries(carritoActual()).map(([id, cantidad]) => ({ id: Number(id), cantidad }))));
  if ($('#grupo-formula').hidden) { datos.delete('formula'); datos.delete('fecha_formula'); datos.delete('medico'); }
  const boton = $('#confirmar-pedido');
  enviando = true;
  boton.disabled = true;
  boton.textContent = 'Enviando pedido…';
  try {
    const respuesta = await enviar('/api/pedidos', datos);
    vaciarCarrito();
    window.location.assign(respuesta.url);
  } catch (error) {
    mostrarErrores(error.message, error.errores);
    if (error.estado === 409) cargarProductos(); // las existencias cambiaron: se vuelven a pedir
  } finally {
    enviando = false;
    boton.disabled = false;
    boton.textContent = 'Confirmar pedido';
  }
}

/* ------------------------------------------------------------------ arranque */
iniciarEncabezado();
$('#fecha_formula').max = new Date().toLocaleDateString('en-CA'); // AAAA-MM-DD de hoy
formulario.addEventListener('change', (evento) => {
  if (evento.target.name === 'tipo_entrega') alternarEntrega();
  if (evento.target.id === 'ciudad') { pintarBarrios(); revisarCobertura(); }
  if (evento.target.id === 'barrio') revisarCobertura();
});
$('#revisar-cobertura').addEventListener('click', revisarCobertura);
$('#barrio').addEventListener('input', () => { if (zona) { zona = null; $('#cobertura').textContent = ''; pintarResumen(); } });
formulario.addEventListener('submit', confirmar);
window.addEventListener('carrito:cambio', () => {
  if (Object.keys(carritoActual()).some((id) => !productos.has(id))) cargarProductos(); else pintar();
});
cargarTienda();
cargarProductos();
