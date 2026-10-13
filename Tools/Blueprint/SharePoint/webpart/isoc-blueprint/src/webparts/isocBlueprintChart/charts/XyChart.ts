import { type IXyData, type IXySeries } from './ChartTypes';
import {
  type IChartTheme, type ILegendItem, SERIES, esc, fmt, isNil, legendHtml, list, niceTicks, num, r, rect, str,
  svgDoc, svgText, textWidth, widest, wrapText
} from './ChartKit';

interface ISeries {
  kind: string;
  name: string;
  values: number[];
  colour: string;
}

interface IAxis {
  lo: number;
  hi: number;
  ticks: number[];
}

const FONT_SIZE: number = 12;

// Bars and lines over shared categories. Bars-only charts whose labels do not
// fit under their columns are drawn as horizontal bars instead.
export function renderXy(data: IXyData, theme: IChartTheme, label: string): string {
  const labels: string[] = list<unknown>(data && data.xAxis && data.xAxis.labels).map(str);
  const series: ISeries[] = list<IXySeries>(data && data.series).map((s: IXySeries, i: number): ISeries => ({
    kind: str(s.kind) === 'line' ? 'line' : 'bar',
    name: str(s.name) || 'Series ' + (i + 1),
    values: list<unknown>(s.values).map(num),
    colour: SERIES[i % SERIES.length]
  }));
  const count: number = Math.max(labels.length, series.reduce((m: number, s: ISeries): number => Math.max(m, s.values.length), 0));
  while (labels.length < count) { labels.push(String(labels.length + 1)); }
  if (!count || !series.length) { return ''; }

  const values: number[] = [];
  series.forEach((s: ISeries): void => { s.values.forEach((v: number): void => { values.push(v); }); });
  const y: { title?: string; min?: number; max?: number } = (data && data.yAxis) || {};
  const lo: number = Math.min(isNil(y.min) ? 0 : num(y.min), Math.min(...values.concat([0])));
  const hi: number = Math.max(isNil(y.max) ? 0 : num(y.max), Math.max(...values.concat([0])));
  const whole: boolean = values.every((v: number): boolean => Math.round(v) === v);
  const ticks: number[] = niceTicks(lo, hi, 5, whole);
  const axis: IAxis = { lo: ticks[0], hi: ticks[ticks.length - 1], ticks: ticks };

  const plotW: number = Math.min(680, Math.max(360, count * 56));
  const band: number = plotW / count;
  const barsOnly: boolean = series.every((s: ISeries): boolean => s.kind === 'bar');
  const longest: number = widest(labels, FONT_SIZE);
  const svg: string = barsOnly && longest > band - 6
    ? horizontal(labels, series, axis, theme, label, str(y.title))
    : vertical(labels, series, axis, theme, label, str(y.title), str(data.xAxis && data.xAxis.title), plotW, band);

  const legend: ILegendItem[] = series.length > 1
    ? series.map((s: ISeries): ILegendItem => ({ label: s.name, colour: s.colour }))
    : [];
  return svg + legendHtml(legend, theme);
}

function vertical(labels: string[], series: ISeries[], axis: IAxis, theme: IChartTheme, label: string,
  yTitle: string, xTitle: string, plotW: number, band: number): string {
  const plotH: number = 240;
  const tickW: number = widest(axis.ticks.map(fmt), 11);
  const left: number = tickW + 14 + (yTitle ? 22 : 0);
  const wrapped: string[][] = labels.map((l: string): string[] => wrapText(l, band - 6, FONT_SIZE).slice(0, 2));
  const labelLines: number = wrapped.reduce((m: number, w: string[]): number => Math.max(m, w.length), 1);
  const top: number = 26;
  const bottom: number = 12 + labelLines * 15 + (xTitle ? 22 : 0);
  const scale: (v: number) => number = (v: number): number => top + plotH - ((v - axis.lo) / (axis.hi - axis.lo)) * plotH;

  let body: string = grid(axis, left, plotW, scale, theme);
  const bars: ISeries[] = series.filter((s: ISeries): boolean => s.kind === 'bar');
  const group: number = band * (bars.length > 1 ? 0.8 : 0.62);
  const barW: number = bars.length ? group / bars.length : 0;
  const showValues: boolean = labels.length * Math.max(1, bars.length) <= 36;
  const zero: number = scale(Math.max(axis.lo, Math.min(axis.hi, 0)));
  bars.forEach((s: ISeries, si: number): void => {
    s.values.forEach((v: number, i: number): void => {
      const x: number = left + band * i + (band - group) / 2 + barW * si;
      const yv: number = scale(v);
      body += rect(x + 1, Math.min(yv, zero), barW - 2, Math.abs(zero - yv), 'rx="3" fill="' + esc(s.colour) + '"')
        .replace('/>', '><title>' + esc(labels[i] + (bars.length > 1 ? ' (' + s.name + ')' : '') + ': ' + fmt(v)) + '</title></rect>');
      if (showValues) {
        body += svgText(x + barW / 2, Math.min(yv, zero) - 8, [fmt(v)], { size: 10.5, fill: theme.muted, anchor: 'middle' });
      }
    });
  });
  series.filter((s: ISeries): boolean => s.kind === 'line').forEach((s: ISeries): void => {
    const pts: string[] = s.values.map((v: number, i: number): string => r(left + band * i + band / 2) + ',' + r(scale(v)));
    body += '<polyline points="' + pts.join(' ') + '" fill="none" stroke="' + esc(s.colour) + '" stroke-width="2.5" stroke-linejoin="round"/>';
    s.values.forEach((v: number, i: number): void => {
      body += '<circle cx="' + r(left + band * i + band / 2) + '" cy="' + r(scale(v)) + '" r="4" fill="' + esc(s.colour) + '">' +
        '<title>' + esc(labels[i] + ' (' + s.name + '): ' + fmt(v)) + '</title></circle>';
    });
  });
  wrapped.forEach((lines: string[], i: number): void => {
    body += svgText(left + band * i + band / 2, top + plotH + 10 + (lines.length * 15) / 2, lines,
      { size: FONT_SIZE, fill: theme.text, anchor: 'middle', lineHeight: 15 });
  });
  if (yTitle) {
    body += '<g transform="translate(12,' + r(top + plotH / 2) + ') rotate(-90)">' +
      svgText(0, 0, [yTitle], { size: FONT_SIZE, fill: theme.muted, anchor: 'middle' }) + '</g>';
  }
  if (xTitle) {
    body += svgText(left + plotW / 2, top + plotH + bottom - 10, [xTitle], { size: FONT_SIZE, fill: theme.muted, anchor: 'middle' });
  }
  return svgDoc(left + plotW + 8, top + plotH + bottom, label, body);
}

