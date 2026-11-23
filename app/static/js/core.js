/**
 * DrogueriaGestión — utilidades compartidas por todas las páginas.
 * Comunicación con la API, formato de datos, notificaciones, modales,
 * formularios, paginación y exportación a CSV.
 */

export const $ = (selector, contexto = document) => contexto.querySelector(selector);
export const $$ = (selector, contexto = document) => [...contexto.querySelectorAll(selector)];

/* ------------------------------------------------------------------ */
/*  Permisos del usuario (los define el servidor en <body>)            */
/* ------------------------------------------------------------------ */
const permisos = new Set((document.body.dataset.permisos || '').split(',').filter(Boolean));
export const puede = (permiso) => permisos.has(permiso);

/* ------------------------------------------------------------------ */
/*  Cliente de la API REST                                             */
/* ------------------------------------------------------------------ */
export class ErrorApi extends Error {
  constructor(mensaje, status, errores = {}) {
    super(mensaje);
    this.status = status;
    this.errores = errores;
  }
}

const tokenCsrf = () => document.querySelector('meta[name="csrf-token"]')?.content || '';

export async function api(url, { metodo = 'GET', datos, params } = {}) {
  if (params) {
    const consulta = new URLSearchParams(
      Object.entries(params).filter(([, v]) => v !== '' && v !== null && v !== undefined)
    ).toString();
    if (consulta) url += (url.includes('?') ? '&' : '?') + consulta;
  }
  const opciones = { method: metodo, credentials: 'same-origin', headers: { Accept: 'application/json' } };
  if (datos !== undefined) {
    opciones.headers['Content-Type'] = 'application/json';
    opciones.body = JSON.stringify(datos);
  }
  if (metodo !== 'GET') opciones.headers['X-CSRF-Token'] = tokenCsrf();

  let respuesta;
  try {
    respuesta = await fetch(url, opciones);
  } catch {
    throw new ErrorApi('No hay conexión con el servidor', 0);
  }
  const cuerpo = await respuesta.json().catch(() => ({}));
  if (respuesta.status === 401 && !url.startsWith('/api/auth/login')) {
    window.location.href = '/login?siguiente=' + encodeURIComponent(window.location.pathname);
  }
  if (!respuesta.ok) throw new ErrorApi(cuerpo.error || 'Ocurrió un error inesperado', respuesta.status, cuerpo.errores);
  return cuerpo;
}
api.get = (url, params) => api(url, { params });
api.post = (url, datos = {}) => api(url, { metodo: 'POST', datos });
api.put = (url, datos = {}) => api(url, { metodo: 'PUT', datos });
api.patch = (url, datos = {}) => api(url, { metodo: 'PATCH', datos });
api.del = (url) => api(url, { metodo: 'DELETE' });

/* ------------------------------------------------------------------ */
/*  HTML seguro: toda interpolación se escapa salvo que sea `crudo()`  */
/* ------------------------------------------------------------------ */
class HtmlSeguro {
  constructor(valor) { this.valor = valor; }
  toString() { return this.valor; }
}
export const crudo = (valor) => new HtmlSeguro(String(valor ?? ''));

export function escapar(valor) {
  return String(valor ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function interpolar(valor) {
  if (valor instanceof HtmlSeguro) return valor.valor;
  if (Array.isArray(valor)) return valor.map(interpolar).join('');
  if (valor === false || valor === null || valor === undefined) return '';
  return escapar(valor);
}

/** Plantilla etiquetada: html`<td>${texto}</td>` escapa automáticamente (previene XSS). */
export function html(partes, ...valores) {
  return new HtmlSeguro(partes.reduce((acc, parte, i) => acc + parte + (i < valores.length ? interpolar(valores[i]) : ''), ''));
}

export const icono = (nombre, clase = '') =>
  crudo(`<svg class="icono ${clase}" aria-hidden="true"><use href="#i-${nombre}"/></svg>`);

/* ------------------------------------------------------------------ */
/*  Formatos (pesos colombianos y fechas)                              */
/* ------------------------------------------------------------------ */
const fmtMoneda = new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0, minimumFractionDigits: 0 });
const fmtNumero = new Intl.NumberFormat('es-CO');
export const moneda = (v) => fmtMoneda.format(Math.round(Number(v || 0)));
export const numero = (v) => fmtNumero.format(Number(v || 0));
export const monedaCorta = (v) => {
  const n = Number(v || 0);
  if (Math.abs(n) >= 1e6) return '$' + (n / 1e6).toLocaleString('es-CO', { maximumFractionDigits: 1 }) + ' M';
  if (Math.abs(n) >= 1e3) return '$' + Math.round(n / 1e3).toLocaleString('es-CO') + ' mil';
  return moneda(n);
};

