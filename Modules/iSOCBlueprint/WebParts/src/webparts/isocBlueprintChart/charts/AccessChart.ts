import { type IAccessBand, type IAccessData, type IAccessRole } from './ChartTypes';
import { type IChartTheme, esc, list, num, str } from './ChartKit';
import { BAD, INFO, NEUTRAL, OK, type IPart, card, count, eyebrow, meter, pill, showAll } from './Visual';

// Who holds which role at workspace scope: the roles in bands (broad
// roles first, then the Microsoft Sentinel roles, then Log Analytics and
// monitoring, then the rest), each role with how many users, groups and
// service principals hold it. A band a fired finding speaks to carries it.

const TONE: { [tone: string]: string } = { bad: BAD, ok: OK, info: INFO, neutral: NEUTRAL };
const USER: string = '#2563eb';
const GROUP: string = '#7c3aed';
const SP: string = '#0d9488';

export function renderAccess(data: IAccessData, theme: IChartTheme): string {
  const bands: IAccessBand[] = list<IAccessBand>(data && data.bands).filter((b: IAccessBand): boolean => list<IAccessRole>(b.roles).length > 0);
  if (!bands.length) { return ''; }
  const max: number = Math.max(1, ...bands.map((b: IAccessBand): number => Math.max(...list<IAccessRole>(b.roles).map(total))));
  const key: string = '<div style="display:flex;flex-wrap:wrap;gap:14px;font-size:12px;color:' + esc(theme.muted) + '">' +
    [['Users', USER], ['Groups', GROUP], ['Service principals', SP]].map((k: string[]): string =>
      '<span style="display:inline-flex;align-items:center;gap:6px"><span style="width:10px;height:10px;border-radius:3px;background:' + k[1] + '"></span>' + k[0] + '</span>').join('') + '</div>';
  return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + esc(theme.text) + '">' + key +
    '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(380px,1fr));gap:12px">' +
    bands.map((b: IAccessBand): string => band(b, max, theme)).join('') + '</div></div>';
}

function total(r: IAccessRole): number {
  return num(r.users) + num(r.groups) + num(r.servicePrincipals);
}

function band(b: IAccessBand, max: number, theme: IChartTheme): string {
  const colour: string = TONE[str(b.tone)] || NEUTRAL;
  const roles: IAccessRole[] = list<IAccessRole>(b.roles);
  const sum: number = roles.reduce((a: number, r: IAccessRole): number => a + total(r), 0);
  const findings: string = list<unknown>(b.findings).map((f: unknown): string => pill(str(f), BAD)).join(' ');
  const head: string = '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap">' +
    '<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">' + eyebrow(str(b.name), theme, colour) + findings + '</div>' +
    '<span style="font-size:12px;color:' + esc(theme.muted) + '">' + count(sum) + ' assignment' + (sum === 1 ? '' : 's') + '</span></div>';
  const rows: string[] = roles.map((r: IAccessRole): string => {
    const parts: IPart[] = [
      { label: 'Users', value: num(r.users), colour: USER },
      { label: 'Groups', value: num(r.groups), colour: GROUP },
      { label: 'Service principals', value: num(r.servicePrincipals), colour: SP }
    ];
    const t: number = total(r);
    const detail: string = parts.filter((p: IPart): boolean => p.value > 0).map((p: IPart): string => count(p.value) + ' ' + p.label.toLowerCase()).join(', ');
    return '<div style="display:grid;grid-template-columns:minmax(150px,1.8fr) minmax(80px,1.3fr) 34px;gap:10px;align-items:center;padding:5px 0" title="' + esc(str(r.role) + ': ' + detail) + '">' +
      '<span style="font-size:12.5px;font-weight:650;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(r.role) + '</span>' +
      '<div style="width:' + (t / max * 100).toFixed(1) + '%;min-width:6px">' + meter(parts, theme, 8) + '</div>' +
      '<span style="text-align:right;font-weight:800;font-variant-numeric:tabular-nums">' + count(t) + '</span></div>';
  });
  return card(head + '<div style="margin-top:8px">' + showAll(rows, 8, 'roles') + '</div>', theme, str(b.tone) === 'bad' || str(b.tone) === 'ok' ? colour : undefined);
}
