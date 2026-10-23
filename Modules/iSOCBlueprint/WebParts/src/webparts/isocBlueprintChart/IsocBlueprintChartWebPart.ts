import { Version } from '@microsoft/sp-core-library';
import { BaseClientSideWebPart } from '@microsoft/sp-webpart-base';
import { type IReadonlyTheme } from '@microsoft/sp-component-base';

import { type IChart } from './charts/ChartTypes';
import { type IChartTheme, FONT, setSiteUrl, setTextMeasurer } from './charts/ChartKit';
import { renderChart } from './charts/renderChart';
import { chartStyles } from './charts/Visual';

// The class the chart's own stylesheet is scoped to.
const SCOPE: string = 'sac-chart';

export interface IIsocBlueprintChartWebPartProps {
  chartJson: string;
}

// Draws one chart of an iSOC Blueprint section page. The publisher stores
// the chart block from the Blueprint section model (kind, title, data) as
// JSON in the chartJson property; the chart is drawn here as SVG and HTML,
// with no script libraries and nothing fetched.
export default class IsocBlueprintChartWebPart extends BaseClientSideWebPart<IIsocBlueprintChartWebPartProps> {

  private _theme: IReadonlyTheme | undefined;

  protected onInit(): Promise<void> {
    setTextMeasurer(this._canvasMeasurer());
    // The publisher writes links within the site as ~site/...; they resolve here.
    setSiteUrl(this.context.pageContext.web.serverRelativeUrl);
    // A long list's Show all button, as the dashboard has it: the rows
    // marked data-mr show or hide, and the button reads Show fewer when open.
    this.domElement.addEventListener('click', (e: MouseEvent): void => {
      const target: Element | null = e.target instanceof Element ? e.target : null;
      const button: HTMLElement | null = target ? target.closest('[data-more]') as HTMLElement | null : null;
      const wrap: Element | null = button ? button.closest('.morewrap') : null;
      if (!button || !wrap) { return; }
      const open: boolean = wrap.classList.toggle('open');
      wrap.querySelectorAll('[data-mr]').forEach((row: Element): void => {
        if (row.closest('.morewrap') === wrap) { (row as HTMLElement).hidden = !open; }
      });
      button.textContent = open ? (button.dataset.less || 'Show fewer') : (button.dataset.all || '');
    });
    return super.onInit();
  }

  public render(): void {
    const theme: IChartTheme = this._chartTheme();
    this.domElement.innerHTML = '<style>' + chartStyles(SCOPE, theme) + '</style>' +
      '<div class="' + SCOPE + '">' + renderChart(this._chart(), theme) + '</div>';
  }

  protected onThemeChanged(theme: IReadonlyTheme | undefined): void {
    this._theme = theme;
    if (this.renderedOnce) { this.render(); }
  }

  private _chart(): IChart | undefined {
    const json: string = (this.properties.chartJson || '').trim();
    if (!json) { return undefined; }
    try {
      const parsed: unknown = JSON.parse(json);
      return parsed && typeof parsed === 'object' ? parsed as IChart : undefined;
    } catch {
      return undefined;
    }
  }

  // Colours from the section's theme, so a chart reads on a coloured or
  // dark section background as well as on white.
  private _chartTheme(): IChartTheme {
    const semantic: { [key: string]: string | undefined } =
      (this._theme && this._theme.semanticColors ? this._theme.semanticColors : {}) as { [key: string]: string | undefined };
    const palette: { [key: string]: string | undefined } =
      (this._theme && this._theme.palette ? this._theme.palette : {}) as { [key: string]: string | undefined };
    const dark: boolean = !!(this._theme && this._theme.isInverted);
    return {
      text: semantic.bodyText || (dark ? '#f3f4f6' : '#1f2430'),
      muted: semantic.bodySubtext || (dark ? '#a1a8b8' : '#5b6479'),
      line: semantic.bodyDivider || (dark ? '#3a4255' : '#e3e7ef'),
      surface: semantic.bodyBackground || (dark ? '#1b1f2a' : '#ffffff'),
      accent: palette.themePrimary || '#2563eb',
      dark: dark
    };
  }

  private _canvasMeasurer(): ((text: string, size: number, bold: boolean) => number) | undefined {
    try {
      const context: CanvasRenderingContext2D | null = document.createElement('canvas').getContext('2d');
      if (!context) { return undefined; }
      return (text: string, size: number, bold: boolean): number => {
        context.font = (bold ? '600 ' : '400 ') + size + 'px ' + FONT;
        return context.measureText(text).width;
      };
    } catch {
      return undefined;
    }
  }

  protected get dataVersion(): Version {
    return Version.parse('1.0');
  }
}
