# Sentinel workspace dashboard web part

The SharePoint Framework (SPFx) web part that shows the Sentinel
Documenter's interactive dashboard on the home page of a generated
iSOC Blueprint site.

It does one thing: fetch the dashboard HTML that the publisher uploaded to
the site's **Documenter Assets** library (by default
`DocumenterAssets/dashboard/index.html`) with the viewer's own SharePoint
session, and render it inside a same-origin iframe that grows to the
dashboard's full height.

You do not normally build or deploy this by hand. The SharePoint publish
pipelines build the `.sppkg` on every run and
`Publish-SentinelDocsSite.ps1` deploys it to the site's own app catalog
whenever its version changes. See
[Sentinel SharePoint Site](../../../../../Docs/Tools/Documenter/Sentinel-SharePoint-Site.md).

## Build locally

Needs Node 22 (SPFx 1.21.1 supports `>=22.14.0 <23`).

```bash
npm ci
npm run package
```

The package lands at `sharepoint/solution/sentinel-navigator.sppkg`.
`npm run package` cleans first, so the package never carries stale bundles
from earlier builds. `.npmrc` pins the public npm registry so the lockfile
resolves the same way everywhere.

## Releasing a change

The publisher deploys the package only when its version differs from the
one in the site's app catalog. Bump both:

- `version` in `package.json`
- `solution.version` and `features[0].version` in
  `config/package-solution.json` (four-part, for example `1.2.0.0`)

## How it renders

- **Script.** SharePoint's page content security policy applies inside the
  iframe and blocks inline `<script>`, but allows `eval`. The web part
  takes the dashboard's script out of the HTML, loads the rest through
  `srcdoc`, then runs the script inside the iframe with `eval`.
- **Height.** The iframe is sized to the dashboard body's height (not the
  document's, which never shrinks), kept current by a `ResizeObserver`
  and a `fitIframe` hook the dashboard calls after tab switches.
- **Width.** The manifest declares `supportsFullBleed`, and the publisher
  puts the web part in a full-width section, so it fills the page.

## Security

Because the iframe shares the page's origin and the script runs with
`eval`, whoever can edit the dashboard file can run script for everyone
who opens the home page. Keep write access to the Documenter Assets
library to the publisher identity and site owners. The site itself holds
tenant configuration, so keep its membership to the people who should
read it.
