import { type ISankeyData, type ISankeyLink } from './ChartTypes';
import { type IChartTheme, colourFor, esc, fmt, list, num, r, rect, str, svgDoc, svgText, widest, wrapText } from './ChartKit';

interface INode {
  name: string;
  index: number;
  col: number;
  inValue: number;
  outValue: number;
  x: number;
  y: number;
  h: number;
  inOff: number;
  outOff: number;
  colour: string;
}

interface ILink {
  source: INode;
  target: INode;
  value: number;
}

const NODE_W: number = 12;
const GAP: number = 12;
const MIN_H: number = 3;

// Flows between named stages. Each node sits in the column of its longest
// path from a source; its height is the larger of what flows in and out.
export function renderSankey(data: ISankeyData, theme: IChartTheme, label: string): string {
  const nodes: { [name: string]: INode } = {};
  const order: INode[] = [];
  const node: (name: string) => INode = (name: string): INode => {
    if (!nodes[name]) {
      nodes[name] = { name: name, index: order.length, col: 0, inValue: 0, outValue: 0, x: 0, y: 0, h: 0, inOff: 0, outOff: 0, colour: '' };
      order.push(nodes[name]);
    }
    return nodes[name];
  };
  const links: ILink[] = [];
  list<ISankeyLink>(data && data.links).forEach((l: ISankeyLink): void => {
    const value: number = num(l.value);
    const s: string = str(l.source);
    const t: string = str(l.target);
    if (!s || !t || s === t || value <= 0) { return; }
    const link: ILink = { source: node(s), target: node(t), value: value };
    link.source.outValue += value;
    link.target.inValue += value;
    links.push(link);
  });
  if (!links.length) { return ''; }

  // Longest path from a source; the pass limit stops a cycle looping forever.
  for (let pass: number = 0; pass < order.length; pass++) {
    let moved: boolean = false;
    links.forEach((l: ILink): void => {
      if (l.target.col < l.source.col + 1) { l.target.col = l.source.col + 1; moved = true; }
    });
    if (!moved) { break; }
  }
  const cols: INode[][] = [];
  order.forEach((n: INode): void => {
    n.colour = colourFor(n.name, n.index);
    (cols[n.col] = cols[n.col] || []).push(n);
  });
  for (let c: number = 0; c < cols.length; c++) { cols[c] = cols[c] || []; }

  const height: number = Math.max(260, cols.reduce((m: number, c: INode[]): number => Math.max(m, c.length), 0) * 46);
  const scale: number = Math.min(...cols.filter((c: INode[]): boolean => c.length > 0).map((c: INode[]): number => {
    const total: number = c.reduce((a: number, n: INode): number => a + Math.max(n.inValue, n.outValue), 0);
    return (height - GAP * (c.length - 1)) / total;
  }));

  // Each column is followed by room for its widest label, and each node has
  // a slot at least as tall as its label so small nodes' labels never collide.
  let x: number = 4;
  const colH: number[] = [];
  cols.forEach((c: INode[], ci: number): void => {
    const labelW: number = c.reduce((m: number, n: INode): number => Math.max(m, widest(nameLines(n), 12, true), widest([value(n)], 11)), 0);
    c.forEach((n: INode): void => { n.x = x; n.h = Math.max(MIN_H, Math.max(n.inValue, n.outValue) * scale); });
    colH[ci] = c.reduce((a: number, n: INode): number => a + slot(n), 0) + GAP * (c.length - 1);
    x += NODE_W + Math.max(80, labelW + 30);
  });
  const fullH: number = Math.max(height, ...colH);
  cols.forEach((c: INode[], ci: number): void => {
    let y: number = (fullH - colH[ci]) / 2;
    c.forEach((n: INode): void => { n.y = y + (slot(n) - n.h) / 2; y += slot(n) + GAP; });
  });

  // Bands leave and enter each node in the order of the node at the far end,
  // which keeps them from crossing more than they must.
  const sorted: ILink[] = links.slice().sort((a: ILink, b: ILink): number => a.target.y - b.target.y || a.source.y - b.source.y);
  let body: string = '';
  const bandTop: { [key: number]: number } = {};
  sorted.forEach((l: ILink, i: number): void => {
    const sh: number = (l.value / Math.max(l.source.outValue, l.source.inValue)) * l.source.h;
    bandTop[i] = l.source.y + l.source.outOff;
    l.source.outOff += sh;
  });
  links.slice().sort((a: ILink, b: ILink): number => a.source.y - b.source.y || a.target.y - b.target.y).forEach((l: ILink): void => {
    const i: number = sorted.indexOf(l);
    const sh: number = (l.value / Math.max(l.source.outValue, l.source.inValue)) * l.source.h;
    const th: number = (l.value / Math.max(l.target.inValue, l.target.outValue)) * l.target.h;
    const sy: number = bandTop[i];
    const ty: number = l.target.y + l.target.inOff;
    l.target.inOff += th;
    const x0: number = l.source.x + NODE_W;
    const x1: number = l.target.x;
    const xm: number = (x0 + x1) / 2;
    const d: string = 'M' + r(x0) + ',' + r(sy) + ' C' + r(xm) + ',' + r(sy) + ' ' + r(xm) + ',' + r(ty) + ' ' + r(x1) + ',' + r(ty) +
      ' L' + r(x1) + ',' + r(ty + th) + ' C' + r(xm) + ',' + r(ty + th) + ' ' + r(xm) + ',' + r(sy + sh) + ' ' + r(x0) + ',' + r(sy + sh) + ' Z';
    body += '<path d="' + d + '" fill="' + esc(l.source.colour) + '" fill-opacity="' + (theme.dark ? '0.45' : '0.3') + '">' +
      '<title>' + esc(l.source.name + ' to ' + l.target.name + ': ' + fmt(l.value)) + '</title></path>';
  });
  order.forEach((n: INode): void => {
    const lines: string[] = nameLines(n);
    const cy: number = n.y + n.h / 2;
    body += rect(n.x, n.y, NODE_W, n.h, 'rx="2" fill="' + esc(n.colour) + '"').replace('/>', '><title>' + esc(n.name + ': ' + value(n)) + '</title></rect>');
    body += '<g stroke="' + esc(theme.surface) + '" stroke-width="4" stroke-linejoin="round" paint-order="stroke">' +
      svgText(n.x + NODE_W + 6, cy - 7, lines, { size: 12, weight: 600, fill: theme.text, lineHeight: 14 }) +
      svgText(n.x + NODE_W + 6, cy + (lines.length * 14) / 2, [value(n)], { size: 11, fill: theme.muted }) + '</g>';
  });
  return svgDoc(x, fullH + 4, label, body);
}

function slot(n: INode): number {
  return Math.max(n.h, nameLines(n).length * 14 + 18);
}

function nameLines(n: INode): string[] {
  return wrapText(n.name, 150, 12, true);
}

function value(n: INode): string {
  return fmt(Math.max(n.inValue, n.outValue));
}
