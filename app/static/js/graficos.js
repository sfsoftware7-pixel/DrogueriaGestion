/**
 * Gráficos SVG livianos sin librerías externas: barras, líneas (área) y dona.
 * Funcionan sin conexión a internet y se adaptan al tema claro/oscuro con CSS.
 */
import { escapar } from './core.js';

const NS = 'http://www.w3.org/2000/svg';
export const PALETA = ['#0d9488', '#f59e0b', '#3b82f6', '#8b5cf6', '#ef4444', '#22c55e', '#ec4899', '#64748b'];

function techoBonito(valor) {
  if (valor <= 0) return 1;
  const potencia = 10 ** Math.floor(Math.log10(valor));
  const n = valor / potencia;
  const paso = n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10;
  return paso * potencia;
}

function crearTooltip(contenedor) {
  contenedor.style.position = 'relative';
  const tip = document.createElement('div');
  tip.className = 'grafico-tooltip';
  tip.hidden = true;
  contenedor.appendChild(tip);
  return {
    mostrar(x, y, titulo, valor) {
      tip.innerHTML = `${escapar(titulo)}<strong>${escapar(valor)}</strong>`;
      const caja = contenedor.getBoundingClientRect();
      const svg = contenedor.querySelector('svg').getBoundingClientRect();
      const escala = svg.width / Number(contenedor.querySelector('svg').getAttribute('viewBox').split(' ')[2]);
      tip.style.left = `${x * escala + (svg.left - caja.left)}px`;
      tip.style.top = `${y * escala + (svg.top - caja.top)}px`;
      tip.hidden = false;
    },
    ocultar() { tip.hidden = true; },
  };
}

/**
 * Gráfico de barras verticales.
 * datos: [{ etiqueta, valor, detalle? }]
 */
export function graficoBarras(contenedor, datos, { formato = String, alto = 260, formatoEje = formato } = {}) {
  const ancho = 640;
  const m = { arriba: 16, derecha: 8, abajo: 34, izquierda: 64 };
  const maximo = techoBonito(Math.max(0, ...datos.map((d) => Number(d.valor))));
  const areaAncho = ancho - m.izquierda - m.derecha;
  const areaAlto = alto - m.arriba - m.abajo;
  const paso = areaAncho / Math.max(1, datos.length);
  const anchoBarra = Math.min(42, paso * 0.62);
  const cadaEtiqueta = Math.ceil(datos.length / 14);

  let svg = `<svg viewBox="0 0 ${ancho} ${alto}" role="img" aria-label="Gráfico de barras">`;
  for (let i = 0; i <= 4; i++) {
    const y = m.arriba + areaAlto - (areaAlto * i) / 4;
    svg += `<line class="rejilla-linea" x1="${m.izquierda}" x2="${ancho - m.derecha}" y1="${y}" y2="${y}"/>`;
    svg += `<text class="etiqueta-eje" x="${m.izquierda - 8}" y="${y + 4}" text-anchor="end">${escapar(formatoEje((maximo * i) / 4))}</text>`;
  }
  datos.forEach((d, i) => {
    const h = (Number(d.valor) / maximo) * areaAlto;
    const x = m.izquierda + paso * i + (paso - anchoBarra) / 2;
    const y = m.arriba + areaAlto - h;
    svg += `<rect class="barra" data-i="${i}" x="${x}" y="${y}" width="${anchoBarra}" height="${Math.max(h, 0)}" rx="4"/>`;
    if (i % cadaEtiqueta === 0) {
      svg += `<text class="etiqueta-eje" x="${x + anchoBarra / 2}" y="${alto - 12}" text-anchor="middle">${escapar(d.etiqueta)}</text>`;
    }
  });
  svg += `<line class="eje" x1="${m.izquierda}" x2="${ancho - m.derecha}" y1="${m.arriba + areaAlto}" y2="${m.arriba + areaAlto}"/></svg>`;

  contenedor.innerHTML = svg;
  contenedor.classList.add('grafico');
  const tip = crearTooltip(contenedor);
  contenedor.querySelectorAll('.barra').forEach((barra) => {
    const d = datos[barra.dataset.i];
    barra.addEventListener('mouseenter', () => {
      tip.mostrar(Number(barra.getAttribute('x')) + anchoBarra / 2, Number(barra.getAttribute('y')), d.detalle || d.etiqueta, formato(d.valor));
    });
    barra.addEventListener('mouseleave', tip.ocultar);
  });
}

/**
 * Gráfico de línea con área sombreada.
 * datos: [{ etiqueta, valor, detalle? }]
 */
