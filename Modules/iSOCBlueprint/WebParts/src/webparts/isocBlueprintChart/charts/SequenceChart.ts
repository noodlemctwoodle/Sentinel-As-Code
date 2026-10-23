import { type ISequenceData, type ISequenceStep } from './ChartTypes';
import { type IChartTheme, esc, list, marker, nextId, r, rect, str, svgDoc, svgText, textWidth, widest, wrapText } from './ChartKit';

interface IActor {
  id: string;
  lines: string[];
  w: number;
  x: number;
}

interface IFrame {
  kind: string;
  text: string;
  top: number;
  depth: number;
  dividers: { y: number; text: string }[];
}

const BOX_H_LINE: number = 16;
const TEXT_W: number = 150;

// Participants across the top with their lifelines, and each message, note
// and block (loop, alt, opt and the like) in order down the page.
export function renderSequence(data: ISequenceData, theme: IChartTheme, label: string): string {
  const actors: IActor[] = list<{ id: string; label?: string }>(data && data.participants).map((p: { id: string; label?: string }): IActor => {
    const lines: string[] = wrapText(str(p.label) || str(p.id), 100, 12, true);
    return { id: str(p.id), lines: lines, w: Math.max(72, widest(lines, 12, true) + 20), x: 0 };
  });
  const steps: ISequenceStep[] = list<ISequenceStep>(data && data.steps);
  const at: { [id: string]: number } = {};
  const ensure: (id: string) => number = (id: string): number => {
    if (at[id] === undefined) {
      const lines: string[] = [id];
      actors.push({ id: id, lines: lines, w: Math.max(84, widest(lines, 12, true) + 24), x: 0 });
      at[id] = actors.length - 1;
    }
    return at[id];
  };
  actors.forEach((a: IActor, i: number): void => { at[a.id] = i; });
  steps.forEach((s: ISequenceStep): void => {
    if (s.kind === 'message') { ensure(str(s.from)); ensure(str(s.to)); }
    if (s.kind === 'note') { list<unknown>(s.over).forEach((o: unknown): void => { ensure(str(o)); }); }
  });
  if (!actors.length) { return ''; }

  // Space the lifelines so every message's text fits between its ends.
  const gaps: number[] = actors.map((a: IActor, i: number): number => (i < actors.length - 1 ? Math.max(96, a.w / 2 + actors[i + 1].w / 2 + 16) : 0));
  steps.forEach((s: ISequenceStep): void => {
    const textW: number = widest(wrapText(str(s.text), TEXT_W, 12), 12);
    if (s.kind === 'message') {
      const a: number = at[str(s.from)];
      const b: number = at[str(s.to)];
      if (a === b) { if (a < gaps.length - 1) { gaps[a] = Math.max(gaps[a], textW + 50); } return; }
      const lo: number = Math.min(a, b);
      const hi: number = Math.max(a, b);
      let have: number = 0;
      for (let i: number = lo; i < hi; i++) { have += gaps[i]; }
      const need: number = textW + 36;
      if (have < need) { for (let i: number = lo; i < hi; i++) { gaps[i] += (need - have) / (hi - lo); } }
    }
  });
  let x: number = actors[0].w / 2 + 8;
  actors.forEach((a: IActor, i: number): void => { a.x = x; x += gaps[i]; });
  const right: number = actors[actors.length - 1].x + actors[actors.length - 1].w / 2 + 8;

  const boxH: number = actors.reduce((m: number, a: IActor): number => Math.max(m, a.lines.length * BOX_H_LINE + 18), 0);
  const arrowId: string = nextId('seq');
  const openId: string = nextId('seqo');
  let y: number = boxH + 24;
  let body: string = '';
  let frames: string = '';
  const stack: IFrame[] = [];
  let number: number = 0;
  let extraRight: number = right;

  steps.forEach((s: ISequenceStep): void => {
    if (s.kind === 'message') {
      const a: IActor = actors[at[str(s.from)]];
      const b: IActor = actors[at[str(s.to)]];
      const lines: string[] = wrapText(str(s.text), TEXT_W, 12);
      const textH: number = lines.length * 15;
      const lineY: number = y + textH + 6;
      const dash: string = s.dashed ? ' stroke-dasharray="6 4"' : '';
      if (a === b) {
        const loopX: number = a.x + 44;
        body += '<path d="M' + r(a.x) + ',' + r(lineY) + ' H' + r(loopX) + ' V' + r(lineY + 18) + ' H' + r(a.x + 3) + '" fill="none" stroke="' + esc(theme.text) + '" stroke-width="1.4"' + dash + ' marker-end="url(#' + arrowId + ')"/>';
        body += svgText(a.x + 8, y + textH / 2, lines, { size: 12, fill: theme.text, lineHeight: 15 });
        extraRight = Math.max(extraRight, a.x + 52 + widest(lines, 12));
        y = lineY + 30;
      } else {
        const dir: number = b.x > a.x ? 1 : -1;
        body += '<line x1="' + r(a.x) + '" y1="' + r(lineY) + '" x2="' + r(b.x - dir * 2) + '" y2="' + r(lineY) + '" stroke="' + esc(theme.text) + '" stroke-width="1.4"' + dash +
          ' marker-end="url(#' + (s.dashed ? openId : arrowId) + ')"/>';
        body += svgText((a.x + b.x) / 2, y + textH / 2, lines, { size: 12, fill: theme.text, anchor: 'middle', lineHeight: 15 });
        y = lineY + 16;
      }
      if (data.autonumber) {
        number++;
        body += '<circle cx="' + r(a.x) + '" cy="' + r(lineY) + '" r="9" fill="' + esc(theme.accent) + '"/>' +
          svgText(a.x, lineY, [String(number)], { size: 10, weight: 600, fill: '#ffffff', anchor: 'middle' });
      }
      return;
    }
    if (s.kind === 'note') {
      const over: number[] = list<unknown>(s.over).map((o: unknown): number => at[str(o)]).filter((i: number): boolean => i !== undefined);
      if (!over.length) { return; }
      const lines: string[] = wrapText(str(s.text), 200, 12);
      const w: number = widest(lines, 12) + 20;
      const h: number = lines.length * 15 + 12;
      const xs: number[] = over.map((i: number): number => actors[i].x);
      let x0: number;
      let x1: number;
      if (s.position === 'left of') { x1 = xs[0] - 10; x0 = x1 - w; }
      else if (s.position === 'right of') { x0 = xs[0] + 10; x1 = x0 + w; }
      else {
        const lo: number = Math.min(...xs);
        const hi: number = Math.max(...xs);
        const span: number = Math.max(w, hi - lo + 40);
        x0 = (lo + hi) / 2 - span / 2; x1 = x0 + span;
      }
      extraRight = Math.max(extraRight, x1);
      body += rect(x0, y, x1 - x0, h, 'rx="4" fill="' + (theme.dark ? '#3f2d0a' : '#fef3c7') + '" stroke="#d97706"') +
        svgText(x0 + (x1 - x0) / 2, y + h / 2, lines, { size: 12, fill: theme.dark ? '#fde68a' : '#78350f', anchor: 'middle', lineHeight: 15 });
      y += h + 14;
      return;
    }
    if (s.kind === 'block') {
      const kind: string = str(s.block);
      if ((kind === 'else' || kind === 'and') && stack.length) {
        stack[stack.length - 1].dividers.push({ y: y, text: str(s.text) });
        y += 24;
        return;
      }
      stack.push({ kind: kind, text: str(s.text), top: y, depth: stack.length, dividers: [] });
      y += 30;
      return;
    }
    if (s.kind === 'end' && stack.length) {
      const f: IFrame = stack.pop() as IFrame;
      frames += frame(f, y, actors, theme);
      y += 14;
    }
  });
  while (stack.length) { frames += frame(stack.pop() as IFrame, y, actors, theme); y += 14; }

  let lifelines: string = '';
  let heads: string = '';
  actors.forEach((a: IActor): void => {
    lifelines += '<line x1="' + r(a.x) + '" y1="' + boxH + '" x2="' + r(a.x) + '" y2="' + r(y) + '" stroke="' + esc(theme.line) + '" stroke-width="1.5" stroke-dasharray="4 4"/>';
    heads += rect(a.x - a.w / 2, 0, a.w, boxH, 'rx="8" fill="' + esc(theme.surface) + '" stroke="' + esc(theme.accent) + '" stroke-width="1.5"') +
      rect(a.x - a.w / 2, 0, a.w, boxH, 'rx="8" fill="' + esc(theme.accent) + '" fill-opacity="0.08"') +
      svgText(a.x, boxH / 2, a.lines, { size: 12, weight: 600, fill: theme.text, anchor: 'middle', lineHeight: BOX_H_LINE });
  });
  const defs: string = '<defs>' + marker(arrowId, 'arrow', theme.text, theme.surface) +
    '<marker id="' + openId + '" viewBox="0 0 12 12" refX="11" refY="6" markerWidth="10" markerHeight="10" orient="auto" markerUnits="userSpaceOnUse">' +
    '<path d="M1,1 L11,6 L1,11" fill="none" stroke="' + esc(theme.text) + '" stroke-width="1.4"/></marker></defs>';
  return svgDoc(Math.max(right, extraRight) + 30, y + 6, label, defs + frames + lifelines + body + heads);
}

