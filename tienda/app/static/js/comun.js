/**
 * Utilidades compartidas por todas las páginas (antes vivían en inicio.js): DOM sin innerHTML, formato de
 * pesos colombianos, avisos, estados de error/vacío y el carrito guardado en el navegador.
 */
export const $ = (selector, contexto = document) => contexto.querySelector(selector);
export const formatoCOP = new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 });
export const pesos = (valor) => formatoCOP.format(valor);
export const movimientoReducido = window.matchMedia('(prefers-reduced-motion: reduce)');
const SVG = 'http://www.w3.org/2000/svg';

/* ------------------------------------------------------------------ utilidades del DOM */
export function el(etiqueta, atributos = {}, ...hijos) {
  const nodo = document.createElement(etiqueta);
  for (const [clave, valor] of Object.entries(atributos)) {
    if (valor === null || valor === undefined || valor === false) continue;
    if (clave === 'clase') nodo.className = valor;
    else if (clave === 'texto') nodo.textContent = valor;
    else if (clave.startsWith('on')) nodo.addEventListener(clave.slice(2), valor);
    else nodo.setAttribute(clave, valor === true ? '' : String(valor));
  }
  for (const hijo of hijos.flat()) {
    if (hijo !== null && hijo !== undefined && hijo !== false) nodo.append(hijo);
  }
  return nodo;
}

export function flecha() {
  const svg = document.createElementNS(SVG, 'svg');
  svg.setAttribute('class', 'icono flecha');
  svg.setAttribute('viewBox', '0 0 16 16');
  svg.setAttribute('aria-hidden', 'true');
  const trazo = document.createElementNS(SVG, 'path');
  trazo.setAttribute('d', 'M2 8h11M9 4l4 4-4 4');
  svg.append(trazo);
  return svg;
}

export function avisar(mensaje) {
  const aviso = el('div', { clase: 'aviso', texto: mensaje });
  $('#avisos').append(aviso);
  setTimeout(() => aviso.remove(), 6000);
}

export function mostrarError(contenedor, titulo, error, reintentar) {
  contenedor.replaceChildren(
    el('div', { clase: 'estado estado-error', role: 'alert' },
      el('p', {}, el('strong', { texto: titulo }), ' ', error.message || ''),
      el('button', {
        type: 'button', clase: 'btn btn--secondary',
        onclick: () => { contenedor.replaceChildren(); reintentar(); },
      }, 'Reintentar')));
}

export function mostrarVacio(contenedor, mensaje) {
  contenedor.replaceChildren(el('div', { clase: 'estado' }, el('p', { texto: mensaje })));
}

/* ------------------------------------------------------------------ carrito del navegador */
// { idProducto: cantidad }. Si el navegador no deja guardar, el carrito vive solo en memoria.
// Cada cambio emite "carrito:cambio" para que el contador, la página del carrito y el chatbot se actualicen.
const CLAVE_CARRITO = 'sanalivio:carrito';
const MAX_UNIDADES = 99;
let carrito = leer();

function leer() {
  try {
    const datos = JSON.parse(localStorage.getItem(CLAVE_CARRITO));
    if (!datos || typeof datos !== 'object') return {};
    return Object.fromEntries(Object.entries(datos)
      .map(([id, cantidad]) => [id, Math.min(Math.trunc(Number(cantidad)), MAX_UNIDADES)])
      .filter(([id, cantidad]) => /^\d+$/.test(id) && cantidad > 0));
  } catch { return {}; }
}

function guardar() {
  try { localStorage.setItem(CLAVE_CARRITO, JSON.stringify(carrito)); } catch { /* sin almacenamiento: solo en memoria */ }
  window.dispatchEvent(new CustomEvent('carrito:cambio'));
}

// Otra pestaña cambió el carrito
window.addEventListener('storage', (evento) => {
  if (evento.key !== CLAVE_CARRITO) return;
  carrito = leer();
  window.dispatchEvent(new CustomEvent('carrito:cambio'));
});

export const carritoActual = () => ({ ...carrito });
export const unidadesEnCarrito = () => Object.values(carrito).reduce((suma, cantidad) => suma + cantidad, 0);

/** Agrega unidades sin pasar de las existencias conocidas (producto.stock) ni de 99. */
export function agregarAlCarrito(producto, cantidad = 1) {
  const tope = Math.min(MAX_UNIDADES, Number.isFinite(producto.stock) ? producto.stock : MAX_UNIDADES);
  const actual = carrito[producto.id] || 0;
  if (tope <= 0) {
    avisar(`${producto.nombre} está agotado en este momento.`);
    return actual;
  }
  if (actual >= tope) {
    avisar(`Ya tienes en el carrito todas las unidades disponibles de ${producto.nombre} (${tope}).`);
    return actual;
  }
  carrito[producto.id] = Math.min(actual + cantidad, tope);
  guardar();
  avisar(producto.requiere_formula
    ? `Agregaste ${producto.nombre}. Requiere fórmula médica: la cargas al pagar.`
    : `Agregaste ${producto.nombre} al carrito.`);
  return carrito[producto.id];
}

export function fijarCantidad(id, cantidad) {
  const valor = Math.min(Math.trunc(cantidad), MAX_UNIDADES);
  if (valor > 0) carrito[id] = valor; else delete carrito[id];
  guardar();
}

export function quitarDelCarrito(id) {
  delete carrito[id];
  guardar();
}

export function vaciarCarrito() {
  carrito = {};
  guardar();
}
