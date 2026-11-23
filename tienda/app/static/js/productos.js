/**
 * Tarjetas de producto compartidas por el inicio y las páginas de categoría (antes vivían en inicio.js).
 * Se crean con createElement/textContent (nunca innerHTML).
 */
import { agregarAlCarrito, el, pesos } from './comun.js';

export function esqueletosProducto(cantidad) {
  return Array.from({ length: cantidad }, () => el('li', { clase: 'producto producto--esqueleto' },
    el('span', { clase: 'esqueleto esqueleto-etiqueta' }),
    el('span', { clase: 'esqueleto esqueleto-linea' }),
    el('span', { clase: 'esqueleto esqueleto-linea corta' }),
    el('span', { clase: 'esqueleto esqueleto-boton' })));
}

// "Caja x 30 tabletas" -> { numero: "30", unidad: "tabletas" }; sin cantidad: { numero: "1", unidad: "unidad" }
function cantidadDe(presentacion) {
  const coincidencia = presentacion.match(/x\s*(\d+(?:[.,]\d+)?)\s*(.*)$/i);
  if (coincidencia) return { numero: coincidencia[1], unidad: coincidencia[2] || '' };
  return { numero: '1', unidad: presentacion.toLowerCase() };
}

export function tarjetaProducto(producto) {
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
