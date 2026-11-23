/**
 * Tarjetas de producto compartidas por el inicio y las páginas de categoría (antes vivían en inicio.js).
 * Se crean con createElement/textContent (nunca innerHTML).
 */
import { agregarAlCarrito, el, pesos } from './comun.js';

export function esqueletosProducto(cantidad) {
  return Array.from({ length: cantidad }, () => el('li', { clase: 'producto producto--esqueleto' },
    el('span', { clase: 'esqueleto esqueleto-imagen' }),
    el('span', { clase: 'esqueleto esqueleto-linea' }),
    el('span', { clase: 'esqueleto esqueleto-linea corta' }),
    el('span', { clase: 'esqueleto esqueleto-boton' })));
}

export function tarjetaProducto(producto) {
  const enOferta = producto.precio_oferta !== null;
  const agotado = producto.stock === 0;
  const precios = enOferta
    ? [
      el('span', { clase: 'precio' },
        el('span', { clase: 'solo-lectores', texto: 'Precio con descuento: ' }), pesos(producto.precio_oferta)),
      el('del', { clase: 'precio-anterior' },
        el('span', { clase: 'solo-lectores', texto: 'Precio anterior: ' }), pesos(producto.precio)),
    ]
    : [el('span', { clase: 'precio' }, el('span', { clase: 'solo-lectores', texto: 'Precio: ' }), pesos(producto.precio))];

  return el('li', { clase: `producto${producto.requiere_formula ? ' producto--rx' : ''}` },
    el('div', { clase: 'producto__visual', 'aria-hidden': 'true' },
      el('img', {
        clase: 'producto__imagen',
        src: producto.imagen_url || '/static/img/productos/medicamentos-mesa.jpg',
        alt: '',
        loading: 'lazy',
        decoding: 'async',
      }),
      el('span', { clase: 'producto__laboratorio', texto: producto.laboratorio }),
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
