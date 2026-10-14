# Blueprint Pipeline

CI/CD wiring for the iSOC Blueprint across both CI systems:

- GitHub Actions: [`.github/workflows/sentinel-blueprint.yml`](../../.github/workflows/sentinel-blueprint.yml)
- Azure DevOps: [`Pipelines/Sentinel-Blueprint.yml`](../../Pipelines/Sentinel-Blueprint.yml)

On Azure DevOps the one pipeline carries the three exports as tick boxes at
queue time, in any combination: **Export: SharePoint site**, **Export:
Markdown** (the pack as a review-only pull request) and **Export: Word
report**. The SharePoint site and the Markdown pull request are ticked by
default, as is **Collector: include preview APIs**; untick **Export:
SharePoint site** for a workspace with no site or no `sc-sentinel-sharepoint`
connection. GitHub keeps the
SharePoint publish as a separate chained workflow
([SharePoint-Publish.md](SharePoint-Publish.md)) and has no Word report
([Word-Report.md](Word-Report.md)).

This page covers **pipeline mechanics** only: triggers, inputs, jobs and
steps, the secrets and variables consumed, authentication, artefacts, and
the GitHub / ADO mapping. For what the invoked collector and renderer
scripts actually do (the inventory it gathers, the sections it renders,
the gap analysis, the topology guidance), see
[iSOC Blueprint](../Modules/iSOCBlueprint/Sentinel-Blueprint.md). This
page does not duplicate that.

