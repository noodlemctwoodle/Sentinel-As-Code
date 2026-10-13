import { type IPieData, type IPieSlice } from './ChartTypes';
import { type IChartTheme, colourFor, compact, esc, fmt, list, num, r, str, svgDoc, svgText, textWidth } from './ChartKit';

interface ISlice {
  label: string;
  value: number;
  colour: string;
}

const SIZE: number = 200;
const OUTER: number = 92;
const INNER: number = 58;

// A donut with the total in the middle and every slice in the legend,
// including slices of zero, which the ring cannot show.
export function renderPie(data: IPieData, theme: IChartTheme, label: string): string {
  const slices: ISlice[] = list<IPieSlice>(data && data.slices).map((s: IPieSlice, i: number): ISlice => ({
    label: str(s.label), value: Math.max(0, num(s.value)), colour: colourFor(str(s.label), i)
  }));
  const total: number = slices.reduce((a: number, s: ISlice): number => a + s.value, 0);
  const c: number = SIZE / 2;

  let ring: string = '';
  if (total <= 0) {
    ring = annulus(c, 0, Math.PI * 2, theme.line);
  } else {
    let angle: number = 0;
    slices.forEach((s: ISlice): void => {
      if (s.value <= 0) { return; }
      const sweep: number = (s.value / total) * Math.PI * 2;
      ring += annulus(c, angle, angle + sweep, s.colour, s.label + ': ' + fmt(s.value) + ' (' + pct(s.value, total) + ')');
      angle += sweep;
    });
  }
  // The total fits inside the hole: a large one in compact form (2.36M),
  // the legend keeping every exact figure, and smaller type if need be.
  const room: number = INNER * 2 - 18;
  let shown: string = total > 0 ? fmt(total) : '0';
  if (textWidth(shown, 26, true) > room) { shown = compact(total); }
  const size: number = Math.max(14, Math.min(26, Math.floor(26 * room / Math.max(room, textWidth(shown, 26, true)))));
  const centre: string =
    svgText(c, c - 8, [shown], { size: size, weight: 600, fill: theme.text, anchor: 'middle' }) +
    svgText(c, c + 18, ['total'], { size: 12, fill: theme.muted, anchor: 'middle' });
  const chart: string = svgDoc(SIZE, SIZE, label, ring + centre);

  const showData: boolean = !data || data.showData !== false;
  const legend: string = slices.map((s: ISlice): string =>
    '<div style="display:flex;align-items:center;gap:8px;padding:3px 0">' +
    '<i style="flex:none;width:11px;height:11px;border-radius:3px;background:' + esc(s.colour) + '"></i>' +
    '<span style="flex:1 1 auto;min-width:0;overflow-wrap:anywhere">' + esc(s.label) + '</span>' +
    (showData ? '<span style="flex:none;font-variant-numeric:tabular-nums">' + esc(fmt(s.value)) + '</span>' : '') +
    '<span style="flex:none;width:44px;text-align:right;color:' + esc(theme.muted) + ';font-variant-numeric:tabular-nums">' + esc(pct(s.value, total)) + '</span>' +
    '</div>').join('');

  return '<div style="display:flex;flex-wrap:wrap;align-items:center;gap:16px 28px">' +
    '<div style="flex:none;width:' + SIZE + 'px;max-width:100%">' + chart + '</div>' +
    '<div style="flex:1 1 220px;min-width:0;max-width:340px;font-size:13px">' + legend + '</div>' +
    '</div>';
}

function pct(value: number, total: number): string {
  if (total <= 0) { return '0%'; }
  const p: number = (value / total) * 100;
  return value > 0 && p < 1 ? '<1%' : Math.round(p) + '%';
}

function point(c: number, radius: number, angle: number): string {
  return r(c + radius * Math.sin(angle)) + ',' + r(c - radius * Math.cos(angle));
}

// One slice of the ring, clockwise from twelve o'clock. A full circle is
// drawn as two halves, since an arc cannot start and end at one point.
function annulus(c: number, a0: number, a1: number, colour: string, tip?: string): string {
  if (a1 - a0 >= Math.PI * 2 - 1e-6) {
    return annulus(c, a0, a0 + Math.PI, colour, tip) + annulus(c, a0 + Math.PI, a0 + Math.PI * 2, colour, tip);
  }
  const large: number = a1 - a0 > Math.PI ? 1 : 0;
  const d: string = 'M' + point(c, OUTER, a0) + ' A' + OUTER + ',' + OUTER + ' 0 ' + large + ' 1 ' + point(c, OUTER, a1) +
    ' L' + point(c, INNER, a1) + ' A' + INNER + ',' + INNER + ' 0 ' + large + ' 0 ' + point(c, INNER, a0) + ' Z';
  return '<path d="' + d + '" fill="' + esc(colour) + '">' + (tip ? '<title>' + esc(tip) + '</title>' : '') + '</path>';
}
