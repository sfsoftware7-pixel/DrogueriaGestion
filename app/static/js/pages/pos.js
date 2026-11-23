/**
 * Punto de venta: carrito, cliente, pago y registro de la venta.
 * El servidor recalcula precios, valida existencias y asigna lotes (FEFO);
 * aquí solo se muestra una vista previa de los valores.
 */
import {
  $, $$, abrirModal, api, cerrarModal, conCarga, confirmar, debounce, fecha, html, icono, leerFormulario,
  moneda, mostrarErrores, numero, toast, toastError,
} from '../core.js';

const CONSUMIDOR_FINAL = { id_cliente: 1, nombre: 'Consumidor final', tipo_documento: 'CC', numero_documento: '222222222222' };
const carrito = new Map(); // id_medicamento -> { med, cantidad }
let cliente = CONSUMIDOR_FINAL;
let resultados = [];
let indiceActivo = -1;

const buscador = $('#buscar-producto');
const listaResultados = $('#resultados-producto');
const formVenta = $('#form-venta');
const formFormula = $('#form-formula');

// Tope de descuento: el elemento solo existe para roles sin 'ventas.descuento_libre' (el servidor también lo valida)
const ayudaDescuento = $('#ayuda-descuento');
let descuentoMaximoPct = null; // null = sin tope (regente y administrador)
if (ayudaDescuento) {
  api.get('/api/configuracion').then((c) => {
    descuentoMaximoPct = Number(c.descuento_maximo_vendedor) || 0;
    actualizarTotales();
  }).catch(() => {});
}

/* ---------------------------- Búsqueda de productos ---------------------------- */
function cerrarResultados() {
  listaResultados.hidden = true;
  buscador.setAttribute('aria-expanded', 'false');
  indiceActivo = -1;
}

function pintarResultados() {
  if (!resultados.length) {
    listaResultados.innerHTML = html`<div class="vacio" style="padding:22px">No se encontraron productos activos</div>`;
  } else {
    listaResultados.innerHTML = html`${resultados.map((m, i) => {
      const sinStock = Number(m.stock_disponible) <= 0;
      return html`<button type="button" role="option" class="resultado ${sinStock ? 'sin-stock' : ''} ${i === indiceActivo ? 'activo' : ''}" data-i="${i}">
        <div class="resultado-info">
          <strong>${m.nombre} ${m.requiere_formula ? html`<span class="etiqueta-rx ${m.es_controlado ? 'control-esp' : ''}">${m.es_controlado ? 'CE' : 'Rx'}</span>` : ''}</strong>
          <span>${m.principio_activo} · ${m.presentacion || m.forma_farmaceutica} · <span class="mono">${m.codigo}</span></span>
        </div>
        <div class="resultado-precio">
          <strong>${moneda(m.precio_venta)}</strong>
          <span class="${sinStock ? 'peligro-txt' : Number(m.stock_disponible) <= 5 ? 'alerta-txt' : ''}">${sinStock ? 'Agotado' : `${numero(m.stock_disponible)} disponibles`}</span>
        </div>
      </button>`;
    })}`;
  }
  listaResultados.hidden = false;
  buscador.setAttribute('aria-expanded', 'true');
}

const buscar = debounce(async () => {
  const q = buscador.value.trim();
  if (q.length < 2) return cerrarResultados();
  try {
    resultados = await api.get('/api/medicamentos/buscar', { q });
    indiceActivo = resultados.findIndex((m) => Number(m.stock_disponible) > 0);
    // Coincidencia exacta de código de barras: se agrega directamente
    if (resultados.length && resultados[0].codigo === q.toUpperCase() && Number(resultados[0].stock_disponible) > 0) {
      agregar(resultados[0]);
      return;
    }
    pintarResultados();
  } catch (e) { toastError(e); }
}, 220);

function agregar(med, cantidad = 1) {
  if (Number(med.stock_disponible) <= 0) return toast(`"${med.nombre}" no tiene existencias disponibles`, 'alerta');
  const actual = carrito.get(med.id_medicamento);
  const nueva = (actual?.cantidad || 0) + cantidad;
  if (nueva > Number(med.stock_disponible)) {
    toast(`Solo hay ${med.stock_disponible} unidades de "${med.nombre}"`, 'alerta');
    return;
  }
  carrito.set(med.id_medicamento, { med, cantidad: nueva });
  buscador.value = '';
  cerrarResultados();
  pintarCarrito();
  buscador.focus();
}

