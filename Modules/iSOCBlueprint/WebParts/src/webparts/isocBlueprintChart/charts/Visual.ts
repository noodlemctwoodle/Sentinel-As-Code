import { type IChartTheme, esc, num, tint } from './ChartKit';

// The building blocks of the purpose-built graphics, so every one reads in
// the site's style: soft cards on a hairline border, small spaced capitals
// over large tabular figures, tinted fills and pills for meaning, never a
// coloured edge bar. Each returns markup with inline styles, which both
// the SharePoint web part and the dashboard can show as they are.

export const OK: string = '#16a34a';
export const WARN: string = '#d97706';
export const BAD: string = '#dc2626';
export const INFO: string = '#2563eb';
export const NEUTRAL: string = '#64748b';

export interface IPart {
  label: string;
  value: number;
  colour: string;
}

export function count(n: number): string {
  return Math.round(n).toLocaleString('en-GB');
}

export function pct(part: number, whole: number): string {
  return whole > 0 ? Math.round(part / whole * 100) + '%' : '0%';
}

export function card(inner: string, theme: IChartTheme, colour?: string, extra?: string): string {
  const fill: string = colour ? tint(colour, theme.dark ? 0.12 : 0.05) : 'transparent';
  const edge: string = colour ? tint(colour, 0.35) : esc(theme.line);
  return '<div style="min-width:0;border:1px solid ' + edge + ';border-radius:12px;padding:12px 14px;background:' + fill + (extra ? ';' + extra : '') + '">' + inner + '</div>';
}

export function eyebrow(text: string, theme: IChartTheme, colour?: string): string {
  return '<div style="font-size:10.5px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;color:' + esc(colour || theme.muted) + '">' + esc(text) + '</div>';
}

export function figure(value: string, theme: IChartTheme, size?: number): string {
  return '<div style="font-size:' + (size || 26) + 'px;font-weight:800;line-height:1.15;margin-top:4px;font-variant-numeric:tabular-nums;color:' + esc(theme.text) + '">' + esc(value) + '</div>';
}

export function sub(text: string, theme: IChartTheme): string {
  return text ? '<div style="font-size:12px;line-height:1.45;color:' + esc(theme.muted) + ';margin-top:3px">' + esc(text) + '</div>' : '';
}

export function pill(text: string, colour: string, solid?: boolean): string {
  return '<span style="display:inline-block;white-space:nowrap;padding:1px 8px;border-radius:99px;font-size:10.5px;font-weight:800;' +
    (solid ? 'background:' + esc(colour) + ';color:#fff' : 'background:' + tint(colour, 0.16) + ';color:' + esc(colour)) + '">' + esc(text) + '</span>';
}

export function chip(text: string, theme: IChartTheme, mono?: boolean): string {
  return '<span style="display:inline-block;padding:1px 7px;border-radius:6px;font-size:11px;border:1px solid ' + esc(theme.line) + ';color:' + esc(theme.text) +
    (mono ? ';font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace' : '') + '">' + esc(text) + '</span>';
}

// A stacked bar of parts, each sized by its value, with a hairline gap.
export function meter(parts: IPart[], theme: IChartTheme, height?: number): string {
  const shown: IPart[] = parts.filter((p: IPart): boolean => num(p.value) > 0);
  if (!shown.length) {
    return '<div style="height:' + (height || 10) + 'px;border-radius:99px;background:' + esc(theme.line) + '"></div>';
  }
  return '<div style="display:flex;gap:2px;height:' + (height || 10) + 'px;border-radius:99px;overflow:hidden">' +
    shown.map((p: IPart): string => '<span title="' + esc(p.label + ': ' + count(p.value)) + '" style="flex:' + num(p.value) + ' 1 0;min-width:3px;background:' + esc(p.colour) + '"></span>').join('') +
    '</div>';
}

// One share of a whole: a single bar filled to its fraction.
export function share(value: number, of: number, colour: string, theme: IChartTheme): string {
  const w: number = of > 0 ? Math.max(0, Math.min(100, value / of * 100)) : 0;
  return '<div style="height:6px;border-radius:99px;background:' + tint(colour, theme.dark ? 0.2 : 0.14) + '"><div style="height:100%;border-radius:99px;width:' + w.toFixed(1) + '%;background:' + esc(colour) + '"></div></div>';
}

// A legend row: swatch, label, count and its share of the total.
export function legendRow(p: IPart, total: number, theme: IChartTheme): string {
  return '<div style="display:grid;grid-template-columns:10px minmax(0,1fr) auto 42px;gap:8px;align-items:center;font-size:12px;padding:2px 0">' +
    '<span style="width:10px;height:10px;border-radius:3px;background:' + esc(p.colour) + '"></span>' +
    '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(p.label) + '</span>' +
    '<span style="font-weight:700;font-variant-numeric:tabular-nums">' + count(p.value) + '</span>' +
    '<span style="text-align:right;color:' + esc(theme.muted) + ';font-variant-numeric:tabular-nums">' + pct(p.value, total) + '</span></div>';
}

// A right-pointing connector between two columns, shaded between colours.
export function arrow(from: string, to: string): string {
  return '<div style="display:flex;align-items:center;padding:0 4px"><div style="position:relative;flex:1;height:2px;margin-right:7px;background:linear-gradient(90deg,' + esc(from) + ',' + esc(to) + ')">' +
    '<span style="position:absolute;right:-7px;top:-4px;border-left:8px solid ' + esc(to) + ';border-top:5px solid transparent;border-bottom:5px solid transparent"></span></div></div>';
}

// The first rows of a list, and the rest behind a Show all that needs no
// script, so a long list is complete but does not swamp its card.
export function showAll(rows: string[], first: number, noun: string, theme: IChartTheme): string {
  if (rows.length <= first) { return rows.join(''); }
  return rows.slice(0, first).join('') +
    '<details style="margin-top:4px"><summary style="display:inline-block;cursor:pointer;margin:6px 0 4px;padding:3px 10px;border-radius:8px;font-size:11.5px;font-weight:700;' +
    'color:' + esc(theme.accent) + ';background:' + tint(theme.accent, theme.dark ? 0.16 : 0.08) + '">Show all ' + rows.length + ' ' + esc(noun) + '</summary>' +
    rows.slice(first).join('') + '</details>';
}

// Columns for n cards so the rows balance: six make three and three, never
// five and one. At most max columns.
export function balancedColumns(n: number, max: number): number {
  if (n <= max) { return Math.max(1, n); }
  return Math.ceil(n / Math.ceil(n / max));
}

export function note(text: string, theme: IChartTheme): string {
  return '<p style="margin:0;font-size:12px;color:' + esc(theme.muted) + '">' + esc(text) + '</p>';
}
