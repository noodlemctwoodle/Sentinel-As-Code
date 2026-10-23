import { type IJourneyData } from './ChartTypes';
import { type IChartTheme, esc, list, nextId, num, str, tint } from './ChartKit';

interface IJourneyTask {
  label: string;
  score: number;
  actors?: string[];
}

interface IJourneySection {
  name: string;
  tasks: IJourneyTask[];
}

interface IStep {
  task: IJourneyTask;
  score: number;
}

// A user journey as a journey map: the stages across the top, one column
// per step, and a curve through the steps' scores (5 at the top, smooth;
// 1 at the bottom, friction), so the pain points read as the dips. Each
// point carries its score; the step and who does it sit underneath.
const STEP_MIN: number = 88;
const GUTTER: number = 62;
const PLOT: number = 150;
const PAD: number = 18;

export function renderJourney(data: IJourneyData, theme: IChartTheme): string {
  const sections: IJourneySection[] = list<IJourneySection>(data && data.sections)
    .filter((s: IJourneySection): boolean => list<IJourneyTask>(s.tasks).length > 0);
  const steps: IStep[] = [];
  sections.forEach((s: IJourneySection): void => {
    list<IJourneyTask>(s.tasks).forEach((t: IJourneyTask): void => {
      steps.push({ task: t, score: Math.max(1, Math.min(5, Math.round(num(t.score)))) });
    });
  });
  if (!steps.length) { return ''; }
  const n: number = steps.length;
  const cols: string = 'repeat(' + n + ',minmax(' + STEP_MIN + 'px,1fr))';
  return '<div style="min-width:' + (n * STEP_MIN + GUTTER) + 'px;padding-left:' + GUTTER + 'px;font-size:12.5px;color:' + esc(theme.text) + '">' +
    stages(sections, cols, theme) + plot(steps, sections, theme) + labels(steps, cols, theme) + '</div>';
}

// Each stage's name over its steps, on a soft chip with a hairline under it
// to the stage's edges.
function stages(sections: IJourneySection[], cols: string, theme: IChartTheme): string {
  return '<div style="display:grid;grid-template-columns:' + cols + '">' +
    sections.map((s: IJourneySection): string =>
      '<div style="grid-column:span ' + list<IJourneyTask>(s.tasks).length + ';min-width:0;margin:0 4px;text-align:center;padding-bottom:7px;border-bottom:1px solid ' + esc(theme.line) + '">' +
      '<span style="display:inline-block;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;padding:3px 10px;border-radius:99px;font-size:10.5px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;' +
      'color:' + esc(theme.muted) + ';background:' + tint(theme.accent, theme.dark ? 0.16 : 0.08) + '">' + esc(s.name) + '</span></div>').join('') +
    '</div>';
}

