import { type IMeter, type IMeterFigure, type IMetersData, type IMeterPart } from './ChartTypes';
import { type IChartTheme, SERIES, esc, isNil, list, num, str } from './ChartKit';
import { BAD, INFO, NEUTRAL, OK, WARN, type IPart, card, count, eyebrow, legendRow, meter, sub } from './Visual';

// Proportions of a whole, one card each: what the whole is and its size,
// then a stacked bar of its parts and a legend row per part with its
// count and share. For figures that are parts of something (templates
// deployed or not, packages up to date or not), where a bar chart of the
// same numbers would only repeat the tiles beside it. Figures that belong
// with them but are not parts of a whole sit in a strip underneath.

const TONE: { [tone: string]: string } = {
  ok: OK, warn: WARN, bad: BAD, info: INFO, neutral: NEUTRAL,
  violet: '#7c3aed', teal: '#0d9488', cyan: '#0891b2', rose: '#db2777'
};

export function renderMeters(data: IMetersData, theme: IChartTheme): string {
  const meters: IMeter[] = list<IMeter>(data && data.meters);
  if (!meters.length) { return ''; }
  const figures: IMeterFigure[] = list<IMeterFigure>(data.figures);
  return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + esc(theme.text) + '">' +
    '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px">' +
    meters.map((m: IMeter): string => one(m, theme)).join('') + '</div>' +
    (figures.length ? strip(figures, theme) : '') + '</div>';
}

// The figures side by side across the full width, split by hairlines.
function strip(figures: IMeterFigure[], theme: IChartTheme): string {
  return card('<div style="display:grid;grid-template-columns:repeat(' + figures.length + ',minmax(0,1fr))">' +
    figures.map((f: IMeterFigure, i: number): string =>
      '<div style="min-width:0;padding:2px 16px;' + (i ? 'border-left:1px solid ' + esc(theme.line) : 'padding-left:0') + '">' +
      eyebrow(str(f.label), theme) +
      '<div style="font-size:24px;font-weight:800;line-height:1.15;margin-top:5px;font-variant-numeric:tabular-nums">' + count(num(f.value)) + '</div>' +
      sub(str(f.caption), theme) + '</div>').join('') + '</div>', theme);
}

function one(m: IMeter, theme: IChartTheme): string {
  const parts: IPart[] = list<IMeterPart>(m.parts).map((p: IMeterPart, i: number): IPart => ({
    label: str(p.label), value: Math.max(0, num(p.value)), colour: TONE[str(p.tone)] || SERIES[i % SERIES.length]
  }));
  const total: number = !isNil(m.total) ? num(m.total) : parts.reduce((s: number, p: IPart): number => s + p.value, 0);
  const head: string = '<div style="display:flex;justify-content:space-between;align-items:flex-end;gap:12px">' +
    '<div style="min-width:0">' + eyebrow(str(m.title), theme) + sub(str(m.caption), theme) + '</div>' +
    '<div style="flex:none;font-size:26px;font-weight:800;line-height:1;font-variant-numeric:tabular-nums">' + count(total) + '</div></div>';
  return card(head +
    '<div style="margin:12px 0 10px">' + meter(parts, theme, 12) + '</div>' +
    parts.map((p: IPart): string => legendRow(p, total, theme)).join(''), theme);
}