> **Both pipelines require a private repository.** The Blueprint produces
> `SecurityDocs/`, a tree of tenant configuration (workspace IDs, table
> names, rule details, RBAC principals, cost figures). On GitHub this is
> enforced by an unconditional privacy guard step (below); on ADO it
> relies on ADO repos being private by default within a project. See the
> [tool doc's topology options](../Modules/iSOCBlueprint/Sentinel-Blueprint.md#topology-options).

---

## Trigger comparison

> The collector's `defender-custom-detections` capture reads Defender XDR
> custom detection rules through Microsoft Graph and needs the
> `CustomDetection.Read.All` application permission on the pipeline
> identity (an interactive run can use `Connect-MgGraph -Scopes
> 'CustomDetection.Read.All'` instead). Without it the step still
> succeeds, the capture is recorded as not taken, and detection coverage
> counts Sentinel rules only.

| | GitHub (`sentinel-blueprint.yml`) | ADO (`Sentinel-Blueprint.yml`) |
| --- | --- | --- |
| Schedule | Daily cron `0 6 * * *` (06:00 UTC) | None |
| Manual | `workflow_dispatch` | Run pipeline (`trigger: none`, `pr: none`) |
| Push / PR | None (no `push`, no `pull_request`) | None |

The ADO pipeline is **manual-trigger-only for now**; its header notes a
daily schedule will be wired once the pipeline has been smoke-tested
against the live workspace. On GitHub the daily cron is the primary path,
with `workflow_dispatch` for on-demand runs.

---

## GitHub Actions: `sentinel-blueprint.yml`

### Concurrency, permissions and env

- `concurrency`: group `sentinel-blueprint`, `cancel-in-progress: false`
  (a running snapshot is never cancelled by a newer trigger).
- `permissions`: `id-token: write` (OIDC), `contents: write` (push the
  rolling docs branch), `pull-requests: write` (open / refresh the PR),
  `actions: read`. Both write scopes are only ever exercised behind the
  private-repo guard.
- `env`: `PESTER_VERSION: 5.7.1`, `YAML_VERSION: 0.4.12`. Only
  `powershell-yaml` is actually installed (see the module step); the
  Pester pin is declared for consistency with the other workflows but the
  Blueprint runs no tests.

### Workflow inputs (`workflow_dispatch`)

| Input | Type | Default | Effect |
| --- | --- | --- | --- |
| `include-preview` | boolean | `false` | Passes `-IncludePreview` to the collector (Content Hub product packages, summary rules, pricings, data lake feature flag). |
| `open-pull-request` | boolean | `true` | Whether to open / refresh the rolling docs PR after the artefact is uploaded. On a scheduled run the PR always opens (subject to the private-repo guard). |
| `target-maturity-level` | choice (`1` to `5`) | `3` | Passed to the collector as `-TargetMaturityLevel`: the level the maturity assessment measures the workspace against (see [Sentinel-Maturity-Model.md](../Modules/iSOCBlueprint/Sentinel-Maturity-Model.md)). Scheduled runs use the default. |
| `lookback-days` | number (`1` to `730`) | `30` | Passed to the collector as `-LookbackDays`: the days of activity every KQL capture reads. Scheduled runs read the `BLUEPRINT_LOOKBACK_DAYS` repository variable, else 30. The report's pages, the dashboard's cards and the findings name this window. |
| `currency` | choice (`Auto` or a currency code) | `Auto` | Passed to the collector as `-Currency`: the currency the cost estimate prices in. `Auto` takes it from the workspace's region (UK regions GBP, EU regions EUR); billing currency follows the billing account, so pick it when the guess is wrong. Scheduled runs read the `BLUEPRINT_CURRENCY` repository variable, else `Auto`. |

### Job `document`

`runs-on: ubuntu-latest`, `timeout-minutes: 30`.

Job-level condition:
`if: github.event.repository.private == true || github.event_name == 'workflow_dispatch'`.
This skips **scheduled** runs on a public repo so the public upstream does
not accrue a permanent daily red failure. A manual `workflow_dispatch`
still enters the job on any repo and hits the unconditional guard step,
so an operator who tries it on a public repo is told loudly why it will
not run.

Steps, in order:

1. **Checkout** (`actions/checkout@v5`, `fetch-depth: 1`).
2. **Verify repository is private** (`shell: bash`). Runs
   **unconditionally**, before the collector. If
   `github.event.repository.private` is not `true` it emits a
   `::error::` and exits `1`, failing the whole run regardless of the
   `open-pull-request` input. This is the security guard; there is no
   public-repo path that collects or uploads tenant config.
3. **Set up PowerShell modules** (composite
   [`./.github/actions/setup-pwsh-modules`](../../.github/actions/setup-pwsh-modules/action.yml))
   with `yaml-version: ${{ env.YAML_VERSION }}` and
   `install-pester: 'false'`. Caches and pin-installs `powershell-yaml`
   only.
4. **Azure login (OIDC)** (composite
   [`./.github/actions/azure-login-oidc`](../../.github/actions/azure-login-oidc/action.yml))
   with `client-id: secrets.AZURE_BLUEPRINT_CLIENT_ID`,
   `tenant-id: secrets.AZURE_TENANT_ID`,
   `subscription-id: secrets.AZURE_SUBSCRIPTION_ID`.
5. **Run Sentinel inventory collector** (`azure/powershell@v3`,
   `azPSVersion: latest`). Sets `SENTINEL_RG` and `SENTINEL_WORKSPACE`
   from repo variables, parses `include-preview`, imports
   `Modules/iSOCBlueprint` and runs `Export-iSOCBlueprintInventory` with
   `-SubscriptionId`, `-ResourceGroup`, `-WorkspaceName`,
   `-IncludePreview:$includePreview`, `-TargetMaturityLevel` (from
   `target-maturity-level`, default 3), `-LookbackDays` (from
   `lookback-days`, else the `BLUEPRINT_LOOKBACK_DAYS` repository variable,
   else 30), `-Currency` (from `currency`, else the `BLUEPRINT_CURRENCY`
   repository variable, else `Auto`), `-NoDateFolder` (the run writes
   `SecurityDocs/<workspace>/` itself rather than a day folder under it, so
   the pull request diffs one folder) and `-OutputPath` set to
   `SecurityDocs/` in the checkout.
6. **Render Markdown report** (`shell: pwsh`). Imports the module and runs
   `ConvertTo-iSOCBlueprint -WorkspaceName '${{ vars.SENTINEL_WORKSPACE }}'`
   on `SecurityDocs/<workspace>`, writing both formats.
7. **Confirm `SecurityDocs/` is not git-tracked** (`shell: bash`). Fails
   the run if `git ls-files --error-unmatch SecurityDocs/` succeeds, so a
   folder that was accidentally committed cannot slip past the gitignore
   and defeat the privacy guard.
8. **Upload private artefact** (`actions/upload-artifact@v6`). Name
   `sentinel-docs-${{ vars.SENTINEL_WORKSPACE }}-${{ github.run_id }}`,
   path `SecurityDocs/`, `retention-days: 30`,
   `if-no-files-found: error`. Always runs (subject to the guard).
9. **Stage `SecurityDocs/` for the PR** (`shell: bash`). Guarded by
   `github.event.repository.private == true && (event_name != 'workflow_dispatch' || inputs.open-pull-request == 'true')`.
   Force-adds the folder with `git add -f` despite the `.gitignore`.
10. **Open / refresh rolling PR**
    (`peter-evans/create-pull-request@v8`), same `if:` guard as step 9.
    `token: secrets.GITHUB_TOKEN`, `branch: auto/sentinel-docs/<workspace>`,
    `base: main`, `delete-branch: false`. The PR is review-only: title
    `docs(sentinel): snapshot <workspace>`, a "do not merge" banner in the
    body, and links to the run and the artefact.

### Secrets, variables and auth

Required repository **secrets**:

| Secret | Purpose |
| --- | --- |
| `AZURE_BLUEPRINT_CLIENT_ID` | Entra app id of the **read-only Blueprint SP**, separate from the deploy SP. |
| `AZURE_TENANT_ID` | Entra tenant. |
| `AZURE_SUBSCRIPTION_ID` | Default subscription for OIDC login and passed as `-SubscriptionId`. |
| `GITHUB_TOKEN` | Built-in token for the rolling-PR action. |

Required repository **variables** (non-secret): `SENTINEL_RG`,
`SENTINEL_WORKSPACE`.

Authentication is **OIDC** via the `azure-login-oidc` composite action
(no stored client secret). The Blueprint SP needs a federated credential
trusting subject `repo:<owner>/<repo>:ref:refs/heads/main` with audience
`api://AzureADTokenExchange`, and the read-only role set documented in the
[tool doc](../Modules/iSOCBlueprint/Sentinel-Blueprint.md): Microsoft
Sentinel Reader and Log Analytics Reader (workspace scope), Reader
(resource-group scope), Monitoring Reader and Reader (subscription scope).

### Outputs

- **Artefact** `sentinel-docs-<workspace>-<runId>` (`SecurityDocs/`,
  30-day retention). Always produced.
- **Rolling PR** from `auto/sentinel-docs/<workspace>` into `main`,
  force-pushed each run (no growing history of tenant snapshots). Default
  on, disable per-run with `open-pull-request: false`.

---

## Azure DevOps: `Sentinel-Blueprint.yml`

`trigger: none`, `pr: none`. Manual runs only.

### Parameters (queue-time)

The run panel lists them in this order. It has no headings, so each label
starts with its group (`Export:`, `SharePoint:`, `Charts:`, `Collector:`,
`Maturity:`). The three exports (SharePoint site, Markdown, Word report) can
be ticked in any combination; with none ticked the run still collects,
renders and keeps the `sentinel-docs` artefact. The section model
(`sections/*.json`) is rendered on every run; the Markdown pack only when
the pull request or the Word report reads it, or when nothing is ticked.
A SharePoint-only run renders no Markdown and no PNGs.

| Parameter | Type | Default | Effect |
| --- | --- | --- | --- |
| `publishSharePointSite` | boolean | `true` | SharePoint site: includes the `SharePoint` stage, which builds the site bundle from the run's artefact and publishes it. See [SharePoint-Publish.md](SharePoint-Publish.md). |
| `openPullRequest` | boolean | `true` | The Markdown export: condition on the "Push docs branch and open / refresh PR" step, which commits the pack to a rolling branch and opens a review-only pull request. Ticked (or with the Word report ticked), the renderer writes the Markdown pack alongside the section model; see `renderFormats`. |
| `publishWordReport` | boolean | `false` | Word report: includes the `WordReport` stage (compile-time `${{ if }}`), which renders the run's artefact to a `.docx`. See [Word-Report.md](Word-Report.md). |
| `sharePointWhatIf` | boolean | `false` | SharePoint stage: sign in, read the site and print the plan; change nothing. Compiled to the `flagWhatIf` variable. |
| `deployAppPackage` | boolean | `true` | SharePoint stage: deploy the web part package (the dashboard and chart web parts) when its version differs from the one in the site's app catalog. |
| `prerenderChartsToPng` | boolean | `true` | **ADO-only.** Gates the Mermaid-to-PNG steps. ADO Repos preview does not render Mermaid fences or inline SVG, so charts are pre-rendered to PNG for the Markdown and Word exports. Skipped whenever the renderer writes no Markdown; the SharePoint site never needs it. GitHub renders Mermaid natively and has no equivalent. |
| `includePreview` | boolean | `true` | Compiled to the `flagIncludePreview` variable (`-IncludePreview` or empty), passed to the collector. On by default on ADO; the GitHub `include-preview` input stays off by default. |
| `playbookResourceGroup` | string | `" "` (a single space) | Where the collector enumerates playbooks, passed as `-PlaybookResourceGroup`. Left blank, the collector step uses `sentinelResourceGroup` from the variable group, and the run log's `Playbook RG` line shows which one it used. The default is a space because the run panel treats an empty default as no default, marks the field Required and disables Next; the collector step trims it. |
| `targetMaturityLevel` | number (`1` to `5`) | `3` | Passed to the collector as `-TargetMaturityLevel`: the level the maturity assessment measures the workspace against. |
| `lookbackDays` | number (`1` to `730`) | `30` | Passed to the collector as `-LookbackDays`: the days of activity every KQL capture reads (incidents, alerts, usage and cost, health, agents, table activity). The report's pages, the dashboard's cards and the findings name this window. |
| `currency` | string (`Auto` or a currency code) | `Auto` | Passed to the collector as `-Currency`: the currency the cost estimate prices in. `Auto` takes it from the workspace's region (UK regions GBP, EU regions EUR); billing currency follows the billing account, so pick it when the guess is wrong. |

### Variables

- `- group: sentinel-deployment` (shared with the deploy and drift
  pipelines) supplies `azureSubscriptionId`, `sentinelResourceGroup`,
  `sentinelWorkspaceName`, `sentinelRegion`.
- `serviceConnection: sc-sentinel-as-code`.
- `SuppressAzurePowerShellBreakingChangeWarnings: true`.
- `pesterVersion: 5.7.1`, `yamlVersion: 0.4.12` (kept in sync with
  `Modules/iSOCBlueprint/Engine/Blueprint.psd1` and the PR-validation
  workflow).
- `flagIncludePreview` (compile-time `${{ if }}` mapping of the
  `includePreview` parameter).
- `renderFormats` (compile-time): `Markdown,Json` when `openPullRequest` or
  `publishWordReport` is ticked or `publishSharePointSite` is not, otherwise
  `Json`. Passed to the renderer as `-OutputFormat`; the Mermaid pre-render
  uses the same test.
- `docsBranch: auto/sentinel-docs/$(sentinelWorkspaceName)`,
  `targetBranch: main` (bot-managed, not hand-edited).
- `docsRoot: $(Pipeline.Workspace)/sentinel-docs`: where the two publish
  stages find this run's artefact after `download: current`.
- `pandocVersion: 3.10` (Word report stage).
- `sharePointServiceConnection: sc-sentinel-sharepoint`, `pnpVersion: 3.4.1`,
  `nodeVersion: 22.x`, `npm_config_cache`,
  `webPartDir`, and `flagWhatIf` (compile-time mapping of `sharePointWhatIf`)
  for the SharePoint stage.

### Stage `Document` / job `Run`

`pool: ubuntu-latest`, `timeoutInMinutes: 30`. Steps in order:

1. **`checkout: self`** with `persistCredentials: true` (exposes
   `System.AccessToken` to the git CLI so the later push can reach the
   ADO repo as the Build Service identity).
2. **Install pinned PowerShell modules** (`PowerShell@2`, inline). Installs
   `powershell-yaml` at `$(yamlVersion)` only (no Pester).
3. **Run collector** (`AzurePowerShell@5`, `azureSubscription:
   $(serviceConnection)`, `azurePowerShellVersion: LatestVersion`). Imports
   `Modules/iSOCBlueprint` and runs `Export-iSOCBlueprintInventory` with
   `SubscriptionId`, `ResourceGroup`, `WorkspaceName`, optionally
   `IncludePreview` (when `flagIncludePreview` is set),
   `PlaybookResourceGroup`, `TargetMaturityLevel`, `LookbackDays`, `Currency`, `NoDateFolder` (the run
   writes `SecurityDocs/<workspace>/` itself rather than a day folder under
   it) and `OutputPath` (`$(Build.SourcesDirectory)/SecurityDocs`).
4. **Run renderer** (`PowerShell@2`, inline). Runs
   `ConvertTo-iSOCBlueprint -WorkspaceName $(sentinelWorkspaceName)` on
   `SecurityDocs/<workspace>` with `-Format $(renderFormats)`, and logs
   which formats it wrote.
5. **Mermaid pre-render** (only when `prerenderChartsToPng == true` and the
   renderer writes Markdown):
   `UseNode@1` (Node 20), install `@mermaid-js/mermaid-cli@11`, then run
   `ConvertTo-iSOCBlueprintChartImage -Path .../SecurityDocs -Format png`.
6. **Stage `SecurityDocs/` for artefact publish** (`PowerShell@2`).
   Copies the workspace tree into
   `$(Build.ArtifactStagingDirectory)/sentinel-docs`; fails if
   `SecurityDocs/` was not produced. Logs the raw, section and Markdown
   file counts.
7. **Publish artefact** (`PublishPipelineArtifact@1`, artifact name
   `sentinel-docs`, `publishLocation: pipeline`).
8. **Push docs branch and open / refresh PR** (`bash`), with
   `condition: and(succeeded(), eq('${{ parameters.openPullRequest }}', 'true'))`
   and `env: AZURE_DEVOPS_EXT_PAT: $(System.AccessToken)`. Resets
   `$(docsBranch)` from the latest `$(targetBranch)` tip, force-adds
   `SecurityDocs/`, commits, `git push --force-with-lease`, then uses
   `az repos pr create` / `az repos pr update` to open or refresh a
   review-only PR into `$(targetBranch)`.

### Stage `WordReport` (only when `publishWordReport` is ticked)

`dependsOn: Document`, `pool: ubuntu-latest`, `timeoutInMinutes: 30`, one
job `Render`. Checks the repository out (`fetchDepth: 1`), downloads this
run's `sentinel-docs` artefact (`download: current`), installs LibreOffice
Writer, `python3-uno` and pandoc `$(pandocVersion)`, runs
`Export-iSOCBlueprintWord` on `<docsRoot>/<workspace>` with the title
`<workspace> - Sentinel Documentation` and `-Toc Baked`, verifies the baked
table of contents, and publishes `<workspace>.docx` as the
`sentinel-word-report` artefact. It warns when `prerenderChartsToPng` was
off, because pandoc drops Mermaid fences and the report would carry no
charts. No Azure sign-in. See [Word-Report.md](Word-Report.md).

### Stage `SharePoint` (only when `publishSharePointSite` is ticked)

`dependsOn: Document`, `pool: ubuntu-latest`, `timeoutInMinutes: 45`, one
job `Publish`. Downloads this run's `sentinel-docs` artefact, checks that
`<workspace>/_raw` is in it (and logs how many section files it holds),
builds the web part package (Node 22, `npm ci`, `npm run package`),
installs PnP.PowerShell, builds the site bundle from the section model
with `New-iSOCBlueprintSite`, then signs in through the
`sc-sentinel-sharepoint` service connection inside one `AzureCLI@2` task,
requests a SharePoint token for the site's host and runs
`Publish-iSOCBlueprintSite` (with `-WhatIf` when `sharePointWhatIf` is
ticked, and the `.sppkg` path when `deployAppPackage` is). The bundle and
package are kept as the `sharepoint-site` artefact even when the publish
failed. See [SharePoint-Publish.md](SharePoint-Publish.md).

Both publish stages run in parallel after `Document` and read the artefact
that run produced, so a failed publish never costs a collection: use
"Rerun failed stages" on the run page and it publishes the same snapshot
again.

### Secrets and auth

Authentication is the ADO **service connection** `sc-sentinel-as-code`
(consumed by the `AzurePowerShell@5` collector step) carrying the same
read-only role set as the GitHub Blueprint SP: Microsoft Sentinel Reader
and Log Analytics Reader (workspace scope), Reader (resource-group scope),
Monitoring Reader and Reader (subscription scope). The Azure Retail Prices
API used for cost estimation is anonymous and needs no grant. The git push
and PR calls use the pipeline's built-in `System.AccessToken`, not the
service connection. The SharePoint stage signs in with its own connection,
`sc-sentinel-sharepoint`, bound to the publisher app registration that holds
SharePoint `Sites.Selected` with FullControl on the one site and no Azure
role; the Word report stage signs in nowhere.

### Outputs

- **Artefact** `sentinel-docs` (the `SecurityDocs/<workspace>/` tree).
  Always produced.
- **Artefact** `sentinel-word-report` (`<workspace>.docx`) when
  `publishWordReport` was ticked.
- **Artefact** `sharepoint-site` (the bundle and the `.sppkg`) and the
  **SharePoint site** updated in place, when `publishSharePointSite` was
  ticked.
- **Rolling PR** from `auto/sentinel-docs/<workspace>` into `main` in the
  private ADO repo, force-pushed each run. Default on, disable per-run
  with `openPullRequest: false`. Safe in ADO because the checkout sets
  `origin` to the private ADO repo, never GitHub, so a force-add push
  cannot reach a public mirror.

---

## GitHub / ADO mapping and asymmetries

| Aspect | GitHub (`sentinel-blueprint.yml`) | ADO (`Sentinel-Blueprint.yml`) |
| --- | --- | --- |
| Trigger | Daily cron 06:00 UTC + `workflow_dispatch` | Manual only (`trigger: none`) |
| Identity | Dedicated read-only Blueprint SP via OIDC (`AZURE_BLUEPRINT_CLIENT_ID`) | Service connection `sc-sentinel-as-code` |
| Privacy enforcement | Unconditional guard step; scheduled runs skipped on public repos, manual fails fast | Relies on ADO repos being private by default |
| Config source | Repo secrets + repo variables (`SENTINEL_RG`, `SENTINEL_WORKSPACE`) | Variable group `sentinel-deployment` |
| Preview toggle | `include-preview` input (default off) | `includePreview` parameter (default on) |
| PR toggle | `open-pull-request` input | `openPullRequest` parameter |
| Mermaid handling | Rendered natively; no pre-render | `prerenderChartsToPng` (default on) converts fences to PNG when the run writes Markdown |
| Playbook RG override | Not exposed | `playbookResourceGroup` parameter |
| Target maturity level | `target-maturity-level` input (choice, default 3) | `targetMaturityLevel` parameter (number, default 3) |
| Lookback | `lookback-days` input, or the `BLUEPRINT_LOOKBACK_DAYS` variable on a schedule (default 30) | `lookbackDays` parameter (number, default 30) |
| Currency | `currency` input, or the `BLUEPRINT_CURRENCY` variable on a schedule (default `Auto`) | `currency` parameter (default `Auto`) |
| Collector task | `azure/powershell@v3` | `AzurePowerShell@5` |
| Module install | `setup-pwsh-modules` composite action | Inline `PowerShell@2` step |
| Extra git guard | "Confirm `SecurityDocs/` is not git-tracked" step | None (origin is the private ADO repo) |
| PR mechanism | `peter-evans/create-pull-request@v8` | `git push` + `az repos pr create` / `update` |
| Artefact name | `sentinel-docs-<workspace>-<runId>` | `sentinel-docs` |
| Word report | None | `publishWordReport` stage in the same run |
| SharePoint site | Separate workflow `sentinel-sharepoint-publish.yml`, chained with `workflow_run` | `publishSharePointSite` stage in the same run |

Both pipelines share the same rolling-branch convention
(`auto/sentinel-docs/<workspace>`, force-pushed into `main`) and the same
review-only PR intent (merging would commit tenant configuration
permanently).

---

## See also

- [iSOC Blueprint](../Modules/iSOCBlueprint/Sentinel-Blueprint.md) -
  operating guide: what the collector gathers, the rendered sections, the
  gap analysis, and full topology options.
- [Blueprint Renderer Design](../Modules/iSOCBlueprint/Blueprint-Renderer-Design.md) -
  renderer internals and the chart / Mermaid-safety system.
- [Pipelines overview](README.md) - the full set of ADO pipelines and
  GitHub workflows, and where this one sits.
- [Word-Report.md](Word-Report.md) and
  [SharePoint-Publish.md](SharePoint-Publish.md) - the two optional
  stages of this pipeline on ADO.
- [iSOC Blueprint Word Report](../Modules/iSOCBlueprint/Sentinel-Word-Report.md) -
  what the `.docx` converter does and how to run it locally.