const aFecha = (v) => (typeof v === 'string' && v.length === 10 ? new Date(v + 'T00:00:00') : new Date(v));
export const fecha = (v) => (v ? aFecha(v).toLocaleDateString('es-CO', { day: '2-digit', month: 'short', year: 'numeric' }) : '—');
export const fechaCorta = (v) => (v ? aFecha(v).toLocaleDateString('es-CO', { day: '2-digit', month: 'short' }) : '—');
export const fechaHora = (v) =>
  v ? aFecha(v).toLocaleString('es-CO', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—';

export function fechaISO(d = new Date()) {
  const local = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}
export const sumarDias = (d, dias) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + dias);

export const METODOS_PAGO = {
  EFECTIVO: 'Efectivo',
  TARJETA_DEBITO: 'Tarjeta débito',
  TARJETA_CREDITO: 'Tarjeta crédito',
  TRANSFERENCIA: 'Transferencia',
};

/* ------------------------------------------------------------------ */
/*  Insignias de estado                                                */
/* ------------------------------------------------------------------ */
const INSIGNIAS = {
  AGOTADO: ['peligro', 'Agotado'], BAJO: ['alerta', 'Stock bajo'], NORMAL: ['exito', 'Normal'],
  VENCIDO: ['peligro', 'Vencido'], CRITICO: ['peligro', 'Crítico'], PROXIMO: ['alerta', 'Próximo'], VIGENTE: ['exito', 'Vigente'],
  COMPLETADA: ['exito', 'Completada'], ANULADA: ['peligro', 'Anulada'],
  ACTIVO: ['exito', 'Activo'], INACTIVO: ['neutro', 'Inactivo'],
};
export function insignia(estado, texto) {
  const [tipo, etiqueta] = INSIGNIAS[estado] || ['neutro', estado];
  return html`<span class="insignia insignia-${tipo}">${texto || etiqueta}</span>`;
}
export const insigniaActivo = (activo) => insignia(activo ? 'ACTIVO' : 'INACTIVO');

/* ------------------------------------------------------------------ */
/*  Notificaciones                                                     */
/* ------------------------------------------------------------------ */
const ICONOS_TOAST = { exito: 'check-circulo', error: 'alerta', alerta: 'alerta', info: 'info' };
export function toast(mensaje, tipo = 'exito', duracion = 4200) {
  const contenedor = $('#toasts');
  if (!contenedor) return;
  const el = document.createElement('div');
  el.className = `toast ${tipo}`;
  el.setAttribute('role', tipo === 'error' ? 'alert' : 'status');
  el.innerHTML = html`${icono(ICONOS_TOAST[tipo] || 'info')}<div>${mensaje}</div>`;
  contenedor.appendChild(el);
  setTimeout(() => {
    el.classList.add('saliendo');
    el.addEventListener('animationend', () => el.remove(), { once: true });
  }, duracion);
}
export const toastError = (error) => toast(error?.message || 'Ocurrió un error', 'error', 6000);

/* ------------------------------------------------------------------ */
/*  Modales con <dialog> nativo                                        */
/* ------------------------------------------------------------------ */
document.addEventListener('click', (e) => {
  const boton = e.target.closest('[data-cerrar-modal]');
  if (boton) boton.closest('dialog')?.close();
});

export function abrirModal(modal) {
  const dialogo = typeof modal === 'string' ? document.getElementById(modal) : modal;
  const form = dialogo.querySelector('form');
  if (form) limpiarErrores(form);
  dialogo.showModal();
  dialogo.querySelector('[autofocus], input:not([type=hidden]):not([readonly]), select, textarea')?.focus();
  return dialogo;
}
export const cerrarModal = (modal) => (typeof modal === 'string' ? document.getElementById(modal) : modal).close();

/**
 * Diálogo de confirmación. Si `motivo` es true pide un texto obligatorio.
 * Devuelve false si se cancela, true (o el motivo escrito) si se confirma.
 */
