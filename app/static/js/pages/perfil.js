import { $, api, conCarga, leerFormulario, toast } from '../core.js';

const form = $('#form-password');

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const r = await conCarga($('#btn-cambiar'), () => api.post('/api/auth/cambiar-password', leerFormulario(form)), form);
  if (r) {
    toast(r.mensaje);
    form.reset();
  }
});
