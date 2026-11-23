/**
 * Encabezado compartido (antes en inicio.js): sticky que se compacta, menú de categorías (panel en móvil),
 * autocompletado y contador del carrito. Lo usan el inicio y las páginas de compra.
 */
import { obtenerJSON } from './api.js';
import { $, avisar, el, movimientoReducido, pesos, unidadesEnCarrito } from './comun.js';

/* ------------------------------------------------------------------ contador del carrito */
function pintarContador(animar = false) {
  const total = unidadesEnCarrito();
  const contador = $('#contador-carrito');
  contador.textContent = total > 99 ? '99+' : String(total);
  $('#carrito-descripcion').textContent = `${total} ${total === 1 ? 'producto' : 'productos'}`;
  if (animar && !movimientoReducido.matches) {
    contador.classList.remove('sumado');
    void contador.offsetWidth; // reinicia la animación
    contador.classList.add('sumado');
  }
}

/* ------------------------------------------------------------------ menú de categorías */
// En escritorio el menú es una sola fila: las categorías que no caben se ocultan enteras (también para
// el teclado) y el enlace "Todas las categorías" lleva a la lista completa. En el panel móvil se ven todas.
const escritorio = window.matchMedia('(min-width: 768px)');

export function ajustarMenu() {
  const menu = $('#menu-lista');
  const items = [...menu.children];
  items.forEach((item) => { item.hidden = false; });
  if (!escritorio.matches) return;
  const borde = menu.getBoundingClientRect().right + 0.5;
  const sobran = items.filter((item) => item.getBoundingClientRect().right > borde);
  sobran.forEach((item) => { item.hidden = true; });
}

export function pintarMenu(categorias) {
  // Cada enlace abre la página de la categoría; la de la página actual queda marcada (aria-current)
  $('#menu-lista').replaceChildren(...categorias.map((c) => {
    const ruta = `/categoria/${encodeURIComponent(c.slug)}`;
    return el('li', {}, el('a', {
      clase: 'menu-enlace', href: ruta, texto: c.nombre,
      'aria-current': window.location.pathname === ruta ? 'page' : null,
    }));
  }));
  ajustarMenu();
}

export function menuSinCategorias(texto) {
  $('#menu-lista').replaceChildren(el('li', { clase: 'menu-error', texto }));
  ajustarMenu();
}

async function cargarMenu() {
  const menu = $('#menu-lista');
  menu.setAttribute('aria-busy', 'true');
  try {
    const categorias = await obtenerJSON('/api/categorias');
    if (categorias.length) pintarMenu(categorias); else menuSinCategorias('Sin categorías');
  } catch {
    menuSinCategorias('Categorías no disponibles');
  } finally {
    menu.setAttribute('aria-busy', 'false');
  }
}