export function graficoLinea(contenedor, datos, { formato = String, alto = 260, formatoEje = formato } = {}) {
  const ancho = 640;
  const m = { arriba: 16, derecha: 14, abajo: 34, izquierda: 64 };
  const maximo = techoBonito(Math.max(0, ...datos.map((d) => Number(d.valor))));
  const areaAncho = ancho - m.izquierda - m.derecha;
  const areaAlto = alto - m.arriba - m.abajo;
  const x = (i) => m.izquierda + (datos.length <= 1 ? areaAncho / 2 : (areaAncho * i) / (datos.length - 1));
  const y = (v) => m.arriba + areaAlto - (Number(v) / maximo) * areaAlto;
  const cadaEtiqueta = Math.ceil(datos.length / 10);

  let svg = `<svg viewBox="0 0 ${ancho} ${alto}" role="img" aria-label="Gráfico de línea">
    <defs><linearGradient id="degradado-area" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#14b8a6" stop-opacity=".28"/><stop offset="1" stop-color="#14b8a6" stop-opacity="0"/>
    </linearGradient></defs>`;
  for (let i = 0; i <= 4; i++) {
    const yy = m.arriba + areaAlto - (areaAlto * i) / 4;
    svg += `<line class="rejilla-linea" x1="${m.izquierda}" x2="${ancho - m.derecha}" y1="${yy}" y2="${yy}"/>`;
    svg += `<text class="etiqueta-eje" x="${m.izquierda - 8}" y="${yy + 4}" text-anchor="end">${escapar(formatoEje((maximo * i) / 4))}</text>`;
  }
  if (datos.length) {
    const puntos = datos.map((d, i) => `${x(i)},${y(d.valor)}`).join(' L ');
    svg += `<path class="area" d="M ${x(0)},${m.arriba + areaAlto} L ${puntos} L ${x(datos.length - 1)},${m.arriba + areaAlto} Z"/>`;
    svg += `<path class="linea" d="M ${puntos}"/>`;
    datos.forEach((d, i) => {
      svg += `<circle class="punto-linea" data-i="${i}" cx="${x(i)}" cy="${y(d.valor)}" r="4"/>`;
      if (i % cadaEtiqueta === 0 || i === datos.length - 1) {
        svg += `<text class="etiqueta-eje" x="${x(i)}" y="${alto - 12}" text-anchor="middle">${escapar(d.etiqueta)}</text>`;
      }
    });
  }
  svg += '</svg>';
  contenedor.innerHTML = svg;
  contenedor.classList.add('grafico');
  const tip = crearTooltip(contenedor);
  contenedor.querySelectorAll('.punto-linea').forEach((p) => {
    const d = datos[p.dataset.i];
    p.addEventListener('mouseenter', () => tip.mostrar(Number(p.getAttribute('cx')), Number(p.getAttribute('cy')) - 6, d.detalle || d.etiqueta, formato(d.valor)));
    p.addEventListener('mouseleave', tip.ocultar);
  });
}

/**
 * Gráfico de Pareto: barras por valor (de mayor a menor, coloreadas por clase A/B/C) y la línea del
 * porcentaje acumulado en el eje derecho, con las líneas de los umbrales de las clases.
 * datos: [{ etiqueta, valor, acumulado (0-100), clase }]; umbrales: { A: 80, B: 95 }
 */
