/**
 * Comportamiento común del diseño: menú lateral, tema, fecha, cierre de sesión
 * y contador de alertas de vencimiento en el menú.
 */
import { $, api, confirmar, puede, toastError } from './core.js';

// Fecha actual en la barra superior
const fecha = $('#topbar-fecha');
if (fecha) {
  const texto = new Date().toLocaleDateString('es-CO', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  fecha.textContent = texto.charAt(0).toUpperCase() + texto.slice(1);
}

// Menú lateral en pantallas pequeñas
const sidebar = $('#sidebar');
$('#btn-menu')?.addEventListener('click', () => {
  sidebar.classList.add('abierto');
  const velo = document.createElement('div');
  velo.className = 'velo';
  velo.addEventListener('click', () => { sidebar.classList.remove('abierto'); velo.remove(); });
  document.body.appendChild(velo);
});

// Tema claro / oscuro
const botonTema = $('#btn-tema');
function pintarIconoTema() {
  const oscuro = document.documentElement.dataset.tema === 'oscuro';
  botonTema?.querySelector('use')?.setAttribute('href', oscuro ? '#i-sol' : '#i-luna');
}
botonTema?.addEventListener('click', () => {
  const nuevo = document.documentElement.dataset.tema === 'oscuro' ? 'claro' : 'oscuro';
  document.documentElement.dataset.tema = nuevo;
  try { localStorage.setItem('tema', nuevo); } catch { /* sin almacenamiento */ }
  pintarIconoTema();
});
pintarIconoTema();

// Cerrar sesión
$('#btn-salir')?.addEventListener('click', async () => {
  const ok = await confirmar({ titulo: 'Cerrar sesión', mensaje: '¿Desea salir del sistema?', textoBoton: 'Salir' });
  if (!ok) return;
  try {
    await api.post('/api/auth/logout');
  } catch (e) {
    toastError(e);
  }
  window.location.href = '/login';
});

// Contador de lotes vencidos o críticos en el menú
const contador = $('#contador-vencimientos');
if (contador && puede('inventario.ver')) {
  api.get('/api/inventario/vencimientos/resumen').then((resumen) => {
    const total = resumen.filter((r) => r.estado === 'VENCIDO' || r.estado === 'CRITICO').reduce((s, r) => s + Number(r.lotes), 0);
    if (total > 0) {
      contador.textContent = total;
      contador.title = `${total} lote(s) vencidos o por vencer en 30 días`;
      contador.hidden = false;
    }
  }).catch(() => {});
}
