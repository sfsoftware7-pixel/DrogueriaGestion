/**
 * Página de inicio: banner rotativo de promociones, carrusel, carga de datos desde la API (con estados
 * de carga, vacío y error) y lista de categorías. El encabezado (menú, autocompletado, contador del carrito)
 * está en encabezado.js y las utilidades compartidas en comun.js.
 * El contenido dinámico se crea con createElement/textContent (nunca innerHTML).
 * La entrada del hero, el hover y el momento de la fórmula los aportan los archivos de la skill
 * de diseño (static/vendor/taste), sin modificar.
 */
import { obtenerJSON } from './api.js';
import { $, agregarAlCarrito, el, flecha, mostrarError, mostrarVacio, movimientoReducido, pesos } from './comun.js';
import { iniciarEncabezado, menuSinCategorias, pintarMenu } from './encabezado.js';

function esqueletosProducto(cantidad) {
  return Array.from({ length: cantidad }, () => el('li', { clase: 'producto producto--esqueleto' },
    el('span', { clase: 'esqueleto esqueleto-etiqueta' }),
    el('span', { clase: 'esqueleto esqueleto-linea' }),
    el('span', { clase: 'esqueleto esqueleto-linea corta' }),
    el('span', { clase: 'esqueleto esqueleto-boton' })));
}

/* ------------------------------------------------------------------ tarjetas de producto */
// "Caja x 30 tabletas" -> { numero: "30", unidad: "tabletas" }; sin cantidad: { numero: "1", unidad: "unidad" }
function cantidadDe(presentacion) {
  const coincidencia = presentacion.match(/x\s*(\d+(?:[.,]\d+)?)\s*(.*)$/i);
  if (coincidencia) return { numero: coincidencia[1], unidad: coincidencia[2] || '' };
  return { numero: '1', unidad: presentacion.toLowerCase() };
}

function tarjetaProducto(producto) {
  const enOferta = producto.precio_oferta !== null;
  const agotado = producto.stock === 0;
  const cantidad = cantidadDe(producto.presentacion);
  const precios = enOferta
    ? [
      el('span', { clase: 'precio' },
        el('span', { clase: 'solo-lectores', texto: 'Precio con descuento: ' }), pesos(producto.precio_oferta)),
      el('del', { clase: 'precio-anterior' },
        el('span', { clase: 'solo-lectores', texto: 'Precio anterior: ' }), pesos(producto.precio)),
    ]
    : [el('span', { clase: 'precio' }, el('span', { clase: 'solo-lectores', texto: 'Precio: ' }), pesos(producto.precio))];

  return el('li', { clase: `producto${producto.requiere_formula ? ' producto--rx' : ''}` },
    // Imagen de relleno (brief): una etiqueta tipográfica con el laboratorio, la cantidad y la categoría
    el('div', { clase: `producto__etiqueta${enOferta ? ' producto__etiqueta--oferta' : ''}`, 'aria-hidden': 'true' },
      el('span', { clase: 'etiqueta__lab', texto: producto.laboratorio }),
      el('span', { clase: 'etiqueta__cantidad' }, cantidad.numero, el('span', { clase: 'etiqueta__unidad', texto: cantidad.unidad })),
      el('span', { clase: 'etiqueta__categoria', texto: producto.categoria }),
      enOferta ? el('span', { clase: 'producto__descuento', texto: `-${producto.descuento_porcentaje} %` }) : null),
    el('div', { clase: 'producto__cuerpo' },
      el('h3', { clase: 'producto__nombre', texto: producto.nombre }),
      el('p', { clase: 'producto__presentacion', texto: producto.presentacion }),
      el('div', { clase: 'producto__insignias' },
        producto.requiere_formula ? el('span', { clase: 'insignia-formula', texto: 'Requiere fórmula médica' }) : null),
      el('p', { clase: 'producto__precios' }, precios),
      el('button', {
        type: 'button', clase: 'btn btn--secondary',
        'aria-label': agotado ? `${producto.nombre}: agotado` : `Agregar ${producto.nombre} al carrito`,
        disabled: agotado,
        onclick: () => agregarAlCarrito(producto),
      }, agotado ? 'Agotado' : 'Agregar')));
}

async function cargarProductos({ url, lista, estado, tituloError, mensajeVacio, esqueletos }) {
  lista.setAttribute('aria-busy', 'true');
  if (lista.dataset.cargado) lista.replaceChildren(...esqueletosProducto(esqueletos));
  try {
    const productos = await obtenerJSON(url);
    lista.dataset.cargado = '1';
    if (!productos.length) {
      lista.replaceChildren();
      mostrarVacio(estado, mensajeVacio);
      return;
    }
    estado.replaceChildren();
    lista.replaceChildren(...productos.map(tarjetaProducto));
  } catch (error) {
    lista.dataset.cargado = '1';
    lista.replaceChildren();
    mostrarError(estado, tituloError, error, () => cargarProductos({ url, lista, estado, tituloError, mensajeVacio, esqueletos }));
  } finally {
    lista.setAttribute('aria-busy', 'false');
  }
}

