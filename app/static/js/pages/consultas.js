import { $, api, fechaISO, html, icono, sumarDias, toastError } from '../core.js';
import { activarVerSQL } from '../ver_sql.js';

const hoy = new Date();
$('#c-desde').value = fechaISO(sumarDias(hoy, -29));
$('#c-hasta').value = fechaISO(hoy);
const rango = () => ({ desde: $('#c-desde').value, hasta: $('#c-hasta').value });

async function cargar() {
  try {
    const consultas = await api.get('/api/consultas');
    const grupos = new Map();
    consultas.forEach((c) => {
      if (!grupos.has(c.grupo)) grupos.set(c.grupo, []);
      grupos.get(c.grupo).push(c);
    });
    $('#grupos-consultas').innerHTML = html`${[...grupos].map(([grupo, lista]) => html`
      <section class="tarjeta mb">
        <header class="tarjeta-cabecera"><div><h2>${grupo}</h2><p>${lista.length} consulta(s)</p></div></header>
        <div class="tabla-contenedor"><table class="tabla tabla-compacta">
          <thead><tr><th>Consulta</th><th>Constante en el código</th><th></th></tr></thead>
          <tbody>${lista.map((c) => html`<tr>
            <td><div class="titulo-celda">${c.titulo}</div><div class="sub-celda">${c.descripcion}</div></td>
            <td class="mono">${c.origen}</td>
            <td class="acciones-celda"><button class="btn btn-secundario btn-sm" type="button" data-ver-sql="${c.clave}">
              ${icono('documento', 'icono-sm')} Ver SQL y EXPLAIN</button></td>
          </tr>`)}</tbody>
        </table></div>
      </section>`)}`;
  } catch (e) { toastError(e); }
}

activarVerSQL(rango);
cargar();