// The curve and its points. The line is drawn in a stretched SVG so it
// spans the columns exactly; the points are HTML on top, so they stay round.
function plot(steps: IStep[], sections: IJourneySection[], theme: IChartTheme): string {
  const n: number = steps.length;
  const w: number = n * 100;
  const y: (score: number) => number = (s: number): number => PAD + (5 - s) / 4 * (PLOT - 2 * PAD);
  const pts: number[][] = steps.map((s: IStep, i: number): number[] => [i * 100 + 50, y(s.score)]);
  let curve: string = 'M' + pts[0][0] + ' ' + pts[0][1];
  for (let i: number = 1; i < pts.length; i++) {
    const mid: number = (pts[i - 1][0] + pts[i][0]) / 2;
    curve += ' C' + mid + ' ' + pts[i - 1][1] + ' ' + mid + ' ' + pts[i][1] + ' ' + pts[i][0] + ' ' + pts[i][1];
  }
  const area: string = curve + ' L' + pts[pts.length - 1][0] + ' ' + PLOT + ' L' + pts[0][0] + ' ' + PLOT + ' Z';
  const grad: string = nextId('journey');
  let guides: string = '';
  for (let s: number = 1; s <= 5; s++) {
    guides += '<line x1="0" x2="' + w + '" y1="' + y(s) + '" y2="' + y(s) + '" stroke="' + esc(theme.line) + '" stroke-dasharray="3 4" vector-effect="non-scaling-stroke"/>';
  }
  let x: number = 0;
  sections.slice(0, -1).forEach((sec: IJourneySection): void => {
    x += list<IJourneyTask>(sec.tasks).length * 100;
    guides += '<line x1="' + x + '" x2="' + x + '" y1="0" y2="' + PLOT + '" stroke="' + esc(theme.line) + '" vector-effect="non-scaling-stroke"/>';
  });
  const bandH: number = y(4) - y(5) + PAD;
  const svg: string = '<svg viewBox="0 0 ' + w + ' ' + PLOT + '" preserveAspectRatio="none" aria-hidden="true" style="position:absolute;inset:0;width:100%;height:100%;overflow:visible">' +
    '<defs><linearGradient id="' + grad + '" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + esc(theme.accent) + '" stop-opacity="' + (theme.dark ? 0.32 : 0.2) + '"/>' +
    '<stop offset="1" stop-color="' + esc(theme.accent) + '" stop-opacity="0"/></linearGradient></defs>' +
    '<rect x="0" y="0" width="' + w + '" height="' + bandH + '" fill="#16a34a" fill-opacity="' + (theme.dark ? 0.07 : 0.05) + '"/>' +
    '<rect x="0" y="' + (PLOT - bandH) + '" width="' + w + '" height="' + bandH + '" fill="#dc2626" fill-opacity="' + (theme.dark ? 0.08 : 0.05) + '"/>' +
    guides +
    '<path d="' + area + '" fill="url(#' + grad + ')"/>' +
    '<path d="' + curve + '" fill="none" stroke="' + esc(theme.accent) + '" stroke-width="2.5" stroke-linecap="round" vector-effect="non-scaling-stroke"/>' +
    '</svg>';
  const zone: (text: string, top: boolean) => string = (text: string, top: boolean): string =>
    '<span style="position:absolute;left:-' + GUTTER + 'px;width:' + (GUTTER - 10) + 'px;text-align:right;' + (top ? 'top:6px' : 'bottom:6px') + ';font-size:9.5px;font-weight:800;letter-spacing:.12em;text-transform:uppercase;color:' + esc(top ? '#16a34a' : '#dc2626') + '">' + text + '</span>';
  const dots: string = steps.map((s: IStep, i: number): string => {
    const colour: string = scoreColour(s.score);
    return '<span role="img" aria-label="' + esc(str(s.task.label) + ': score ' + s.score + ' of 5') + '" title="' + esc(str(s.task.label) + ': ' + s.score + ' of 5') + '" style="position:absolute;left:' +
      ((i + 0.5) / n * 100).toFixed(3) + '%;top:' + (y(s.score) / PLOT * 100).toFixed(3) + '%;transform:translate(-50%,-50%);width:24px;height:24px;border-radius:50%;' +
      'display:flex;align-items:center;justify-content:center;font-size:11.5px;font-weight:800;color:#fff;background:' + colour + ';box-shadow:0 0 0 3px ' + esc(theme.surface) + ',0 0 0 4px ' + tint(colour, 0.45) + '">' + s.score + '</span>';
  }).join('');
  return '<div style="position:relative;height:' + PLOT + 'px;margin:14px 0 10px">' + svg + zone('Smooth', true) + zone('Friction', false) + dots + '</div>';
}

function labels(steps: IStep[], cols: string, theme: IChartTheme): string {
  return '<div style="display:grid;grid-template-columns:' + cols + '">' +
    steps.map((s: IStep): string => {
      const actors: string[] = list<unknown>(s.task.actors).map((a: unknown): string => str(a)).filter((a: string): boolean => !!a);
      return '<div style="min-width:0;text-align:center;padding:0 4px">' +
        '<div style="font-weight:700;line-height:1.3;color:' + esc(s.score <= 2 ? scoreColour(s.score) : theme.text) + '">' + esc(s.task.label) + '</div>' +
        (actors.length ? '<div style="margin-top:3px;font-size:11.5px;color:' + esc(theme.muted) + '">' + actors.map((a: string): string => esc(a)).join(', ') + '</div>' : '') +
        '</div>';
    }).join('') +
    '</div>';
}

function scoreColour(score: number): string {
  return score >= 4 ? '#16a34a' : score === 3 ? '#d97706' : '#dc2626';
}
