import {
  $, abrirModal, api, cerrarModal, conCarga, confirmar, debounce, fechaHora, filaVacia, filasCargando, html, icono,
  insigniaActivo, leerFormulario, llenarFormulario, llenarSelect, toast, toastError,
} from '../core.js';

const ICONOS_ROL = { ADMINISTRADOR: ['escudo', 'marca'], REGENTE: ['pildora', 'info'], VENDEDOR: ['carrito', 'alerta'], BODEGA: ['caja', 'exito'] };
const form = $('#form-usuario');
let usuarios = [];
let editando = null;

async function cargarRoles() {
  const roles = await api.get('/api/roles');
  llenarSelect($('#u-rol'), roles.map((r) => ({ valor: r.id_rol, texto: r.nombre })), { vacio: 'Seleccione…' });
  $('#roles').innerHTML = html`${roles.map((r) => {
    const [nombreIcono, color] = ICONOS_ROL[r.nombre] || ['usuario', 'marca'];
    return html`<article class="tarjeta kpi">
      <div class="kpi-icono ${color}">${icono(nombreIcono)}</div>
      <div><div class="kpi-etiqueta">${r.nombre}</div><div class="kpi-valor">${r.usuarios}</div>
        <div class="kpi-detalle">${r.descripcion}</div></div>
    </article>`;
  })}`;
}

async function cargar() {
  const cuerpo = $('#tabla-cuerpo');
  cuerpo.innerHTML = html`${filasCargando(7)}`;
  try {
    usuarios = await api.get('/api/usuarios', { q: $('#f-buscar').value.trim() });
    cuerpo.innerHTML = usuarios.length ? html`${usuarios.map((u) => html`<tr class="${u.activo ? '' : 'inactivo'}">
      <td class="mono fuerte">${u.usuario}</td>
      <td>${u.nombres} ${u.apellidos}<div class="sub-celda">Doc. ${u.documento}</div></td>
      <td><span class="insignia insignia-marca sin-punto">${u.rol}</span></td>
      <td>${u.email}</td>
      <td>${u.ultimo_acceso ? fechaHora(u.ultimo_acceso) : html`<span class="tenue">Nunca</span>`}</td>
      <td>${u.bloqueado ? html`<span class="insignia insignia-peligro">Bloqueado</span>` : insigniaActivo(u.activo)}</td>
      <td class="acciones-celda"><div class="acciones">
        ${u.bloqueado ? html`<button class="btn-icono exito" data-accion="desbloquear" data-id="${u.id_usuario}" title="Desbloquear">${icono('desbloquear')}</button>` : ''}
        <button class="btn-icono" data-accion="editar" data-id="${u.id_usuario}" title="Editar">${icono('editar')}</button>
        <button class="btn-icono ${u.activo ? 'peligro' : 'exito'}" data-accion="estado" data-id="${u.id_usuario}" title="${u.activo ? 'Desactivar' : 'Activar'}">${icono('encender')}</button>
        ${u.id_usuario !== Number(document.body.dataset.usuarioId || 0) ? html`<button class="btn-icono peligro" data-accion="eliminar" data-id="${u.id_usuario}" title="Eliminar usuario">${icono('papelera')}</button>` : ''}
      </div></td>
    </tr>`)}` : filaVacia(7);
  } catch (e) {
    cuerpo.innerHTML = filaVacia(7, 'No fue posible cargar', e.message);
  }
}

function abrir(u = null) {
  editando = u?.id_usuario ?? null;
  form.reset();
  $('#titulo-usuario').textContent = u ? `Editar usuario: ${u.usuario}` : 'Nuevo usuario';
  $('#password-req').hidden = Boolean(u);
  $('#password-ayuda').textContent = u
    ? 'Déjela vacía para conservar la actual. Si la escribe, se restablecerá.'
    : 'Mínimo 8 caracteres con mayúscula, minúscula, número y símbolo.';
  if (u) llenarFormulario(form, u);
  abrirModal('modal-usuario');
}

$('#tabla-cuerpo').addEventListener('click', async (e) => {
  const boton = e.target.closest('button[data-accion]');
  if (!boton) return;
  const u = usuarios.find((x) => x.id_usuario === Number(boton.dataset.id));
  try {
    if (boton.dataset.accion === 'editar') return abrir(u);
    if (boton.dataset.accion === 'eliminar') {
      if (!(await confirmar({ titulo: 'Eliminar usuario', mensaje: 'Esta acción es permanente. Usuarios con ventas o entradas deben desactivarse para conservar la trazabilidad.', textoBoton: 'Eliminar', peligro: true }))) return;
      toast((await api.del(`/api/usuarios/${u.id_usuario}`)).mensaje);
      cargar();
      cargarRoles();
      return;
    }
    if (boton.dataset.accion === 'desbloquear') toast((await api.post(`/api/usuarios/${u.id_usuario}/desbloquear`)).mensaje);
    if (boton.dataset.accion === 'estado') {
      if (u.activo && !(await confirmar({ titulo: 'Desactivar usuario', mensaje: `${u.nombres} no podrá ingresar al sistema.`, textoBoton: 'Desactivar', peligro: true }))) return;
      toast((await api.patch(`/api/usuarios/${u.id_usuario}/estado`, { activo: !u.activo })).mensaje);
    }
    cargar();
    cargarRoles();
  } catch (err) { toastError(err); }
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const datos = leerFormulario(form);
  if (editando && !datos.password) delete datos.password;
  const r = await conCarga($('#btn-guardar'), () => (editando ? api.put(`/api/usuarios/${editando}`, datos) : api.post('/api/usuarios', datos)), form);
  if (r) { toast(r.mensaje); cerrarModal('modal-usuario'); cargar(); cargarRoles(); }
});

$('#btn-nuevo').addEventListener('click', () => abrir());
$('#f-buscar').addEventListener('input', debounce(cargar));
cargarRoles().catch(toastError);
cargar();
