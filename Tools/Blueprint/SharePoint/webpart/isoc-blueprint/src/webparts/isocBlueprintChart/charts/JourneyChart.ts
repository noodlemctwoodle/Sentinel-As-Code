import { type IJourneyData } from './ChartTypes';
import { type IChartTheme, esc, list, num, str } from './ChartKit';

interface IJourneyTask {
  label: string;
  score: number;
  actors?: string[];
}

interface IJourneySection {
  name: string;
  tasks: IJourneyTask[];
}

// A user journey: one card per step, grouped by stage, each with its
// satisfaction score (1 to 5) and the actors involved.
export function renderJourney(data: IJourneyData, theme: IChartTheme): string {
  const sections: IJourneySection[] = list<IJourneySection>(data && data.sections);
  if (!sections.length) { return ''; }
  let out: string = '<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:16px;font-size:13px;color:' + esc(theme.text) + '">';
  sections.forEach((s: IJourneySection): void => {
    out += '<section style="min-width:0">' +
      '<div style="font-size:12px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;color:' + esc(theme.muted) + ';margin-bottom:6px">' + esc(s.name) + '</div>' +
      '<div style="display:flex;flex-direction:column;gap:8px">';
    list<IJourneyTask>(s.tasks).forEach((t: IJourneyTask): void => {
      const score: number = Math.max(0, Math.min(5, Math.round(num(t.score))));
      const colour: string = score >= 4 ? '#16a34a' : score === 3 ? '#d97706' : '#dc2626';
      out += '<div style="border:1px solid ' + esc(theme.line) + ';border-left:4px solid ' + colour + ';border-radius:8px;padding:8px 10px">' +
        '<div style="display:flex;justify-content:space-between;gap:8px;align-items:baseline">' +
        '<span style="font-weight:600">' + esc(t.label) + '</span>' +
        '<span role="img" aria-label="Score ' + score + ' of 5" title="Score ' + score + ' of 5" style="flex:none;color:' + colour + ';letter-spacing:1px">' + dots(score) + '</span></div>' +
        (list<unknown>(t.actors).length
          ? '<div style="margin-top:4px;color:' + esc(theme.muted) + '">' + list<unknown>(t.actors).map((a: unknown): string => esc(str(a))).join(', ') + '</div>'
          : '') +
        '</div>';
    });
    out += '</div></section>';
  });
  return out + '</div>';
}

function dots(score: number): string {
  let s: string = '';
  for (let i: number = 1; i <= 5; i++) { s += i <= score ? '&#9679;' : '&#9675;'; }
  return s;
}