buscador.addEventListener('input', buscar);
buscador.addEventListener('keydown', (e) => {
  if (listaResultados.hidden || !resultados.length) return;
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault();
    const paso = e.key === 'ArrowDown' ? 1 : -1;
    indiceActivo = (indiceActivo + paso + resultados.length) % resultados.length;
    pintarResultados();
    $(`.resultado[data-i="${indiceActivo}"]`, listaResultados)?.scrollIntoView({ block: 'nearest' });
  } else if (e.key === 'Enter') {
    e.preventDefault();
    if (indiceActivo >= 0) agregar(resultados[indiceActivo]);
  } else if (e.key === 'Escape') {
    cerrarResultados();
  }
});
listaResultados.addEventListener('click', (e) => {
  const opcion = e.target.closest('.resultado');
  if (opcion) agregar(resultados[Number(opcion.dataset.i)]);
});

/* ---------------------------------- Carrito ---------------------------------- */
function calcular() {
  let subtotal = 0, iva = 0, unidades = 0;
  for (const { med, cantidad } of carrito.values()) {
    const linea = Number(med.precio_venta) * cantidad;
    subtotal += linea;
    iva += Math.round(linea * Number(med.iva_porcentaje)) / 100;
    unidades += cantidad;
  }
  const descuento = Math.max(0, Number(formVenta.descuento.value) || 0);
  const total = Math.max(0, subtotal + iva - descuento);
  return { subtotal, iva, descuento, total, unidades };
}

function pintarCarrito() {
  const cuerpo = $('#carrito');
  if (!carrito.size) {
    cuerpo.innerHTML = html`<tr><td colspan="6"><div class="vacio">${icono('carrito')}<strong>El carrito está vacío</strong>Busque un producto para iniciar la venta.</div></td></tr>`;
  } else {
    cuerpo.innerHTML = html`${[...carrito.values()].map(({ med, cantidad }) => {
      const linea = Number(med.precio_venta) * cantidad;
      return html`<tr>
        <td>
          <div class="titulo-celda">${med.nombre} ${med.requiere_formula ? html`<span class="etiqueta-rx ${med.es_controlado ? 'control-esp' : ''}">${med.es_controlado ? 'CE' : 'Rx'}</span>` : ''}</div>
          <div class="sub-celda">${med.presentacion || med.forma_farmaceutica} · ${numero(med.stock_disponible)} disp.${med.proximo_vencimiento ? ` · vence ${fecha(med.proximo_vencimiento)}` : ''}</div>
        </td>
        <td class="num">${moneda(med.precio_venta)}</td>
        <td class="centro">
          <div class="carrito-cantidad">
            <button type="button" data-accion="menos" data-id="${med.id_medicamento}" aria-label="Disminuir">${icono('menos', 'icono-sm')}</button>
            <input type="number" min="1" max="${med.stock_disponible}" value="${cantidad}" data-id="${med.id_medicamento}" aria-label="Cantidad">
            <button type="button" data-accion="mas" data-id="${med.id_medicamento}" aria-label="Aumentar">${icono('mas', 'icono-sm')}</button>
          </div>
        </td>
        <td class="num">${Number(med.iva_porcentaje) ? `${Number(med.iva_porcentaje)} %` : '—'}</td>
        <td class="num fuerte">${moneda(linea)}</td>
        <td class="acciones-celda"><button class="btn-icono peligro" type="button" data-accion="quitar" data-id="${med.id_medicamento}" title="Quitar">${icono('x')}</button></td>
      </tr>`;
    })}`;
  }
  const requiereFormula = [...carrito.values()].some(({ med }) => med.requiere_formula);
  $('#panel-formula').hidden = !requiereFormula;
  $('#btn-vaciar').hidden = !carrito.size;
  actualizarTotales();
}