const cargarDestacados = () => cargarProductos({
  url: '/api/productos/destacados?tipo=destacados&limite=12',
  lista: $('#carrusel-destacados'),
  estado: $('#estado-destacados'),
  tituloError: 'No pudimos cargar los productos destacados.',
  mensajeVacio: 'Por ahora no hay productos destacados.',
  esqueletos: 4,
});

const cargarPromociones = () => cargarProductos({
  url: '/api/productos/destacados?tipo=promocion&limite=8',
  lista: $('#grilla-promociones'),
  estado: $('#estado-promociones'),
  tituloError: 'No pudimos cargar las promociones.',
  mensajeVacio: 'No hay promociones vigentes en este momento.',
  esqueletos: 4,
});

/* ------------------------------------------------------------------ categorías (menú y lista del inicio) */
async function cargarCategorias() {
  const menu = $('#menu-lista');
  const lista = $('#grilla-categorias');
  const estado = $('#estado-categorias');
  lista.setAttribute('aria-busy', 'true');
  menu.setAttribute('aria-busy', 'true');
  try {
    const categorias = await obtenerJSON('/api/categorias');
    if (!categorias.length) {
      lista.replaceChildren();
      menuSinCategorias('Sin categorías');
      mostrarVacio(estado, 'Aún no hay categorías publicadas.');
      return;
    }
    estado.replaceChildren();
    pintarMenu(categorias);
    lista.replaceChildren(...categorias.map((c) => el('li', {},
      el('a', { clase: 'fila-cat', href: '#categorias', 'data-categoria': c.nombre },
        el('span', { clase: 'fila-cat__nombre', texto: c.nombre }),
        el('span', { clase: 'fila-cat__total', texto: `${c.total_productos} ${c.total_productos === 1 ? 'producto' : 'productos'}` }),
        flecha()))));
  } catch (error) {
    lista.replaceChildren();
    menuSinCategorias('Categorías no disponibles');
    mostrarError(estado, 'No pudimos cargar las categorías.', error, cargarCategorias);
  } finally {
    lista.setAttribute('aria-busy', 'false');
    menu.setAttribute('aria-busy', 'false');
  }
}

/* ------------------------------------------------------------------ banner rotativo de promociones */
function iniciarBanner() {
  const diapositivas = [...document.querySelectorAll('.promo')];
  if (diapositivas.length < 2) return;
  const banner = $('#banner');
  const contenedor = $('#banner-diapositivas');
  const contador = $('#banner-contador');
  const botonPausa = $('#banner-pausa');
  let actual = 0;
  let temporizador = null;
  let pausado = movimientoReducido.matches; // sin rotación automática si se pidió menos movimiento

  function mostrar(indice) {
    actual = (indice + diapositivas.length) % diapositivas.length;
    diapositivas.forEach((d, i) => {
      const activa = i === actual;
      d.classList.toggle('activa', activa);
      d.toggleAttribute('inert', !activa);
      if (activa) d.removeAttribute('aria-hidden'); else d.setAttribute('aria-hidden', 'true');
    });
    contador.textContent = `${actual + 1} / ${diapositivas.length}`;
  }

  const detener = () => clearInterval(temporizador);
  function programar() {
    detener();
    if (!pausado) temporizador = setInterval(() => mostrar(actual + 1), 6000);
  }
  function pintarPausa() {
    botonPausa.setAttribute('aria-pressed', String(pausado));
    botonPausa.textContent = pausado ? 'Reanudar' : 'Pausar';
  }
  function navegar(indice) {
    contenedor.setAttribute('aria-live', 'polite'); // al navegar a mano se anuncia la promoción
    mostrar(indice);
    programar();
  }

  $('#banner-anterior').addEventListener('click', () => navegar(actual - 1));
  $('#banner-siguiente').addEventListener('click', () => navegar(actual + 1));
  botonPausa.addEventListener('click', () => { pausado = !pausado; pintarPausa(); programar(); });
  // Se detiene mientras el puntero o el foco están dentro
  banner.addEventListener('mouseenter', detener);
  banner.addEventListener('mouseleave', programar);
  banner.addEventListener('focusin', detener);
  banner.addEventListener('focusout', (evento) => { if (!banner.contains(evento.relatedTarget)) programar(); });

  pintarPausa();
  programar();
}

/* ------------------------------------------------------------------ carrusel */
function iniciarCarruseles() {
  document.querySelectorAll('[data-carrusel]').forEach((boton) => {
    boton.addEventListener('click', () => {
      const lista = document.getElementById(boton.dataset.carrusel);
      lista.scrollBy({
        left: Number(boton.dataset.direccion) * lista.clientWidth * 0.9,
        behavior: movimientoReducido.matches ? 'auto' : 'smooth',
      });
    });
  });
}

/* ------------------------------------------------------------------ arranque */
iniciarEncabezado({ cargarMenu: false });
iniciarBanner();
iniciarCarruseles();
cargarCategorias();
cargarDestacados();
cargarPromociones();
