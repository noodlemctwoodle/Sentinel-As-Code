import { type IMindmapNode } from './ChartTypes';
import { type IChartTheme, SERIES, esc, list, r, rect, str, svgDoc, svgText, widest, wrapText } from './ChartKit';

interface IBox {
  lines: string[];
  w: number;
  h: number;
  depth: number;
  colour: string;
  x: number;
  y: number;
  children: IBox[];
}

const GAP_X: number = 44;
const GAP_Y: number = 10;
const LINE: number = 16;

// A tree read left to right: the root, then each branch in its own colour.
export function renderMindmap(data: { root?: IMindmapNode }, theme: IChartTheme, label: string): string {
  if (!data || !data.root) { return ''; }
  const root: IBox = build(data.root, 0, theme.accent);
  const colW: number[] = [];
  measure(root, colW);
  const colX: number[] = [];
  let x: number = 2;
  colW.forEach((w: number, d: number): void => { colX[d] = x; x += w + GAP_X; });
  const height: number = place(root, 2, colX);

  let edges: string = '';
  let boxes: string = '';
  const draw: (b: IBox) => void = (b: IBox): void => {
    b.children.forEach((c: IBox): void => {
      const x0: number = b.x + b.w;
      const y0: number = b.y + b.h / 2;
      const x1: number = c.x;
      const y1: number = c.y + c.h / 2;
      const xm: number = (x0 + x1) / 2;
      edges += '<path d="M' + r(x0) + ',' + r(y0) + ' C' + r(xm) + ',' + r(y0) + ' ' + r(xm) + ',' + r(y1) + ' ' + r(x1) + ',' + r(y1) + '" fill="none" stroke="' + esc(c.colour) + '" stroke-width="2" stroke-opacity="0.7"/>';
      draw(c);
    });
    const isRoot: boolean = b.depth === 0;
    boxes += rect(b.x, b.y, b.w, b.h, 'rx="8" fill="' + esc(isRoot ? b.colour : theme.surface) + '" stroke="' + esc(b.colour) + '" stroke-width="' + (isRoot ? 0 : 1.5) + '"');
    if (!isRoot) { boxes += rect(b.x, b.y, b.w, b.h, 'rx="8" fill="' + esc(b.colour) + '" fill-opacity="0.1"'); }
    boxes += svgText(b.x + b.w / 2, b.y + b.h / 2, b.lines,
      { size: isRoot ? 14 : 12, weight: isRoot ? 600 : 400, fill: isRoot ? '#ffffff' : theme.text, anchor: 'middle', lineHeight: LINE });
  };
  draw(root);
  return svgDoc(x - GAP_X + 4, height + 4, label, edges + boxes);
}

function build(n: IMindmapNode, depth: number, colour: string): IBox {
  const size: number = depth === 0 ? 14 : 12;
  const lines: string[] = wrapText(str(n.text), 200, size, depth === 0);
  const box: IBox = {
    lines: lines, w: widest(lines, size, depth === 0) + 24, h: lines.length * LINE + 14,
    depth: depth, colour: colour, x: 0, y: 0, children: []
  };
  box.children = list<IMindmapNode>(n.children).map((c: IMindmapNode, i: number): IBox =>
    build(c, depth + 1, depth === 0 ? SERIES[i % SERIES.length] : colour));
  return box;
}

function measure(b: IBox, colW: number[]): void {
  colW[b.depth] = Math.max(colW[b.depth] || 0, b.w);
  b.children.forEach((c: IBox): void => measure(c, colW));
}

// Leaves are stacked top to bottom; a parent sits level with the middle of
// its children. Returns the bottom of the subtree.
function place(b: IBox, top: number, colX: number[]): number {
  b.x = colX[b.depth];
  if (!b.children.length) {
    b.y = top;
    return top + b.h + GAP_Y;
  }
  let y: number = top;
  b.children.forEach((c: IBox): void => { y = place(c, y, colX); });
  const first: IBox = b.children[0];
  const last: IBox = b.children[b.children.length - 1];
  b.y = (first.y + last.y + last.h) / 2 - b.h / 2;
  if (b.y < top) {
    const shift: number = top - b.y;
    b.y = top;
    shiftTree(b, shift, true);
    y += shift;
  }
  return Math.max(y, b.y + b.h + GAP_Y);
}

function shiftTree(b: IBox, dy: number, skipSelf: boolean): void {
  if (!skipSelf) { b.y += dy; }
  b.children.forEach((c: IBox): void => shiftTree(c, dy, false));
}
