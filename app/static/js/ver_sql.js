/**
 * «Ver SQL»: modal con la consulta exacta de un reporte (la misma constante que ejecuta su endpoint),
 * sus parámetros y el plan de ejecución (EXPLAIN), resaltando cuándo MySQL usa un índice.
 * Botones: <button data-ver-sql="clave"> donde clave está en la lista blanca de routes/consultas.py.
 */
import { abrirModal, api, crudo, escapar, html, icono, numero, toastError } from './core.js';

const PALABRAS = /\b(SELECT|FROM|WHERE|JOIN|LEFT|ON|GROUP BY|ORDER BY|LIMIT|AS|AND|OR|WITH|OVER|PARTITION BY|SUM|COUNT|RANK|ROWS|BETWEEN|UNBOUNDED|PRECEDING|CURRENT ROW|CASE|WHEN|THEN|ELSE|END|CALL|INTERVAL|DAY|COALESCE|NULLIF|ROUND|DESC|ASC|IN|DISTINCT|IS|NOT|NULL|LEAST|GREATEST|CONCAT_WS|AVG|DATE|CURDATE|BEGIN)\b/g;

/** Resalta palabras clave sobre el texto YA escapado (no puede introducir HTML). */
function resaltarSQL(sql) {
  return crudo(escapar(sql).replace(PALABRAS, '<span class="sql-clave">$1</span>'));
}

let dialogo = null;
function obtenerDialogo() {
  if (dialogo) return dialogo;
  dialogo = document.createElement('dialog');
  dialogo.className = 'modal grande';
  dialogo.id = 'modal-ver-sql';
  dialogo.setAttribute('aria-labelledby', 'ver-sql-titulo');
  document.body.appendChild(dialogo);
  return dialogo;
}

function resumenIndices(analisis) {
  if (!analisis.length) return '';
  return html`<div class="sql-resumen">${analisis.map((a) => {
    const filas = a.filas == null ? '' : ` · ${numero(a.filas)} fila(s) estimadas`;
    if (a.recorrido_completo) {
      return html`<span class="insignia insignia-peligro">Tabla ${a.tabla}: recorrido completo (sin índice)${filas}</span>`;
    }
    if (a.usa_indice) {
      return html`<span class="insignia insignia-exito">Tabla ${a.tabla}: índice ${a.indice} (${a.acceso})${a.cobertura ? ' · solo con el índice' : ''}${filas}</span>`;
    }
    return html`<span class="insignia insignia-neutro">${a.tabla}: ${a.acceso || '—'}${filas}</span>`;
  })}</div>`;
}

function tablaExplain(filas) {
  const columnas = ['id', 'select_type', 'table', 'type', 'possible_keys', 'key', 'key_len', 'ref', 'rows', 'filtered', 'Extra'];
  return html`<div class="tabla-contenedor"><table class="tabla tabla-compacta tabla-explain">
    <thead><tr>${columnas.map((c) => html`<th>${c}</th>`)}</tr></thead>
    <tbody>${filas.map((f) => {
      const clase = f.type === 'ALL' ? 'fila-sin-indice' : f.key ? 'fila-con-indice' : '';
      return html`<tr class="${clase}">${columnas.map((c) => html`<td class="${c === 'key' ? 'fuerte' : ''}">${f[c] ?? '—'}</td>`)}</tr>`;
    })}</tbody></table></div>`;
}

function contenido(d) {
  return html`
    <header class="modal-cabecera">
      <div><h2 id="ver-sql-titulo">${d.titulo}</h2><p>${d.grupo} · ${d.descripcion}</p></div>
      <button type="button" class="btn-icono" data-cerrar-modal aria-label="Cerrar">${icono('x')}</button>
    </header>
    <div class="modal-cuerpo ver-sql">
      <p class="sql-origen">Constante <span class="mono">${d.origen}</span>: el endpoint ejecuta exactamente este texto con parámetros <span class="mono">%s</span> (sin concatenar datos del usuario).</p>
      ${d.nota ? html`<div class="sql-nota">${icono('info', 'icono-sm')}<span>${d.nota}</span></div>` : ''}
      ${resumenIndices(d.analisis)}
      <h3 class="sql-subtitulo">Consulta parametrizada</h3>
      <pre class="sql-codigo">${resaltarSQL(d.sql)}</pre>
      <h3 class="sql-subtitulo">Parámetros</h3>
      <p class="mono">${d.parametros.length ? d.parametros.map((p, i) => html`${i ? ', ' : ''}<span class="sql-parametro">${String(p)}</span>`) : 'Sin parámetros'}</p>
      ${d.parametros.length ? html`<details class="sql-detalles"><summary>Consulta con los valores (como la envía PyMySQL al servidor)</summary>
        <pre class="sql-codigo">${resaltarSQL(d.sql_con_valores)}</pre></details>` : ''}
      ${d.procedimiento ? html`<h3 class="sql-subtitulo">Definición de ${d.procedimiento.nombre}</h3>
        <pre class="sql-codigo">${d.procedimiento.definicion ? resaltarSQL(d.procedimiento.definicion) : 'No disponible: aplique database/04_mejoras.sql (sp_modelo_objetos).'}</pre>` : ''}
      ${d.explain ? html`<h3 class="sql-subtitulo">EXPLAIN</h3>${tablaExplain(d.explain)}
        <p class="sql-leyenda"><span class="fila-con-indice-muestra"></span> usa un índice ·
          <span class="fila-sin-indice-muestra"></span> recorre la tabla completa (type ALL) ·
          «Using index» = MySQL responde solo con el índice (índice de cobertura)</p>` : ''}
      ${d.plan ? html`<details class="sql-detalles"><summary>Plan de ejecución (EXPLAIN FORMAT=TREE)</summary><pre class="sql-codigo">${d.plan}</pre></details>` : ''}
    </div>
    <footer class="modal-pie"><button type="button" class="btn btn-secundario" data-cerrar-modal>Cerrar</button></footer>`;
}

export async function verSQL(clave, params = {}) {
  try {
    const datos = await api.get(`/api/consultas/${encodeURIComponent(clave)}`, params);
    const modal = obtenerDialogo();
    modal.innerHTML = contenido(datos);
    abrirModal(modal);
    modal.querySelector('[data-cerrar-modal]')?.focus();
  } catch (e) { toastError(e); }
}

/** Conecta todos los botones [data-ver-sql] de la página. obtenerParams() da el rango vigente de la página. */
export function activarVerSQL(obtenerParams = () => ({})) {
  document.addEventListener('click', (e) => {
    const boton = e.target.closest('[data-ver-sql]');
    if (!boton) return;
    e.preventDefault();
    verSQL(boton.dataset.verSql, obtenerParams());
  });
}
