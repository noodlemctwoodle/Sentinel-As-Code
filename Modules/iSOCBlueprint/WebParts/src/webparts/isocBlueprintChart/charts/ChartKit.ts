// Shared drawing helpers for the chart web part: escaping, reading loosely
// typed JSON, colours, text measuring and wrapping, and SVG fragments. Every
// chart builds a string of markup; anything taken from the chart data goes
// through esc() first.

export interface IChartTheme {
  text: string;
  muted: string;
  line: string;
  surface: string;
  accent: string;
  dark: boolean;
}

export const FONT: string =
  '"Segoe UI", "Segoe UI Web (West European)", -apple-system, BlinkMacSystemFont, Roboto, "Helvetica Neue", sans-serif';

// The dashboard's series colours, so a chart reads the same on both.
export const SERIES: string[] = [
  '#2563eb', '#0d9488', '#7c3aed', '#d97706', '#e11d48',
  '#0891b2', '#4f46e5', '#16a34a', '#ea580c', '#64748b'
];

// Labels that carry a meaning get the colour that meaning has elsewhere in
// the Blueprint; everything else takes the next series colour.
const NAMED: { [label: string]: string } = {
  critical: '#991b1b', high: '#ff4d1f', medium: '#ffaa00', warning: '#d97706',
  low: '#fff100', info: '#2563eb', informational: '#8a8886',
  success: '#16a34a', succeeded: '#16a34a', failure: '#dc2626', failed: '#dc2626',
  truepositive: '#dc2626', falsepositive: '#16a34a', benignpositive: '#d97706',
  undetermined: '#64748b', unclassified: '#94a3b8', unknown: '#94a3b8',
  registered: '#16a34a', notregistered: '#dc2626', notmonitored: '#dc2626',
  open: '#d97706', closed: '#16a34a'
};

export function isNil(value: unknown): boolean {
  return value === undefined || value === null;
}

export function str(value: unknown): string {
  return isNil(value) ? '' : String(value);
}

export function num(value: unknown): number {
  const n: number = typeof value === 'number' ? value : parseFloat(str(value));
  return isFinite(n) ? n : 0;
}

export function list<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]).filter((v: T): boolean => !isNil(v)) : [];
}

export function esc(value: unknown): string {
  return str(value).replace(/[&<>"']/g, (c: string): string => {
    return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' } as { [k: string]: string })[c];
  });
}

export function fmt(value: number): string {
  const rounded: number = Math.round(value * 100) / 100;
  return rounded.toLocaleString('en-GB');
}

// A large figure in compact form for a tight space: 2.36M, 236K, 4.1B.
export function compact(value: number): string {
  const units: [number, string][] = [[1e9, 'B'], [1e6, 'M'], [1e3, 'K']];
  for (const [size, unit] of units) {
    if (Math.abs(value) >= size) {
      const x: number = value / size;
      const digits: number = Math.abs(x) >= 100 ? 0 : Math.abs(x) >= 10 ? 1 : 2;
      return parseFloat(x.toFixed(digits)).toString() + unit;
    }
  }
  return fmt(value);
}

// The site the charts are drawn on, for the publisher's ~site/ links. The
// chart web part sets it to its site's server-relative URL.
let siteBase: string = '';

export function setSiteUrl(url: string | undefined): void {
  siteBase = str(url).replace(/\/+$/, '');
}

// Only links the publisher writes: web URLs, mail, site-relative paths, and
// ~site/ paths, which resolve against the site.
export function safeHref(href: unknown): string | undefined {
  let h: string = str(href).trim();
  if (h.indexOf('~site/') === 0) { h = siteBase + h.substring(5); }
  return /^(https?:\/\/|mailto:|\/)/i.test(h) ? h : undefined;
}

export function colourFor(label: string, index: number): string {
  const key: string = str(label).toLowerCase().replace(/[^a-z]/g, '');
  return NAMED[key] || SERIES[index % SERIES.length];
}