export function graficoPareto(contenedor, datos, { formato = String, formatoEje = formato, umbrales = { A: 80, B: 95 }, alto = 300 } = {}) {
  const ancho = 720;
  const m = { arriba: 18, derecha: 46, abajo: 30, izquierda: 64 };
  const maximo = techoBonito(Math.max(0, ...datos.map((d) => Number(d.valor))));
  const areaAncho = ancho - m.izquierda - m.derecha;
  const areaAlto = alto - m.arriba - m.abajo;
  const paso = areaAncho / Math.max(1, datos.length);
  const anchoBarra = Math.max(2, Math.min(28, paso * 0.72));
  const yValor = (v) => m.arriba + areaAlto - (Number(v) / maximo) * areaAlto;
  const yPorcentaje = (p) => m.arriba + areaAlto - (Number(p) / 100) * areaAlto;
  const xCentro = (i) => m.izquierda + paso * i + paso / 2;

  let svg = `<svg viewBox="0 0 ${ancho} ${alto}" role="img" aria-label="Gráfico de Pareto del análisis ABC">`;
  for (let i = 0; i <= 4; i++) {
    const y = m.arriba + areaAlto - (areaAlto * i) / 4;
    svg += `<line class="rejilla-linea" x1="${m.izquierda}" x2="${ancho - m.derecha}" y1="${y}" y2="${y}"/>`;
    svg += `<text class="etiqueta-eje" x="${m.izquierda - 8}" y="${y + 4}" text-anchor="end">${escapar(formatoEje((maximo * i) / 4))}</text>`;
    svg += `<text class="etiqueta-eje" x="${ancho - m.derecha + 8}" y="${y + 4}">${i * 25}%</text>`;
  }
  Object.entries(umbrales).forEach(([clase, valor]) => {
    const y = yPorcentaje(valor);
    svg += `<line class="pareto-umbral" x1="${m.izquierda}" x2="${ancho - m.derecha}" y1="${y}" y2="${y}"/>`;
    svg += `<text class="pareto-umbral-texto" x="${m.izquierda + 6}" y="${y - 5}">Límite ${clase}: ${valor}%</text>`;
  });
  datos.forEach((d, i) => {
    const y = yValor(d.valor);
    svg += `<rect class="barra pareto-${escapar(String(d.clase).toLowerCase())}" data-i="${i}" x="${xCentro(i) - anchoBarra / 2}" y="${y}"
      width="${anchoBarra}" height="${Math.max(m.arriba + areaAlto - y, 0)}" rx="2"/>`;
  });
  if (datos.length) {
    const puntos = datos.map((d, i) => `${xCentro(i)},${yPorcentaje(d.acumulado)}`).join(' L ');
    svg += `<path class="pareto-acumulado" d="M ${puntos}"/>`;
  }
  svg += `<text class="etiqueta-eje" x="${m.izquierda}" y="${alto - 8}">Mayor valor</text>`;
  svg += `<text class="etiqueta-eje" x="${ancho - m.derecha}" y="${alto - 8}" text-anchor="end">Menor valor →</text>`;
  svg += `<line class="eje" x1="${m.izquierda}" x2="${ancho - m.derecha}" y1="${m.arriba + areaAlto}" y2="${m.arriba + areaAlto}"/></svg>`;

  contenedor.innerHTML = svg;
  contenedor.classList.add('grafico');
  const tip = crearTooltip(contenedor);
  contenedor.querySelectorAll('.barra').forEach((barra) => {
    const d = datos[barra.dataset.i];
    barra.addEventListener('mouseenter', () => {
      tip.mostrar(Number(barra.getAttribute('x')) + anchoBarra / 2, Number(barra.getAttribute('y')),
        `${d.etiqueta} · clase ${d.clase} · acumulado ${d.acumulado}%`, formato(d.valor));
    });
    barra.addEventListener('mouseleave', tip.ocultar);
  });
}

/**
 * Gráfico de dona con leyenda.
 * datos: [{ etiqueta, valor }]
 */
export function graficoDona(contenedor, datos, { formato = String, centro = '', etiquetaCentro = 'Total' } = {}) {
  const total = datos.reduce((s, d) => s + Number(d.valor), 0) || 1;
  const r = 70, grosor = 22, c = 2 * Math.PI * r;
  let desplazamiento = 0;
  let arcos = '';
  datos.forEach((d, i) => {
    const largo = (Number(d.valor) / total) * c;
    arcos += `<circle cx="90" cy="90" r="${r}" fill="none" stroke="${PALETA[i % PALETA.length]}" stroke-width="${grosor}"
      stroke-dasharray="${largo} ${c - largo}" stroke-dashoffset="${-desplazamiento}" transform="rotate(-90 90 90)">
      <title>${escapar(d.etiqueta)}: ${escapar(formato(d.valor))}</title></circle>`;
    desplazamiento += largo;
  });
  const leyenda = datos.map((d, i) => `<span><i style="background:${PALETA[i % PALETA.length]}"></i>${escapar(d.etiqueta)}
      <strong>${Math.round((Number(d.valor) / total) * 100)}%</strong></span>`).join('');
  contenedor.innerHTML = `<div class="dona-contenedor">
      <svg viewBox="0 0 180 180" role="img" aria-label="Gráfico de dona">${arcos}
        <text class="dona-centro-valor" x="90" y="90" text-anchor="middle">${escapar(centro)}</text>
        <text class="dona-centro-etiqueta" x="90" y="108" text-anchor="middle">${escapar(etiquetaCentro)}</text>
      </svg>
      <div class="leyenda" style="flex-direction:column;align-items:flex-start">${leyenda}</div>
    </div>`;
}
