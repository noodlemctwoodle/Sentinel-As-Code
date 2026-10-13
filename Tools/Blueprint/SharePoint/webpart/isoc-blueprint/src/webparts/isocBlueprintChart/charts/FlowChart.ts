import { type IFlowData, type IFlowEdge, type IFlowNode } from './ChartTypes';
import { type IChartTheme, esc, list, readableOn, rect, safeHref, str, svgText, widest, wrapText } from './ChartKit';
import { type IDrawEdge, type IDrawGroup, type IDrawNode, drawGraph } from './GraphDraw';

const LINE: number = 16;

// Boxes and arrows, in subgraph groups, with the colours and links the
// renderer gave them. TB, TD and BT run top to bottom; anything else runs
// left to right.
export function renderFlowchart(data: IFlowData, theme: IChartTheme, label: string): string {
  const vertical: boolean = /^(TB|TD|BT)$/i.test(str(data && data.direction));
  const nodes: IDrawNode[] = list<IFlowNode>(data && data.nodes).map((n: IFlowNode): IDrawNode => {
    const lines: string[] = wrapText(str(n.label) || str(n.id), 190, 12);
    return {
      id: str(n.id), w: widest(lines, 12) + 26, h: lines.length * LINE + 16, group: str(n.group) || undefined,
      x: 0, y: 0, rank: 0,
      draw: (b: IDrawNode): string => drawNode(b, n, lines, theme)
    };
  });
  const edges: IDrawEdge[] = list<IFlowEdge>(data && data.edges).map((e: IFlowEdge): IDrawEdge => ({
    from: str(e.from), to: str(e.to), label: str(e.label) || undefined,
    dashed: e.style === 'dotted', thick: e.style === 'thick', end: e.arrow === false ? undefined : 'arrow'
  }));
  const groups: IDrawGroup[] = list<{ id: string; label?: string; parent?: string }>(data && data.groups)
    .map((g: { id: string; label?: string; parent?: string }): IDrawGroup => ({
      id: str(g.id), label: str(g.label) || str(g.id), parent: str(g.parent) || undefined
    }));
  return drawGraph(nodes, edges, groups, vertical, theme, label);
}

function drawNode(b: IDrawNode, n: IFlowNode, lines: string[], theme: IChartTheme): string {
  const fill: string = str(n.fill);
  const stroke: string = str(n.stroke) || fill || theme.accent;
  const ink: string = str(n.color) || (fill ? readableOn(fill) : theme.text);
  const href: string | undefined = safeHref(n.href);
  let out: string = rect(b.x, b.y, b.w, b.h, 'rx="8" fill="' + esc(fill || theme.surface) + '" stroke="' + esc(stroke) + '" stroke-width="1.5"');
  if (!fill) { out += rect(b.x, b.y, b.w, b.h, 'rx="8" fill="' + esc(theme.accent) + '" fill-opacity="0.07"'); }
  out += svgText(b.x + b.w / 2, b.y + b.h / 2, lines, {
    size: 12, fill: ink, anchor: 'middle', lineHeight: LINE, weight: href ? 600 : undefined
  });
  const tip: string = str(n.tooltip) || (href ? 'Open ' + str(n.label || n.id).replace(/\n/g, ' ') : '');
  if (tip) { out = '<title>' + esc(tip) + '</title>' + out; }
  return href
    ? '<a href="' + esc(href) + '" style="cursor:pointer">' + out + '</a>'
    : '<g>' + out + '</g>';
}
