/* Se carga en <head> antes de pintar (la CSP no permite scripts en línea).
   m-enter: las palabras del hero esperan a motion.js para entrar una sola vez; m-enter-done las muestra igual a los 700 ms.
   mo-js / mo-safe: lo mismo para el momento de la página (assets de la skill de diseño). */
document.documentElement.classList.add('m-enter', 'mo-js');
setTimeout(() => document.documentElement.classList.add('m-enter-done'), 700);
setTimeout(() => document.documentElement.classList.add('mo-safe'), 2500);
