import { type IChainPhase, type IChainStep, type IResponseChainData } from './ChartTypes';
import { type IChartTheme, esc, list, str, tint } from './ChartKit';
import { BAD, OK, WARN, pill } from './Visual';

// The alert-to-response chain as the target shape against this workspace: a
// rail of phases, each a glowing node with its icon and this workspace's
// figure, joined in order by gradient connectors, and under each node a spine
// of its numbered steps. A phase with a step missing or at risk takes that
// state's colour, and the step carries the finding that says so.

const STATE: { [state: string]: { colour: string; label: string } } = {
  ok: { colour: OK, label: 'In place' },
  missing: { colour: BAD, label: 'Missing' },
  risk: { colour: WARN, label: 'At risk' }
};

// Cyan through violet, in the order the chain runs.
const PHASE: string[] = ['#0891b2', '#2563eb', '#4f46e5', '#7c3aed', '#c026d3', '#0d9488'];

const GAP: number = 12;
const MIN_COL: number = 150;

const ICON: Array<[RegExp, string]> = [
  [/ingest|collect|source/i, '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v6c0 1.7 3.6 3 8 3s8-1.3 8-3V5"/><path d="M4 11v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/>'],
  [/detect|analy/i, '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/><path d="M7.5 11h2l1-2 1.5 4 1-2h1.5"/>'],
  [/automat|orchestr/i, '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>'],
  [/notif|alert|escalat/i, '<path d="M6 8a6 6 0 1 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/>'],
  [/respond|investigat|remediat/i, '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>']
];

export function renderResponseChain(data: IResponseChainData, theme: IChartTheme): string {
  const phases: IChainPhase[] = list<IChainPhase>(data && data.phases).filter((p: IChainPhase): boolean => list<IChainStep>(p.steps).length > 0);
  if (!phases.length) { return ''; }
  const colours: string[] = phases.map((p: IChainPhase, i: number): string => {
    const worst: string = worstOf(list<IChainStep>(p.steps));
    return worst ? STATE[worst].colour : PHASE[i % PHASE.length];
  });
  const n: number = phases.length;
  const grid: string = 'display:grid;grid-template-columns:repeat(' + n + ',minmax(0,1fr));column-gap:' + GAP + 'px';
  return '<div style="overflow-x:auto;font-size:13px;color:' + esc(theme.text) + '">' +
    '<div style="min-width:' + (n * MIN_COL + (n - 1) * GAP) + 'px">' +
    summary(phases, theme) +
    '<div style="' + grid + '">' + phases.map((p: IChainPhase, i: number): string => node(p, i, colours, theme)).join('') + '</div>' +
    '<div style="' + grid + ';margin-top:12px">' + phases.map((p: IChainPhase, i: number): string => column(p, colours[i], theme)).join('') + '</div>' +
    '</div></div>';
}

function worstOf(steps: IChainStep[]): string {
  return steps.some((s: IChainStep): boolean => s.state === 'missing') ? 'missing'
    : steps.some((s: IChainStep): boolean => s.state === 'risk') ? 'risk' : '';
}

// How many steps are in place, at risk and missing, as a key above the rail.
function summary(phases: IChainPhase[], theme: IChartTheme): string {
  const steps: IChainStep[] = [];
  phases.forEach((p: IChainPhase): void => { list<IChainStep>(p.steps).forEach((s: IChainStep): void => { steps.push(s); }); });
  const tally: (state: string) => number = (state: string): number =>
    steps.filter((s: IChainStep): boolean => (STATE[str(s.state)] ? str(s.state) : 'ok') === state).length;
  const item: (state: string) => string = (state: string): string => {
    const c: number = tally(state);
    if (!c && state !== 'ok') { return ''; }
    return '<span style="display:inline-flex;align-items:center;gap:6px"><span style="width:8px;height:8px;border-radius:50%;background:' + STATE[state].colour + '"></span>' +
      '<b style="font-variant-numeric:tabular-nums">' + c + '</b> ' + STATE[state].label.toLowerCase() + '</span>';
  };
  return '<div style="display:flex;flex-wrap:wrap;align-items:center;gap:6px 16px;margin-bottom:18px;font-size:12px;color:' + esc(theme.muted) + '">' +
    '<span>' + steps.length + ' steps across ' + phases.length + ' phases</span>' + item('ok') + item('risk') + item('missing') + '</div>';
}

