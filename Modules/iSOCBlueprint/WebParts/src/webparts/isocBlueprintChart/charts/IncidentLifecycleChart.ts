import { type IIncidentLifecycleData, type ILifecycleCount } from './ChartTypes';
import { type IChartTheme, colourFor, esc, isNil, list, num, str, tint } from './ChartKit';

// The incident lifecycle: the window's incidents at their current status
// (New, Active, Closed) as stage tiles, the two ways a closed incident got
// there (acknowledged first, or closed straight from New, which SAC-INC-05
// checks), and how the open ones split by severity and the closed ones by
// classification and by who closed them. A figure the capture lacks is
// left out rather than shown as zero.

const STAGE: { [id: string]: string } = { new: '#d97706', active: '#2563eb', closed: '#0d9488' };
const CLOSER: { [key: string]: string } = { automationrule: '#7c3aed', analyst: '#2563eb', defenderxdr: '#0891b2', other: '#64748b' };

export function renderIncidentLifecycle(data: IIncidentLifecycleData, theme: IChartTheme): string {
  if (!data || isNil(data.raised)) { return ''; }
  const raised: number = num(data.raised);
  const days: number = num(data.days) || 30;
  if (raised <= 0) {
    return '<p style="margin:0;color:' + esc(theme.muted) + '">No incidents were raised in the last ' + days + ' days.</p>';
  }
  return '<div style="display:flex;flex-direction:column;gap:16px;font-size:13px;color:' + esc(theme.text) + '">' +
    pipeline(data, theme, raised, days) +
    '<p style="margin:0;font-size:12px;color:' + esc(theme.muted) + '">Each stage shows where the last ' + days + ' days\' incidents are now; the arrows show how the closed ones got there.</p>' +
    breakdowns(data, theme) +
    '</div>';
}

function pipeline(data: IIncidentLifecycleData, theme: IChartTheme, raised: number, days: number): string {
  const closed: number | undefined = opt(data.closed);
  const ack: number | undefined = opt(data.acknowledged);
  const unack: number | undefined = opt(data.unacknowledged);
  const mtta: number | undefined = opt(data.mttaMinutes);
  const mttr: number | undefined = opt(data.mttrMinutes);
  const unified: number | undefined = opt(data.unified);
  const cols: string = 'minmax(118px,1fr) 52px minmax(118px,1fr) 108px minmax(118px,1fr) 92px minmax(118px,1fr)';
  let out: string = '<div style="display:grid;grid-template-columns:' + cols + ';min-width:700px;padding-bottom:' + (isNil(unack) ? '0' : '16px') + '">' +
    tile('Raised', theme.accent, raised, 'in the last ' + days + ' days', undefined, isNil(unified) ? '' : count(unified as number) + ' through Defender XDR', theme) +
    arrow(theme.accent, STAGE.new, '', '', theme) +
    tile('New', STAGE.new, opt(data.new), 'waiting, not yet acknowledged', raised, '', theme) +
    arrow(STAGE.new, STAGE.active, 'Acknowledged', isNil(mtta) ? '' : 'MTTA ' + duration(mtta as number), theme) +
    tile('Active', STAGE.active, opt(data.active), 'being investigated', raised, '', theme) +
    arrow(STAGE.active, STAGE.closed, 'Resolved', isNil(ack) ? '' : count(ack as number) + ' closed', theme) +
    tile('Closed', STAGE.closed, closed, isNil(closed) ? '' : pct(closed as number, raised) + ' of raised', raised, isNil(mttr) ? '' : 'MTTR ' + duration(mttr as number), theme);
  if (!isNil(unack)) { out += bypass(unack as number, closed, !!(data.check && data.check.fired), str(data.check && data.check.id), theme); }
  return out + '</div>';
}

