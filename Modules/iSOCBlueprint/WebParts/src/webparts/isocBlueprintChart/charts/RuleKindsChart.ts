import { type IRuleKind, type IRuleKindsData } from './ChartTypes';
import { type IChartTheme, esc, list, num, str } from './ChartKit';
import { INFO, WARN, balancedColumns, card, chip, count, eyebrow, figure, pill, share, sub } from './Visual';

// The analytics rule kinds: what every rule carries, then one card per
// kind with how many this workspace has deployed and enabled, what the
// kind does and the settings only it has. A kind with none deployed is
// shown faded, so the reader sees what is not in use as well.

const COLOUR: { [kind: string]: string } = {
  Scheduled: INFO, NRT: '#0d9488', Fusion: '#7c3aed', MicrosoftSecurityIncidentCreation: WARN,
  ThreatIntelligence: '#0891b2', MLBehaviorAnalytics: '#db2777'
};

export function renderRuleKinds(data: IRuleKindsData, theme: IChartTheme): string {
  const kinds: IRuleKind[] = list<IRuleKind>(data && data.kinds);
  if (!kinds.length) { return ''; }
  const total: number = num(data.total);
  const common: string[] = list<unknown>(data.common).map((f: unknown): string => str(f));
  const base: string = common.length
    ? card('<div style="display:flex;flex-wrap:wrap;align-items:center;gap:6px 10px">' + eyebrow('Every rule carries', theme) +
      common.map((f: string): string => chip(f, theme, true)).join('') + '</div>', theme)
    : '';
  return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + esc(theme.text) + '">' + base +
    '<div style="display:grid;grid-template-columns:repeat(' + balancedColumns(kinds.length, 5) + ',minmax(170px,1fr));gap:12px">' +
    kinds.map((k: IRuleKind): string => kindCard(k, total, theme)).join('') + '</div></div>';
}

function kindCard(k: IRuleKind, total: number, theme: IChartTheme): string {
  const colour: string = COLOUR[str(k.kind)] || INFO;
  const deployed: number = num(k.deployed);
  const enabled: number = num(k.enabled);
  const fields: string[] = list<unknown>(k.fields).map((f: unknown): string => str(f));
  const head: string = '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px">' +
    eyebrow(str(k.label) || str(k.kind), theme, colour) + (k.legacy ? pill('Legacy', WARN) : '') + '</div>';
  const inner: string = head +
    figure(count(deployed), theme) +
    sub(deployed > 0 ? count(enabled) + ' enabled' : 'None deployed', theme) +
    '<div style="margin:9px 0 10px">' + share(deployed, total, colour, theme) + '</div>' +
    '<div style="font-size:12px;line-height:1.5;color:' + esc(theme.muted) + '">' + esc(k.summary) + '</div>' +
    (fields.length ? '<div style="display:flex;flex-wrap:wrap;gap:5px;margin-top:9px">' + fields.map((f: string): string => chip(f, theme, true)).join('') + '</div>' : '');
  return card(inner, theme, deployed > 0 ? colour : undefined, deployed > 0 ? '' : 'opacity:.62');
}
