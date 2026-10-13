// The chart block of the Blueprint section model, as the publisher stores it
// in the web part's chartJson property. Shapes follow
// Docs/Modules/iSOCBlueprint/Section-Model.md (Charts). The JSON carries null for
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

// A purpose-built graphic's data, from a "%% visual" line in the Mermaid.
// Counts are the window's incidents at their current status; acknowledged
// and unacknowledged split the closed ones by whether they were picked up
// before closing. Anything the capture lacks is null in the JSON, read as
// absent.
export interface IIncidentLifecycleData {
  days?: number;
  raised?: number;
  new?: number;
  active?: number;
  closed?: number;
  acknowledged?: number;
  unacknowledged?: number;
  mttaMinutes?: number;
  mttrMinutes?: number;
  unified?: number;
  openBySeverity?: ILifecycleCount[];
  classification?: ILifecycleCount[];
  closedBy?: ILifecycleCount[];
  check?: { id?: string; fired?: boolean };
}

export interface ILifecycleCount {
  label: string;
  count: number;
}

// Proportions of a whole: one card per meter, a stacked bar of its parts.
// A part's tone is ok, warn, bad, info, neutral, violet, teal, cyan or rose.
export interface IMetersData {
  meters: IMeter[];
}

export interface IMeter {
  title?: string;
  caption?: string;
  total?: number;
  parts: IMeterPart[];
}

export interface IMeterPart {
  label: string;
  value: number;
  tone?: string;
}

// The analytics rule kinds, with what each carries and how many are in use.
export interface IRuleKindsData {
  total?: number;
  common?: string[];
  kinds: IRuleKind[];
}

export interface IRuleKind {
  kind: string;
  label?: string;
  summary?: string;
  fields?: string[];
  deployed?: number;
  enabled?: number;
  legacy?: boolean;
}

// The alert-to-response chain: phases of numbered steps, each step ok,
// missing or risk on this workspace, with the finding behind it.
export interface IResponseChainData {
  phases: IChainPhase[];
}

export interface IChainPhase {
  name: string;
  figure?: string;
  steps: IChainStep[];
}

export interface IChainStep {
  n: number;
  action: string;
  actor?: string;
  target?: string;
  state?: string;
  finding?: string;
}

// The workspace topology: source families, the workspace's table plans and
// rules, and the destinations downstream.
export interface ITopologyData {
  sources: ITopologyItem[];
  sourceTotal?: number;
  rules?: number;
  plans?: ITopologyItem[];
  downstream?: ITopologyItem[];
}

export interface ITopologyItem {
  name: string;
  count?: number;
  inUse?: boolean;
  detail?: string;
}

// The monthly cost: the total, billable GB and cost by plan, and every
// source family's GB with every one of its tables.
export interface ICostBreakdownData {
  currency?: string;
  monthlyTotal?: number;
  totalGb?: number;
  plans?: ICostPlan[];
  sources?: ICostSource[];
}

export interface ICostPlan {
  name: string;
  gb: number;
  cost?: number;
}

export interface ICostSource {
  name: string;
  gb: number;
  tables?: ICostTable[];
}

export interface ICostTable {
  table: string;
  gb: number;
  tier?: string;
}

// Role assignments at workspace scope, in bands, by principal type.
export interface IAccessData {
  bands: IAccessBand[];
}

export interface IAccessBand {
  name: string;
  tone?: string;
  findings?: string[];
  roles: IAccessRole[];
}

export interface IAccessRole {
  role: string;
  users?: number;
  groups?: number;
  servicePrincipals?: number;
}

// The data lake's tiers on this workspace, by table count, and the ways the
// lake is worked with.
export interface ILakeData {
  analyticsOnly?: number;
  mirrored?: number;
  extended?: number;
  lakeOnly?: number;
  retentionYears?: number;
  uses?: ILakeUse[];
}

export interface ILakeUse {
  name: string;
  detail?: string;
}

// The estate: source families with the GB a detection reads, and the four
// pipeline stages as in use of a whole.
export interface IEstateData {
  totalGb?: number;
  coveredGb?: number;
  sources?: IEstateSource[];
  stages?: IEstateStage[];
}

export interface IEstateSource {
  name: string;
  gb: number;
  coveredGb?: number;
  tables?: number;
  covered?: number;
}

export interface IEstateStage {
  name: string;
  value: number;
  of: number;
  label?: string;
  detail?: string;
}

// Platform retirements with their dates and whether this workspace uses
// what each retires (inUse null when the workspace cannot say).
export interface IRunwayData {
  today?: string;
  items: IRunwayItem[];
}

export interface IRunwayItem {
  label: string;
  date: string;
  state?: string;
  inUse?: boolean;
  evidence?: string;
}

// The workspace's own history: created, age, terms and what it holds.
export interface IWorkspaceAgeData {
  created?: string;
  today?: string;
  ageDays?: number;
  sku?: string;
  retentionDays?: number;
  rulesEnabled?: number;
  connectors?: number;
  tablesReceiving?: number;
  tablesCatalogue?: number;
}
