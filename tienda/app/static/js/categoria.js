/**
 * Página de una categoría: sus productos (y los de sus subcategorías) con el precio vigente y las existencias,
 * leídos de /api/categorias/<slug>. Estados de carga, vacío y error; las tarjetas son las del inicio.
 */
import { obtenerJSON } from './api.js';
import { $, mostrarError, mostrarVacio } from './comun.js';
import { iniciarEncabezado } from './encabezado.js';
import { esqueletosProducto, tarjetaProducto } from './productos.js';

const lista = $('#grilla-categoria');
const estado = $('#estado-categoria');
const total = $('#total-categoria');

async function cargarCategoria() {
  lista.setAttribute('aria-busy', 'true');
  if (!lista.children.length) lista.replaceChildren(...esqueletosProducto(4));
  try {
    const categoria = await obtenerJSON(`/api/categorias/${encodeURIComponent(lista.dataset.slug)}`);
    const cantidad = categoria.productos.length;
    total.textContent = `${cantidad} ${cantidad === 1 ? 'producto' : 'productos'}, precios con IVA incluido.`;
    if (!cantidad) {
      lista.replaceChildren();
      mostrarVacio(estado, 'Por ahora no hay productos en esta categoría.');
      return;
    }
    estado.replaceChildren();
    lista.replaceChildren(...categoria.productos.map(tarjetaProducto));
  } catch (error) {
    lista.replaceChildren();
    mostrarError(estado, 'No pudimos cargar los productos de esta categoría.', error, cargarCategoria);
  } finally {
    lista.setAttribute('aria-busy', 'false');
  }
}

iniciarEncabezado();
cargarCategoria();
