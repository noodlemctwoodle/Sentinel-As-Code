import { type IGanttData, type IGanttTask } from './ChartTypes';
import { type IChartTheme, esc, list, r, rect, str, svgDoc, svgText, textWidth, widest, wrapText } from './ChartKit';

interface ITask {
  label: string;
  tags: string[];
  from: number;
  to: number;
  date: number;
  milestone: boolean;
}

interface IRow {
  heading?: string;
  task?: ITask;
}

const DAY: number = 86400000;
const MONTHS: string[] = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const ROW: number = 26;
const PLOT_W: number = 560;
// Room after the axis for the date beside a bar that ends near it.
const DATE_W: number = 84;

// Tasks on a date axis, by section. A task's length may be negative (a
// deadline already passed); the bar then runs back from its start. Each
// bar is labelled with the date it marks.
export function renderGantt(data: IGanttData, theme: IChartTheme, label: string): string {
  const rows: IRow[] = [];
  const ends: { [id: string]: number } = {};
  let previous: number = NaN;
  list<{ name: string; tasks: IGanttTask[] }>(data && data.sections).forEach((s: { name: string; tasks: IGanttTask[] }): void => {
    if (str(s.name)) { rows.push({ heading: str(s.name) }); }
    list<IGanttTask>(s.tasks).forEach((t: IGanttTask): void => {
      const start: number = startOf(str(t.start), ends, previous);
      if (isNaN(start)) { return; }
      const days: number = lengthInDays(str(t.length));
      const end: number = start + days * DAY;
      const tags: string[] = list<unknown>(t.tags).map(str);
      const task: ITask = {
        label: str(t.label), tags: tags, from: Math.min(start, end), to: Math.max(start, end),
        date: days >= 0 && days <= 1 ? start : end,
        milestone: tags.indexOf('milestone') >= 0 || days === 0
      };
      if (str(t.id)) { ends[str(t.id)] = Math.max(start, end); }
      previous = Math.max(start, end);
      rows.push({ task: task });
    });
  });
  const tasks: ITask[] = rows.filter((x: IRow): boolean => !!x.task).map((x: IRow): ITask => x.task as ITask);
  if (!tasks.length) { return ''; }

  let lo: number = Math.min(...tasks.map((t: ITask): number => t.from));
  let hi: number = Math.max(...tasks.map((t: ITask): number => t.to));
  if (hi - lo < 30 * DAY) { lo -= 15 * DAY; hi += 15 * DAY; }
  const pad: number = (hi - lo) * 0.04;
  lo -= pad;
  hi += pad;

  const labelW: number = Math.min(260, widest(tasks.map((t: ITask): string => t.label), 12)) + 14;
  const top: number = 26;
  const x: (t: number) => number = (t: number): number => labelW + ((t - lo) / (hi - lo)) * PLOT_W;
  const height: number = top + rows.length * ROW + 8;

  let body: string = '';
  ticks(lo, hi).forEach((t: number): void => {
    body += '<line x1="' + r(x(t)) + '" y1="' + (top - 6) + '" x2="' + r(x(t)) + '" y2="' + r(height - 8) + '" stroke="' + esc(theme.line) + '"/>';
    body += svgText(x(t), 10, [formatAxis(t, str(data.axisFormat))], { size: 11, fill: theme.muted, anchor: 'middle' });
  });
  rows.forEach((row: IRow, i: number): void => {
    const y: number = top + i * ROW;
    if (row.heading) {
      body += svgText(0, y + ROW / 2, [row.heading.toUpperCase()], { size: 11, weight: 600, fill: theme.muted });
      return;
    }
    const t: ITask = row.task as ITask;
    const colour: string = t.tags.indexOf('crit') >= 0 ? '#dc2626' : t.tags.indexOf('done') >= 0 ? '#94a3b8' : theme.accent;
    body += svgText(labelW - 12, y + ROW / 2, wrapText(t.label, labelW - 14, 12).slice(0, 1), { size: 12, fill: theme.text, anchor: 'end' });
    const tip: string = '<title>' + esc(t.label + ': ' + formatDay(t.date)) + '</title>';
    let right: number;
    if (t.milestone) {
      const cx: number = x(t.date);
      const cy: number = y + ROW / 2;
      body += '<path d="M' + r(cx) + ',' + r(cy - 7) + ' L' + r(cx + 7) + ',' + r(cy) + ' L' + r(cx) + ',' + r(cy + 7) + ' L' + r(cx - 7) + ',' + r(cy) + ' Z" fill="' + esc(colour) + '">' + tip + '</path>';
      right = cx + 8;
    } else {
      const x0: number = x(t.from);
      const w: number = Math.max(4, x(t.to) - x0);
      body += rect(x0, y + 6, w, ROW - 12, 'rx="4" fill="' + esc(colour) + '"' + (t.tags.indexOf('active') >= 0 ? '' : ' fill-opacity="0.85"')).replace('/>', '>' + tip + '</rect>');
      right = x0 + w;
    }
    const text: string = formatDay(t.date);
    const fits: boolean = right + 6 + textWidth(text, 11) <= labelW + PLOT_W + DATE_W;
    body += svgText(fits ? right + 6 : (t.milestone ? x(t.date) - 9 : x(t.from) - 6), y + ROW / 2, [text],
      { size: 11, fill: theme.muted, anchor: fits ? 'start' : 'end' });
  });
  return svgDoc(labelW + PLOT_W + DATE_W, height, label, body);
}

