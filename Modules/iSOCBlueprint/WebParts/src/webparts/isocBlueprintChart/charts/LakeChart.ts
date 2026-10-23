import { type ILakeData, type ILakeUse } from './ChartTypes';
import { type IChartTheme, esc, list, num, str, tint } from './ChartKit';
import { arrow, card, chip, count, eyebrow, figure, sub } from './Visual';

// The Sentinel data lake's tiers on this workspace: the Analytics tier and
// how much of it is mirrored or kept longer in the lake, the lake-only
// tier, the lake they both land in, and the ways the lake is worked with.

const ANA: string = '#d97706';
const LAKE: string = '#2563eb';
const ONLY: string = '#0891b2';
const USE: string = '#16a34a';

export function renderLake(data: ILakeData, theme: IChartTheme): string {
  if (!data) { return ''; }
  const analytics: number = num(data.analyticsOnly) + num(data.mirrored) + num(data.extended);
  const lakeOnly: number = num(data.lakeOnly);
  const uses: ILakeUse[] = list<ILakeUse>(data.uses);
  const left: string = '<div style="display:flex;flex-direction:column;gap:12px">' +
    card(eyebrow('Analytics tier', theme, ANA) + figure(count(analytics) + ' tables', theme, 22) +
      sub('Real-time KQL and analytics rules', theme) +
      '<div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:9px">' +
      chip(count(num(data.mirrored) + num(data.extended)) + ' mirrored to the lake', theme) +
      chip(count(num(data.extended)) + ' kept longer in the lake', theme) +
      chip(count(num(data.analyticsOnly)) + ' Analytics only', theme) + '</div>', theme, ANA) +
    card(eyebrow('Lake-only tier', theme, ONLY) + figure(count(lakeOnly) + ' tables', theme, 22) +
      sub('Verbose, rarely queried data, straight to the lake; no real-time rules', theme), theme, lakeOnly > 0 ? ONLY : undefined, lakeOnly > 0 ? '' : 'opacity:.7') +
    '</div>';
  const lake: string = card(eyebrow('Sentinel data lake', theme, LAKE) +
    '<div style="font-size:15px;font-weight:800;margin-top:6px">Up to ' + esc(str(data.retentionYears) || '12') + ' years of affordable retention</div>' +
    sub('Stored as Parquet, about 6:1 compressed. The Analytics tier mirrors to it automatically.', theme), theme, LAKE, 'display:flex;flex-direction:column;justify-content:center');
  const use: string = uses.length
    ? '<div>' + eyebrow('Working with the lake', theme) +
      '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-top:8px">' +
      uses.map((u: ILakeUse): string => '<div style="min-width:0;border-radius:10px;padding:9px 11px;background:' + tint(USE, theme.dark ? 0.1 : 0.05) + ';border:1px solid ' + tint(USE, 0.3) + '">' +
        '<div style="font-size:12.5px;font-weight:750">' + esc(u.name) + '</div>' +
        '<div style="font-size:11.5px;color:' + esc(theme.muted) + ';margin-top:2px;line-height:1.4">' + esc(u.detail) + '</div></div>').join('') + '</div></div>'
    : '';
  return '<div style="display:flex;flex-direction:column;gap:14px;font-size:13px;color:' + esc(theme.text) + '">' +
    '<div style="display:grid;grid-template-columns:minmax(240px,1fr) 44px minmax(220px,.9fr);min-width:540px;align-items:stretch">' +
    left + arrow(ANA, LAKE) + lake + '</div>' + use + '</div>';
}
