/**
 * Cliente mínimo de la API: fetch con tiempo máximo y mensajes de error comprensibles.
 */
export class ErrorApi extends Error {
  constructor(mensaje, estado) {
    super(mensaje);
    this.name = 'ErrorApi';
    this.estado = estado;
  }
}

export async function obtenerJSON(url, { signal, tiempoMaximo = 8000 } = {}) {
  const controlador = new AbortController();
  let agotado = false;
  const temporizador = setTimeout(() => { agotado = true; controlador.abort(); }, tiempoMaximo);
  const cancelarExterno = () => controlador.abort();
  signal?.addEventListener('abort', cancelarExterno, { once: true });

  try {
    let respuesta;
    try {
      respuesta = await fetch(url, { headers: { Accept: 'application/json' }, signal: controlador.signal });
    } catch {
      if (signal?.aborted) throw new DOMException('Petición cancelada', 'AbortError');
      if (agotado) throw new ErrorApi('El servidor tardó demasiado en responder.', 0);
      throw new ErrorApi('No hay conexión con el servidor.', 0);
    }
    const cuerpo = await respuesta.json().catch(() => null);
    if (!respuesta.ok) {
      throw new ErrorApi(cuerpo?.error || `El servidor respondió con el código ${respuesta.status}.`, respuesta.status);
    }
    return cuerpo;
  } finally {
    clearTimeout(temporizador);
    signal?.removeEventListener('abort', cancelarExterno);
  }
}

/**
 * POST a la API de la tienda. cuerpo: FormData (con archivos) u objeto (se envía como JSON).
 * La cabecera X-Requested-With la exige el servidor: un formulario de otro sitio no puede enviarla.
 * Si la respuesta es un error, ErrorApi lleva también los errores por campo (error.errores).
 */
export async function enviar(url, cuerpo, { tiempoMaximo = 20000 } = {}) {
  const controlador = new AbortController();
  const temporizador = setTimeout(() => controlador.abort(), tiempoMaximo);
  const esFormulario = cuerpo instanceof FormData;
  try {
    let respuesta;
    try {
      respuesta = await fetch(url, {
        method: 'POST',
        headers: { Accept: 'application/json', 'X-Requested-With': 'tienda', ...(esFormulario ? {} : { 'Content-Type': 'application/json' }) },
        body: esFormulario ? cuerpo : JSON.stringify(cuerpo),
        signal: controlador.signal,
        credentials: 'same-origin',
      });
    } catch {
      throw new ErrorApi(controlador.signal.aborted ? 'El servidor tardó demasiado en responder.' : 'No hay conexión con el servidor.', 0);
    }
    const datos = await respuesta.json().catch(() => null);
    if (!respuesta.ok) {
      const error = new ErrorApi(datos?.error || `El servidor respondió con el código ${respuesta.status}.`, respuesta.status);
      error.errores = datos?.errores || {};
      throw error;
    }
    return datos;
  } finally {
    clearTimeout(temporizador);
  }
}