// A phase on the rail: its node, the connector on to the next phase, and its
// name and figure.
function node(p: IChainPhase, index: number, colours: string[], theme: IChartTheme): string {
  const c: string = colours[index];
  const worst: string = worstOf(list<IChainStep>(p.steps));
  const glow: string = theme.dark
    ? '0 0 0 5px ' + tint(c, 0.12) + ',0 0 24px ' + tint(c, 0.5)
    : '0 0 0 5px ' + tint(c, 0.08) + ',0 6px 16px -6px ' + tint(c, 0.55);
  const next: string = index < colours.length - 1 ? colours[index + 1] : '';
  const link: string = next
    ? '<div style="position:absolute;top:27px;left:50%;width:calc(100% + ' + GAP + 'px);height:3px;border-radius:99px;background:linear-gradient(90deg,' + c + ',' + next + ')">' +
      '<span style="position:absolute;left:50%;top:50%;width:7px;height:7px;border-top:2px solid ' + next + ';border-right:2px solid ' + next + ';transform:translate(-70%,-50%) rotate(45deg)"></span></div>'
    : '';
  const icon: [RegExp, string] | undefined = ICON.filter((x: [RegExp, string]): boolean => x[0].test(str(p.name)))[0];
  const mark: string = icon
    ? '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + icon[1] + '</svg>'
    : '<span style="font-size:15px;font-weight:800;color:' + c + '">' + (index + 1) + '</span>';
  const badge: string = worst
    ? '<span title="' + esc(STATE[worst].label) + '" style="position:absolute;top:-3px;right:-3px;width:17px;height:17px;border-radius:50%;display:flex;align-items:center;justify-content:center;' +
      'font-size:11px;font-weight:900;color:#fff;background:' + STATE[worst].colour + ';box-shadow:0 0 0 2px ' + esc(theme.surface) + '">!</span>'
    : '';
  return '<div style="position:relative;min-width:0;text-align:center">' + link +
    '<div style="position:relative;width:56px;height:56px;margin:0 auto;border-radius:50%;display:flex;align-items:center;justify-content:center;' +
    'border:2px solid ' + c + ';background-color:' + esc(theme.surface) + ';background-image:linear-gradient(' + tint(c, theme.dark ? 0.22 : 0.1) + ',' + tint(c, theme.dark ? 0.22 : 0.1) + ');box-shadow:' + glow + '">' +
    mark + badge + '</div>' +
    '<div style="margin-top:12px;font-size:10.5px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;color:' + c + '">' + (index + 1) + ' · ' + esc(p.name) + '</div>' +
    (str(p.figure) ? '<div style="margin-top:3px;font-size:13px;font-weight:750;line-height:1.3">' + esc(p.figure) + '</div>' : '') +
    '</div>';
}

// A phase's steps on a spine in the phase's colour.
function column(p: IChainPhase, c: string, theme: IChartTheme): string {
  const steps: IChainStep[] = list<IChainStep>(p.steps);
  return '<div style="position:relative;min-width:0;padding:14px 12px 12px;border-radius:14px;background:' + tint(c, theme.dark ? 0.08 : 0.04) + '">' +
    '<div style="position:absolute;left:23px;top:24px;bottom:24px;width:2px;border-radius:2px;background:linear-gradient(' + tint(c, 0.5) + ',' + tint(c, 0.08) + ')"></div>' +
    '<div style="position:relative;display:flex;flex-direction:column;gap:12px">' + steps.map((s: IChainStep): string => step(s, c, theme)).join('') + '</div></div>';
}

function step(s: IChainStep, phaseColour: string, theme: IChartTheme): string {
  const state: { colour: string; label: string } | undefined = s.state !== 'ok' ? STATE[str(s.state)] : undefined;
  const dot: string = state ? state.colour : phaseColour;
  const flag: string = state ? '<div style="margin-top:5px">' + pill(state.label + (str(s.finding) ? ' · ' + str(s.finding) : ''), state.colour) + '</div>' : '';
  return '<div style="display:grid;grid-template-columns:24px minmax(0,1fr);gap:9px;align-items:start">' +
    '<span style="width:24px;height:24px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:800;line-height:1;' +
    'color:' + (state ? '#fff' : dot) + ';background-color:' + esc(theme.surface) + ';background-image:linear-gradient(' + (state ? dot : tint(dot, theme.dark ? 0.25 : 0.14)) + ',' + (state ? dot : tint(dot, theme.dark ? 0.25 : 0.14)) + ');' +
    'box-shadow:0 0 0 1.5px ' + tint(dot, 0.55) + '">' + esc(s.n) + '</span>' +
    '<div style="min-width:0"><div style="font-weight:650;line-height:1.35">' + esc(s.action) + '</div>' +
    '<div style="font-size:11.5px;color:' + esc(theme.muted) + ';margin-top:2px;line-height:1.35">' + esc(s.actor) + (str(s.target) ? ' → ' + esc(s.target) : '') + '</div>' +
    flag + '</div></div>';
}