function actualizarTotales() {
  const t = calcular();
  $('#r-subtotal').textContent = moneda(t.subtotal);
  $('#r-iva').textContent = moneda(t.iva);
  $('#r-descuento').textContent = t.descuento ? `- ${moneda(t.descuento)}` : moneda(0);
  if (ayudaDescuento && descuentoMaximoPct !== null) {
    const tope = Math.round((t.subtotal + t.iva) * descuentoMaximoPct) / 100;
    // Se muestra redondeado hacia abajo para que el valor indicado siempre sea aceptado por el servidor
    ayudaDescuento.textContent = `Máximo ${numero(descuentoMaximoPct)} % (${moneda(Math.floor(tope))})`;
    ayudaDescuento.classList.toggle('peligro-txt', t.descuento > tope);
  }
  $('#r-total').textContent = moneda(t.total);
  $('#resumen-items').textContent = carrito.size ? `${carrito.size} producto(s) · ${t.unidades} unidad(es)` : 'Sin productos';

  const efectivo = formVenta.metodo_pago.value === 'EFECTIVO';
  $('#campo-recibido').hidden = !efectivo;
  $('#fila-cambio').hidden = !efectivo;
  const recibido = Number(formVenta.monto_recibido.value) || 0;
  const cambio = recibido - t.total;
  const celdaCambio = $('#r-cambio');
  celdaCambio.textContent = recibido ? moneda(cambio) : '—';
  celdaCambio.className = `num ${recibido && cambio < 0 ? 'peligro-txt' : 'exito-txt'}`;
  $('#btn-cobrar').disabled = !carrito.size;
}

function cambiarCantidad(id, cantidad) {
  const item = carrito.get(id);
  if (!item) return;
  if (cantidad <= 0) { carrito.delete(id); return pintarCarrito(); }
  if (cantidad > Number(item.med.stock_disponible)) {
    toast(`Solo hay ${item.med.stock_disponible} unidades disponibles`, 'alerta');
    cantidad = Number(item.med.stock_disponible);
  }
  item.cantidad = cantidad;
  pintarCarrito();
}

$('#carrito').addEventListener('click', (e) => {
  const boton = e.target.closest('button[data-accion]');
  if (!boton) return;
  const id = Number(boton.dataset.id);
  const item = carrito.get(id);
  if (boton.dataset.accion === 'mas') cambiarCantidad(id, item.cantidad + 1);
  if (boton.dataset.accion === 'menos') cambiarCantidad(id, item.cantidad - 1);
  if (boton.dataset.accion === 'quitar') { carrito.delete(id); pintarCarrito(); }
});
$('#carrito').addEventListener('change', (e) => {
  if (e.target.matches('input[data-id]')) cambiarCantidad(Number(e.target.dataset.id), Math.floor(Number(e.target.value)) || 0);
});

/* ---------------------------------- Cliente ---------------------------------- */
function pintarCliente() {
  const iniciales = cliente.nombre.split(' ').slice(0, 2).map((p) => p[0]).join('').toUpperCase();
  $('#cliente-seleccionado').innerHTML = html`
    <div class="avatar">${iniciales}</div>
    <div class="crecer" style="min-width:0">
      <strong style="display:block;font-size:13.5px">${cliente.nombre}</strong>
      <span class="tenue" style="font-size:12px">${cliente.tipo_documento} ${cliente.numero_documento}</span>
    </div>
    ${cliente.id_cliente !== CONSUMIDOR_FINAL.id_cliente
      ? html`<button type="button" class="btn-icono" id="quitar-cliente" title="Usar consumidor final">${icono('x')}</button>` : ''}`;
  $('#quitar-cliente')?.addEventListener('click', () => { cliente = CONSUMIDOR_FINAL; pintarCliente(); });
}

const buscadorCliente = $('#buscar-cliente');
const resultadosCliente = $('#resultados-cliente');
let clientesEncontrados = [];
buscadorCliente.addEventListener('input', debounce(async () => {
  const q = buscadorCliente.value.trim();
  if (q.length < 2) { resultadosCliente.hidden = true; return; }
  try {
    clientesEncontrados = await api.get('/api/clientes/buscar', { q });
    resultadosCliente.innerHTML = clientesEncontrados.length
      ? html`${clientesEncontrados.map((c, i) => html`<button type="button" class="resultado" data-i="${i}">
          <div class="resultado-info"><strong>${c.nombre}</strong><span>${c.tipo_documento} ${c.numero_documento}${c.telefono ? ` · ${c.telefono}` : ''}</span></div>
        </button>`)}`
      : html`<div class="vacio" style="padding:16px">Sin coincidencias. Use “Nuevo” para registrarlo.</div>`;
    resultadosCliente.hidden = false;
  } catch (e) { toastError(e); }
}, 250));
resultadosCliente.addEventListener('click', (e) => {
  const opcion = e.target.closest('.resultado');
  if (!opcion) return;
  cliente = clientesEncontrados[Number(opcion.dataset.i)];
  buscadorCliente.value = '';
  resultadosCliente.hidden = true;
  pintarCliente();
});

