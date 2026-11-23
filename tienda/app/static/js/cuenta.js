/**
 * Mi cuenta: inicio de sesión con correo y contraseña, y cierre de sesión.
 * El servidor verifica la contraseña (Argon2id) y guarda la sesión en una cookie firmada; aquí solo se envía
 * el formulario con enviar() (que pone la cabecera X-Requested-With que exige la API).
 */
import { enviar } from './api.js';
import { $, avisar } from './comun.js';
import { iniciarEncabezado } from './encabezado.js';

const formulario = $('#form-sesion');

function mostrarError(caja, mensaje) {
  caja.textContent = mensaje;
  caja.hidden = false;
  caja.focus();
}

if (formulario) {
  const error = $('#error-sesion');
  const boton = $('button[type="submit"]', formulario);

  formulario.addEventListener('submit', async (evento) => {
    evento.preventDefault();
    error.hidden = true;
    const datos = { email: formulario.email.value.trim(), contrasena: formulario.contrasena.value };
    if (!datos.email || !datos.contrasena) {
      mostrarError(error, 'Escribe tu correo y tu contraseña.');
      return;
    }
    boton.disabled = true;
    try {
      const respuesta = await enviar('/api/sesion', datos);
      window.location.assign(respuesta.url);
    } catch (fallo) {
      formulario.contrasena.value = '';
      mostrarError(error, fallo.message);
      boton.disabled = false;
    }
  });
}

$('#boton-salir')?.addEventListener('click', async (evento) => {
  const boton = evento.currentTarget; // después del await, evento.currentTarget ya es null
  boton.disabled = true;
  try {
    const respuesta = await enviar('/api/sesion/salir', {});
    window.location.assign(respuesta.url);
  } catch (fallo) {
    avisar(fallo.message);
    boton.disabled = false;
  }
});

iniciarEncabezado();