function horizontal(labels: string[], series: ISeries[], axis: IAxis, theme: IChartTheme, label: string, xTitle: string): string {
  const labelW: number = Math.min(220, widest(labels, FONT_SIZE));
  const left: number = labelW + 16;
  const plotW: number = 440;
  const barH: number = series.length > 1 ? 14 : 18;
  const rowH: number = barH * series.length + 12;
  const top: number = 8;
  const plotH: number = rowH * labels.length;
  const valueW: number = widest(axis.ticks.map(fmt), 11) + 12;
  const bottom: number = 26 + (xTitle ? 20 : 0);
  const scale: (v: number) => number = (v: number): number => left + ((v - axis.lo) / (axis.hi - axis.lo)) * plotW;
  const zero: number = scale(Math.max(axis.lo, Math.min(axis.hi, 0)));

  let body: string = '';
  axis.ticks.forEach((t: number): void => {
    const x: number = scale(t);
    body += '<line x1="' + r(x) + '" y1="' + top + '" x2="' + r(x) + '" y2="' + r(top + plotH) + '" stroke="' + esc(theme.line) + '"/>';
    body += svgText(x, top + plotH + 12, [fmt(t)], { size: 11, fill: theme.muted, anchor: 'middle' });
  });
  labels.forEach((l: string, i: number): void => {
    const y0: number = top + rowH * i + 6;
    const lines: string[] = wrapText(l, labelW, FONT_SIZE).slice(0, 2);
    body += svgText(left - 10, y0 + (barH * series.length) / 2, lines, { size: FONT_SIZE, fill: theme.text, anchor: 'end', lineHeight: 14 });
    series.forEach((s: ISeries, si: number): void => {
      const v: number = i < s.values.length ? s.values[i] : 0;
      const x: number = scale(v);
      const y: number = y0 + barH * si;
      body += rect(Math.min(x, zero), y + 1, Math.abs(x - zero), barH - 2, 'rx="3" fill="' + esc(s.colour) + '"')
        .replace('/>', '><title>' + esc(l + (series.length > 1 ? ' (' + s.name + ')' : '') + ': ' + fmt(v)) + '</title></rect>');
      body += svgText(Math.max(x, zero) + 6, y + barH / 2, [fmt(v)], { size: 11, fill: theme.muted });
    });
  });
  if (xTitle) {
    body += svgText(left + plotW / 2, top + plotH + 32, [xTitle], { size: FONT_SIZE, fill: theme.muted, anchor: 'middle' });
  }
  return svgDoc(left + plotW + valueW + textWidth('0', 11), top + plotH + bottom, label, body);
}

function grid(axis: IAxis, left: number, plotW: number, scale: (v: number) => number, theme: IChartTheme): string {
  let out: string = '';
  axis.ticks.forEach((t: number): void => {
    const y: number = scale(t);
    out += '<line x1="' + r(left) + '" y1="' + r(y) + '" x2="' + r(left + plotW) + '" y2="' + r(y) + '" stroke="' + esc(theme.line) + '"/>';
    out += svgText(left - 8, y, [fmt(t)], { size: 11, fill: theme.muted, anchor: 'end' });
  });
  return out;
}
