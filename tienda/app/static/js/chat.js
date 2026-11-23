/**
 * Chatbot por reglas (sin IA, sin claves ni servicios externos). Responde:
 *   a. horarios (y si está abierto ahora)   b. domicilios y cobertura por barrio
 *   c. disponibilidad de productos           d. navegación y carrito
 * Todo sale de la API de la tienda: horario, zonas y contacto de datos_tienda.toml; el stock, de la misma
 * consulta del catálogo en MySQL. Nunca inventa datos. Ante dosis, síntomas o qué tomar, no recomienda nada.
 */
import { obtenerJSON } from './api.js';
import { $, agregarAlCarrito, carritoActual, el, pesos } from './comun.js';

const boton = $('#chat-boton');
const panel = $('#chat-panel');
const mensajes = $('#chat-mensajes');
const rapidas = $('#chat-rapidas');
const formulario = $('#chat-form');
const entrada = $('#chat-entrada');

let espera = null;     // 'barrio' | 'producto' | null: qué se espera en el próximo mensaje
let iniciado = false;
let infoTienda = null; // /api/tienda (zonas, contacto, pago); el horario se pide fresco cada vez

/* ------------------------------------------------------------------ texto */
// "¿Tienen ACETAMINOFÉN?" -> "tienen acetaminofen"
const normalizar = (texto) => texto.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  .replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
const contiene = (texto, frases) => frases.some((frase) => ` ${texto} `.includes(` ${frase} `));
const quitar = (texto, palabras) => texto.split(' ').filter((p) => !palabras.includes(p)).join(' ').trim();

const REGLAS = {
  urgencia: ['urgencia', 'emergencia', 'sobredosis', 'intoxicacion', 'intoxicado', 'envenenamiento', 'no respira', 'convulsion', 'convulsiones', 'desmayo'],
  medica: ['dosis', 'dosificacion', 'posologia', 'cuanto tomo', 'cuanto me tomo', 'cuantas tomo', 'cuantas pastillas', 'cuantas tabletas',
    'cuantas capsulas', 'cuantas gotas', 'cuanto le doy', 'cuanto debo tomar', 'cada cuanto', 'cada cuantas horas', 'cuantas veces al dia',
    'que tomo', 'que me tomo', 'que puedo tomar', 'que debo tomar', 'que le doy', 'puedo tomar', 'me recomiendas', 'me recomienda',
    'recomiendame', 'recomiendeme', 'que recomiendas', 'que me sirve', 'sirve para', 'es bueno para', 'para que sirve', 'sintoma', 'sintomas',
    'me duele', 'me arde', 'tengo dolor', 'tengo fiebre', 'tengo gripa', 'tengo tos', 'tengo diarrea', 'tengo alergia', 'diagnostico',
    'diagnosticar', 'que enfermedad', 'efectos secundarios', 'contraindicaciones', 'contraindicacion', 'embarazada', 'embarazo', 'lactancia',
    'interaccion', 'mezclar con', 'algo para el', 'algo para la', 'algo para los', 'remedio para', 'medicamento para', 'pastilla para'],
  saludo: ['hola', 'buenas', 'buenos dias', 'buenas tardes', 'buenas noches', 'ayuda', 'menu', 'opciones', 'empezar'],
  gracias: ['gracias', 'muchas gracias', 'chao', 'adios'],
  contacto: ['persona', 'asesor', 'asesora', 'humano', 'hablar con', 'farmaceutico', 'farmaceuta', 'contacto', 'telefono', 'llamar',
    'correo', 'atencion al cliente', 'queja', 'reclamo'],
  seguimiento: ['seguir mi pedido', 'estado de mi pedido', 'estado del pedido', 'donde esta mi pedido', 'rastrear', 'seguimiento'],
  horario: ['horario', 'horarios', 'abren', 'abre', 'abierto', 'abierta', 'abiertos', 'cierran', 'cierra', 'cerrado',
    'cerrados', 'atienden', 'domingo', 'domingos', 'festivo', 'festivos'],
  domicilio: ['domicilio', 'domicilios', 'envio', 'envios', 'envian', 'enviar', 'envia', 'cobertura', 'barrio', 'barrios', 'llegan', 'llega',
    'entregan', 'despacho', 'despachan', 'reparten', 'zona', 'zonas', 'cuanto demora', 'cuanto tarda', 'tiempo de entrega', 'mandan', 'traen'],
  verCarrito: ['mi carrito', 'ver carrito', 'ver el carrito', 'que tengo en el carrito', 'que hay en el carrito', 'que hay en mi carrito',
    'que llevo', 'cuanto llevo', 'total del carrito', 'total de mi carrito', 'resumen del carrito'],
  buscar: ['como busco', 'como buscar', 'como puedo buscar', 'donde busco', 'como encuentro', 'como encontrar', 'buscador', 'como se busca'],
  agregar: ['agregar', 'agrego', 'anadir', 'anado', 'como agrego', 'meter al carrito', 'poner en el carrito'],
  quitar: ['quitar', 'quito', 'eliminar', 'elimino', 'borrar', 'borro', 'sacar', 'saco'],
  cantidad: ['cantidad', 'cantidades', 'cambiar la cantidad', 'mas unidades', 'menos unidades'],
  pagar: ['pagar', 'pago', 'pagos', 'comprar', 'compro', 'finalizar', 'checkout', 'metodo de pago', 'metodos de pago', 'contra entrega',
    'tarjeta', 'pse', 'efectivo', 'datafono'],
  carrito: ['carrito', 'como compro', 'como comprar', 'como hago un pedido', 'hacer un pedido', 'como pido', 'como funciona'],
  stock: ['tienen', 'tiene', 'tienes', 'hay', 'disponible', 'disponibles', 'disponibilidad', 'stock', 'existencias', 'agotado', 'agotados',
    'quedan', 'queda', 'unidades', 'venden', 'vende', 'manejan', 'consigo', 'consiguen', 'precio', 'cuesta', 'vale'],
};
// Palabras que no son parte del nombre de un producto ni de un barrio
const RELLENO = ['de', 'del', 'la', 'el', 'los', 'las', 'un', 'una', 'unos', 'unas', 'me', 'mi', 'por', 'favor', 'porfa', 'para', 'con', 'en',
  'que', 'y', 'o', 'a', 'al', 'si', 'no', 'ustedes', 'usted', 'algo', 'producto', 'productos', 'quiero', 'necesito', 'busco', 'buscando',
  'saber', 'quisiera', 'pueden', 'puedo', 'todavia', 'aun', 'ahora', 'hoy', 'cuantas', 'cuantos', 'cuanto', 'hasta', 'como', 'esta', 'estan',
  'hola', 'buenas', 'sector', 'vivo', 'estoy', 'queda', 'hacen', 'tambien', 'ya'];

