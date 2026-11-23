/**
 * Modelo de datos en vivo: diagrama entidad-relación en SVG propio (sin librerías, como graficos.js),
 * diccionario de datos por tabla y objetos programados. Todo sale de /api/modelo (information_schema).
 */
import { $, api, escapar, exportarCSV, html, numero, toastError } from '../core.js';

const AREA_CLASE = { Seguridad: 'seguridad', 'Catálogo': 'catalogo', Inventario: 'inventario', Ventas: 'ventas', Otras: 'otras' };
const M = { ancho: 232, sepX: 96, cabecera: 30, fila: 20, sepY: 26, margen: 20, tituloArea: 30 };
let modelo = null;

/* ------------------------------------------------------------------ disposición del diagrama */
function filasDiagrama(tabla) {
  const foraneas = new Set(tabla.llaves_foraneas.map((f) => f.columna));
  const filas = tabla.columnas
    .filter((c) => c.clave === 'PRI' || foraneas.has(c.nombre))
    .map((c) => ({ nombre: c.nombre, tipo: c.tipo, pk: c.clave === 'PRI', fk: foraneas.has(c.nombre) }));
  return { filas, resto: tabla.columnas.length - filas.length };
}

/** Una columna por área y las tablas apiladas: ninguna caja se superpone con otra. */
function disponer(tablas, areas) {
  const columnas = areas.filter((a) => tablas.some((t) => t.area === a));
  const pos = new Map();
  let altoMaximo = 0;
  columnas.forEach((area, i) => {
    const x = M.margen + i * (M.ancho + M.sepX);
    let y = M.margen + M.tituloArea;
    tablas.filter((t) => t.area === area).forEach((t) => {
      const { filas, resto } = filasDiagrama(t);
      const alto = M.cabecera + filas.length * M.fila + (resto ? M.fila : 0) + 8;
      const yFila = {};
      filas.forEach((f, j) => { yFila[f.nombre] = y + M.cabecera + j * M.fila + M.fila / 2 + 2; });
      pos.set(t.nombre, { x, y, alto, filas, resto, yFila, tabla: t });
      y += alto + M.sepY;
    });
    altoMaximo = Math.max(altoMaximo, y);
  });
  return {
    columnas, pos,
    ancho: M.margen * 2 + columnas.length * M.ancho + Math.max(0, columnas.length - 1) * M.sepX,
    alto: altoMaximo + M.margen,
  };
}

/** Curva de la columna FK (lado N) a la columna referida (lado 1). */
function ruta(rel, pos) {
  const hijo = pos.get(rel.tabla);
  const padre = pos.get(rel.tabla_referida);
  if (!hijo || !padre) return null;
  const y1 = hijo.yFila[rel.columna] ?? hijo.y + M.cabecera / 2;
  const y2 = padre.yFila[rel.columna_referida] ?? padre.y + M.cabecera / 2;
  let x1; let x2; let c1; let c2;
  if (hijo.x > padre.x) {
    x1 = hijo.x; x2 = padre.x + M.ancho;
    const d = Math.max(40, (x1 - x2) / 2); c1 = x1 - d; c2 = x2 + d;
  } else if (hijo.x < padre.x) {
    x1 = hijo.x + M.ancho; x2 = padre.x;
    const d = Math.max(40, (x2 - x1) / 2); c1 = x1 + d; c2 = x2 - d;
  } else {
    // Misma área: la curva sale por la derecha y vuelve, más abierta cuanto más lejos están las tablas
    x1 = hijo.x + M.ancho; x2 = padre.x + M.ancho;
    const d = Math.min(M.sepX - 14, 26 + Math.abs(y1 - y2) * 0.22); c1 = x1 + d; c2 = x2 + d;
  }
  return { d: `M ${x1} ${y1} C ${c1} ${y1}, ${c2} ${y2}, ${x2} ${y2}`, x1, y1, x2, y2, lado1: Math.sign(c1 - x1), lado2: Math.sign(c2 - x2) };
}

const recortar = (texto, max) => (texto.length > max ? `${texto.slice(0, max - 1)}…` : texto);

