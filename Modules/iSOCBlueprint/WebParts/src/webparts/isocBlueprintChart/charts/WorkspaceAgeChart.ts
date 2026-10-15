import { type IWorkspaceAgeData } from './ChartTypes';
import { type IChartTheme, esc, fmtDay, isNil, num, str, tint } from './ChartKit';
import { card, chip, count, eyebrow, figure, sub } from './Visual';

// The workspace's own history: when it was created and on what terms, how
// old it is, and what it holds today. Platform retirements are on the
// deprecated features page, so they are not repeated here.

export function renderWorkspaceAge(data: IWorkspaceAgeData, theme: IChartTheme): string {
  if (!data) { return ''; }
  const created: number = Date.parse(str(data.created));
  const today: number = Date.parse(str(data.today)) || Date.now();
  const fmtDate: (t: number) => string = fmtDay;
  const age: number = num(data.ageDays);
  const ageText: string = isNil(data.ageDays) ? 'Age unknown' : age >= 730 ? (Math.round(age / 365.25 * 10) / 10) + ' years old' : age >= 60 ? Math.round(age / 30.4) + ' months old' : count(age) + ' days old';
  const terms: string = [str(data.sku), isNil(data.retentionDays) ? '' : count(num(data.retentionDays)) + '-day retention'].filter((t: string): boolean => !!t)
    .map((t: string): string => chip(t, theme)).join(' ');
  const span: string = '<div style="margin:14px 0 4px">' +
    '<div style="display:flex;justify-content:space-between;gap:12px;font-size:12px;margin-bottom:6px">' +
    '<span><b>Created</b> <span style="color:' + esc(theme.muted) + '">' + esc(isNaN(created) ? 'unknown' : fmtDate(created)) + '</span></span>' +
    '<span><b>Documented</b> <span style="color:' + esc(theme.muted) + '">' + esc(fmtDate(today)) + '</span></span></div>' +
    '<div style="position:relative;height:12px;border-radius:99px;background:linear-gradient(90deg,' + tint(theme.accent, 0.35) + ',' + esc(theme.accent) + ')">' +
    '<span style="position:absolute;left:-3px;top:-3px;width:18px;height:18px;border-radius:50%;background:' + esc(theme.accent) + ';box-shadow:0 0 0 3px ' + esc(theme.surface) + '"></span>' +
    '<span style="position:absolute;right:-3px;top:-3px;width:18px;height:18px;border-radius:50%;background:' + esc(theme.accent) + ';box-shadow:0 0 0 3px ' + esc(theme.surface) + '"></span></div></div>';
  const tile: (label: string, value: unknown, note?: string) => string = (label: string, value: unknown, note?: string): string =>
    isNil(value) ? '' : card(eyebrow(label, theme) + figure(count(num(value)), theme, 22) + sub(note || '', theme), theme);
  const tiles: string = [
    tile('Analytics rules enabled', data.rulesEnabled),
    tile('Data connectors', data.connectors),
    tile('Tables receiving data', data.tablesReceiving, isNil(data.tablesCatalogue) ? '' : 'of ' + count(num(data.tablesCatalogue)) + ' in the catalogue')
  ].join('');
  return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + esc(theme.text) + '">' +
    card('<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap">' +
      '<div>' + eyebrow('Workspace lifespan', theme) + figure(ageText, theme) + '</div>' +
      '<div style="display:flex;flex-wrap:wrap;gap:6px">' + terms + '</div></div>' + span, theme) +
    (tiles ? '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px">' + tiles + '</div>' : '') +
    '</div>';
}
