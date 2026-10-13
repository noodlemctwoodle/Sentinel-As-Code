// A small layered (Sugiyama-style) layout for the node-and-edge diagrams:
// break cycles, rank nodes by longest path, give an edge that skips ranks a
// placeholder in each rank it crosses (so it is routed round the nodes there,
// and a long edge's label has room of its own), order each rank to cut
// crossings while keeping a group's nodes together, then place the ranks side
// by side (left to right) or one under another (top to bottom).

export interface IGraphNode {
  id: string;
  w: number;
  h: number;
  group?: string;
  x: number;
  y: number;
  rank: number;
}

export interface IGraphEdge {
  from: string;
  to: string;
  labelW?: number;
  labelH?: number;
  // Set by the layout: a back edge closes a cycle; via are the placeholders
  // a long edge runs through, and labelAt the one that holds its label.
  back?: boolean;
  via?: IGraphNode[];
  labelAt?: IGraphNode;
}

export interface ILayoutOptions {
  vertical: boolean;
  rankGap: number;
  nodeGap: number;
  groupGap: number;
  groupOrder: string[];
}

export interface ISize {
  width: number;
  height: number;
}

interface ILink {
  from: IGraphNode;
  to: IGraphNode;
}

// Positions nodes in place (x, y are top-left) and annotates the edges.
// Returns the drawing's size.
export function layoutGraph(nodes: IGraphNode[], edges: IGraphEdge[], opts: ILayoutOptions): ISize {
  const byId: { [id: string]: IGraphNode } = {};
  nodes.forEach((n: IGraphNode): void => { byId[n.id] = n; n.rank = 0; });
  const live: IGraphEdge[] = edges.filter((e: IGraphEdge): boolean => !!byId[e.from] && !!byId[e.to] && e.from !== e.to);
  markBackEdges(nodes, live);

  // Longest path over the forward edges, relaxed until nothing moves.
  for (let pass: number = 0; pass <= nodes.length; pass++) {
    let moved: boolean = false;
    live.forEach((e: IGraphEdge): void => {
      if (e.back) { return; }
      if (byId[e.to].rank < byId[e.from].rank + 1) { byId[e.to].rank = byId[e.from].rank + 1; moved = true; }
    });
    if (!moved) { break; }
  }

  const all: IGraphNode[] = nodes.slice();
  const links: ILink[] = [];
  live.forEach((e: IGraphEdge): void => {
    e.via = [];
    e.labelAt = undefined;
    if (e.back) { return; }
    const a: IGraphNode = byId[e.from];
    const b: IGraphNode = byId[e.to];
    const mid: number = Math.floor((a.rank + b.rank) / 2);
    let prev: IGraphNode = a;
    for (let k: number = a.rank + 1; k < b.rank; k++) {
      const holds: boolean = k === mid && !!e.labelW;
      const across: number = holds ? (opts.vertical ? e.labelW || 0 : e.labelH || 0) : 6;
      const depth: number = holds ? (opts.vertical ? e.labelH || 0 : e.labelW || 0) : 6;
      const d: IGraphNode = {
        id: '\u0001' + all.length, w: opts.vertical ? across : depth, h: opts.vertical ? depth : across,
        group: a.group === b.group ? a.group : undefined, x: 0, y: 0, rank: k
      };
      all.push(d);
      e.via.push(d);
      if (holds) { e.labelAt = d; }
      links.push({ from: prev, to: d });
      prev = d;
    }
    links.push({ from: prev, to: b });
  });
  const up: { [id: string]: IGraphNode[] } = {};
  const down: { [id: string]: IGraphNode[] } = {};
  links.forEach((l: ILink): void => {
    (up[l.to.id] = up[l.to.id] || []).push(l.from);
    (down[l.from.id] = down[l.from.id] || []).push(l.to);
  });

  const index: { [id: string]: number } = {};
  all.forEach((n: IGraphNode, i: number): void => { index[n.id] = i; });
  const ranks: IGraphNode[][] = [];
  all.forEach((n: IGraphNode): void => { (ranks[n.rank] = ranks[n.rank] || []).push(n); });
  for (let i: number = 0; i < ranks.length; i++) { ranks[i] = ranks[i] || []; }
  const groupKey: (n: IGraphNode) => number = (n: IGraphNode): number => {
    const g: number = n.group ? opts.groupOrder.indexOf(n.group) : -1;
    return g < 0 ? opts.groupOrder.length : g;
  };
  const pos: { [id: string]: number } = {};
  const setPos: () => void = (): void => { ranks.forEach((rk: IGraphNode[]): void => { rk.forEach((n: IGraphNode, i: number): void => { pos[n.id] = i; }); }); };
  ranks.forEach((rk: IGraphNode[]): void => { rk.sort((a: IGraphNode, b: IGraphNode): number => groupKey(a) - groupKey(b) || index[a.id] - index[b.id]); });
  setPos();

  // Barycentre sweeps, down then up.
  for (let sweep: number = 0; sweep < 8; sweep++) {
    const downward: boolean = sweep % 2 === 0;
    for (let k: number = 1; k < ranks.length; k++) {
      const rk: IGraphNode[] = ranks[downward ? k : ranks.length - 1 - k];
      const bary: { [id: string]: number } = {};
      rk.forEach((n: IGraphNode): void => {
        const near: IGraphNode[] = (downward ? up[n.id] : down[n.id]) || [];
        bary[n.id] = near.length ? near.reduce((s: number, m: IGraphNode): number => s + pos[m.id], 0) / near.length : pos[n.id];
      });
      rk.sort((a: IGraphNode, b: IGraphNode): number => groupKey(a) - groupKey(b) || bary[a.id] - bary[b.id] || index[a.id] - index[b.id]);
      setPos();
    }
  }

  // Place: across = position along a rank, along = the rank's offset.
  const across: (n: IGraphNode) => number = (n: IGraphNode): number => (opts.vertical ? n.w : n.h);
  const depth: (n: IGraphNode) => number = (n: IGraphNode): number => (opts.vertical ? n.h : n.w);
  const centre: { [id: string]: number } = {};
  let along: number = 0;
  ranks.forEach((rk: IGraphNode[]): void => {
    const size: number = rk.reduce((m: number, n: IGraphNode): number => Math.max(m, depth(n)), 0);
    // Where each node would like to be: level with what feeds it.
    const want: number[] = rk.map((n: IGraphNode): number => {
      const near: IGraphNode[] = up[n.id] || [];
      return near.length ? near.reduce((s: number, m: IGraphNode): number => s + centre[m.id], 0) / near.length : NaN;
    });
    let cursor: number = 0;
    const start: number[] = [];
    rk.forEach((n: IGraphNode, i: number): void => {
      const gap: number = i === 0 ? 0 : (rk[i - 1].group !== n.group ? opts.groupGap : opts.nodeGap);
      const lowest: number = i === 0 ? -Infinity : cursor + gap;
      const desired: number = isNaN(want[i]) ? lowest : want[i] - across(n) / 2;
      start[i] = i === 0 && isNaN(want[i]) ? 0 : Math.max(lowest, desired);
      cursor = start[i] + across(n);
    });
    // Shift the rank as a whole so it sits evenly about where it wanted to be.
    const wanted: number[] = [];
    rk.forEach((n: IGraphNode, i: number): void => { if (!isNaN(want[i])) { wanted.push(want[i] - across(n) / 2 - start[i]); } });
    const shift: number = wanted.length ? wanted.reduce((s: number, v: number): number => s + v, 0) / wanted.length : 0;
    rk.forEach((n: IGraphNode, i: number): void => {
      const a: number = start[i] + shift;
      const d: number = along + (size - depth(n)) / 2;
      if (opts.vertical) { n.x = a; n.y = d; } else { n.x = d; n.y = a; }
      centre[n.id] = a + across(n) / 2;
    });
    along += size + opts.rankGap;
  });

  if (!all.length) { return { width: 0, height: 0 }; }
  let minX: number = Infinity;
  let minY: number = Infinity;
  let maxX: number = -Infinity;
  let maxY: number = -Infinity;
  all.forEach((n: IGraphNode): void => {
    minX = Math.min(minX, n.x); minY = Math.min(minY, n.y);
    maxX = Math.max(maxX, n.x + n.w); maxY = Math.max(maxY, n.y + n.h);
  });
  all.forEach((n: IGraphNode): void => { n.x -= minX; n.y -= minY; });
  return { width: maxX - minX, height: maxY - minY };
}