function parseDay(text: string): number {
  const m: RegExpExecArray | null = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text.trim());
  if (m) { return Date.UTC(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10)); }
  const t: number = Date.parse(text);
  return isNaN(t) ? NaN : t;
}

// A start is a date, 'after id ...' (the latest end of those tasks), or
// absent (straight after the previous task).
function startOf(text: string, ends: { [id: string]: number }, previous: number): number {
  const after: RegExpExecArray | null = /^after\s+(.+)$/i.exec(text.trim());
  if (after) {
    const known: number[] = after[1].split(/\s+/).filter((id: string): boolean => ends[id] !== undefined).map((id: string): number => ends[id]);
    return known.length ? Math.max(...known) : previous;
  }
  return text.trim() ? parseDay(text) : previous;
}

function lengthInDays(text: string): number {
  const m: RegExpExecArray | null = /^(-?\d+(?:\.\d+)?)\s*(ms|s|m|h|d|w|M|y)?$/.exec(text.trim());
  if (!m) { return 1; }
  const n: number = parseFloat(m[1]);
  const per: { [unit: string]: number } = { ms: 1 / DAY, s: 1 / 86400, m: 1 / 1440, h: 1 / 24, d: 1, w: 7, M: 30, y: 365 };
  return n * (per[m[2] || 'd'] || 1);
}

// First-of-month ticks, every one to 24 months, about eight in all.
function ticks(lo: number, hi: number): number[] {
  const months: number = (hi - lo) / (30 * DAY);
  const steps: number[] = [1, 2, 3, 6, 12, 24];
  let step: number = steps[steps.length - 1];
  for (const s of steps) { if (months / s <= 8) { step = s; break; } }
  const d: Date = new Date(lo);
  let y: number = d.getUTCFullYear();
  let m: number = d.getUTCMonth() + 1;
  const out: number[] = [];
  for (let guard: number = 0; guard < 200; guard++) {
    if (m > 11) { y += Math.floor(m / 12); m = m % 12; }
    const t: number = Date.UTC(y, m, 1);
    if (t > hi) { break; }
    if (step < 12 ? m % step === 0 : m === 0 && y % (step / 12) === 0) { out.push(t); }
    m++;
  }
  return out;
}

function formatDay(t: number): string {
  const d: Date = new Date(t);
  return d.getUTCDate() + ' ' + MONTHS[d.getUTCMonth()] + ' ' + d.getUTCFullYear();
}

// The few strftime codes Mermaid axis formats use.
function formatAxis(t: number, format: string): string {
  const d: Date = new Date(t);
  const f: string = format || '%b %Y';
  return f.replace(/%([YymbBde])/g, (_m: string, c: string): string => {
    switch (c) {
      case 'Y': return String(d.getUTCFullYear());
      case 'y': return String(d.getUTCFullYear()).substring(2);
      case 'm': return ('0' + (d.getUTCMonth() + 1)).slice(-2);
      case 'b': return MONTHS[d.getUTCMonth()];
      case 'B': return MONTHS[d.getUTCMonth()];
      case 'd': return ('0' + d.getUTCDate()).slice(-2);
      default: return String(d.getUTCDate());
    }
  });
}