/* ------------------------------------------------------------------ mensajes */
function desplazar() { mensajes.scrollTop = mensajes.scrollHeight; }

function mensajeUsuario(texto) {
  mensajes.append(el('div', { clase: 'chat-msj chat-msj--usuario' }, el('span', { clase: 'solo-lectores', texto: 'Tú: ' }), texto));
  desplazar();
}

function mensajeBot(...contenido) {
  const nodo = el('div', { clase: 'chat-msj chat-msj--bot' }, el('span', { clase: 'solo-lectores', texto: 'Asistente: ' }), ...contenido);
  mensajes.append(nodo);
  desplazar();
  return nodo;
}

const parrafo = (...contenido) => el('p', {}, ...contenido);
const lista = (items) => el('ul', { clase: 'chat-lista' }, items.map((item) => el('li', {}, item)));
const enlace = (href, texto) => el('a', { clase: 'enlace', href }, texto);

const OPCIONES = [
  ['Horarios', () => horarios()],
  ['Domicilios', () => domicilios()],
  ['Disponibilidad', () => pedirProducto()],
  ['Carrito y compra', () => navegacion('carrito')],
  ['Hablar con una persona', () => contacto()],
];

function opciones(lista = OPCIONES) {
  rapidas.replaceChildren(...lista.map(([texto, accion]) => el('button', {
    type: 'button', clase: 'chat-rapida',
    onclick: () => { mensajeUsuario(texto); accion(); },
  }, texto)));
}

async function info() {
  if (!infoTienda) infoTienda = await obtenerJSON('/api/tienda');
  return infoTienda;
}

async function conDatos(trabajo) {
  try {
    await trabajo();
  } catch (error) {
    mensajeBot(parrafo(`No pude consultar esa información (${error.message}). Intenta de nuevo en un momento.`));
    opciones();
  }
}

/* ------------------------------------------------------------------ respuestas */
function bienvenida() {
  iniciado = true;
  mensajeBot(parrafo('Hola, soy el asistente automático de la droguería. Te ayudo con horarios, domicilios, disponibilidad de productos y tu carrito.'),
    parrafo('Elige una opción o escribe tu pregunta.'));
  opciones();
}

