# Sentinel SharePoint Publish Pipeline

CI/CD wiring for the two ways the **iSOC Blueprint** SharePoint site is
published from the Sentinel Blueprint's output:

- Azure DevOps: the `SharePoint` stage of
  [`Pipelines/Sentinel-Blueprint.yml`](../../Pipelines/Sentinel-Blueprint.yml),
  included when the `publishSharePointSite` tick box is set at queue time.
- GitHub Actions: the separate workflow
  [`.github/workflows/sentinel-sharepoint-publish.yml`](../../.github/workflows/sentinel-sharepoint-publish.yml),
  chained after the Blueprint.

This page covers the **pipeline mechanics**: triggers, inputs, steps,
identity and outputs. For what the generated site contains, the one-time
bootstrap and running the scripts locally, see the tool page:
[Sentinel SharePoint Site](../Tools/Blueprint/Sentinel-SharePoint-Site.md).

## At a glance

| Property | Azure DevOps | GitHub Actions |
| --- | --- | --- |
| Trigger | **Export: SharePoint site** (`publishSharePointSite`) on a `Sentinel-Blueprint` run; the stage follows `Document` in the same run | `workflow_run`: every successful "Sentinel Blueprint" run on `main`, plus `workflow_dispatch` |
| Schedule | None (the ADO Blueprint is manual) | None of its own (follows the Blueprint's 06:00 UTC cron) |
| Input | The same run's `sentinel-docs` artefact (`download: current`) | The Blueprint run's `sentinel-docs-<ws>-<runId>` artefact |
| Agent | `ubuntu-latest`, its own job | `ubuntu-latest`, environment `sharepoint-publish` |
| Identity | Service connection `sc-sentinel-sharepoint` (workload identity federation) | `SHAREPOINT_CLIENT_ID` via OIDC |
| SharePoint rights | `Sites.Selected` with FullControl on the one site | Same app or a second one, same rights |
| Azure roles | Reader on one empty resource group (so `AzureCLI@2` can select a subscription) | None (`allow-no-subscriptions`) |
| Published artefact | `sharepoint-site` | `sharepoint-site-<ws>-<runId>` (30 days) |
| Concurrency | `lockBehavior: sequential` on the Blueprint pipeline | `concurrency: sentinel-sharepoint-publish` |

## Purpose

The Blueprint collects and renders. This pipeline makes the result readable
by people who live in SharePoint rather than in a repository or a pipeline
artefact: it turns one Blueprint run into a complete, generated site for
that workspace (a page per section, navigation, a findings list with
history, and the interactive dashboard as the home page) and keeps it in
step with every run.

On ADO it is a stage of the Blueprint pipeline rather than a pipeline of
its own, so one run produces whichever outputs are ticked: the Markdown
pull request, the Word report, the SharePoint site, or any mixture. Two
properties that argue for keeping publishing apart from collecting still
hold:

- **Separate identity.** The `Document` stage's identity reads Azure. The
  `SharePoint` stage signs in with `sc-sentinel-sharepoint`, which writes
  to one SharePoint site and nothing else. Neither holds the other's
  rights.
- **Separate failure.** The stage depends on `Document` and reads the
  artefact that run produced. A SharePoint outage or a throttled publish
  fails the stage, not the collection: the Markdown artefact and the docs
  pull request stand, and "Rerun failed stages" publishes the same
  snapshot again without collecting.

## Trigger

Neither platform publishes on a schedule of its own: a publish always
follows a Blueprint run and uses that run's artefact, so the site shows the
latest snapshot.

- **ADO.** The `SharePoint` stage is included at compile time only when
  `publishSharePointSite` is ticked, and runs after `Document` succeeds,
  reading the artefact of the run it belongs to. There is no pipeline
  resource and no chained trigger.
- **GitHub.** `workflow_run` on "Sentinel Blueprint", `completed`, `main`,
  gated on `conclusion == 'success'`. `workflow_dispatch` takes an optional
  `blueprint-run-id`; blank means the latest successful Blueprint run on
  `main`, which is what a chained run would use.

## Inputs

| ADO parameter | GitHub input | Default | Effect |
| --- | --- | --- | --- |
| `publishSharePointSite` (**Export: SharePoint site**) | (the workflow itself) | `true` | Include the `SharePoint` stage in the Blueprint run. Untick it for a workspace with no site or no `sc-sentinel-sharepoint` connection. |
| `sharePointWhatIf` (**SharePoint: what-if**) | `what-if` | `false` | Sign in, read the site and print the plan; change nothing. |
| `deployAppPackage` (**SharePoint: deploy the web part if it changed**) | `deploy-app-package` | `true` | Deploy the dashboard web part package when its version differs from the one in the site's app catalog. |
| (the same run) | `blueprint-run-id` | latest successful | Which Blueprint run to publish. |

Chained runs get the defaults, so they behave exactly like an untouched
manual run.

## Steps, in order

1. **Checkout** the repository (scripts and the web part source).
2. **Download** the artefact: on ADO this run's own `sentinel-docs`
   (`download: current`); on GitHub the chosen Blueprint run's.
3. **Locate** `<workspace>/_raw` in it, and fail if the workspace name does
   not match.
4. **Build the web part package** (the dashboard and chart web parts):
   Node 22, `npm ci`, `npm run package` (clean, bundle, package). The lock
   file resolves from the public npm registry (`.npmrc`), and the npm cache
   is keyed on it. Nothing else is rendered: charts reach the site as data
   in the [section model](../Tools/Blueprint/Section-Model.md), drawn by the
   dashboard and the chart web part.
5. **Install PnP.PowerShell 3.4.1** (needs PowerShell 7.4, which the image
   has).
6. **Build the site bundle** with
   [`Build-SentinelDocsSite.ps1`](../../Tools/Blueprint/SharePoint/Build-SentinelDocsSite.ps1).
7. **Sign in and publish.** Request a SharePoint token for the tenant's
   SharePoint host through the federated credential
   (`az account get-access-token --resource https://<tenant>.sharepoint.com`),
   mask it, and run
   [`Publish-SentinelDocsSite.ps1`](../../Tools/Blueprint/SharePoint/Publish-SentinelDocsSite.ps1)
   with `-AccessToken`. On ADO the whole step runs inside one `AzureCLI@2`
   task bound to the service connection; on GitHub it follows the
   `azure-login-oidc` composite action with `allow-no-subscriptions`.
8. **Publish the bundle and package** as an artefact, even when the publish
   failed, so you can see exactly what was being published.

## Variables, secrets and identity

### Azure DevOps

| Name | Where | Purpose |
| --- | --- | --- |
| `sentinelWorkspaceName` | Variable group `sentinel-deployment` | Workspace folder inside the artefact (shared with the Blueprint) |
| `sharePointSiteUrl` | Variable group `sentinel-deployment` | The site for this workspace |
| `sc-sentinel-sharepoint` | Service connection (the `sharePointServiceConnection` variable) | Azure Resource Manager connection, workload identity federation (manual), for the publisher app |

[`Deploy/setup/Setup-SharePointPublisher.ps1`](../Deploy/Scripts.md#setup-sharepointpublisherps1)
creates the connection (and everything behind it) in one run; that is the
recommended route. To create it by hand instead, follow
`sc-sentinel-as-code` in [ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md),
with two differences:

- Use the **publisher** app registration, not the deploy identity.
- Give the app Reader on one empty resource group (what the script does)
  or scope it to a management group. `AzureCLI@2` selects the connection's
  subscription after signing in, which fails for an identity that can see
  no subscription.

### GitHub

| Name | Kind | Purpose |
| --- | --- | --- |
| `SHAREPOINT_CLIENT_ID` | Secret | Publisher app registration |
| `AZURE_TENANT_ID` | Secret | Tenant (shared) |
| `SENTINEL_WORKSPACE` | Variable | Workspace name (shared with the Blueprint) |
| `SHAREPOINT_SITE_URL` | Variable | The site for this workspace |
| `sharepoint-publish` | Environment | Binds the federated credential; restrict it to `main` |

Federated credential on the publisher app:

| Field | Value |
| --- | --- |
| Issuer | `https://token.actions.githubusercontent.com` |
| Subject | `repo:<owner>/<repo>:environment:sharepoint-publish` |
| Audience | `api://AzureADTokenExchange` |

Binding the credential to an environment (rather than to `ref:refs/heads/main`,
as the Blueprint does) means no other workflow on `main` can mint a
SharePoint token.

### The publisher app registration

For Azure DevOps, [`Deploy/setup/Setup-SharePointPublisher.ps1`](../Deploy/Scripts.md#setup-sharepointpublisherps1)
creates the app, its permission and consent, the service connection and the
federated credential in one run. The requirements it satisfies:

One app registration (or one per platform, if you prefer) with:

- **SharePoint** application permission `Sites.Selected`, admin consented.
  Microsoft Graph's `Sites.Selected` alone is not enough: the publisher calls
  SharePoint's own APIs.
- **FullControl on the one site**, granted by
  [`Initialize-SentinelDocsSite.ps1`](../../Tools/Blueprint/SharePoint/Initialize-SentinelDocsSite.ps1).
  FullControl is what the site collection app catalog, the home page and the
  navigation changes need. It covers nothing outside that site.
- **No client secret or certificate.** The token comes from the pipeline's
  federated credential. On ADO the app also holds Reader on one empty
  resource group (see above) and no other Azure role; on GitHub it holds
  none.

SharePoint rejects app-only tokens obtained with a client secret. Tokens
obtained with a federated credential are assertion-based, like certificate
tokens, and SharePoint accepts them: an ADO what-if run signs in through
the service connection and reads the site with the same token the real
publish uses. Run that what-if first in your own tenant.

## Outputs

- The **SharePoint site**, updated in place. See the tool page for what a
  publish changes and in what order.
- A run **artefact** (`sharepoint-site` on ADO, `sharepoint-site-<ws>-<runId>`
  on GitHub, 30 days) with the bundle (`index.html`, `model.json`,
  `site.json`, `pages/`, `findings.json`) and the `.sppkg`.

The artefact holds the same tenant configuration as the Blueprint's. The
GitHub workflow refuses to run on a public repository for that reason (the
same guard the Blueprint uses).

## Failure conditions

The run fails when:

- the repository is public (GitHub only, before any download);
- the `Document` stage failed (ADO: the stage then does not run), there is
  no successful Blueprint run to publish (GitHub), or the artefact has no
  `<workspace>/_raw` for the configured workspace;
- `npm ci` or the package build fails;
- the SharePoint token cannot be obtained (federated credential, consent or
  service connection scope);
- the dashboard web part is still not in the site's component list five
  minutes after its package was deployed (the error names the web part id
  and says to check the site's app catalog);
- a publish step fails outright. A failure on an individual section page
  does not stop the run: the other pages, the dashboard, the findings and
  the navigation still publish, nothing is pruned, and the run fails at the
  end listing the pages that did not publish. The next run retries them.

## GitHub / ADO parity

The pair follows the same steps in the same order. The differences are
forced by the platforms:

| Aspect | ADO | GitHub | Why |
| --- | --- | --- | --- |
| Chaining | A stage of the Blueprint run, ticked at queue time | `workflow_run` after the Blueprint | One pipeline with options on ADO; GitHub keeps a separate workflow so the publisher's federated credential binds to its own environment |
| Sign-in | One `AzureCLI@2` task around token + publish | `azure-login-oidc` with `allow-no-subscriptions`, then a `pwsh` step | `AzureCLI@2` owns the federated sign-in on ADO |
| Privacy guard | None needed (ADO repos are private) | Refuses public repositories | Same as the Blueprint pair |
| Federated subject | Service connection subject | `environment:sharepoint-publish` | Platform mechanism |

## Related

- [Sentinel SharePoint Site](../Tools/Blueprint/Sentinel-SharePoint-Site.md): what is generated, the bootstrap, running locally, privacy.
- [Blueprint pipeline](Blueprint.md): the pipeline this stage belongs to on ADO, and the producer of the artefact the GitHub workflow publishes.
- [Sentinel Blueprint](../Tools/Blueprint/Sentinel-Blueprint.md): the collector and renderer.
- [ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md): creating a workload identity federation service connection.