// Black or white, whichever reads better on a fill.
export function readableOn(fill: string): string {
  const m: RegExpExecArray | null = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(str(fill).trim());
  if (!m) { return '#111827'; }
  const hex: string = m[1].length === 3 ? m[1].split('').map((c: string): string => c + c).join('') : m[1];
  const r: number = parseInt(hex.substring(0, 2), 16);
  const g: number = parseInt(hex.substring(2, 4), 16);
  const b: number = parseInt(hex.substring(4, 6), 16);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6 ? '#111827' : '#ffffff';
}

export type TextMeasurer = (text: string, size: number, bold: boolean) => number;

function estimateWidth(text: string, size: number, bold: boolean): number {
  let w: number = 0;
  for (const ch of text) {
    w += /[A-Z@%MW]/.test(ch) ? 0.68 : /[ijlI.,:;'|! ]/.test(ch) ? 0.3 : /[0-9]/.test(ch) ? 0.56 : 0.54;
  }
  return w * size * (bold ? 1.06 : 1);
}

let measurer: TextMeasurer = estimateWidth;

// The web part passes a canvas-based measurer; tests and fallbacks estimate.
export function setTextMeasurer(m: TextMeasurer | undefined): void {
  measurer = m || estimateWidth;
}

export function textWidth(text: string, size: number, bold: boolean = false): number {
  return Math.ceil(measurer(text, size, bold));
}

// Greedy word wrap; '\n' in the text always breaks. A word longer than the
// line is cut rather than allowed to overflow.
export function wrapText(text: string, maxWidth: number, size: number, bold: boolean = false): string[] {
  const out: string[] = [];
  for (const para of str(text).split('\n')) {
    let line: string = '';
    for (const word of para.split(/\s+/).filter((w: string): boolean => w.length > 0)) {
      const next: string = line ? line + ' ' + word : word;
      if (textWidth(next, size, bold) <= maxWidth) { line = next; continue; }
      if (line) { out.push(line); }
      let rest: string = word;
      while (textWidth(rest, size, bold) > maxWidth && rest.length > 1) {
        let cut: number = rest.length - 1;
        while (cut > 1 && textWidth(rest.substring(0, cut), size, bold) > maxWidth) { cut--; }
        out.push(rest.substring(0, cut));
        rest = rest.substring(cut);
      }
      line = rest;
    }
    out.push(line);
  }
  return out;
}

export function widest(lines: string[], size: number, bold: boolean = false): number {
  return lines.reduce((m: number, l: string): number => Math.max(m, textWidth(l, size, bold)), 0);
}

let idCounter: number = 0;

// Marker and clip ids must be unique on the page, which can hold many charts.
export function nextId(prefix: string): string {
  idCounter++;
  return 'ibc-' + prefix + '-' + idCounter;
}

// The drawing scales down with its column to two thirds of its size, then
// the column scrolls sideways (see renderChart), so text stays readable.
export function svgDoc(width: number, height: number, label: string, body: string): string {
  const w: number = Math.ceil(width);
  const h: number = Math.ceil(height);
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + w + ' ' + h + '" width="' + w + '" height="' + h + '"' +
    ' style="display:block;width:100%;max-width:' + w + 'px;min-width:' + Math.round(w * 0.66) + 'px;height:auto;overflow:visible"' +
    ' role="img" aria-label="' + esc(label) + '">' +
    '<title>' + esc(label) + '</title>' + body + '</svg>';
}

export interface ITextOptions {
  size?: number;
  weight?: number;
  fill?: string;
  anchor?: string;
  lineHeight?: number;
}

// One <text> per block of lines, vertically centred on y.
export function svgText(x: number, y: number, lines: string[], opts: ITextOptions): string {
  const size: number = opts.size || 12;
  const lh: number = opts.lineHeight || Math.round(size * 1.3);
  const top: number = y - ((lines.length - 1) * lh) / 2 + size * 0.35;
  let out: string = '<text x="' + r(x) + '" y="' + r(top) + '" font-size="' + size + '"' +
    (opts.weight ? ' font-weight="' + opts.weight + '"' : '') +
    (opts.fill ? ' fill="' + esc(opts.fill) + '"' : '') +
    (opts.anchor ? ' text-anchor="' + opts.anchor + '"' : '') + '>';
  lines.forEach((line: string, i: number): void => {
    out += '<tspan x="' + r(x) + '"' + (i > 0 ? ' dy="' + lh + '"' : '') + '>' + esc(line) + '</tspan>';
  });
  return out + '</text>';
}

export function r(n: number): string {
  return String(Math.round(n * 10) / 10);
}

export function rect(x: number, y: number, w: number, h: number, attrs: string): string {
  return '<rect x="' + r(x) + '" y="' + r(y) + '" width="' + r(Math.max(0, w)) + '" height="' + r(Math.max(0, h)) + '" ' + attrs + '/>';
}

// An arrowhead for edges: 'arrow' (filled), 'triangle' (hollow, for
// inheritance), 'diamond' (filled), 'odiamond' (hollow) or 'cross'.
export function marker(id: string, shape: string, colour: string, surface: string): string {
  const c: string = esc(colour);
  const s: string = esc(surface);
  let path: string;
  switch (shape) {
    case 'triangle': path = '<path d="M0,0 L12,6 L0,12 Z" fill="' + s + '" stroke="' + c + '" stroke-width="1.4"/>'; break;
    case 'diamond': path = '<path d="M0,6 L6,0 L12,6 L6,12 Z" fill="' + c + '"/>'; break;
    case 'odiamond': path = '<path d="M0,6 L6,0 L12,6 L6,12 Z" fill="' + s + '" stroke="' + c + '" stroke-width="1.4"/>'; break;
    case 'cross': path = '<path d="M2,2 L10,10 M10,2 L2,10" stroke="' + c + '" stroke-width="1.8"/>'; break;
    default: path = '<path d="M0,1 L11,6 L0,11 Z" fill="' + c + '"/>';
  }
  return '<marker id="' + id + '" viewBox="0 0 12 12" refX="11" refY="6" markerWidth="10" markerHeight="10" orient="auto-start-reverse" markerUnits="userSpaceOnUse">' + path + '</marker>';
}

export interface ILegendItem {
  label: string;
  colour: string;
  value?: string;
}

export function legendHtml(items: ILegendItem[], theme: IChartTheme): string {
  if (!items.length) { return ''; }
  return '<div style="display:flex;flex-wrap:wrap;gap:6px 16px;margin-top:10px;font-size:13px;color:' + esc(theme.text) + '">' +
    items.map((i: ILegendItem): string =>
      '<span style="display:inline-flex;align-items:center;gap:6px">' +
      '<i style="display:inline-block;width:10px;height:10px;border-radius:3px;background:' + esc(i.colour) + '"></i>' +
      esc(i.label) + (i.value ? '<span style="color:' + esc(theme.muted) + '">' + esc(i.value) + '</span>' : '') +
      '</span>').join('') +
    '</div>';
}

// Round numbers for an axis from lo to hi, about `count` of them; whole
// numbers only when the values are counts.
export function niceTicks(lo: number, hi: number, count: number, whole: boolean = false): number[] {
  if (hi <= lo) { hi = lo + 1; }
  const raw: number = (hi - lo) / Math.max(1, count);
  const mag: number = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10));
  const norm: number = raw / mag;
  let step: number = (norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10) * mag;
  if (whole) { step = Math.max(1, Math.round(step)); }
  const ticks: number[] = [];
  for (let v: number = Math.floor(lo / step) * step; v <= hi + step * 0.001; v += step) {
    ticks.push(Math.round(v / step) * step);
  }
  return ticks;
}

// A colour, see-through, for fills and borders; a theme colour that is not
// six-digit hex is mixed with transparent instead.
export function tint(hex: string, alpha: number): string {
  const m: RegExpExecArray | null = /^#?([0-9a-f]{6})$/i.exec(str(hex).trim());
  if (!m) { return 'color-mix(in srgb,' + esc(hex) + ' ' + Math.round(alpha * 100) + '%,transparent)'; }
  const v: number = parseInt(m[1], 16);
  return 'rgba(' + ((v >> 16) & 255) + ',' + ((v >> 8) & 255) + ',' + (v & 255) + ',' + alpha + ')';
}