function lineaContacto(datos) {
  return parrafo(`Te atiende ${datos.contacto.atiende} en el teléfono ${datos.contacto.telefono} o en el correo `,
    enlace(`mailto:${datos.contacto.correo}`, datos.contacto.correo), '.');
}

const contacto = () => conDatos(async () => {
  espera = null;
  const datos = await obtenerJSON('/api/tienda');
  mensajeBot(lineaContacto(datos), parrafo(datos.horario.resumen));
  opciones();
});

const medica = (urgente = false) => conDatos(async () => {
  espera = null;
  const datos = await info();
  mensajeBot(
    urgente ? parrafo(el('strong', { texto: 'Si es una emergencia, llama ya a la línea 123 o ve al servicio de urgencias más cercano.' })) : null,
    parrafo('No puedo recomendar medicamentos ni dosis, ni orientarte sobre síntomas o diagnósticos. Consulta al farmacéutico o a tu médico.'),
    lineaContacto(datos));
  opciones();
});

const horarios = () => conDatos(async () => {
  espera = null;
  const { horario } = await obtenerJSON('/api/tienda'); // fresco: "abierto ahora" depende de la hora
  mensajeBot(parrafo(el('strong', { texto: horario.resumen })),
    lista(horario.dias.map((d) => `${d.dia}: ${d.texto}`)),
    parrafo(`Hora de Colombia: ${horario.hora_actual}`)); // la hora ya termina en "a. m." o "p. m."
  opciones();
});

const domicilios = () => conDatos(async () => {
  const datos = await info();
  const porCiudad = new Map();
  for (const zona of datos.domicilio.zonas) {
    if (!porCiudad.has(zona.ciudad)) porCiudad.set(zona.ciudad, []);
    porCiudad.get(zona.ciudad).push(`${zona.nombre}: ${pesos(zona.costo)}, ${zona.tiempo}`);
  }
  mensajeBot(parrafo('Llevamos pedidos a estas zonas (costo del domicilio y tiempo estimado):'),
    lista([...porCiudad].map(([ciudad, zonas]) => `${ciudad}. ${zonas.join(' · ')}`)),
    parrafo('El retiro en sede es gratis. Escribe tu barrio y te digo si llegamos.'));
  espera = 'barrio';
  opciones();
});

const cobertura = (barrio) => conDatos(async () => {
  const r = await obtenerJSON(`/api/domicilios/cobertura?barrio=${encodeURIComponent(barrio)}`);
  if (r.cobertura) {
    espera = null;
    mensajeBot(...r.coincidencias.map((c) => parrafo(
      `Sí llegamos a ${c.barrio} (${c.zona}, ${c.ciudad}): domicilio de ${pesos(c.costo)}, entrega en ${c.tiempo}.`)));
    opciones();
    return;
  }
  espera = 'barrio';
  const nombre = r.barrio.replace(/(^|\s)(\p{L})/gu, (_, espacio, letra) => espacio + letra.toUpperCase()); // "kennedy" -> "Kennedy"
  mensajeBot(parrafo(`Por ahora no tenemos domicilio en «${nombre}». Puedes retirar gratis en una sede o escribir otro barrio.`));
  opciones(r.sugerencias.length
    ? r.sugerencias.slice(0, 4).map((s) => [s.barrio, () => cobertura(s.barrio)]).concat([OPCIONES[4]])
    : OPCIONES);
});

function pedirProducto() {
  espera = 'producto';
  mensajeBot(parrafo('¿Qué producto buscas? Escribe su nombre o el principio activo, aunque sea incompleto (por ejemplo «acetaminofen» o «lorata»).'));
  opciones();
}

