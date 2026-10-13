import { type IChainPhase, type IChainStep, type IResponseChainData } from './ChartTypes';
import { type IChartTheme, esc, list, str, tint } from './ChartKit';
import { BAD, OK, WARN, card, eyebrow, pill } from './Visual';

// The alert-to-response chain as the target shape against this workspace:
// the phases in order, each with this workspace's figure, and its numbered
// steps; a step this workspace is missing, or has at risk, carries the
// finding that says so.

const STATE: { [state: string]: { colour: string; label: string } } = {
  ok: { colour: OK, label: 'In place' },
  missing: { colour: BAD, label: 'Missing' },
  risk: { colour: WARN, label: 'At risk' }
};

export function renderResponseChain(data: IResponseChainData, theme: IChartTheme): string {
  const phases: IChainPhase[] = list<IChainPhase>(data && data.phases).filter((p: IChainPhase): boolean => list<IChainStep>(p.steps).length > 0);
  if (!phases.length) { return ''; }
  return '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(178px,1fr));gap:12px;font-size:13px;color:' + esc(theme.text) + '">' +
    phases.map((p: IChainPhase, i: number): string => phase(p, i, theme)).join('') + '</div>';
}

function phase(p: IChainPhase, index: number, theme: IChartTheme): string {
  const steps: IChainStep[] = list<IChainStep>(p.steps);
  const worst: string = steps.some((s: IChainStep): boolean => s.state === 'missing') ? 'missing'
    : steps.some((s: IChainStep): boolean => s.state === 'risk') ? 'risk' : '';
  const head: string = '<div style="display:flex;align-items:center;gap:8px">' +
    '<span style="flex:none;font-size:10.5px;font-weight:800;color:' + esc(theme.muted) + ';font-variant-numeric:tabular-nums">' + (index + 1) + '</span>' +
    eyebrow(str(p.name), theme) + '</div>' +
    (str(p.figure) ? '<div style="font-size:13px;font-weight:750;margin:6px 0 2px">' + esc(p.figure) + '</div>' : '');
  const body: string = steps.map((s: IChainStep): string => step(s, theme)).join('');
  return card(head + '<div style="display:flex;flex-direction:column;gap:9px;margin-top:10px">' + body + '</div>', theme, worst ? STATE[worst].colour : undefined);
}

function step(s: IChainStep, theme: IChartTheme): string {
  const state: { colour: string; label: string } | undefined = STATE[str(s.state)];
  const dot: string = state && s.state !== 'ok' ? state.colour : theme.accent;
  const flag: string = state && s.state !== 'ok'
    ? '<div style="margin-top:4px">' + pill(state.label + (str(s.finding) ? ' · ' + str(s.finding) : ''), state.colour) + '</div>'
    : '';
  return '<div style="display:grid;grid-template-columns:22px minmax(0,1fr);gap:8px;align-items:start">' +
    '<span style="width:22px;height:22px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:800;' +
    'color:' + esc(dot) + ';background:' + tint(dot, theme.dark ? 0.2 : 0.12) + '">' + esc(s.n) + '</span>' +
    '<div style="min-width:0"><div style="font-weight:650;line-height:1.35">' + esc(s.action) + '</div>' +
    '<div style="font-size:11.5px;color:' + esc(theme.muted) + ';margin-top:1px">' + esc(s.actor) + (str(s.target) ? ' → ' + esc(s.target) : '') + '</div>' +
    flag + '</div></div>';
}