// Depth-first in input order; an edge back to a node still on the path
// closes a cycle and is drawn as a back edge.
function markBackEdges(nodes: IGraphNode[], edges: IGraphEdge[]): void {
  const state: { [id: string]: number } = {};
  const out: { [id: string]: IGraphEdge[] } = {};
  edges.forEach((e: IGraphEdge): void => { e.back = false; (out[e.from] = out[e.from] || []).push(e); });
  const visit: (id: string) => void = (id: string): void => {
    state[id] = 1;
    (out[id] || []).forEach((e: IGraphEdge): void => {
      if (state[e.to] === 1) { e.back = true; } else if (!state[e.to]) { visit(e.to); }
    });
    state[id] = 2;
  };
  // Start from nodes nothing points at, so a cycle breaks at its far end.
  const fed: { [id: string]: boolean } = {};
  edges.forEach((e: IGraphEdge): void => { fed[e.to] = true; });
  nodes.forEach((n: IGraphNode): void => { if (!fed[n.id] && !state[n.id]) { visit(n.id); } });
  nodes.forEach((n: IGraphNode): void => { if (!state[n.id]) { visit(n.id); } });
}

export interface IEdgePath {
  d: string;
  mid: { x: number; y: number };
}

function f(n: number): string {
  return String(Math.round(n * 10) / 10);
}