/* ------------------------------------------------------------------ autocompletado */
function iniciarBuscador() {
  const formulario = $('#buscador');
  const entrada = $('#buscar');
  const panel = $('#sugerencias-panel');
  const lista = $('#sugerencias');
  const estado = $('#sugerencias-estado');
  let controlador = null;
  let espera = null;
  let resultados = [];
  let activo = -1;

  const abrir = () => { panel.hidden = false; entrada.setAttribute('aria-expanded', 'true'); };
  function cerrar() {
    panel.hidden = true;
    entrada.setAttribute('aria-expanded', 'false');
    entrada.removeAttribute('aria-activedescendant');
    activo = -1;
  }

  function marcar(indice) {
    const opciones = lista.querySelectorAll('[role="option"]');
    activo = indice;
    opciones.forEach((opcion, i) => opcion.setAttribute('aria-selected', String(i === indice)));
    if (indice >= 0 && opciones[indice]) {
      entrada.setAttribute('aria-activedescendant', opciones[indice].id);
      opciones[indice].scrollIntoView({ block: 'nearest' });
    } else {
      entrada.removeAttribute('aria-activedescendant');
    }
  }

  function elegir(indice) {
    const producto = resultados[indice];
    if (!producto) return;
    entrada.value = producto.nombre;
    cerrar();
    avisar(`La ficha de «${producto.nombre}» llega en la siguiente fase del proyecto.`);
  }

  function pintar(texto) {
    lista.replaceChildren(...resultados.map((p, i) => el('li', {
      id: `sugerencia-${i}`, role: 'option', 'aria-selected': 'false', clase: 'sugerencia',
      onmousedown: (evento) => evento.preventDefault(), // conserva el foco en el buscador
      onclick: () => elegir(i),
    },
    el('span', { clase: 'sugerencia-nombre', texto: p.nombre }),
    el('span', { clase: 'sugerencia-detalle' }, p.presentacion,
      p.requiere_formula ? el('span', { clase: 'insignia-formula', texto: 'Requiere fórmula médica' }) : null),
    el('span', { clase: 'sugerencia-precio', texto: pesos(p.precio_oferta ?? p.precio) }))));

    if (resultados.length) {
      estado.className = 'sugerencias-estado solo-lectores';
      estado.textContent = `${resultados.length} ${resultados.length === 1 ? 'sugerencia disponible' : 'sugerencias disponibles'}`;
    } else {
      estado.className = 'sugerencias-estado';
      estado.textContent = `Sin resultados para «${texto}».`;
    }
    abrir();
  }

  async function buscar(texto) {
    controlador?.abort();
    controlador = new AbortController();
    resultados = [];
    lista.replaceChildren();
    estado.className = 'sugerencias-estado';
    estado.textContent = 'Buscando…';
    abrir();
    try {
      resultados = await obtenerJSON(`/api/productos/buscar?q=${encodeURIComponent(texto)}&limite=8`, { signal: controlador.signal });
      activo = -1;
      pintar(texto);
    } catch (error) {
      if (error.name === 'AbortError') return;
      resultados = [];
      lista.replaceChildren();
      estado.className = 'sugerencias-estado con-error';
      estado.replaceChildren(
        document.createTextNode('No pudimos buscar en este momento. '),
        el('button', {
          type: 'button', clase: 'enlace',
          onmousedown: (evento) => evento.preventDefault(),
          onclick: () => buscar(texto),
        }, 'Reintentar'));
      abrir();
    }
  }

  const textoActual = () => entrada.value.trim().replace(/\s+/g, ' ');

  entrada.addEventListener('input', () => {
    clearTimeout(espera);
    const texto = textoActual();
    if (texto.length < 2) {
      controlador?.abort();
      resultados = [];
      cerrar();
      return;
    }
    espera = setTimeout(() => buscar(texto), 250);
  });

  entrada.addEventListener('keydown', (evento) => {
    if (evento.key === 'ArrowDown') {
      evento.preventDefault();
      if (!resultados.length) return;
      abrir();
      marcar(Math.min(activo + 1, resultados.length - 1));
    } else if (evento.key === 'ArrowUp') {
      evento.preventDefault();
      marcar(Math.max(activo - 1, -1));
    } else if (evento.key === 'Escape' && !panel.hidden) {
      evento.preventDefault();
      cerrar();
    }
  });

  entrada.addEventListener('blur', () => setTimeout(cerrar, 150));
  entrada.addEventListener('focus', () => { if (resultados.length && textoActual().length >= 2) abrir(); });

  formulario.addEventListener('submit', (evento) => {
    evento.preventDefault();
    if (activo >= 0) { elegir(activo); return; }
    const texto = textoActual();
    if (texto.length >= 2) { clearTimeout(espera); buscar(texto); }
  });
}

/* ------------------------------------------------------------------ arranque del encabezado */
/** cargarMenu: false en el inicio, que carga las categorías una vez para el menú y para su lista. */
export function iniciarEncabezado({ cargarMenu: conMenu = true } = {}) {
  const encabezado = $('#encabezado');

  // Cuando la barra promocional sale de la pantalla, el encabezado ya está pegado arriba:
  // se compacta (menos altura y una sombra). Al volver arriba recupera su tamaño.
  new IntersectionObserver(([entrada]) => {
    encabezado.classList.toggle('compacto', !entrada.isIntersecting);
  }).observe($('#barra-promo'));

  const boton = $('#menu-boton');
  const menu = $('#menu-categorias');
  const texto = $('#menu-boton-texto');
  const icono = $('#menu-icono');

  function alternarMenu(abrir) {
    boton.setAttribute('aria-expanded', String(abrir));
    menu.classList.toggle('abierto', abrir);
    texto.textContent = abrir ? 'Cerrar el menú de categorías' : 'Abrir el menú de categorías';
    icono.setAttribute('d', abrir ? 'M6 6l12 12M18 6 6 18' : 'M4 8h16M4 16h16');
    document.body.style.overflow = abrir ? 'hidden' : '';
    if (abrir) $('.menu-enlace', menu)?.focus();
  }

  boton.addEventListener('click', () => alternarMenu(boton.getAttribute('aria-expanded') !== 'true'));
  document.addEventListener('keydown', (evento) => {
    if (evento.key === 'Escape' && menu.classList.contains('abierto')) {
      alternarMenu(false);
      boton.focus();
    }
  });
  escritorio.addEventListener('change', (evento) => {
    if (evento.matches) alternarMenu(false);
  });

  new ResizeObserver(ajustarMenu).observe($('#menu-lista'));
  escritorio.addEventListener('change', ajustarMenu);
  document.fonts?.ready.then(ajustarMenu);

  pintarContador();
  window.addEventListener('carrito:cambio', () => pintarContador(true));

  iniciarBuscador();
  if (conMenu) cargarMenu();
}
