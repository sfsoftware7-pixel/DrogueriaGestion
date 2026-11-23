/**
 * Recibo en PDF («Comprobante de compra») con jsPDF 4.2.1 (static/vendor/jspdf, global window.jspdf).
 * Recibe el pedido tal como quedó guardado en MySQL (lo inserta el servidor en la página): nunca usa el carrito.
 * Tamaño carta, unidades en milímetros.
 */
import { pesos } from './comun.js';

const TINTA = [19, 41, 58];
const TENUE = [75, 89, 102];
const LINEA = [205, 210, 204];
const SUPERFICIE = [230, 233, 226];
const MARGEN = 18;

// Intl usa espacio duro entre "$" y el número; las fuentes estándar del PDF lo muestran mejor como espacio normal
const dinero = (valor) => pesos(valor).replace(/[  ]/g, ' ');

async function logoPNG() {
  try {
    const imagen = new Image();
    imagen.src = '/static/img/logo.svg';
    await imagen.decode();
    const lienzo = document.createElement('canvas');
    lienzo.width = 96;
    lienzo.height = 96;
    lienzo.getContext('2d').drawImage(imagen, 0, 0, 96, 96);
    return lienzo.toDataURL('image/png');
  } catch {
    return null; // sin logo, el recibo sale igual con el nombre
  }
}

