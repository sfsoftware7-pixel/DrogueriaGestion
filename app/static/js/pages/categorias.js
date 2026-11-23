import {
  $, abrirModal, api, cerrarModal, conCarga, confirmar, filaVacia, filasCargando, html, icono, insigniaActivo,
  leerFormulario, llenarFormulario, numero, puede, toast, toastError,
} from '../core.js';

const form = $('#form-categoria');
let categorias = [];
let editando = null;

function pintar() {
  const q = $('#f-buscar').value.trim().toLowerCase();
  const filas = categorias.filter((c) => !q || `${c.nombre} ${c.descripcion || ''}`.toLowerCase().includes(q));
  const editar = puede('categorias.editar');
  $('#tabla-cuerpo').innerHTML = filas.length ? html`${filas.map((c) => html`
    <tr class="${c.activo ? '' : 'inactivo'}">
      <td class="titulo-celda">${c.nombre}</td>
      <td class="texto-2">${c.descripcion || '—'}</td>
      <td class="num">${numero(c.total_medicamentos)}</td>
      <td class="num">${numero(c.unidades_disponibles)}</td>
      <td>${insigniaActivo(c.activo)}</td>
      <td class="acciones-celda"><div class="acciones">
        <a class="btn-icono" href="/medicamentos?categoria=${c.id_categoria}" title="Ver medicamentos">${icono('pildora')}</a>
        ${editar ? html`
          <button class="btn-icono" data-accion="editar" data-id="${c.id_categoria}" title="Editar">${icono('editar')}</button>
          <button class="btn-icono ${c.activo ? 'peligro' : 'exito'}" data-accion="estado" data-id="${c.id_categoria}"
            title="${c.activo ? 'Desactivar' : 'Activar'}">${icono('encender')}</button>
          ${Number(c.total_medicamentos) === 0 ? html`<button class="btn-icono peligro" data-accion="eliminar" data-id="${c.id_categoria}" title="Eliminar">${icono('papelera')}</button>` : ''}` : ''}
      </div></td>
    </tr>`)}` : filaVacia(6);
}

async function cargar() {
  $('#tabla-cuerpo').innerHTML = html`${filasCargando(6)}`;
  try {
    categorias = await api.get('/api/categorias');
    pintar();
  } catch (e) {
    $('#tabla-cuerpo').innerHTML = filaVacia(6, 'No fue posible cargar', e.message);
  }
}

function abrir(cat = null) {
  editando = cat?.id_categoria ?? null;
  form.reset();
  $('#titulo-categoria').textContent = cat ? 'Editar categoría' : 'Nueva categoría';
  if (cat) llenarFormulario(form, cat);
  abrirModal('modal-categoria');
}

$('#tabla-cuerpo').addEventListener('click', async (e) => {
  const boton = e.target.closest('button[data-accion]');
  if (!boton) return;
  const cat = categorias.find((c) => c.id_categoria === Number(boton.dataset.id));
  try {
    if (boton.dataset.accion === 'editar') return abrir(cat);
    if (boton.dataset.accion === 'estado') {
      const r = await api.patch(`/api/categorias/${cat.id_categoria}/estado`, { activo: !cat.activo });
      toast(r.mensaje);
    }
    if (boton.dataset.accion === 'eliminar') {
      const ok = await confirmar({ titulo: 'Eliminar categoría', mensaje: `Se eliminará "${cat.nombre}" de forma permanente.`, textoBoton: 'Eliminar', peligro: true });
      if (!ok) return;
      const r = await api.del(`/api/categorias/${cat.id_categoria}`);
      toast(r.mensaje);
    }
    cargar();
  } catch (err) { toastError(err); }
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const datos = leerFormulario(form);
  const r = await conCarga($('#btn-guardar'), () => (editando ? api.put(`/api/categorias/${editando}`, datos) : api.post('/api/categorias', datos)), form);
  if (r) { toast(r.mensaje); cerrarModal('modal-categoria'); cargar(); }
});

$('#btn-nuevo')?.addEventListener('click', () => abrir());
$('#f-buscar').addEventListener('input', pintar);
cargar().catch(toastError);
