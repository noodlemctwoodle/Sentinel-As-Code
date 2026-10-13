import { type IClassData } from './ChartTypes';
import { type IChartTheme, esc, list, r, rect, str, svgText, widest } from './ChartKit';
import { type IDrawEdge, type IDrawNode, drawGraph } from './GraphDraw';
import { noteNode } from './NoteNode';

interface IClass {
  name: string;
  members?: string[];
}

interface IRelation {
  from: string;
  to: string;
  kind: string;
  label?: string;
}

const MONO: string = 'Consolas, "Cascadia Mono", Menlo, monospace';

// Classes as name-and-members boxes, top to bottom, with UML ends on the
// relations: a hollow triangle for inheritance or realisation, diamonds for
// composition and aggregation, arrows for association and dependency.
export function renderClass(data: IClassData, theme: IChartTheme, label: string): string {
  const classes: IClass[] = list<IClass>(data && data.classes);
  const nodes: IDrawNode[] = [];
  const known: { [name: string]: boolean } = {};
  const add: (c: IClass) => void = (c: IClass): void => {
    const name: string = str(c.name);
    if (!name || known[name]) { return; }
    known[name] = true;
    const members: string[] = list<unknown>(c.members).map(str);
    const w: number = Math.max(widest([name], 13, true), widest(members, 12) * 1.15) + 26;
    const h: number = 32 + (members.length ? members.length * 16 + 12 : 0);
    nodes.push({ id: name, w: w, h: h, x: 0, y: 0, rank: 0, draw: (b: IDrawNode): string => classBox(b, name, members, theme) });
  };
  classes.forEach(add);

  const edges: IDrawEdge[] = [];
  list<IRelation>(data && data.relations).forEach((rel: IRelation): void => {
    add({ name: str(rel.from) });
    add({ name: str(rel.to) });
    const kind: string = str(rel.kind);
    const left: string | undefined = endShape(kind.substring(0, 2), true);
    const right: string | undefined = endShape(kind.substring(kind.length - 2), false);
    const dashed: boolean = kind.indexOf('..') >= 0;
    // The end with the triangle or diamond (the parent or whole) goes on top.
    if (right && !left) {
      edges.push({ from: str(rel.to), to: str(rel.from), start: right, dashed: dashed, label: str(rel.label) || undefined });
    } else {
      edges.push({ from: str(rel.from), to: str(rel.to), start: left, end: right, dashed: dashed, label: str(rel.label) || undefined });
    }
  });
  list<{ for?: string; text?: string }>(data && data.notes).forEach((n: { for?: string; text?: string }, i: number): void => {
    const id: string = '__note' + i;
    nodes.push(noteNode(id, str(n.text), theme));
    if (str(n.for) && known[str(n.for)]) { edges.push({ from: str(n.for), to: id, dashed: true }); }
  });
  return drawGraph(nodes, edges, [], true, theme, label);
}

// The marker for one end of a Mermaid relation ('<|', '*', 'o', '<' on the
// left; '|>', '*', 'o', '>' on the right).
function endShape(end: string, left: boolean): string | undefined {
  if (left ? end === '<|' : end === '|>') { return 'triangle'; }
  const c: string = left ? end.charAt(0) : end.charAt(end.length - 1);
  if (c === '*') { return 'diamond'; }
  if (c === 'o') { return 'odiamond'; }
  if (left ? c === '<' : c === '>') { return 'arrow'; }
  return undefined;
}

function classBox(b: IDrawNode, name: string, members: string[], theme: IChartTheme): string {
  let out: string = rect(b.x, b.y, b.w, b.h, 'rx="6" fill="' + esc(theme.surface) + '" stroke="' + esc(theme.accent) + '" stroke-width="1.5"') +
    rect(b.x, b.y, b.w, 32, 'rx="6" fill="' + esc(theme.accent) + '" fill-opacity="0.12"') +
    svgText(b.x + b.w / 2, b.y + 16, [name], { size: 13, weight: 600, fill: theme.text, anchor: 'middle' });
  if (members.length) {
    out += '<line x1="' + r(b.x) + '" y1="' + r(b.y + 32) + '" x2="' + r(b.x + b.w) + '" y2="' + r(b.y + 32) + '" stroke="' + esc(theme.line) + '"/>' +
      '<g font-family="' + esc(MONO) + '">' +
      svgText(b.x + 13, b.y + 32 + (b.h - 32) / 2, members, { size: 12, fill: theme.text, lineHeight: 16 }) + '</g>';
  }
  return out;
}
