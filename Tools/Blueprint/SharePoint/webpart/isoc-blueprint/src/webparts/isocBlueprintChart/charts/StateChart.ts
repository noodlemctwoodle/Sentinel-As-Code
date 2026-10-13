import { type IStateData } from './ChartTypes';
import { type IChartTheme, esc, list, r, rect, str, svgText, widest, wrapText } from './ChartKit';
import { type IDrawEdge, type IDrawNode, drawGraph } from './GraphDraw';
import { noteNode } from './NoteNode';

interface IState {
  id: string;
  label?: string;
  parent?: string;
}

interface ITransition {
  from: string;
  to: string;
  label?: string;
  parent?: string;
}

const START: string = '__start';
const END: string = '__end';

// States and the transitions between them, top to bottom. A composite state
// is one box listing its substates (the transitions that only say "one of
// these" are folded into that list); [*] is the start dot or the end ring.
export function renderState(data: IStateData, theme: IChartTheme, label: string): string {
  const states: IState[] = list<IState>(data && data.states);
  const transitions: ITransition[] = list<ITransition>(data && data.transitions);
  const parentOf: { [id: string]: string | undefined } = {};
  states.forEach((s: IState): void => { parentOf[str(s.id)] = str(s.parent) || undefined; });
  const top: (id: string) => string = (id: string): string => {
    let cur: string = id;
    for (let guard: number = 0; parentOf[cur] && guard < 20; guard++) { cur = parentOf[cur] as string; }
    return cur;
  };
  const children: { [id: string]: string[] } = {};
  states.forEach((s: IState): void => {
    const p: string | undefined = parentOf[str(s.id)];
    if (p) { (children[p] = children[p] || []).push(str(s.label) || str(s.id)); }
  });
  // Inner transitions between substates are listed in the composite's box.
  transitions.forEach((t: ITransition): void => {
    if (t.parent && t.from !== '[*]' && t.to !== '[*]') {
      (children[t.parent] = children[t.parent] || []).push(t.from + ' to ' + t.to + (t.label ? ': ' + t.label : ''));
    }
  });

  const nodes: IDrawNode[] = [];
  const seen: { [id: string]: boolean } = {};
  const add: (id: string) => void = (id: string): void => {
    if (seen[id]) { return; }
    seen[id] = true;
    if (id === START || id === END) {
      nodes.push({ id: id, w: 20, h: 20, x: 0, y: 0, rank: 0, draw: (b: IDrawNode): string => pseudo(b, id === END, theme) });
      return;
    }
    const s: IState[] = states.filter((x: IState): boolean => str(x.id) === id);
    const name: string = s.length ? str(s[0].label) || id : id;
    const inner: string[] = children[id] || [];
    const nameLines: string[] = wrapText(name, 200, 13, true);
    const innerLines: string[] = inner.length ? wrapText(inner.join('\n'), 220, 12) : [];
    const w: number = Math.max(widest(nameLines, 13, true), widest(innerLines, 12)) + 28;
    const h: number = nameLines.length * 17 + 18 + (innerLines.length ? innerLines.length * 16 + 12 : 0);
    nodes.push({ id: id, w: w, h: h, x: 0, y: 0, rank: 0, draw: (b: IDrawNode): string => stateBox(b, nameLines, innerLines, theme) });
  };

  const edges: IDrawEdge[] = [];
  transitions.forEach((t: ITransition): void => {
    if (t.parent) { return; }
    const from: string = t.from === '[*]' ? START : top(t.from);
    const to: string = t.to === '[*]' ? END : top(t.to);
    add(from);
    add(to);
    edges.push({ from: from, to: to, label: str(t.label) || undefined, end: 'arrow' });
  });
  states.forEach((s: IState): void => { if (!parentOf[str(s.id)]) { add(str(s.id)); } });
  list<{ state: string; text?: string }>(data && data.notes).forEach((n: { state: string; text?: string }, i: number): void => {
    const id: string = '__note' + i;
    nodes.push(noteNode(id, str(n.text), theme));
    edges.push({ from: top(str(n.state)), to: id, dashed: true });
  });
  return drawGraph(nodes, edges, [], true, theme, label);
}

function pseudo(b: IDrawNode, end: boolean, theme: IChartTheme): string {
  const cx: number = b.x + b.w / 2;
  const cy: number = b.y + b.h / 2;
  return end
    ? '<circle cx="' + r(cx) + '" cy="' + r(cy) + '" r="9" fill="none" stroke="' + esc(theme.text) + '" stroke-width="1.5"/>' +
      '<circle cx="' + r(cx) + '" cy="' + r(cy) + '" r="5" fill="' + esc(theme.text) + '"/>'
    : '<circle cx="' + r(cx) + '" cy="' + r(cy) + '" r="8" fill="' + esc(theme.text) + '"/>';
}

function stateBox(b: IDrawNode, nameLines: string[], innerLines: string[], theme: IChartTheme): string {
  const nameH: number = nameLines.length * 17 + 18;
  let out: string = rect(b.x, b.y, b.w, b.h, 'rx="12" fill="' + esc(theme.surface) + '" stroke="' + esc(theme.accent) + '" stroke-width="1.5"') +
    rect(b.x, b.y, b.w, b.h, 'rx="12" fill="' + esc(theme.accent) + '" fill-opacity="0.07"') +
    svgText(b.x + b.w / 2, b.y + nameH / 2, nameLines, { size: 13, weight: 600, fill: theme.text, anchor: 'middle', lineHeight: 17 });
  if (innerLines.length) {
    out += '<line x1="' + r(b.x) + '" y1="' + r(b.y + nameH) + '" x2="' + r(b.x + b.w) + '" y2="' + r(b.y + nameH) + '" stroke="' + esc(theme.line) + '"/>' +
      svgText(b.x + 14, b.y + nameH + (b.h - nameH) / 2, innerLines, { size: 12, fill: theme.muted, lineHeight: 16 });
  }
  return out;
}
