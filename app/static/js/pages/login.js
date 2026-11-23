import { $, api } from '../core.js';

const form = $('#form-login');
const error = $('#login-error');

$('#ver-password').addEventListener('click', () => {
  const campo = form.password;
  campo.type = campo.type === 'password' ? 'text' : 'password';
  campo.focus();
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  error.hidden = true;
  const usuario = form.usuario.value.trim();
  const password = form.password.value;
  if (!usuario || !password) {
    error.textContent = 'Ingrese el usuario y la contraseña.';
    error.hidden = false;
    return;
  }
  const boton = $('#btn-ingresar');
  boton.classList.add('cargando');
  boton.disabled = true;
  try {
    await api.post('/api/auth/login', { usuario, password });
    window.location.href = form.dataset.siguiente || '/';
  } catch (err) {
    error.textContent = err.message;
    error.hidden = false;
    form.password.value = '';
    form.password.focus();
    boton.classList.remove('cargando');
    boton.disabled = false;
  }
});
