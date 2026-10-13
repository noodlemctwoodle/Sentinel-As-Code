// The chart block of the Blueprint section model, as the publisher stores it
// in the web part's chartJson property. Shapes follow
// Docs/iSOCBlueprint/Section-Model.md (Charts). The JSON carries null for
// absent values, so every field is read as optional and checked at runtime.

export interface IChart {
  kind: string;
  title?: string;
  data?: unknown;
  source?: string;
}

export interface IPieData {
  showData?: boolean;
  slices: IPieSlice[];
}

export interface IPieSlice {
  label: string;
  value: number;
}

export interface IXyData {
  xAxis?: { title?: string; labels?: string[] };
  yAxis?: { title?: string; min?: number; max?: number };
  series: IXySeries[];
}

export interface IXySeries {
  kind: string;
  name?: string;
  values: number[];
}

export interface ISankeyData {
  links: ISankeyLink[];
}

export interface ISankeyLink {
  source: string;
  target: string;
  value: number;
}

export interface ITimelineData {
  periods: { label: string; section?: string; events: string[] }[];
}

export interface IGanttData {
  dateFormat?: string;
  axisFormat?: string;
  sections: { name: string; tasks: IGanttTask[] }[];
}

export interface IGanttTask {
  label: string;
  tags?: string[];
  id?: string;
  start?: string;
  length?: string;
}

export interface IMindmapNode {
  text: string;
  children?: IMindmapNode[];
}

export interface IFlowData {
  direction?: string;
  groups?: { id: string; label?: string; parent?: string }[];
  nodes: IFlowNode[];
  edges: IFlowEdge[];
}

export interface IFlowNode {
  id: string;
  label?: string;
  group?: string;
  fill?: string;
  stroke?: string;
  color?: string;
  href?: string;
  tooltip?: string;
}

export interface IFlowEdge {
  from: string;
  to: string;
  label?: string;
  style?: string;
  arrow?: boolean;
}

export interface ISequenceData {
  autonumber?: boolean;
  participants: { id: string; label?: string; kind?: string }[];
  steps: ISequenceStep[];
}

export interface ISequenceStep {
  kind: string;
  from?: string;
  to?: string;
  text?: string;
  dashed?: boolean;
  position?: string;
  over?: string[];
  block?: string;
}

export interface IStateData {
  states: { id: string; label?: string; parent?: string }[];
  transitions: { from: string; to: string; label?: string; parent?: string }[];
  notes?: { state: string; position?: string; text?: string }[];
}

export interface IClassData {
  classes: { name: string; members?: string[] }[];
  relations: { from: string; to: string; kind: string; label?: string }[];
  notes?: { for?: string; text?: string }[];
}

export interface IJourneyData {
  sections: { name: string; tasks: { label: string; score: number; actors?: string[] }[] }[];
}
