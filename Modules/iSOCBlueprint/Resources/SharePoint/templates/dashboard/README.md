# Dashboard template

The SharePoint site's dashboard (`index.html`) is one HTML page: its style,
its markup and one script. It is kept here as numbered parts so each concern
can be read and changed on its own. `Get-SiteDashboardTemplate` joins them,
as they are, in the order of their paths (compared ordinally), and the site
build fills in the three placeholders.

| Part | What it holds |
| --- | --- |
| `01-head.html` | The document head up to the opening `<style>` tag, with the `__TITLE__` placeholder |
| `02-style/` | The stylesheet, one file per area: tokens, top bar, headers, cards, the insights board, the sections browser, the flow and detection matrix, tables, the alert lifecycle, the ATT&CK grid |
| `03-body.html` | The closing `</style>`, the body and the page's markup |
| `04-script/00-open.html` | The model block (`/*__MODEL__*/null`), the chart renderers' slot (`/*__SAC_CHARTS__*/`) and the opening `<script>` |
| `04-script/NN-*.js` | The one script, cut between its statements: the core and shared helpers, then one file per part of the dashboard in the order they run |
| `05-end.html` | The closing `</script>`, `</body>` and `</html>` |

A `.js` part is a slice of one script (it opens inside the wrapping function
that `01-core.js` starts and `22-tabs.js` ends), so it is not valid on its
own; it is whole only when the parts are joined. Parts hold whole lines and
nothing is added between them, so to move a piece, move whole lines.

Keep each part within 300 lines (`Tests/iSOCBlueprint/Dashboard-Template.Tests.ps1`
enforces it) and name a new part with the number that puts it where it
belongs. Only `.html`, `.css` and `.js` files are read, so this file is not
part of the page.

`../dashboard-charts.js` is not one of these parts. It is generated from the
chart web part's TypeScript by `WebParts/Build-DashboardCharts.ps1`, and the
site build puts it into the `/*__SAC_CHARTS__*/` slot; change the TypeScript
and regenerate it rather than editing it.
