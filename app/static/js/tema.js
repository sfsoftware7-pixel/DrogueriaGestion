// Aplica el tema guardado antes de pintar la página (evita el parpadeo claro/oscuro).
(function () {
  var tema = null;
  try { tema = localStorage.getItem('tema'); } catch (e) { /* almacenamiento no disponible */ }
  if (!tema && window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    tema = 'oscuro';
  }
  document.documentElement.setAttribute('data-tema', tema === 'oscuro' ? 'oscuro' : 'claro');
})();