function frame(f: IFrame, bottom: number, actors: IActor[], theme: IChartTheme): string {
  const inset: number = f.depth * 8;
  const x0: number = actors[0].x - actors[0].w / 2 - 6 + inset;
  const x1: number = actors[actors.length - 1].x + actors[actors.length - 1].w / 2 + 6 - inset;
  const tag: string = f.kind + (f.text ? ' [' + f.text + ']' : '');
  const tagW: number = textWidth(tag, 11, true) + 16;
  let out: string = rect(x0, f.top, x1 - x0, bottom - f.top + 4, 'rx="4" fill="none" stroke="' + esc(theme.muted) + '" stroke-width="1.2"') +
    rect(x0, f.top, tagW, 20, 'fill="' + esc(theme.muted) + '" fill-opacity="0.15"') +
    svgText(x0 + 8, f.top + 10, [tag], { size: 11, weight: 600, fill: theme.text });
  f.dividers.forEach((d: { y: number; text: string }): void => {
    out += '<line x1="' + r(x0) + '" y1="' + r(d.y + 4) + '" x2="' + r(x1) + '" y2="' + r(d.y + 4) + '" stroke="' + esc(theme.muted) + '" stroke-dasharray="5 4"/>' +
      (d.text ? svgText(x0 + 8, d.y + 15, ['[' + d.text + ']'], { size: 11, fill: theme.muted }) : '');
  });
  return out;
}
