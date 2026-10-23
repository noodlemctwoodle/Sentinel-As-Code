import { type IRunwayData, type IRunwayItem } from './ChartTypes';
import { type IChartTheme, esc, fmtDay, isNil, list, str, tint } from './ChartKit';
import { BAD, NEUTRAL, OK, WARN, balancedColumns, card, pill } from './Visual';

// Platform retirements on a time axis: each deadline a numbered marker
// placed by its date, today marked, the past muted; then a card per
// deadline with its date, how long ago or how far off it is, and whether
// this workspace still uses what it retires.

const DAY: number = 86400000;

interface IPlaced {
  item: IRunwayItem;
  at: number;
}

export function renderRunway(data: IRunwayData, theme: IChartTheme): string {
  const today: number = Date.parse(str(data && data.today)) || Date.now();
  const items: IPlaced[] = list<IRunwayItem>(data && data.items)
    .map((i: IRunwayItem): IPlaced => ({ item: i, at: Date.parse(str(i.date)) }))
    .filter((p: IPlaced): boolean => !isNaN(p.at))
    .sort((a: IPlaced, b: IPlaced): number => a.at - b.at);
  if (!items.length) { return ''; }
  const first: number = Math.min(items[0].at, today);
  const last: number = Math.max(items[items.length - 1].at, today);
  const pad: number = Math.max(60 * DAY, (last - first) * 0.06);
  const lo: number = first - pad;
  const hi: number = last + pad;
  const x: (t: number) => number = (t: number): number => (t - lo) / (hi - lo) * 100;
  return '<div style="display:flex;flex-direction:column;gap:14px;font-size:13px;color:' + esc(theme.text) + '">' +
    axis(items, today, lo, hi, x, theme) +
    '<div style="display:grid;grid-template-columns:repeat(' + balancedColumns(items.length, 5) + ',minmax(170px,1fr));gap:10px">' +
    items.map((p: IPlaced, i: number): string => itemCard(p, i, today, theme)).join('') + '</div></div>';
}

function colourOf(p: IPlaced, today: number): string {
  if (p.at < today) { return NEUTRAL; }
  return str(p.item.state) === 'crit' ? BAD : WARN;
}

function axis(items: IPlaced[], today: number, lo: number, hi: number, x: (t: number) => number, theme: IChartTheme): string {
  let ticks: string = '';
  for (let y: number = new Date(lo).getUTCFullYear() + 1; Date.UTC(y, 0, 1) < hi; y++) {
    ticks += '<span style="position:absolute;left:' + x(Date.UTC(y, 0, 1)).toFixed(2) + '%;top:44px;transform:translateX(-50%);font-size:10.5px;color:' + esc(theme.muted) + '">' + y + '</span>' +
      '<span style="position:absolute;left:' + x(Date.UTC(y, 0, 1)).toFixed(2) + '%;top:30px;width:1px;height:8px;background:' + esc(theme.line) + '"></span>';
  }
  const tx: string = x(today).toFixed(2);
  const markers: string = items.map((p: IPlaced, i: number): string => {
    const c: string = colourOf(p, today);
    return '<span title="' + esc(str(p.item.label) + ', ' + str(p.item.date)) + '" style="position:absolute;left:' + x(p.at).toFixed(2) + '%;top:22px;transform:translate(-50%,-50%);width:22px;height:22px;border-radius:50%;' +
      'display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:800;color:#fff;background:' + c + ';box-shadow:0 0 0 3px ' + esc(theme.surface) + '">' + (i + 1) + '</span>';
  }).join('');
  return card('<div style="position:relative;height:62px;margin:0 10px">' +
    '<div style="position:absolute;left:0;right:0;top:21px;height:3px;border-radius:99px;background:linear-gradient(90deg,' + tint(NEUTRAL, 0.35) + ' ' + tx + '%,' + tint(theme.accent, 0.55) + ' ' + tx + '%)"></div>' +
    ticks +
    '<span style="position:absolute;left:' + tx + '%;top:0;bottom:16px;width:2px;background:' + esc(theme.accent) + '"></span>' +
    '<span style="position:absolute;left:' + tx + '%;top:-2px;transform:translateX(6px);font-size:10.5px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:' + esc(theme.accent) + '">Today</span>' +
    markers + '</div>', theme);
}

function itemCard(p: IPlaced, index: number, today: number, theme: IChartTheme): string {
  const c: string = colourOf(p, today);
  const days: number = Math.round((p.at - today) / DAY);
  const when: string = days < 0 ? when2(-days) + ' ago' : days === 0 ? 'Today' : 'In ' + when2(days);
  const status: string = days < 0 ? pill('Retired', NEUTRAL) : pill(str(p.item.state) === 'crit' ? 'Retiring' : 'Deprecating', c);
  const use: unknown = p.item.inUse;
  const usage: string = isNil(use) ? pill('Not readable from the workspace', NEUTRAL)
    : use ? pill('In use' + (str(p.item.evidence) ? ': ' + str(p.item.evidence) : ''), BAD) : pill('Not in use', OK);
  const date: string = fmtDay(p.at);
  return card('<div style="display:flex;align-items:center;gap:8px">' +
    '<span style="flex:none;width:20px;height:20px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:10.5px;font-weight:800;color:#fff;background:' + c + '">' + (index + 1) + '</span>' +
    '<span style="font-size:12px;font-weight:800;font-variant-numeric:tabular-nums">' + esc(date) + '</span>' +
    '<span style="font-size:11.5px;color:' + esc(theme.muted) + '">' + esc(when) + '</span></div>' +
    '<div style="font-weight:700;line-height:1.35;margin:7px 0 8px">' + esc(p.item.label) + '</div>' +
    '<div style="display:flex;flex-wrap:wrap;gap:5px">' + status + usage + '</div>', theme, days >= 0 ? c : undefined, days < 0 ? 'opacity:.85' : '');
}

function when2(days: number): string {
  if (days < 45) { return days + ' day' + (days === 1 ? '' : 's'); }
  const months: number = Math.round(days / 30.4);
  if (months < 18) { return months + ' month' + (months === 1 ? '' : 's'); }
  return (Math.round(days / 365.25 * 10) / 10) + ' years';
}
