import { type IEdgePath, type IGraphEdge, type IGraphNode, type ISize, forwardPath, layoutGraph, loopPath } from './GraphLayout';
import { type IChartTheme, esc, marker, nextId, r, rect, svgDoc, svgText, textWidth } from './ChartKit';

// Drawing shared by the flowchart, state and class diagrams: lay the graph
// out, box the groups, draw the edges with their labels and ends, then let
// the caller draw each node.

export interface IDrawNode extends IGraphNode {
  draw: (n: IDrawNode) => string;
}

export interface IDrawEdge extends IGraphEdge {
  label?: string;
  dashed?: boolean;
  thick?: boolean;
  start?: string;
  end?: string;
}

export interface IDrawGroup {
  id: string;
  label: string;
  parent?: string;
}

interface IBox {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
}

const PAD: number = 14;
const PAD_TOP: number = 26;

export function drawGraph(nodes: IDrawNode[], edges: IDrawEdge[], groups: IDrawGroup[], vertical: boolean,
  theme: IChartTheme, label: string): string {
  if (!nodes.length) { return ''; }
  // Each label's size, so the layout can give a long edge's label room.
  edges.forEach((e: IDrawEdge): void => {
    if (!e.label) { return; }
    const parts: string[] = e.label.split('\n');
    e.labelW = parts.reduce((m: number, t: string): number => Math.max(m, textWidth(t, 11)), 0) + 12;
    e.labelH = parts.length * 14 + 8;
  });
  const labelled: boolean = edges.some((e: IDrawEdge): boolean => !!e.label);
  const size: ISize = layoutGraph(nodes, edges, {
    vertical: vertical,
    rankGap: vertical ? (labelled ? 70 : 54) : (labelled ? 110 : 70),
    nodeGap: vertical ? 28 : 16,
    groupGap: PAD + PAD_TOP + 14,
    groupOrder: groups.map((g: IDrawGroup): string => g.id)
  });
  const byId: { [id: string]: IDrawNode } = {};
  nodes.forEach((n: IDrawNode): void => { byId[n.id] = n; });

  // Group boxes, innermost first so a parent can wrap its children's boxes.
  const boxes: { [id: string]: IBox } = {};
  const parentOf: { [id: string]: string | undefined } = {};
  groups.forEach((g: IDrawGroup): void => { parentOf[g.id] = g.parent; });
  const depthOf: (g: IDrawGroup) => number = (g: IDrawGroup): number => {
    let d: number = 0;
    for (let p: string | undefined = g.parent; p && d < 20; p = parentOf[p]) { d++; }
    return d;
  };
  const ordered: IDrawGroup[] = groups.slice().sort((a: IDrawGroup, b: IDrawGroup): number => depthOf(b) - depthOf(a));
  ordered.forEach((g: IDrawGroup): void => {
    const parts: IBox[] = [];
    nodes.forEach((n: IDrawNode): void => { if (n.group === g.id) { parts.push({ x0: n.x, y0: n.y, x1: n.x + n.w, y1: n.y + n.h }); } });
    groups.forEach((c: IDrawGroup): void => { if (c.parent === g.id && boxes[c.id]) { parts.push(boxes[c.id]); } });
    if (!parts.length) { return; }
    const b: IBox = parts.reduce((m: IBox, x: IBox): IBox =>
      ({ x0: Math.min(m.x0, x.x0), y0: Math.min(m.y0, x.y0), x1: Math.max(m.x1, x.x1), y1: Math.max(m.y1, x.y1) }));
    const titleW: number = textWidth(g.label, 12, true) + PAD * 2;
    boxes[g.id] = { x0: b.x0 - PAD, y0: b.y0 - PAD_TOP, x1: Math.max(b.x1 + PAD, b.x0 - PAD + titleW), y1: b.y1 + PAD };
  });

  const arrowId: string = nextId('arrow');
  const ends: { [shape: string]: string } = {};
  const endRef: (shape: string | undefined) => string = (shape: string | undefined): string => {
    if (!shape) { return ''; }
    if (!ends[shape]) { ends[shape] = shape === 'arrow' ? arrowId : nextId(shape); }
    return 'url(#' + ends[shape] + ')';
  };

  let lane: number = 0;
  let lines: string = '';
  let labels: string = '';
  let extent: IBox = { x0: 0, y0: 0, x1: size.width, y1: size.height };
  edges.forEach((e: IDrawEdge): void => {
    const a: IDrawNode = byId[e.from];
    const b: IDrawNode = byId[e.to];
    if (!a || !b || a === b) { return; }
    const around: boolean = !!e.back || b.rank <= a.rank;
    const myLane: number = around ? lane++ : 0;
    // A loop goes round whichever side of the drawing its ends are nearer.
    const before: boolean = vertical
      ? (a.x + b.x + (a.w + b.w) / 2) / 2 < size.width / 2
      : (a.y + b.y + (a.h + b.h) / 2) / 2 < size.height / 2;
    const far: number = 36 + myLane * 12 + (e.label ? ((vertical ? e.labelW : e.labelH) || 0) : 0);
    const p: IEdgePath = around ? loopPath(a, b, vertical, far, before) : forwardPath(a, b, e.via || [], vertical);
    const at: { x: number; y: number } = !around && e.labelAt
      ? { x: e.labelAt.x + e.labelAt.w / 2, y: e.labelAt.y + e.labelAt.h / 2 }
      : p.mid;
    if (around) {
      // The curve's control points sit `far` past the nodes; the curve itself
      // reaches three quarters of the way, and its label is centred there.
      if (vertical) {
        extent = before
          ? { x0: Math.min(extent.x0, Math.min(a.x, b.x) - far), y0: extent.y0, x1: extent.x1, y1: extent.y1 }
          : { x0: extent.x0, y0: extent.y0, x1: Math.max(extent.x1, Math.max(a.x + a.w, b.x + b.w) + far), y1: extent.y1 };
      } else {
        extent = before
          ? { x0: extent.x0, y0: Math.min(extent.y0, Math.min(a.y, b.y) - far), x1: extent.x1, y1: extent.y1 }
          : { x0: extent.x0, y0: extent.y0, x1: extent.x1, y1: Math.max(extent.y1, Math.max(a.y + a.h, b.y + b.h) + far) };
      }
    }
    const startRef: string = endRef(e.start);
    const endUrl: string = endRef(e.end);
    lines += '<path d="' + p.d + '" fill="none" stroke="' + esc(theme.muted) + '" stroke-width="' + (e.thick ? 3 : 1.5) + '"' +
      (e.dashed ? ' stroke-dasharray="5 4"' : '') +
      (startRef ? ' marker-start="' + startRef + '"' : '') + (endUrl ? ' marker-end="' + endUrl + '"' : '') + '/>';
    if (e.label) {
      const parts: string[] = e.label.split('\n');
      const w: number = (e.labelW || 0) - 2;
      const h: number = (e.labelH || 0) - 2;
      labels += rect(at.x - w / 2, at.y - h / 2, w, h, 'rx="4" fill="' + esc(theme.surface) + '" stroke="' + esc(theme.line) + '"') +
        svgText(at.x, at.y, parts, { size: 11, fill: theme.muted, anchor: 'middle', lineHeight: 14 });
    }
  });

  let groupSvg: string = '';
  groups.slice().sort((a: IDrawGroup, b: IDrawGroup): number => depthOf(a) - depthOf(b)).forEach((g: IDrawGroup): void => {
    const b: IBox | undefined = boxes[g.id];
    if (!b) { return; }
    extent = { x0: Math.min(extent.x0, b.x0), y0: Math.min(extent.y0, b.y0), x1: Math.max(extent.x1, b.x1), y1: Math.max(extent.y1, b.y1) };
    groupSvg += rect(b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0, 'rx="10" fill="' + esc(theme.accent) + '" fill-opacity="' + (theme.dark ? '0.08' : '0.04') + '" stroke="' + esc(theme.line) + '" stroke-width="1.2"') +
      svgText(b.x0 + PAD, b.y0 + 13, [g.label], { size: 12, weight: 600, fill: theme.muted });
  });

  let defs: string = '';
  Object.keys(ends).forEach((shape: string): void => { defs += marker(ends[shape], shape, theme.muted, theme.surface); });
  const nodeSvg: string = nodes.map((n: IDrawNode): string => n.draw(n)).join('');
  const dx: number = 4 - extent.x0;
  const dy: number = 4 - extent.y0;
  return svgDoc(extent.x1 - extent.x0 + 8, extent.y1 - extent.y0 + 8, label,
    (defs ? '<defs>' + defs + '</defs>' : '') +
    '<g transform="translate(' + r(dx) + ',' + r(dy) + ')">' + groupSvg + lines + nodeSvg + labels + '</g>');
}
