import { type IFindingCard, type IFindingCardsData } from './ChartTypes';
import { type IChartTheme, esc, list, safeHref, str } from './ChartKit';
import { BAD, INFO, WARN, card, chip, eyebrow, pill } from './Visual';

// The most severe findings as cards, as the dashboard's Overview shows
// them: severity, id and title, the category, what was found beside how to
// fix it (four lines each; the finding holds the full text), and links to
// the finding and to Microsoft Learn.

const SEVERITY: { [severity: string]: string } = { Critical: BAD, Warning: WARN, Info: INFO };
const CLAMP: string = 'display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;overflow:hidden';

export function renderFindingCards(data: IFindingCardsData, theme: IChartTheme): string {
  const cards: IFindingCard[] = list<IFindingCard>(data && data.cards);
  if (!cards.length) { return ''; }
  return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + esc(theme.text) + '">' +
    cards.map((c: IFindingCard): string => one(c, theme)).join('') + '</div>';
}

function one(c: IFindingCard, theme: IChartTheme): string {
  const colour: string = SEVERITY[str(c.severity)] || INFO;
  const head: string = '<div style="display:flex;align-items:baseline;gap:10px;flex-wrap:wrap">' +
    pill(str(c.severity), colour, true) +
    '<b style="font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12.5px">' + esc(c.id) + '</b>' +
    '<span style="font-weight:700;font-size:14px;line-height:1.35">' + esc(c.title) + '</span></div>';
  const meta: string = str(c.category) ? '<div style="margin-top:8px">' + chip(str(c.category), theme) + '</div>' : '';
  const block: (label: string, text: string) => string = (label: string, text: string): string => text
    ? '<div style="min-width:0">' + eyebrow(label, theme) + '<div style="margin-top:4px;font-size:12.5px;line-height:1.55;color:' + esc(theme.text) + ';' + CLAMP + '">' + esc(text) + '</div></div>'
    : '';
  const findingHref: string | undefined = safeHref(c.href);
  const learnHref: string | undefined = safeHref(c.learn);
  const link: (href: string, text: string, external: boolean) => string = (href: string, text: string, external: boolean): string =>
    '<a href="' + esc(href) + '"' + (external ? ' target="_blank" rel="noopener"' : '') + ' style="font-size:12px;font-weight:700;color:' + esc(theme.accent) + ';text-decoration:none">' + esc(text) + ' →</a>';
  const links: string[] = [];
  if (findingHref) { links.push(link(findingHref, 'Open the finding', false)); }
  if (learnHref) { links.push(link(learnHref, 'Microsoft Learn', true)); }
  return card(head + meta +
    '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px 22px;margin-top:12px">' +
    block('What was found', str(c.evidence)) + block('How to fix it', str(c.remediation)) + '</div>' +
    (links.length ? '<div style="display:flex;gap:18px;flex-wrap:wrap;margin-top:12px">' + links.join('') + '</div>' : ''), theme);
}
