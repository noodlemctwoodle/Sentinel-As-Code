import { type IChartTheme, rect, svgText, widest, wrapText } from './ChartKit';
import { type IDrawNode } from './GraphDraw';

// A sticky note for state and class diagrams, joined to what it describes by
// a dashed line.
export function noteNode(id: string, text: string, theme: IChartTheme): IDrawNode {
  const lines: string[] = wrapText(text, 200, 12);
  const fill: string = theme.dark ? '#3f2d0a' : '#fef3c7';
  const ink: string = theme.dark ? '#fde68a' : '#78350f';
  return {
    id: id, w: widest(lines, 12) + 22, h: lines.length * 16 + 16, x: 0, y: 0, rank: 0,
    draw: (b: IDrawNode): string =>
      rect(b.x, b.y, b.w, b.h, 'rx="4" fill="' + fill + '" stroke="#d97706" stroke-width="1"') +
      svgText(b.x + 11, b.y + b.h / 2, lines, { size: 12, fill: ink, lineHeight: 16 })
  };
}