export function confirmar({ titulo, mensaje, textoBoton = 'Confirmar', peligro = false, motivo = false, minimoMotivo = 10 }) {
  return new Promise((resolver) => {
    const dialogo = document.createElement('dialog');
    dialogo.className = 'modal pequeno';
    dialogo.innerHTML = html`
      <form method="dialog" novalidate>
        <div class="modal-cuerpo">
          <div class="confirmacion-icono ${peligro ? 'peligro' : ''}">${icono('alerta', 'icono-lg')}</div>
          <h2 style="font-size:17px">${titulo}</h2>
          <p class="texto-2 mt-1">${mensaje}</p>
          ${motivo ? html`<div class="campo mt-2">
              <label for="confirmar-motivo">Motivo <span class="req">*</span></label>
              <textarea id="confirmar-motivo" name="motivo" maxlength="255" placeholder="Describa el motivo (mínimo ${minimoMotivo} caracteres)"></textarea>
            </div>` : ''}
        </div>
        <footer class="modal-pie">
          <button type="button" class="btn btn-secundario" value="cancelar" data-accion="cancelar">Cancelar</button>
          <button type="submit" class="btn ${peligro ? 'btn-peligro' : 'btn-primario'}" value="ok">${textoBoton}</button>
        </footer>
      </form>`;
    document.body.appendChild(dialogo);
    const form = dialogo.querySelector('form');
    let resultado = false;
    dialogo.querySelector('[data-accion="cancelar"]').addEventListener('click', () => dialogo.close());
    form.addEventListener('submit', (e) => {
      if (motivo) {
        const texto = form.motivo.value.trim();
        if (texto.length < minimoMotivo) {
          e.preventDefault();
          mostrarErrores(form, { motivo: `Escriba al menos ${minimoMotivo} caracteres` });
          return;
        }
        resultado = texto;
      } else {
        resultado = true;
      }
    });
    dialogo.addEventListener('close', () => { dialogo.remove(); resolver(resultado); });
    dialogo.showModal();
    (motivo ? form.motivo : form.querySelector('[type=submit]')).focus();
  });
}

/* ------------------------------------------------------------------ */
/*  Formularios                                                        */
/* ------------------------------------------------------------------ */
export function leerFormulario(form) {
  const datos = {};
  for (const el of form.elements) {
    if (!el.name || el.disabled) continue;
    if (el.type === 'checkbox') datos[el.name] = el.checked;
    else if (el.type === 'radio') { if (el.checked) datos[el.name] = el.value; }
    else datos[el.name] = el.value.trim();
  }
  return datos;
}

export function llenarFormulario(form, datos = {}) {
  for (const el of form.elements) {
    if (!el.name || !(el.name in datos)) continue;
    const valor = datos[el.name];
    if (el.type === 'checkbox') el.checked = Boolean(Number(valor)) || valor === true;
    else if (el.type === 'radio') el.checked = String(valor) === el.value;
    else if (el.type === 'number' && valor !== null && valor !== '') el.value = Number(valor);
    else el.value = valor ?? '';
  }
}

export function limpiarErrores(form) {
  $$('.campo.invalido', form).forEach((c) => c.classList.remove('invalido'));
  $$('.error-campo', form).forEach((e) => e.remove());
}

export function mostrarErrores(form, errores = {}) {
  limpiarErrores(form);
  let primero = null;
  for (const [campo, mensaje] of Object.entries(errores)) {
    const el = form.querySelector(`[name="${CSS.escape(campo)}"]`);
    const contenedor = el?.closest('.campo');
    if (!contenedor) continue;
    contenedor.classList.add('invalido');
    const aviso = document.createElement('small');
    aviso.className = 'error-campo';
    aviso.textContent = mensaje;
    contenedor.appendChild(aviso);
    primero ??= el;
  }
  primero?.focus();
}

/** Ejecuta `accion` mostrando estado de carga en el botón y los errores de validación. */
export async function conCarga(boton, accion, form = null) {
  boton?.classList.add('cargando');
  if (boton) boton.disabled = true;
  try {
    return await accion();
  } catch (error) {
    if (form && error.status === 422 && error.errores) mostrarErrores(form, error.errores);
    toastError(error);
    return undefined;
  } finally {
    boton?.classList.remove('cargando');
    if (boton) boton.disabled = false;
  }
}

/* ------------------------------------------------------------------ */
/*  Tablas y paginación                                                */
/* ------------------------------------------------------------------ */
export function filaVacia(columnas, mensaje = 'No se encontraron registros', detalle = 'Ajuste los filtros o registre un nuevo elemento.') {
  return html`<tr><td colspan="${columnas}"><div class="vacio">${icono('buscar')}<strong>${mensaje}</strong>${detalle}</div></td></tr>`;
}

