import {
  type IChart, type IClassData, type IFlowData, type IGanttData, type IJourneyData, type IMindmapNode, type IPieData,
  type ISankeyData, type ISequenceData, type IStateData, type ITimelineData, type IXyData
} from './ChartTypes';
import { type IChartTheme, FONT, esc, str } from './ChartKit';
import { renderPie } from './PieChart';
import { renderXy } from './XyChart';
import { renderSankey } from './SankeyChart';
import { renderTimeline } from './TimelineChart';
import { renderGantt } from './GanttChart';
import { renderMindmap } from './MindmapChart';
import { renderFlowchart } from './FlowChart';
import { renderState } from './StateChart';
import { renderClass } from './ClassChart';
import { renderSequence } from './SequenceChart';
import { renderJourney } from './JourneyChart';

// The markup for one chart block: its title, then the chart drawn from its
// data. A kind this web part does not draw, or data it cannot read, shows
// the chart's Mermaid source (when it has one) rather than nothing.
export function renderChart(chart: IChart | undefined, theme: IChartTheme): string {
  if (!chart || !str(chart.kind)) {
    return wrap('', note('This web part draws a chart from the iSOC Blueprint. The Blueprint publisher supplies its data.', theme), theme);
  }
  const title: string = str(chart.title);
  const label: string = title || describe(chart.kind);
  let body: string = '';
  try {
    body = draw(chart, theme, label);
  } catch {
    body = '';
  }
  if (!body) {
    body = chart.source
      ? '<pre style="margin:0;padding:12px;border:1px solid ' + esc(theme.line) + ';border-radius:8px;overflow:auto;font-size:12px;white-space:pre">' + esc(chart.source) + '</pre>'
      : note('No data to chart.', theme);
  }
  return wrap(title, body, theme);
}

function draw(chart: IChart, theme: IChartTheme, label: string): string {
  const data: unknown = chart.data;
  switch (str(chart.kind)) {
    case 'pie': return renderPie(data as IPieData, theme, label);
    case 'xy': return renderXy(data as IXyData, theme, label);
    case 'sankey': return renderSankey(data as ISankeyData, theme, label);
    case 'timeline': return renderTimeline(data as ITimelineData, theme);
    case 'gantt': return renderGantt(data as IGanttData, theme, label);
    case 'mindmap': return renderMindmap(data as { root?: IMindmapNode }, theme, label);
    case 'flowchart': return renderFlowchart(data as IFlowData, theme, label);
    case 'state': return renderState(data as IStateData, theme, label);
    case 'class': return renderClass(data as IClassData, theme, label);
    case 'sequence': return renderSequence(data as ISequenceData, theme, label);
    case 'journey': return renderJourney(data as IJourneyData, theme);
    default: return '';
  }
}

function describe(kind: string): string {
  const names: { [kind: string]: string } = {
    pie: 'Pie chart', xy: 'Bar chart', sankey: 'Flow diagram', timeline: 'Timeline', gantt: 'Schedule',
    mindmap: 'Mind map', flowchart: 'Diagram', state: 'State diagram', class: 'Class diagram',
    sequence: 'Sequence diagram', journey: 'Journey'
  };
  return names[kind] || 'Chart';
}

function note(text: string, theme: IChartTheme): string {
  return '<p style="margin:0;color:' + esc(theme.muted) + ';font-style:italic">' + esc(text) + '</p>';
}

// Wide diagrams scroll sideways on a narrow screen rather than shrinking
// their text out of reach.
function wrap(title: string, body: string, theme: IChartTheme): string {
  return '<figure style="margin:0;font-family:' + esc(FONT) + ';color:' + esc(theme.text) + '">' +
    (title ? '<figcaption style="font-size:15px;font-weight:600;margin:0 0 12px">' + esc(title) + '</figcaption>' : '') +
    '<div style="overflow-x:auto;-webkit-overflow-scrolling:touch">' + body + '</div>' +
    '</figure>';
}