function tarjetaStock(producto) {
  const disponible = producto.stock > 0;
  const sedes = producto.sedes.map((s) => `${s.nombre}: ${s.stock > 0 ? `${s.stock}` : 'agotado'}`).join(' · ');
  return el('div', { clase: 'chat-producto' },
    el('p', { clase: 'chat-producto__nombre', texto: producto.nombre }),
    el('p', { clase: 'chat-producto__detalle', texto: `${producto.presentacion} · ${pesos(producto.precio_oferta ?? producto.precio)}` }),
    el('p', { clase: disponible ? 'chat-producto__stock' : 'chat-producto__stock chat-producto__stock--agotado' },
      disponible ? `Disponible: ${producto.stock} ${producto.stock === 1 ? 'unidad' : 'unidades'} en total` : 'Agotado en este momento'),
    disponible ? el('p', { clase: 'chat-producto__detalle', texto: sedes }) : null,
    producto.requiere_formula ? el('p', { clase: 'chat-producto__detalle', texto: 'Requiere fórmula médica: la adjuntas al pagar.' }) : null,
    el('button', {
      type: 'button', clase: 'btn btn--secondary', disabled: !disponible,
      'aria-label': disponible ? `Agregar ${producto.nombre} al carrito` : `${producto.nombre}: agotado`,
      onclick: () => {
        if (agregarAlCarrito(producto) > 0) mensajeBot(parrafo(`Listo: ${producto.nombre} está en tu carrito. `, enlace('/carrito', 'Ir al carrito')));
      },
    }, disponible ? 'Agregar al carrito' : 'Agotado'));
}

const disponibilidad = (termino) => conDatos(async () => {
  const resultados = await obtenerJSON(`/api/productos/disponibilidad?q=${encodeURIComponent(termino)}`);
  if (!resultados.length) {
    espera = 'producto';
    mensajeBot(parrafo(`No encontré «${termino}» en el catálogo. Revisa cómo se escribe o prueba con el principio activo.`));
    opciones();
    return;
  }
  espera = null;
  mensajeBot(parrafo(`Esto encontré para «${termino}»:`), ...resultados.slice(0, 3).map(tarjetaStock),
    resultados.length > 3 ? parrafo('Hay más coincidencias: escribe el nombre más completo para afinar la búsqueda.') : null);
  opciones();
});

const resumenCarrito = () => conDatos(async () => {
  const carrito = carritoActual();
  const ids = Object.keys(carrito);
  if (!ids.length) {
    mensajeBot(parrafo('Tu carrito está vacío. Pregúntame por un producto o búscalo arriba.'));
    opciones();
    return;
  }
  const productos = await obtenerJSON(`/api/productos?ids=${ids.join(',')}`);
  let total = 0;
  const lineas = productos.filter((p) => carrito[p.id]).map((p) => {
    const subtotal = (p.precio_oferta ?? p.precio) * carrito[p.id];
    total += subtotal;
    return `${carrito[p.id]} × ${p.nombre}: ${pesos(subtotal)}`;
  });
  mensajeBot(parrafo('En tu carrito tienes:'), lista(lineas),
    parrafo(el('strong', { texto: `Total actual: ${pesos(total)}` }), ' (sin domicilio; ya incluye los descuentos vigentes).'),
    parrafo(enlace('/carrito', 'Ir al carrito y pagar')));
  opciones();
});

const GUIAS = {
  buscar: 'Escribe el nombre del producto o su principio activo en el buscador de arriba (por ejemplo «loratadina»). Desde la segunda letra salen sugerencias; con las flechas las recorres. También puedes preguntarme aquí si hay un producto.',
  agregar: 'En cada tarjeta de producto pulsa «Agregar». El botón Carrito, arriba a la derecha, muestra cuántas unidades llevas. Si un producto requiere fórmula médica, la adjuntas al pagar.',
  quitar: 'Entra a Carrito y pulsa «Quitar» junto al producto.',
  cantidad: 'En Carrito usa los botones − y + o escribe la cantidad. No puedes pasar de las unidades disponibles.',
};

const navegacion = (tema) => conDatos(async () => {
  espera = null;
  if (GUIAS[tema]) {
    mensajeBot(parrafo(GUIAS[tema]), parrafo(enlace('/carrito', 'Ir al carrito')));
  } else {
    const datos = await info();
    mensajeBot(parrafo('Así compras:'), el('ol', { clase: 'chat-lista' },
      el('li', { texto: 'Busca el producto y pulsa «Agregar».' }),
      el('li', { texto: 'Abre Carrito: ahí cambias cantidades o quitas productos.' }),
      el('li', { texto: 'Completa tus datos y elige domicilio (revisamos la cobertura de tu barrio) o retiro gratis en sede. Si te lo pide, adjunta la fórmula médica.' }),
      el('li', { texto: `Pulsa «Confirmar pedido». Pago: ${datos.pago.nombre.toLowerCase()}; ${datos.pago.descripcion.charAt(0).toLowerCase()}${datos.pago.descripcion.slice(1)}` }),
      el('li', { texto: 'Al final descargas o imprimes el comprobante de compra en PDF.' })));
    opciones([['Ver mi carrito', () => resumenCarrito()], ...OPCIONES.slice(0, 3), OPCIONES[4]]);
    return;
  }
  opciones();
});

