import {
  $, api, debounce, exportarCSV, fechaHora, filaVacia, filasCargando, html, llenarSelect, paginacion, toastError,
} from '../core.js';

const COLORES = {
  LOGIN: 'exito', LOGOUT: 'neutro', LOGIN_FALLIDO: 'peligro', CREAR: 'info', ACTUALIZAR: 'marca', VENTA: 'exito',
  ANULAR: 'peligro', DESACTIVAR: 'alerta', ACTIVAR: 'exito', AJUSTE: 'alerta', BAJA_VENCIDOS: 'peligro', ELIMINAR: 'peligro',
};
let pagina = 1;

const filtros = () => ({
  q: $('#f-buscar').value.trim(), modulo: $('#f-modulo').value, accion: $('#f-accion').value,
  desde: $('#f-desde').value, hasta: $('#f-hasta').value,
});

async function cargar(p = pagina) {
  pagina = p;
  const cuerpo = $('#tabla-cuerpo');
  cuerpo.innerHTML = html`${filasCargando(6)}`;
  try {
    const r = await api.get('/api/auditoria', { ...filtros(), pagina: p });
    cuerpo.innerHTML = r.datos.length ? html`${r.datos.map((a) => html`<tr>
      <td class="nowrap">${fechaHora(a.fecha)}</td>
      <td>${a.usuario ? html`<span class="mono">${a.usuario}</span><div class="sub-celda">${a.nombre_usuario}</div>` : html`<span class="tenue">—</span>`}</td>
      <td><span class="insignia insignia-${COLORES[a.accion] || 'neutro'}">${a.accion}</span></td>
      <td>${a.modulo}</td>
      <td class="texto-2">${a.descripcion || '—'}</td>
      <td class="mono tenue">${a.ip || '—'}</td>
    </tr>`)}` : filaVacia(6);
    paginacion($('#paginacion'), r, cargar);
  } catch (e) {
    cuerpo.innerHTML = filaVacia(6, 'No fue posible cargar la auditoría', e.message);
  }
}

api.get('/api/auditoria/filtros').then((f) => {
  llenarSelect($('#f-modulo'), f.modulos.map((m) => ({ valor: m, texto: m })), { vacio: 'Todos los módulos' });
  llenarSelect($('#f-accion'), f.acciones.map((a) => ({ valor: a, texto: a })), { vacio: 'Todas las acciones' });
}).catch(toastError);

$('#f-buscar').addEventListener('input', debounce(() => cargar(1)));
['#f-modulo', '#f-accion', '#f-desde', '#f-hasta'].forEach((s) => $(s).addEventListener('change', () => cargar(1)));
$('#btn-exportar').addEventListener('click', async () => {
  try {
    const r = await api.get('/api/auditoria', { ...filtros(), pagina: 1, por_pagina: 100 });
    exportarCSV('auditoria', [
      { titulo: 'Fecha', valor: 'fecha' }, { titulo: 'Usuario', valor: 'usuario' }, { titulo: 'Acción', valor: 'accion' },
      { titulo: 'Módulo', valor: 'modulo' }, { titulo: 'Descripción', valor: 'descripcion' }, { titulo: 'IP', valor: 'ip' },
    ], r.datos);
  } catch (e) { toastError(e); }
});

cargar(1);
