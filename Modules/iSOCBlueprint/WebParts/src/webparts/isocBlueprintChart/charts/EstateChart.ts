import { type IEstateData, type IEstateSource, type IEstateStage } from './ChartTypes';
import { type IChartTheme, esc, list, num, str, windowText } from './ChartKit';
import { BAD, NEUTRAL, OK, WARN, type IPart, arrow, card, count, eyebrow, figure, meter, pct, pill, share, showAll, sub } from './Visual';

// The estate in the last 30 days: every source family's billable GB split
// into what an enabled detection reads and what nothing reads, then the
// pipeline from ingestion to incidents as four stages, each with the share
// that made it through and a rating (80% and over strong, 65% fair).

const READ: string = '#0d9488';
const STAGE: string[] = ['#2563eb', '#0d9488', '#d97706', '#7c3aed'];

export function renderEstate(data: IEstateData, theme: IChartTheme): string {
  const sources: IEstateSource[] = list<IEstateSource>(data && data.sources);
  const stages: IEstateStage[] = list<IEstateStage>(data && data.stages);
  if (!sources.length && !stages.length) { return ''; }
  return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + esc(theme.text) + '">' +
    (stages.length ? pipeline(stages, theme) : '') + (sources.length ? families(sources, data, theme) : '') + '</div>';
}

function pipeline(stages: IEstateStage[], theme: IChartTheme): string {
  const cols: string[] = [];
  stages.forEach((s: IEstateStage, i: number): void => {
    if (i) { cols.push('40px'); }
    cols.push('minmax(150px,1fr)');
  });
  let out: string = '<div style="display:grid;grid-template-columns:' + cols.join(' ') + ';min-width:' + (stages.length * 160 + 120) + 'px;align-items:stretch">';
  stages.forEach((s: IEstateStage, i: number): void => {
    const colour: string = STAGE[i % STAGE.length];
    if (i) { out += arrow(STAGE[(i - 1) % STAGE.length], colour); }
    const value: number = num(s.value);
    const of: number = num(s.of);
    const p: number = of > 0 ? value / of : 0;
    const rating: string = of <= 0 ? '' : p >= 0.8 ? pill('Strong', OK) : p >= 0.65 ? pill('Fair', WARN) : pill('Weak', BAD);
    out += card('<div style="display:flex;justify-content:space-between;align-items:center;gap:6px">' + eyebrow(str(s.name), theme, colour) + rating + '</div>' +
      figure(of > 0 ? pct(value, of) : 'n/a', theme) +
      sub(count(value) + ' of ' + count(of) + ' ' + str(s.label), theme) +
      '<div style="margin:9px 0 8px">' + share(value, of, colour, theme) + '</div>' +
      (str(s.detail) ? '<div style="font-size:12px;font-weight:700">' + esc(s.detail) + '</div>' : ''), theme, colour);
  });
  return out + '</div>';
}

function families(sources: IEstateSource[], data: IEstateData, theme: IChartTheme): string {
  const total: number = num(data.totalGb) || sources.reduce((a: number, s: IEstateSource): number => a + num(s.gb), 0);
  const covered: number = num(data.coveredGb);
  const max: number = Math.max(...sources.map((s: IEstateSource): number => num(s.gb)));
  const rows: string[] = sources.map((s: IEstateSource): string => {
    const gb: number = num(s.gb);
    const read: number = Math.min(gb, num(s.coveredGb));
    const parts: IPart[] = [{ label: 'Read by a detection', value: read, colour: READ }, { label: 'Not monitored', value: gb - read, colour: NEUTRAL }];
    return '<div style="display:grid;grid-template-columns:minmax(150px,1.2fr) minmax(120px,2fr) 76px 150px;gap:12px;align-items:center;padding:6px 0;border-top:1px solid ' + esc(theme.line) + '">' +
      '<span style="font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="' + esc(s.name) + '">' + esc(s.name) + '</span>' +
      '<div style="width:' + (max > 0 ? gb / max * 100 : 0).toFixed(1) + '%;min-width:6px">' + meter(parts, theme, 8) + '</div>' +
      '<span style="text-align:right;font-weight:750;font-variant-numeric:tabular-nums">' + gbText(gb) + '</span>' +
      '<span style="text-align:right;font-size:11.5px;color:' + esc(theme.muted) + '">' + pct(read, gb) + ' read · ' + count(num(s.covered)) + '/' + count(num(s.tables)) + ' tables</span></div>';
  });
  const key: string = '<div style="display:flex;flex-wrap:wrap;gap:14px;font-size:12px;color:' + esc(theme.muted) + ';margin-top:6px">' +
    '<span style="display:inline-flex;align-items:center;gap:6px"><span style="width:10px;height:10px;border-radius:3px;background:' + READ + '"></span>Read by an enabled detection</span>' +
    '<span style="display:inline-flex;align-items:center;gap:6px"><span style="width:10px;height:10px;border-radius:3px;background:' + NEUTRAL + '"></span>Not monitored (ingested and billed, read by no detection)</span></div>';
  return card('<div style="display:flex;justify-content:space-between;align-items:flex-end;gap:12px">' +
    '<div>' + eyebrow('Source families', theme) + sub(gbText(total) + ' billable in ' + windowText(data.windowDays) + ', ' + pct(covered, total) + ' of it read by a detection', theme) + '</div></div>' +
    key + '<div style="margin-top:8px">' + showAll(rows, 8, 'families') + '</div>', theme);
}

function gbText(v: number): string {
  return (v >= 100 ? Math.round(v).toLocaleString('en-GB') : v >= 10 ? (Math.round(v * 10) / 10).toString() : (Math.round(v * 100) / 100).toString()) + ' GB';
}
