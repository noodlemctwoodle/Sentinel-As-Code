import { type ITimelineData } from './ChartTypes';
import { type IChartTheme, esc, list, str } from './ChartKit';

interface IPeriod {
  label: string;
  section?: string;
  events: string[];
}

// A vertical timeline: each period's label beside a dot on a rail, with its
// events listed. Section headings, when the timeline has them, sit on the rail.
export function renderTimeline(data: ITimelineData, theme: IChartTheme): string {
  const periods: IPeriod[] = list<IPeriod>(data && data.periods);
  if (!periods.length) { return ''; }
  let lastSection: string = '';
  let out: string = '<ol style="list-style:none;margin:0;padding:0;font-size:14px;color:' + esc(theme.text) + '">';
  periods.forEach((p: IPeriod, i: number): void => {
    const section: string = str(p.section);
    if (section && section !== lastSection) {
      out += '<li style="margin:' + (i ? '14px' : '0') + ' 0 6px;font-size:12px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;color:' + esc(theme.muted) + '">' + esc(section) + '</li>';
      lastSection = section;
    }
    const last: boolean = i === periods.length - 1;
    out += '<li style="display:flex;gap:14px;align-items:stretch">' +
      '<div style="flex:none;width:112px;text-align:right;font-weight:600;padding:1px 0 14px;font-variant-numeric:tabular-nums">' + esc(p.label) + '</div>' +
      '<div style="flex:none;position:relative;width:14px">' +
      '<span style="position:absolute;left:3px;top:5px;width:8px;height:8px;border-radius:50%;background:' + esc(theme.accent) + '"></span>' +
      (last ? '' : '<span style="position:absolute;left:6px;top:15px;bottom:-4px;width:2px;background:' + esc(theme.line) + '"></span>') +
      '</div>' +
      '<ul style="flex:1 1 auto;min-width:0;margin:0;padding:0 0 14px 0;list-style:none">' +
      list<unknown>(p.events).map((e: unknown): string => '<li style="padding:1px 0">' + esc(str(e)) + '</li>').join('') +
      '</ul></li>';
  });
  return out + '</ol>';
}