function tile(label: string, colour: string, value: number | undefined, sub: string, of: number | undefined, foot: string, theme: IChartTheme): string {
  const share: string = isNil(value) || isNil(of) || !of ? '' :
    '<div style="margin-top:10px;height:4px;border-radius:99px;background:' + tint(colour, 0.2) + '"><div style="height:100%;border-radius:99px;width:' +
    Math.min(100, (value as number) / (of as number) * 100).toFixed(1) + '%;background:' + esc(colour) + '"></div></div>';
  return '<div style="min-width:0;border:1px solid ' + tint(colour, 0.38) + ';border-radius:14px;padding:12px 14px;background:' + tint(colour, theme.dark ? 0.13 : 0.06) + '">' +
    '<div style="font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:' + esc(colour) + '">' + esc(label) + '</div>' +
    '<div style="font-size:28px;font-weight:800;line-height:1.15;margin-top:6px;font-variant-numeric:tabular-nums">' + (isNil(value) ? '<span style="color:' + esc(theme.muted) + '">n/a</span>' : count(value as number)) + '</div>' +
    (sub ? '<div style="font-size:12px;color:' + esc(theme.muted) + ';margin-top:2px">' + esc(sub) + '</div>' : '') +
    share +
    (foot ? '<div style="font-size:11.5px;font-weight:650;margin-top:8px;color:' + esc(theme.text) + '">' + esc(foot) + '</div>' : '') +
    '</div>';
}

// A connector between two tiles, shaded from one stage's colour to the
// next, with what happens on it above and a figure below.
function arrow(from: string, to: string, above: string, below: string, theme: IChartTheme): string {
  const small: string = 'font-size:11px;line-height:1.3;color:' + esc(theme.muted) + ';text-align:center;min-height:15px';
  return '<div style="display:flex;flex-direction:column;justify-content:center;gap:5px;padding:0 6px">' +
    '<div style="' + small + ';font-weight:700">' + esc(above) + '</div>' +
    '<div style="position:relative;height:2px;margin-right:6px;background:linear-gradient(90deg,' + esc(from) + ',' + esc(to) + ')">' +
    '<span style="position:absolute;right:-7px;top:-4px;border-left:8px solid ' + esc(to) + ';border-top:5px solid transparent;border-bottom:5px solid transparent"></span></div>' +
    '<div style="' + small + ';font-weight:650;color:' + esc(theme.text) + '">' + esc(below) + '</div>' +
    '</div>';
}

// The path from New straight to Closed, under the tiles: dashed, red with
// the check's id when the check fired, faint when nothing took it.
function bypass(unack: number, closed: number | undefined, fired: boolean, checkId: string, theme: IChartTheme): string {
  const colour: string = unack <= 0 ? theme.line : fired ? '#dc2626' : '#d97706';
  const line: string = '2px dashed ' + esc(colour);
  const share: string = isNil(closed) || !closed ? '' : ' (' + pct(unack, closed as number) + ' of closed)';
  const text: string = unack <= 0 ? 'None closed without acknowledgement' : count(unack) + ' closed without acknowledgement' + share;
  const badge: string = fired && checkId
    ? '<span style="margin-left:8px;padding:1px 7px;border-radius:5px;background:#dc2626;color:#fff;font-weight:800;font-size:10.5px">' + esc(checkId) + '</span>' : '';
  return '<div style="grid-column:3;height:26px;margin-left:50%;border-left:' + line + ';border-bottom:' + line + ';border-bottom-left-radius:14px"></div>' +
    '<div style="grid-column:4 / 7;height:26px;border-bottom:' + line + ';position:relative">' +
    '<span style="position:absolute;left:50%;bottom:-13px;transform:translateX(-50%);white-space:nowrap;padding:3px 10px;border-radius:99px;font-size:11.5px;font-weight:700;' +
    'border:1px solid ' + esc(colour) + ';background:' + esc(theme.surface) + ';color:' + esc(unack <= 0 ? theme.muted : theme.text) + '">' + esc(text) + badge + '</span></div>' +
    '<div style="grid-column:7;height:26px;margin-right:50%;border-right:' + line + ';border-bottom:' + line + ';border-bottom-right-radius:14px;position:relative">' +
    '<span style="position:absolute;right:-6px;top:-1px;border-bottom:8px solid ' + esc(colour) + ';border-left:5px solid transparent;border-right:5px solid transparent"></span></div>';
}