export function filasCargando(columnas, filas = 5) {
  const celdas = Array.from({ length: columnas }, () => html`<td><div class="esqueleto"></div></td>`);
  return Array.from({ length: filas }, () => html`<tr>${celdas}</tr>`);
}

export function paginacion(contenedor, { pagina, paginas, total, por_pagina: porPagina }, alCambiar) {
  if (!contenedor) return;
  if (!total) { contenedor.innerHTML = ''; return; }
  const desde = (pagina - 1) * porPagina + 1;
  const hasta = Math.min(total, pagina * porPagina);
  const numeros = [];
  for (let i = Math.max(1, pagina - 2); i <= Math.min(paginas, pagina + 2); i++) numeros.push(i);
  contenedor.innerHTML = html`
    <span>Mostrando <strong>${numero(desde)}–${numero(hasta)}</strong> de <strong>${numero(total)}</strong></span>
    <div class="paginacion-botones">
      <button type="button" data-pagina="${pagina - 1}" ${crudo(pagina <= 1 ? 'disabled' : '')} aria-label="Anterior">${icono('izquierda', 'icono-sm')}</button>
      ${numeros.map((n) => html`<button type="button" data-pagina="${n}" class="${n === pagina ? 'activo' : ''}">${n}</button>`)}
      <button type="button" data-pagina="${pagina + 1}" ${crudo(pagina >= paginas ? 'disabled' : '')} aria-label="Siguiente">${icono('derecha', 'icono-sm')}</button>
    </div>`;
  contenedor.onclick = (e) => {
    const boton = e.target.closest('button[data-pagina]');
    if (boton && !boton.disabled) alCambiar(Number(boton.dataset.pagina));
  };
}

export function debounce(fn, espera = 300) {
  let temporizador;
  return (...args) => {
    clearTimeout(temporizador);
    temporizador = setTimeout(() => fn(...args), espera);
  };
}

/** Activa pestañas: botones [data-pestana] muestran el panel con el mismo id. */
export function pestanas(contenedor, alCambiar) {
  const botones = $$('[data-pestana]', contenedor);
  botones.forEach((b) => b.addEventListener('click', () => {
    botones.forEach((x) => {
      x.classList.toggle('activa', x === b);
      x.setAttribute('aria-selected', x === b);
      document.getElementById(x.dataset.pestana).hidden = x !== b;
    });
    alCambiar?.(b.dataset.pestana);
  }));
}

/* ------------------------------------------------------------------ */
/*  Exportación a CSV (compatible con Excel en español)                */
/* ------------------------------------------------------------------ */
export function exportarCSV(nombreArchivo, columnas, filas) {
  const celda = (v) => {
    let texto = String(v ?? '');
    // Inyección de fórmulas: un texto que empiece por = + - @ (p. ej. un nombre "=HYPERLINK(...)")
    // se ejecutaría al abrir el archivo en Excel. Se antepone ' para que se lea como texto.
    // Los números (incluidos los negativos) no se modifican.
    if (typeof v === 'string' && /^[=+\-@\t\r]/.test(texto) && !/^-?\d+([.,]\d+)?$/.test(texto)) {
      texto = `'${texto}`;
    }
    return /[;"\r\n]/.test(texto) ? `"${texto.replace(/"/g, '""')}"` : texto;
  };
  const lineas = [columnas.map((c) => celda(c.titulo)).join(';')];
  for (const fila of filas) {
    lineas.push(columnas.map((c) => celda(typeof c.valor === 'function' ? c.valor(fila) : fila[c.valor])).join(';'));
  }
  const blob = new Blob(['﻿' + lineas.join('\r\n')], { type: 'text/csv;charset=utf-8' });
  const enlace = document.createElement('a');
  enlace.href = URL.createObjectURL(blob);
  enlace.download = `${nombreArchivo}_${fechaISO()}.csv`;
  enlace.click();
  setTimeout(() => URL.revokeObjectURL(enlace.href), 1000);
}

/** Llena un <select> con opciones { valor, texto }. */
export function llenarSelect(select, opciones, { vacio = null, seleccionado = '' } = {}) {
  select.innerHTML = html`${vacio !== null ? html`<option value="">${vacio}</option>` : ''}${opciones.map(
    (o) => html`<option value="${o.valor}" ${crudo(String(o.valor) === String(seleccionado) ? 'selected' : '')}>${o.texto}</option>`
  )}`;
}
