import { type ICostBreakdownData, type ICostPlan, type ICostSource, type ICostTable } from './ChartTypes';
import { type IChartTheme, SERIES, esc, fmt, isNil, list, num, str, tint } from './ChartKit';
import { INFO, type IPart, card, chip, eyebrow, figure, meter, pct, share, sub } from './Visual';

// Where the monthly estimate comes from: the total, then the billable GB by
// plan with each plan's cost, then every source family's GB, each opening
// to every one of its tables with its billing rate. One view of the cost,
// in place of the separate mind map, flow diagram and compact flow.

const PLAN: { [plan: string]: string } = { Analytics: '#dc2626', Basic: '#0d9488', Auxiliary: '#0891b2', DataLake: '#7c3aed' };
const PLAN_NAME: { [plan: string]: string } = { DataLake: 'Data lake' };

export function renderCostBreakdown(data: ICostBreakdownData, theme: IChartTheme): string {
  const sources: ICostSource[] = list<ICostSource>(data && data.sources).filter((s: ICostSource): boolean => num(s.gb) > 0);
  const plans: ICostPlan[] = list<ICostPlan>(data && data.plans);
  if (!sources.length && !plans.length) { return ''; }
  const currency: string = str(data.currency);
  const totalGb: number = num(data.totalGb) || sources.reduce((a: number, s: ICostSource): number => a + num(s.gb), 0);
  const money: (v: unknown) => string = (v: unknown): string => isNil(v) || str(v) === '' ? '' : (currency ? currency + ' ' : '') + fmt(num(v));
  const head: string = '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px">' +
    card(eyebrow('Estimated monthly cost', theme) + figure(money(data.monthlyTotal) || 'n/a', theme, 28) +
      sub('From the last 30 days of billable data: ' + gb(totalGb) + '.', theme), theme, INFO) +
    plansCard(plans, money, theme) + '</div>';
  return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + esc(theme.text) + '">' + head +
    (sources.length ? sourcesCard(sources, totalGb, theme) : '') + '</div>';
}

function plansCard(plans: ICostPlan[], money: (v: unknown) => string, theme: IChartTheme): string {
  const parts: IPart[] = plans.map((p: ICostPlan, i: number): IPart => ({ label: PLAN_NAME[str(p.name)] || str(p.name), value: num(p.gb), colour: PLAN[str(p.name)] || SERIES[i % SERIES.length] }));
  const total: number = parts.reduce((a: number, p: IPart): number => a + p.value, 0);
  const rows: string = parts.map((p: IPart, i: number): string =>
    '<div style="display:grid;grid-template-columns:10px minmax(0,1fr) auto auto;gap:10px;align-items:center;font-size:12px;padding:2px 0">' +
    '<span style="width:10px;height:10px;border-radius:3px;background:' + esc(p.colour) + '"></span>' +
    '<span>' + esc(p.label) + ' <span style="color:' + esc(theme.muted) + '">' + pct(p.value, total) + '</span></span>' +
    '<span style="font-variant-numeric:tabular-nums;color:' + esc(theme.muted) + '">' + gb(p.value) + '</span>' +
    '<span style="font-weight:750;font-variant-numeric:tabular-nums;text-align:right;min-width:84px">' + esc(money(plans[i].cost)) + '</span></div>').join('');
  return card(eyebrow('By plan', theme) + sub('Billable GB in 30 days, and each plan\'s monthly cost', theme) +
    '<div style="margin:10px 0 9px">' + meter(parts, theme, 12) + '</div>' + rows, theme);
}

function sourcesCard(sources: ICostSource[], totalGb: number, theme: IChartTheme): string {
  const max: number = Math.max(...sources.map((s: ICostSource): number => num(s.gb)));
  const rows: string = sources.map((s: ICostSource, i: number): string => {
    const tables: ICostTable[] = list<ICostTable>(s.tables);
    const colour: string = SERIES[i % SERIES.length];
    const summary: string = '<summary style="display:grid;grid-template-columns:minmax(140px,1.1fr) minmax(120px,2fr) 80px 44px 76px;gap:12px;align-items:center;cursor:pointer;padding:7px 4px;list-style:none">' +
      '<span style="font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="' + esc(s.name) + '">' + esc(s.name) + '</span>' +
      share(num(s.gb), max, colour, theme) +
      '<span style="text-align:right;font-weight:750;font-variant-numeric:tabular-nums">' + gb(num(s.gb)) + '</span>' +
      '<span style="text-align:right;color:' + esc(theme.muted) + ';font-variant-numeric:tabular-nums">' + pct(num(s.gb), totalGb) + '</span>' +
      '<span style="justify-self:end">' + chip(tables.length + ' table' + (tables.length === 1 ? '' : 's'), theme) + '</span></summary>';
    const detail: string = '<div style="margin:2px 0 8px;padding:6px 10px;border-radius:9px;background:' + tint(colour, theme.dark ? 0.08 : 0.04) + '">' +
      tables.map((t: ICostTable): string => '<div style="display:grid;grid-template-columns:minmax(0,1fr) auto 80px;gap:12px;align-items:center;font-size:12px;padding:3px 0">' +
        '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" title="' + esc(t.table) + '">' + esc(t.table) + '</span>' +
        '<span style="font-size:11px;color:' + esc(theme.muted) + '">' + esc(t.tier) + '</span>' +
        '<span style="text-align:right;font-variant-numeric:tabular-nums">' + gb(num(t.gb)) + '</span></div>').join('') + '</div>';
    return '<details style="border-top:1px solid ' + esc(theme.line) + '">' + summary + detail + '</details>';
  }).join('');
  return card(eyebrow('By source', theme) + sub('Every source family\'s billable GB; select one for its tables and billing rate', theme) +
    '<div style="margin-top:8px">' + rows + '</div>', theme);
}

function gb(v: number): string {
  return (v >= 100 ? Math.round(v).toLocaleString('en-GB') : v >= 10 ? (Math.round(v * 10) / 10).toString() : (Math.round(v * 100) / 100).toString()) + ' GB';
}