// A forward edge: out of one node, through each placeholder it crosses, into
// the next, as curves between ranks and straight runs through placeholders.
export function forwardPath(a: IGraphNode, b: IGraphNode, via: IGraphNode[], vertical: boolean): IEdgePath {
  let cur: number[] = vertical ? [a.x + a.w / 2, a.y + a.h] : [a.x + a.w, a.y + a.h / 2];
  let d: string = 'M' + f(cur[0]) + ',' + f(cur[1]);
  let mid: { x: number; y: number } = { x: 0, y: 0 };
  const curveTo: (q: number[]) => void = (q: number[]): void => {
    const m: number = vertical ? (cur[1] + q[1]) / 2 : (cur[0] + q[0]) / 2;
    const c1: number[] = vertical ? [cur[0], m] : [m, cur[1]];
    const c2: number[] = vertical ? [q[0], m] : [m, q[1]];
    d += ' C' + f(c1[0]) + ',' + f(c1[1]) + ' ' + f(c2[0]) + ',' + f(c2[1]) + ' ' + f(q[0]) + ',' + f(q[1]);
    mid = { x: (cur[0] + 3 * c1[0] + 3 * c2[0] + q[0]) / 8, y: (cur[1] + 3 * c1[1] + 3 * c2[1] + q[1]) / 8 };
    cur = q;
  };
  via.forEach((v: IGraphNode): void => {
    curveTo(vertical ? [v.x + v.w / 2, v.y] : [v.x, v.y + v.h / 2]);
    cur = vertical ? [v.x + v.w / 2, v.y + v.h] : [v.x + v.w, v.y + v.h / 2];
    d += ' L' + f(cur[0]) + ',' + f(cur[1]);
  });
  curveTo(vertical ? [b.x + b.w / 2, b.y] : [b.x, b.y + b.h / 2]);
  return { d: d, mid: mid };
}

// A back or same-rank edge: a loop round the outside of the drawing, on the
// near side (`before` is above, or left when vertical), `reach` beyond the
// nodes so its label clears whatever runs between them.
export function loopPath(a: IGraphNode, b: IGraphNode, vertical: boolean, reach: number, before: boolean): IEdgePath {
  let p0: number[];
  let p3: number[];
  let p1: number[];
  let p2: number[];
  if (vertical) {
    const ax: number = before ? a.x : a.x + a.w;
    const bx: number = before ? b.x : b.x + b.w;
    p0 = [ax, a.y + a.h / 2]; p3 = [bx, b.y + b.h / 2];
    const out: number = before ? Math.min(ax, bx) - reach : Math.max(ax, bx) + reach;
    p1 = [out, p0[1]]; p2 = [out, p3[1]];
  } else {
    const ay: number = before ? a.y : a.y + a.h;
    const by: number = before ? b.y : b.y + b.h;
    p0 = [a.x + a.w / 2, ay]; p3 = [b.x + b.w / 2, by];
    const out: number = before ? Math.min(ay, by) - reach : Math.max(ay, by) + reach;
    p1 = [p0[0], out]; p2 = [p3[0], out];
  }
  return {
    d: 'M' + f(p0[0]) + ',' + f(p0[1]) + ' C' + f(p1[0]) + ',' + f(p1[1]) + ' ' + f(p2[0]) + ',' + f(p2[1]) + ' ' + f(p3[0]) + ',' + f(p3[1]),
    mid: { x: (p0[0] + 3 * p1[0] + 3 * p2[0] + p3[0]) / 8, y: (p0[1] + 3 * p1[1] + 3 * p2[1] + p3[1]) / 8 }
  };
}
