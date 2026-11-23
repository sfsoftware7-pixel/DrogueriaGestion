import { $, api, conCarga, leerFormulario, llenarFormulario, toast, toastError } from '../core.js';

const form = $('#form-config');

api.get('/api/configuracion').then((c) => llenarFormulario(form, c)).catch(toastError);

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const r = await conCarga($('#btn-guardar'), () => api.put('/api/configuracion', leerFormulario(form)), form);
  if (r) toast(r.mensaje);
});