function dibujar() {
  const { tablas, areas, relaciones } = modelo;
  const d = disponer(tablas, areas);
  let svg = `<svg class="er-svg" viewBox="0 0 ${d.ancho} ${d.alto}" width="${d.ancho}" height="${d.alto}" role="group" aria-label="Diagrama entidad-relación">`;

  d.columnas.forEach((area, i) => {
    const x = M.margen + i * (M.ancho + M.sepX);
    svg += `<text class="er-area er-${AREA_CLASE[area] || 'otras'}" x="${x}" y="${M.margen + 14}">${escapar(area.toUpperCase())}</text>`;
  });

  // Relaciones primero: quedan por debajo de las cajas
  relaciones.forEach((rel, i) => {
    const r = ruta(rel, d.pos);
    if (!r) return;
    svg += `<g class="er-relacion" data-i="${i}" data-hijo="${escapar(rel.tabla)}" data-padre="${escapar(rel.tabla_referida)}">
      <title>${escapar(`${rel.tabla}.${rel.columna} → ${rel.tabla_referida}.${rel.columna_referida} (${rel.nombre})`)}</title>
      <path d="${r.d}"/>
      <text class="er-card" x="${r.x1 + r.lado1 * 9}" y="${r.y1 - 4}" text-anchor="middle">N</text>
      <text class="er-card" x="${r.x2 + r.lado2 * 9}" y="${r.y2 - 4}" text-anchor="middle">1</text></g>`;
  });

  d.pos.forEach((p, nombre) => {
    const t = p.tabla;
    const clase = AREA_CLASE[t.area] || 'otras';
    const filas = t.filas == null ? '' : `${numero(t.filas)} filas`;
    svg += `<g class="er-tabla er-${clase}" data-tabla="${escapar(nombre)}" tabindex="0" role="button"
        aria-label="${escapar(`Tabla ${nombre}, ${filas}. Ver diccionario de datos`)}">
      <rect class="er-caja" x="${p.x}" y="${p.y}" width="${M.ancho}" height="${p.alto}" rx="8"/>
      <path class="er-cabecera" d="M ${p.x} ${p.y + M.cabecera} V ${p.y + 8} Q ${p.x} ${p.y} ${p.x + 8} ${p.y} H ${p.x + M.ancho - 8} Q ${p.x + M.ancho} ${p.y} ${p.x + M.ancho} ${p.y + 8} V ${p.y + M.cabecera} Z"/>
      <text class="er-nombre" x="${p.x + 10}" y="${p.y + 20}">${escapar(recortar(nombre, 20))}</text>
      <text class="er-filas" x="${p.x + M.ancho - 10}" y="${p.y + 20}" text-anchor="end">${escapar(filas)}</text>`;
    p.filas.forEach((f, j) => {
      const y = p.y + M.cabecera + j * M.fila + 14;
      const marca = f.pk && f.fk ? 'PK FK' : f.pk ? 'PK' : 'FK';
      svg += `<text class="er-marca-svg ${f.pk ? 'er-pk' : 'er-fk'}" x="${p.x + 10}" y="${y}">${marca}</text>
        <text class="er-columna" x="${p.x + (f.pk && f.fk ? 56 : 36)}" y="${y}">${escapar(recortar(f.nombre, 18))}</text>
        <text class="er-tipo" x="${p.x + M.ancho - 10}" y="${y}" text-anchor="end">${escapar(recortar(f.tipo, 14))}</text>`;
    });
    if (p.resto) {
      svg += `<text class="er-resto" x="${p.x + 10}" y="${p.y + M.cabecera + p.filas.length * M.fila + 14}">+ ${p.resto} columna(s) más</text>`;
    }
    svg += '</g>';
  });
  svg += '</svg>';

  const contenedor = $('#er-diagrama');
  contenedor.innerHTML = svg;
  contenedor.querySelectorAll('.er-tabla').forEach((g) => {
    g.addEventListener('click', () => seleccionar(g.dataset.tabla, true));
    g.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); seleccionar(g.dataset.tabla, true); }
    });
  });
}

/* ------------------------------------------------------------------ diccionario de datos */
function tablaHtml(columnas, filas, vacio) {
  if (!filas.length) return html`<p class="d-vacio">${vacio}</p>`;
  return html`<div class="tabla-contenedor"><table class="tabla tabla-compacta">
    <thead><tr>${columnas.map((c) => html`<th class="${c.num ? 'num' : ''}">${c.titulo}</th>`)}</tr></thead>
    <tbody>${filas.map((f) => html`<tr>${columnas.map((c) => html`<td class="${c.clase || ''}">${c.valor(f)}</td>`)}</tr>`)}</tbody>
  </table></div>`;
}

const enlaceTabla = (nombre) => html`<button type="button" class="enlace-tabla mono" data-ir-tabla="${nombre}">${nombre}</button>`;

