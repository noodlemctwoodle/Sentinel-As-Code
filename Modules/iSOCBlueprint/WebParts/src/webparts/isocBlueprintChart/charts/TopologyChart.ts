import { type ITopologyData, type ITopologyItem } from './ChartTypes';
import { type IChartTheme, esc, list, num, str, tint } from './ChartKit';
import { NEUTRAL, OK, arrow, card, count, eyebrow, figure, share, showAll, sub } from './Visual';

// How data reaches the workspace and where it goes: every source family
// with how many sources feed it, the workspace with the table plans in use
// (and those not in use, faded), and the destinations downstream.

const SRC: string = '#2563eb';
const WSP: string = '#d97706';
const DST: string = '#0d9488';

export function renderTopology(data: ITopologyData, theme: IChartTheme): string {
  const sources: ITopologyItem[] = list<ITopologyItem>(data && data.sources);
  if (!sources.length) { return ''; }
  const cols: string = 'minmax(220px,1.15fr) 40px minmax(210px,1fr) 40px minmax(190px,.95fr)';
  // Each card keeps its own height, so opening the source list does not
  // stretch the others; the arrows sit level with the cards' headings.
  const link: (from: string, to: string) => string = (from: string, to: string): string => '<div style="margin-top:70px">' + arrow(from, to) + '</div>';
  return '<div style="display:grid;grid-template-columns:' + cols + ';min-width:760px;align-items:start;font-size:13px;color:' + esc(theme.text) + '">' +
    sourcesCard(sources, num(data.sourceTotal), theme) + link(SRC, WSP) + workspaceCard(data, theme) + link(WSP, DST) + downstreamCard(list<ITopologyItem>(data.downstream), theme) +
    '</div>';
}

function sourcesCard(sources: ITopologyItem[], total: number, theme: IChartTheme): string {
  const max: number = Math.max(1, ...sources.map((s: ITopologyItem): number => num(s.count)));
  const rows: string[] = sources.map((s: ITopologyItem): string =>
    '<div style="padding:4px 0"><div style="display:flex;justify-content:space-between;gap:8px;font-size:12.5px">' +
    '<span style="min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="' + esc(s.name) + '">' + esc(s.name) + '</span>' +
    '<span style="flex:none;font-weight:750;font-variant-numeric:tabular-nums">' + count(num(s.count)) + '</span></div>' +
    '<div style="margin-top:3px">' + share(num(s.count), max, SRC, theme) + '</div></div>');
  return card(eyebrow('Connected sources', theme, SRC) + figure(count(total || sources.reduce((a: number, s: ITopologyItem): number => a + num(s.count), 0)), theme) +
    sub(sources.length + ' families, by sources feeding each', theme) +
    '<div style="margin-top:10px">' + showAll(rows, 10, 'families') + '</div>', theme);
}

function workspaceCard(data: ITopologyData, theme: IChartTheme): string {
  const plans: ITopologyItem[] = list<ITopologyItem>(data.plans);
  const rules: number = num(data.rules);
  const plan: (p: ITopologyItem) => string = (p: ITopologyItem): string => {
    const on: boolean = !!p.inUse;
    return '<div style="border-radius:9px;padding:7px 9px;border:1px solid ' + (on ? tint(OK, 0.35) : esc(theme.line)) + ';background:' + (on ? tint(OK, theme.dark ? 0.12 : 0.06) : 'transparent') + (on ? '' : ';opacity:.6') + '">' +
      '<div style="font-size:12px;font-weight:700">' + esc(p.name) + '</div>' +
      '<div style="font-size:11px;color:' + esc(on ? theme.text : theme.muted) + ';margin-top:1px">' + esc(on ? (str(p.detail) || 'In use') : 'Not in use') + '</div></div>';
  };
  return card(eyebrow('Sentinel workspace', theme, WSP) +
    '<div style="font-size:15px;font-weight:800;margin-top:5px">Log Analytics workspace</div>' +
    '<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin:10px 0 12px;font-size:12.5px">' +
    '<span style="padding:3px 9px;border-radius:8px;background:' + tint(WSP, 0.16) + ';font-weight:700">' + count(rules) + ' enabled analytics rules</span>' +
    '<span style="color:' + esc(theme.muted) + '">→</span><span style="padding:3px 9px;border-radius:8px;background:' + tint(WSP, 0.16) + ';font-weight:700">Incidents</span></div>' +
    eyebrow('Table plans', theme) +
    '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:6px;margin-top:6px">' + plans.map(plan).join('') + '</div>', theme, WSP);
}

function downstreamCard(items: ITopologyItem[], theme: IChartTheme): string {
  const rows: string = items.map((d: ITopologyItem): string => {
    const on: boolean = !!d.inUse;
    return '<div style="display:flex;justify-content:space-between;align-items:baseline;gap:8px;padding:7px 0;border-top:1px solid ' + esc(theme.line) + (on ? '' : ';opacity:.6') + '">' +
      '<span style="font-size:12.5px;font-weight:650">' + esc(d.name) + '</span>' +
      '<span style="flex:none;font-size:12.5px;font-weight:800;font-variant-numeric:tabular-nums;color:' + esc(on ? theme.text : NEUTRAL) + '">' + esc(on ? (str(d.detail) || 'Yes') : 'None') + '</span></div>';
  }).join('');
  return card(eyebrow('Downstream', theme, DST) + '<div style="margin-top:8px">' + rows + '</div>', theme);
}