const formCliente = $('#form-cliente');
$('#btn-nuevo-cliente').addEventListener('click', () => {
  formCliente.reset();
  abrirModal('modal-cliente');
});
formCliente.addEventListener('submit', async (e) => {
  e.preventDefault();
  const r = await conCarga($('#btn-guardar-cliente'), () => api.post('/api/clientes', leerFormulario(formCliente)), formCliente);
  if (r) {
    cliente = { id_cliente: r.id_cliente, nombre: r.nombre, tipo_documento: r.tipo_documento, numero_documento: r.numero_documento };
    pintarCliente();
    cerrarModal('modal-cliente');
    toast('Cliente registrado y seleccionado');
  }
});

document.addEventListener('click', (e) => {
  if (!e.target.closest('.pos-buscador')) { cerrarResultados(); resultadosCliente.hidden = true; }
});

/* ---------------------------------- Cobro ---------------------------------- */
function reiniciar() {
  carrito.clear();
  cliente = CONSUMIDOR_FINAL;
  formVenta.reset();
  formFormula.reset();
  pintarCliente();
  pintarCarrito();
  buscador.focus();
}

formVenta.addEventListener('input', actualizarTotales);
formVenta.addEventListener('change', actualizarTotales);

formVenta.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!carrito.size) return;
  const t = calcular();
  const venta = {
    ...leerFormulario(formVenta),
    ...leerFormulario(formFormula),
    id_cliente: cliente.id_cliente,
    items: [...carrito.values()].map(({ med, cantidad }) => ({ id_medicamento: med.id_medicamento, cantidad })),
  };
  if (!$('#panel-formula').hidden && !venta.formula_medica) {
    mostrarErrores(formFormula, { formula_medica: 'Ingrese el número de la fórmula médica' });
    return toast('Hay productos que requieren fórmula médica', 'alerta');
  }
  if (venta.metodo_pago === 'EFECTIVO') {
    if (!venta.monto_recibido) venta.monto_recibido = String(t.total);
    if (Number(venta.monto_recibido) < t.total) {
      mostrarErrores(formVenta, { monto_recibido: 'Es menor que el total' });
      return;
    }
  } else {
    delete venta.monto_recibido;
  }

  const r = await conCarga($('#btn-cobrar'), () => api.post('/api/ventas', venta), formVenta);
  if (!r) return;
  $('#exito-numero').textContent = `Factura ${r.numero_factura}`;
  $('#exito-total').textContent = moneda(r.total);
  $('#exito-cambio').textContent = venta.metodo_pago === 'EFECTIVO' ? `Cambio: ${moneda(r.cambio)}` : '';
  $('#exito-imprimir').href = `/ventas/${r.id_venta}/comprobante`;
  reiniciar();
  abrirModal('modal-exito');
});

$('#modal-exito').addEventListener('close', () => buscador.focus());
$('#btn-vaciar').addEventListener('click', () => { carrito.clear(); pintarCarrito(); });
$('#btn-cancelar').addEventListener('click', async () => {
  if (carrito.size && !(await confirmar({ titulo: 'Cancelar venta', mensaje: 'Se descartarán los productos agregados.', textoBoton: 'Descartar', peligro: true }))) return;
  reiniciar();
});

document.addEventListener('keydown', (e) => {
  if ($$('dialog[open]').length) return;
  if (e.key === 'F2') { e.preventDefault(); buscador.focus(); buscador.select(); }
  if (e.key === 'F9') { e.preventDefault(); formVenta.requestSubmit(); }
});

pintarCliente();
pintarCarrito();