export async function generarRecibo(pedido) {
  const { jsPDF } = window.jspdf;
  const doc = new jsPDF({ unit: 'mm', format: 'letter', compress: true });
  const ancho = doc.internal.pageSize.getWidth();
  const alto = doc.internal.pageSize.getHeight();
  const derecha = ancho - MARGEN;
  const tienda = pedido.drogueria;

  doc.setProperties({ title: `Comprobante de compra ${pedido.codigo}`, subject: 'Comprobante de compra', author: tienda.nombre, creator: tienda.nombre });

  const fuente = (estilo, tamano, color = TINTA) => {
    doc.setFont('helvetica', estilo);
    doc.setFontSize(tamano);
    doc.setTextColor(...color);
  };

  /* ---------------- encabezado: marca, NIT, dirección y título */
  const logo = await logoPNG();
  if (logo) doc.addImage(logo, 'PNG', MARGEN, 15, 11, 11);
  const xMarca = logo ? MARGEN + 14 : MARGEN;
  fuente('bold', 15);
  doc.text(tienda.nombre, xMarca, 21);
  fuente('normal', 8.5, TENUE);
  doc.text(`${tienda.razon_social} · NIT ${tienda.nit}`, xMarca, 26);
  doc.text(tienda.direccion, xMarca, 30);
  fuente('bold', 16);
  doc.text('Comprobante de compra', derecha, 21, { align: 'right' });
  fuente('normal', 10, TENUE);
  doc.text(`Pedido ${pedido.codigo}`, derecha, 27, { align: 'right' });
  doc.setDrawColor(...LINEA);
  doc.setLineWidth(0.3);
  doc.line(MARGEN, 36, derecha, 36);

  /* ---------------- datos del pedido (dos columnas) */
  function dato(etiqueta, valor, x, y, anchoColumna) {
    fuente('normal', 8.5, TENUE);
    doc.text(etiqueta, x, y);
    fuente('normal', 10);
    const lineas = doc.splitTextToSize(valor, anchoColumna);
    doc.text(lineas, x, y + 4.5);
    return y + 4.5 + lineas.length * 4.6 + 3;
  }
  const columna = (ancho - 2 * MARGEN - 10) / 2;
  const xDerecha = MARGEN + columna + 10;
  let yIzq = 44;
  yIzq = dato('Número de pedido', pedido.codigo, MARGEN, yIzq, columna);
  yIzq = dato('Fecha y hora', pedido.fecha_texto, MARGEN, yIzq, columna);
  yIzq = dato('Método de pago', pedido.metodo_pago, MARGEN, yIzq, columna);
  let yDer = 44;
  yDer = dato('Cliente', `${pedido.cliente.nombre} · ${pedido.cliente.documento}`, xDerecha, yDer, columna);
  yDer = pedido.tipo_entrega === 'DOMICILIO'
    ? dato('Dirección de entrega', pedido.direccion_entrega, xDerecha, yDer, columna)
    : dato('Retiro en sede', `${pedido.sede.nombre} · ${pedido.sede.direccion}`, xDerecha, yDer, columna);
  yDer = dato('Estado', pedido.estado_texto, xDerecha, yDer, columna);
  let y = Math.max(yIzq, yDer) + 4;

  /* ---------------- tabla de productos */
  const colCantidad = MARGEN + 118;
  const colPrecio = MARGEN + 150;
  const anchoNombre = 108;
  function cabeceraTabla() {
    doc.setFillColor(...SUPERFICIE);
    doc.rect(MARGEN, y, derecha - MARGEN, 8, 'F');
    fuente('bold', 9);
    doc.text('Producto', MARGEN + 2, y + 5.3);
    doc.text('Cantidad', colCantidad, y + 5.3, { align: 'right' });
    doc.text('Precio unitario', colPrecio, y + 5.3, { align: 'right' });
    doc.text('Subtotal', derecha - 2, y + 5.3, { align: 'right' });
    y += 8;
  }
  cabeceraTabla();
  for (const item of pedido.items) {
    fuente('normal', 10);
    const nombre = doc.splitTextToSize(item.nombre, anchoNombre);
    const detalle = doc.splitTextToSize(`${item.presentacion}${item.requiere_formula ? ' · Con fórmula médica' : ''}`, anchoNombre);
    const altoFila = 4 + nombre.length * 4.6 + detalle.length * 4 + 2;
    if (y + altoFila > alto - 40) { doc.addPage(); y = MARGEN; cabeceraTabla(); }
    fuente('normal', 10);
    doc.text(nombre, MARGEN + 2, y + 5);
    doc.text(String(item.cantidad), colCantidad, y + 5, { align: 'right' });
    doc.text(dinero(item.precio_unitario), colPrecio, y + 5, { align: 'right' });
    doc.text(dinero(item.subtotal), derecha - 2, y + 5, { align: 'right' });
    fuente('normal', 8.5, TENUE);
    doc.text(detalle, MARGEN + 2, y + 5 + nombre.length * 4.6);
    y += altoFila;
    doc.setDrawColor(...LINEA);
    doc.line(MARGEN, y, derecha, y);
  }

  /* ---------------- totales */
  if (y + 40 > alto - 20) { doc.addPage(); y = MARGEN; }
  y += 8;
  const xEtiqueta = MARGEN + 100;
  function total(etiqueta, valor, negrita = false) {
    fuente(negrita ? 'bold' : 'normal', negrita ? 12 : 10);
    doc.text(etiqueta, xEtiqueta, y);
    doc.text(valor, derecha - 2, y, { align: 'right' });
    y += negrita ? 7 : 6;
  }
  total('Subtotal', dinero(pedido.subtotal));
  total('Descuentos', pedido.descuento ? `-${dinero(pedido.descuento)}` : dinero(0));
  total('Domicilio', pedido.tipo_entrega === 'DOMICILIO' ? dinero(pedido.costo_envio) : 'Sin costo (retiro en sede)');
  doc.setDrawColor(...TINTA);
  doc.line(xEtiqueta, y - 3, derecha, y - 3);
  y += 2;
  total('Total', dinero(pedido.total), true);

  /* ---------------- pie de cada página */
  const paginas = doc.getNumberOfPages();
  for (let pagina = 1; pagina <= paginas; pagina += 1) {
    doc.setPage(pagina);
    doc.setDrawColor(...LINEA);
    doc.line(MARGEN, alto - 20, derecha, alto - 20);
    fuente('normal', 8.5, TENUE);
    doc.text(`Gracias por tu compra. Guarda este comprobante: con el código ${pedido.codigo} consultas el estado del pedido.`, MARGEN, alto - 15);
    doc.text(`${tienda.nombre} · ${tienda.telefono} · ${tienda.correo}`, MARGEN, alto - 11);
    doc.text(`Página ${pagina} de ${paginas}`, derecha, alto - 11, { align: 'right' });
  }
  return doc;
}

export const nombreArchivo = (pedido) => `recibo-${pedido.codigo}.pdf`;