function seguimiento() {
  espera = null;
  mensajeBot(parrafo('Para ver el estado de tu pedido entra a ', enlace('/seguimiento', 'Seguir mi pedido'),
    ' y escribe el código (por ejemplo PED-000123) y tu número de documento.'));
  opciones();
}

function noEntendi() {
  return conDatos(async () => {
    const datos = await info();
    mensajeBot(parrafo('No entendí tu pregunta. Puedo ayudarte con horarios, domicilios, disponibilidad de productos y el carrito.'),
      parrafo('Si prefieres hablar con una persona:'), lineaContacto(datos));
    opciones();
  });
}

async function barrioMencionado(texto) {
  const datos = await info().catch(() => null);
  if (!datos) return null;
  const barrios = datos.domicilio.zonas.flatMap((z) => [...z.barrios, z.nombre]);
  return barrios.find((b) => contiene(texto, [normalizar(b)])) || null;
}

/* ------------------------------------------------------------------ reglas */
async function responder(original) {
  const texto = normalizar(original);
  if (!texto) return;
  const corto = texto.split(' ').length <= 3;
  const r = (regla) => contiene(texto, REGLAS[regla]);

  if (r('urgencia')) return medica(true);
  if (r('medica')) return medica();               // antes que cualquier otra regla: nunca se recomienda nada
  if (r('saludo') && corto) return bienvenida();
  if (r('gracias') && corto) { mensajeBot(parrafo('Con gusto. ¿Te ayudo con algo más?')); return opciones(); }
  if (r('contacto')) return contacto();
  if (r('seguimiento')) return seguimiento();
  if (r('horario')) return horarios();
  if (r('domicilio')) {
    // Lo que queda al quitar las palabras de la pregunta es el barrio: "hacen domicilios a Chapinero" -> "chapinero"
    const barrio = quitar(texto, [...REGLAS.domicilio, ...RELLENO, 'tienen', 'cuesta', 'vale', 'precio', 'costo', 'valor', 'tiempo',
      'demora', 'demoran', 'tarda', 'tardan', 'se', 'su', 'sus', 'entrega', 'llegar', 'sale', 'hora', 'horas', 'dias', 'pedido', 'pedidos']);
    return barrio.length >= 3 ? cobertura(barrio) : domicilios();
  }
  if (r('verCarrito')) return resumenCarrito();
  for (const tema of ['buscar', 'quitar', 'cantidad', 'agregar']) if (r(tema)) return navegacion(tema);
  if (r('pagar') || r('carrito')) return navegacion('carrito');
  if (r('stock')) {
    const termino = quitar(texto, [...REGLAS.stock, ...RELLENO]);
    return termino.length >= 3 ? disponibilidad(termino) : pedirProducto();
  }
  if (espera === 'barrio') return cobertura(original.trim());
  if (espera === 'producto') return disponibilidad(quitar(texto, RELLENO) || texto);
  const barrio = await barrioMencionado(texto);
  if (barrio) return cobertura(barrio);
  // Último intento: quizá escribió solo el nombre de un producto ("acetaminofen 500")
  const termino = quitar(texto, RELLENO);
  if (termino.length >= 3 && texto.split(' ').length <= 6) {
    const resultados = await obtenerJSON(`/api/productos/disponibilidad?q=${encodeURIComponent(termino)}`).catch(() => []);
    if (resultados.length) return disponibilidad(termino);
  }
  return noEntendi();
}

/* ------------------------------------------------------------------ panel */
function abrir() {
  panel.hidden = false;
  boton.setAttribute('aria-expanded', 'true');
  if (!iniciado) bienvenida();
  entrada.focus();
}

function cerrar() {
  panel.hidden = true;
  boton.setAttribute('aria-expanded', 'false');
  boton.focus();
}

boton.addEventListener('click', () => (panel.hidden ? abrir() : cerrar()));
$('#chat-cerrar').addEventListener('click', cerrar);
document.addEventListener('keydown', (evento) => {
  if (evento.key === 'Escape' && !panel.hidden && (panel.contains(document.activeElement) || document.activeElement === boton)) {
    evento.preventDefault();
    cerrar();
  }
});
formulario.addEventListener('submit', (evento) => {
  evento.preventDefault();
  const texto = entrada.value.trim();
  if (!texto) return;
  entrada.value = '';
  mensajeUsuario(texto);
  responder(texto);
});
