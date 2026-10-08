import { Version } from '@microsoft/sp-core-library';
import {
  type IPropertyPaneConfiguration,
  PropertyPaneTextField
} from '@microsoft/sp-property-pane';
import { BaseClientSideWebPart } from '@microsoft/sp-webpart-base';
import { SPHttpClient, SPHttpClientResponse } from '@microsoft/sp-http';

import * as strings from 'SentinelNavigatorWebPartStrings';

export interface ISentinelNavigatorWebPartProps {
  fileRelativeUrl: string;
}

const DEFAULT_FILE: string = 'DocumenterAssets/dashboard/index.html';

export default class SentinelNavigatorWebPart extends BaseClientSideWebPart<ISentinelNavigatorWebPartProps> {

  private _onWindowResize: (() => void) | undefined;
  private _resizeObserver: ResizeObserver | undefined;

  public render(): void {
    this._detachListeners();
    const rel: string = (this.properties.fileRelativeUrl || DEFAULT_FILE).replace(/^\/+/, '');
    // The publisher places this web part in a full-width section (the
    // manifest declares supportsFullBleed), so the host simply fills it.
    this.domElement.innerHTML =
      '<div class="sdnHost" style="position:relative;width:100%"><div class="sdnMsg" style="font-family:Segoe UI,system-ui,sans-serif;color:#6b7280;padding:28px;text-align:center">Loading Sentinel dashboard&hellip;</div></div>';
    const host: HTMLElement = this.domElement.querySelector('.sdnHost') as HTMLElement;

    this._fetchHtml(rel)
      .then((html: string): void => {
        if (!html) { this._showError(host, rel, 'The dashboard file is empty.'); return; }
        this._renderIframe(host, html);
      })
      .catch((err: Error): void => {
        this._showError(host, rel, err && err.message ? err.message : String(err));
      });
  }

  protected onDispose(): void {
    this._detachListeners();
    super.onDispose();
  }

  private _detachListeners(): void {
    if (this._onWindowResize) {
      window.removeEventListener('resize', this._onWindowResize);
      this._onWindowResize = undefined;
    }
    if (this._resizeObserver) {
      this._resizeObserver.disconnect();
      this._resizeObserver = undefined;
    }
  }

  private _fetchHtml(rel: string): Promise<string> {
    const web = this.context.pageContext.web;
    const serverRel: string = (web.serverRelativeUrl + '/' + rel).replace(/\/{2,}/g, '/');
    const apiUrl: string =
      web.absoluteUrl +
      "/_api/web/GetFileByServerRelativeUrl('" + serverRel.replace(/'/g, "''") + "')/$value";
    return this.context.spHttpClient
      .get(apiUrl, SPHttpClient.configurations.v1, { headers: { accept: 'text/plain' } })
      .then((res: SPHttpClientResponse): Promise<string> => {
        if (!res.ok) { throw new Error('HTTP ' + res.status + ' fetching ' + serverRel); }
        return res.text();
      });
  }