function pintarDiccionario(t) {
  $('#d-subtitulo').textContent = `${t.area} · ${t.motor} · ${t.filas == null ? '—' : numero(t.filas)} filas (COUNT(*))${t.comentario ? ` · ${t.comentario}` : ''}`;
  const clave = (c) => ({ PRI: 'PK', MUL: 'Índice', UNI: 'Única' }[c.clave] || '');
  $('#d-contenido').innerHTML = html`<div class="tarjeta-cuerpo diccionario">
    <h3 class="d-titulo">Tabla <span class="mono">${t.nombre}</span></h3>
    <h4 class="d-subtitulo">Columnas (${t.columnas.length})</h4>
    ${tablaHtml([
      { titulo: 'Columna', valor: (c) => c.nombre, clase: 'mono fuerte' },
      { titulo: 'Tipo', valor: (c) => c.tipo, clase: 'mono' },
      { titulo: 'Nulo', valor: (c) => (c.nulo === 'YES' ? 'Sí' : 'No') },
      { titulo: 'Clave', valor: (c) => clave(c) },
      { titulo: 'Predeterminado', valor: (c) => (c.predeterminado ?? '—'), clase: 'mono' },
      { titulo: 'Extra', valor: (c) => c.extra || '—', clase: 'mono' },
      { titulo: 'Comentario', valor: (c) => c.comentario || '—' },
    ], t.columnas, 'Sin columnas')}
    <h4 class="d-subtitulo">Índices (${t.indices.length})</h4>
    ${tablaHtml([
      { titulo: 'Índice', valor: (i) => i.nombre, clase: 'mono fuerte' },
      { titulo: 'Columnas', valor: (i) => i.columnas, clase: 'mono' },
      { titulo: 'Único', valor: (i) => (i.unico ? 'Sí' : 'No') },
      { titulo: 'Tipo', valor: (i) => i.tipo },
    ], t.indices, 'Sin índices')}
    <div class="rejilla rejilla-2">
      <div><h4 class="d-subtitulo">Llaves foráneas (sale hacia)</h4>
        ${t.llaves_foraneas.length ? html`<ul class="d-lista">${t.llaves_foraneas.map((f) => html`<li>
          <span class="mono">${f.columna}</span> → ${enlaceTabla(f.tabla_referida)}<span class="mono">.${f.columna_referida}</span>
          <span class="sub-celda">ON UPDATE ${f.al_actualizar} · ON DELETE ${f.al_borrar}</span></li>`)}</ul>` : html`<p class="d-vacio">No tiene llaves foráneas.</p>`}</div>
      <div><h4 class="d-subtitulo">Referida por (relaciones 1:N)</h4>
        ${t.referida_por.length ? html`<ul class="d-lista">${t.referida_por.map((r) => html`<li>
          ${enlaceTabla(r.tabla)}<span class="mono">.${r.columna}</span> → <span class="mono">${t.nombre}.${r.columna_referida}</span></li>`)}</ul>`
          : html`<p class="d-vacio">Ninguna tabla la referencia.</p>`}</div>
    </div>
    <h4 class="d-subtitulo">Restricciones CHECK (${t.checks.length})</h4>
    ${t.checks.length ? html`<ul class="d-lista">${t.checks.map((c) => html`<li><span class="mono fuerte">${c.nombre}</span>
      <code class="d-codigo">${c.condicion}</code></li>`)}</ul>` : html`<p class="d-vacio">Sin restricciones CHECK.</p>`}
  </div>`;
}

function seleccionar(nombre, desplazar = false) {
  const t = modelo.tablas.find((x) => x.nombre === nombre);
  if (!t) return;
  $('#m-tabla').value = nombre;
  document.querySelectorAll('.er-tabla').forEach((g) => g.classList.toggle('seleccionada', g.dataset.tabla === nombre));
  document.querySelectorAll('.er-relacion').forEach((g) => {
    const toca = g.dataset.hijo === nombre || g.dataset.padre === nombre;
    g.classList.toggle('activa', toca);
    g.classList.toggle('atenuada', !toca);
  });
  pintarDiccionario(t);
  if (desplazar && window.matchMedia('(max-width: 960px)').matches) $('#diccionario').scrollIntoView({ behavior: 'smooth' });
}

/* ------------------------------------------------------------------ objetos programados */
function bloqueObjetos(titulo, lista, detalle) {
  return html`<div class="objetos-grupo"><h4 class="d-subtitulo">${titulo} (${lista.length})</h4>
    ${lista.length ? html`<ul class="d-lista">${lista.map((o) => html`<li>
      <div><span class="mono fuerte">${o.nombre}</span> <span class="sub-celda">${detalle(o)}</span></div>
      ${o.definicion ? html`<details class="sql-detalles"><summary>Ver definición</summary><pre class="sql-codigo">${o.definicion}</pre></details>` : ''}
    </li>`)}</ul>` : html`<p class="d-vacio">Ninguno visible para el usuario de la aplicación.</p>`}</div>`;
}