function breakdowns(data: IIncidentLifecycleData, theme: IChartTheme): string {
  const open: number = num(data.new) + num(data.active);
  const panels: string[] = [
    panel('Open now, by severity', list<ILifecycleCount>(data.openBySeverity), (l: string, i: number): string => colourFor(l, i),
      isNil(data.new) && isNil(data.active) ? 'Not captured in this snapshot.' : open <= 0 ? 'No incidents are open.' : 'Not captured in this snapshot.', theme),
    panel('Closed, by classification', list<ILifecycleCount>(data.classification), (l: string, i: number): string => colourFor(l, i), 'Not captured in this snapshot.', theme),
    panel('Closed by', list<ILifecycleCount>(data.closedBy), (l: string, i: number): string => CLOSER[l.toLowerCase().replace(/[^a-z]/g, '')] || colourFor(l, i), 'Not captured in this snapshot.', theme)
  ];
  return '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px">' + panels.join('') + '</div>';
}

// One breakdown: a stacked bar and a legend row per part with its count and
// share.
function panel(title: string, parts: ILifecycleCount[], colour: (label: string, i: number) => string, empty: string, theme: IChartTheme): string {
  const rows: ILifecycleCount[] = parts.filter((p: ILifecycleCount): boolean => num(p.count) > 0);
  const total: number = rows.reduce((s: number, p: ILifecycleCount): number => s + num(p.count), 0);
  let body: string;
  if (!total) {
    body = '<p style="margin:8px 0 0;font-size:12px;font-style:italic;color:' + esc(theme.muted) + '">' + esc(empty) + '</p>';
  } else {
    body = '<div style="display:flex;height:10px;border-radius:99px;overflow:hidden;margin:10px 0 10px;gap:2px">' +
      rows.map((p: ILifecycleCount, i: number): string => '<span title="' + esc(str(p.label) + ': ' + count(num(p.count))) + '" style="flex:' + num(p.count) + ' 1 0;min-width:3px;background:' + esc(colour(str(p.label), i)) + '"></span>').join('') +
      '</div>' +
      rows.map((p: ILifecycleCount, i: number): string =>
        '<div style="display:grid;grid-template-columns:10px minmax(0,1fr) auto 42px;gap:8px;align-items:center;font-size:12px;padding:2px 0">' +
        '<span style="width:10px;height:10px;border-radius:3px;background:' + esc(colour(str(p.label), i)) + '"></span>' +
        '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(p.label) + '</span>' +
        '<span style="font-weight:700;font-variant-numeric:tabular-nums">' + count(num(p.count)) + '</span>' +
        '<span style="text-align:right;color:' + esc(theme.muted) + ';font-variant-numeric:tabular-nums">' + pct(num(p.count), total) + '</span></div>').join('');
  }
  return '<div style="min-width:0;border:1px solid ' + esc(theme.line) + ';border-radius:12px;padding:11px 14px 12px">' +
    '<div style="font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:' + esc(theme.muted) + '">' + esc(title) + '</div>' +
    body + '</div>';
}

function opt(value: unknown): number | undefined {
  return isNil(value) || str(value) === '' ? undefined : num(value);
}

function count(n: number): string {
  return Math.round(n).toLocaleString('en-GB');
}

function pct(part: number, whole: number): string {
  return whole > 0 ? Math.round(part / whole * 100) + '%' : '0%';
}

// Minutes as the dashboard writes them: 45m, 3h 20m, 1d 11h.
export function duration(minutes: number): string {
  const m: number = Math.round(minutes);
  if (m < 1) { return '< 1m'; }
  if (m < 60) { return m + 'm'; }
  if (m < 1440) { return Math.floor(m / 60) + 'h' + (m % 60 ? ' ' + (m % 60) + 'm' : ''); }
  let d: number = Math.floor(m / 1440);
  let h: number = Math.round((m % 1440) / 60);
  if (h === 24) { d += 1; h = 0; }
  return d + 'd' + (h ? ' ' + h + 'h' : '');
}