  private _renderIframe(host: HTMLElement, html: string): void {
    host.innerHTML = '';
    const iframe: HTMLIFrameElement = document.createElement('iframe');
    iframe.setAttribute('title', 'Sentinel workspace dashboard');
    iframe.setAttribute('scrolling', 'no');
    iframe.style.width = '100%';
    iframe.style.border = '0';
    iframe.style.display = 'block';
    iframe.style.overflow = 'hidden';

    // SharePoint's page CSP is inherited by srcdoc documents and blocks inline
    // <script> but allows eval. So the dashboard's executable inline script is
    // taken out of the markup (inline styles and the inert application/json
    // model block are allowed and stay), then run inside the iframe with eval
    // once it has loaded. The dashboard HTML is trusted content: it comes from
    // this site's Documenter Assets library, which only the publisher and
    // site owners can write.
    const extracted: { markup: string; script: string } = this._extractScript(html);
    iframe.srcdoc = extracted.markup;
    host.appendChild(iframe);

    // Auto-height: grow the iframe to its content so the SharePoint page
    // scrolls as one, rather than squeezing a ~6000px dashboard into an inner
    // scroll box. Measure the body only: documentElement.scrollHeight is never
    // smaller than the iframe itself, so using it would only ever grow.
    const fitHeight = (): void => {
      try {
        const doc: Document | null = iframe.contentDocument;
        if (doc && doc.body) {
          const h: number = Math.max(doc.body.scrollHeight, doc.body.offsetHeight);
          if (h > 0 && Math.abs(h - (parseInt(iframe.style.height, 10) || 0)) > 1) {
            iframe.style.height = h + 'px';
          }
        }
      } catch { /* ignore */ }
    };

    iframe.addEventListener('load', (): void => {
      try {
        const win: Window | null = iframe.contentWindow;
        if (win && extracted.script) {
          (win as unknown as { eval: (s: string) => void }).eval(extracted.script);
        }
        if (win) {
          // Lets the dashboard ask for a remeasure after it changes the DOM
          // (tab switches, table filters, chart renders).
          (win as unknown as { fitIframe?: () => void }).fitIframe = (): void => { setTimeout(fitHeight, 0); };
          try {
            const RO: typeof ResizeObserver | undefined =
              (win as unknown as { ResizeObserver?: typeof ResizeObserver }).ResizeObserver;
            const doc: Document | null = iframe.contentDocument;
            if (RO && doc && doc.body) {
              this._resizeObserver = new RO((): void => fitHeight());
              this._resizeObserver.observe(doc.body);
            }
          } catch { /* ignore */ }
        }
      } catch { /* ignore */ }
      fitHeight();
      [120, 350, 800, 1500].forEach((t: number): void => { setTimeout(fitHeight, t); });
    });

    this._onWindowResize = fitHeight;
    window.addEventListener('resize', this._onWindowResize);
  }

  // Split out the dashboard's executable inline <script> (no type, or a
  // JavaScript type) and return the markup without it plus the script body.
  private _extractScript(html: string): { markup: string; script: string } {
    const re: RegExp = /<script(?![^>]*type\s*=\s*["']application\/json["'])[^>]*>([\s\S]*?)<\/script>/gi;
    let script: string = '';
    const markup: string = html.replace(re, (_m: string, body: string): string => {
      script += body + '\n;\n';
      return '';
    });
    return { markup: markup, script: script };
  }

  private _showError(host: HTMLElement, rel: string, detail: string): void {
    host.innerHTML =
      '<div style="font-family:Segoe UI,system-ui,sans-serif;border:1px solid #e7eaf3;border-radius:12px;padding:20px 22px;background:#fff">' +
      '<h3 style="margin:0 0 6px;color:#0f1222">Sentinel dashboard not found</h3>' +
      '<p style="margin:0 0 10px;color:#6b7280">Expected the published dashboard at <code>' + this._esc(rel) + '</code> in this site.</p>' +
      '<p style="margin:0;color:#8b93a7;font-size:12px">Run the SharePoint publish pipeline (or Publish-SentinelDocsSite.ps1) to upload it, then refresh. (' + this._esc(detail) + ')</p>' +
      '</div>';
  }

  private _esc(s: string): string {
    return (s || '').replace(/[&<>"]/g, (c: string): string => {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' } as { [k: string]: string })[c];
    });
  }

  protected get dataVersion(): Version {
    return Version.parse('1.0');
  }

  protected getPropertyPaneConfiguration(): IPropertyPaneConfiguration {
    return {
      pages: [
        {
          header: { description: strings.PropertyPaneDescription },
          groups: [
            {
              groupName: strings.BasicGroupName,
              groupFields: [
                PropertyPaneTextField('fileRelativeUrl', {
                  label: strings.DescriptionFieldLabel
                })
              ]
            }
          ]
        }
      ]
    };
  }
}