function pintarObjetos(o) {
  const funciones = o.rutinas.filter((r) => r.tipo === 'FUNCTION');
  const procedimientos = o.rutinas.filter((r) => r.tipo === 'PROCEDURE');
  $('#o-subtitulo').textContent = o.fuente === 'sp_modelo_objetos'
    ? `Leídos con sp_modelo_objetos (SQL SECURITY DEFINER). Directamente en information_schema el usuario de la aplicación ve ${o.visibles_sin_procedimiento.triggers} trigger(s): verlos exige el privilegio TRIGGER.`
    : 'Solo lo que information_schema muestra al usuario de la aplicación. Aplique database/04_mejoras.sql para ver triggers y definiciones.';
  $('#o-contenido').innerHTML = html`<div class="rejilla rejilla-2">
    ${bloqueObjetos('Vistas', o.vistas, () => 'VIEW')}
    ${bloqueObjetos('Triggers', o.triggers, (t) => `${t.momento} ${t.evento} ON ${t.tabla}`)}
    ${bloqueObjetos('Funciones', funciones, (f) => `retorna ${f.retorna || '—'} · ${f.seguridad}`)}
    ${bloqueObjetos('Procedimientos', procedimientos, (p) => `${p.seguridad}${p.comentario ? ` · ${p.comentario}` : ''}`)}
  </div>`;
}

/* ------------------------------------------------------------------ carga y exportación */
function pintarResumen() {
  const { tablas, relaciones } = modelo;
  $('#m-subtitulo').innerHTML = html`Base de datos <span class="mono">${modelo.base_datos}</span>, leída en vivo de <span class="mono">information_schema</span>. Haga clic en una tabla para ver su diccionario de datos.`;
  $('#k-tablas').textContent = numero(tablas.length);
  $('#k-tablas-d').textContent = `${modelo.objetos.vistas.length} vista(s) además de las tablas`;
  $('#k-fk').textContent = numero(relaciones.length);
  const indices = tablas.reduce((s, t) => s + t.indices.length, 0);
  $('#k-indices').textContent = numero(indices);
  $('#k-indices-d').textContent = `${tablas.reduce((s, t) => s + t.checks.length, 0)} restricciones CHECK`;
  $('#k-filas').textContent = numero(tablas.reduce((s, t) => s + Number(t.filas || 0), 0));

  const grupos = modelo.areas.filter((a) => tablas.some((t) => t.area === a));
  $('#m-tabla').innerHTML = html`<option value="">Elija una tabla…</option>${grupos.map((a) => html`<optgroup label="${a}">
    ${tablas.filter((t) => t.area === a).map((t) => html`<option value="${t.nombre}">${t.nombre}</option>`)}</optgroup>`)}`;
}

async function cargar() {
  try {
    modelo = await api.get('/api/modelo');
    pintarResumen();
    dibujar();
    pintarObjetos(modelo.objetos);
  } catch (e) {
    $('#er-diagrama').innerHTML = html`<div class="vacio"><strong>No se pudo leer el modelo</strong>${e.message}</div>`;
    toastError(e);
  }
}

$('#m-tabla').addEventListener('change', (e) => e.target.value && seleccionar(e.target.value));
$('#d-contenido').addEventListener('click', (e) => {
  const boton = e.target.closest('[data-ir-tabla]');
  if (boton) seleccionar(boton.dataset.irTabla);
});
$('#m-csv').addEventListener('click', () => {
  if (!modelo) return;
  const filas = modelo.tablas.flatMap((t) => t.columnas.map((c) => ({ ...c, tabla: t.nombre, area: t.area, filas_tabla: t.filas })));
  exportarCSV('diccionario_datos', [
    { titulo: 'Área', valor: 'area' }, { titulo: 'Tabla', valor: 'tabla' }, { titulo: 'Filas de la tabla', valor: 'filas_tabla' },
    { titulo: 'Columna', valor: 'nombre' }, { titulo: 'Tipo', valor: 'tipo' }, { titulo: 'Nulo', valor: 'nulo' },
    { titulo: 'Clave', valor: 'clave' }, { titulo: 'Predeterminado', valor: 'predeterminado' }, { titulo: 'Extra', valor: 'extra' },
    { titulo: 'Comentario', valor: 'comentario' },
  ], filas);
});

cargar();
