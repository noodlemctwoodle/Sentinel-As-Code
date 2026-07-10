# Documenter Pipeline

CI/CD wiring for the Sentinel Documenter across both CI systems:

- GitHub Actions: [`.github/workflows/sentinel-document.yml`](../../.github/workflows/sentinel-document.yml)
- Azure DevOps: [`Pipelines/Sentinel-Documenter.yml`](../../Pipelines/Sentinel-Documenter.yml)

This page covers **pipeline mechanics** only: triggers, inputs, jobs and
steps, the secrets and variables consumed, authentication, artefacts, and
the GitHub / ADO mapping. For what the invoked collector and renderer
scripts actually do (the inventory it gathers, the sections it renders,
the gap analysis, the topology guidance), see
[Sentinel Documenter](../Tools/Documenter/Sentinel-Documenter.md). This
page does not duplicate that.

> **Both pipelines require a private repository.** The Documenter produces
> `SecurityDocs/`, a tree of tenant configuration (workspace IDs, table
> names, rule details, RBAC principals, cost figures). On GitHub this is
> enforced by an unconditional privacy guard step (below); on ADO it
> relies on ADO repos being private by default within a project. See the
> [tool doc's topology options](../Tools/Documenter/Sentinel-Documenter.md#topology-options).

---

## Trigger comparison

| | GitHub (`sentinel-document.yml`) | ADO (`Sentinel-Documenter.yml`) |
| --- | --- | --- |
| Schedule | Daily cron `0 6 * * *` (06:00 UTC) | None |
| Manual | `workflow_dispatch` | Run pipeline (`trigger: none`, `pr: none`) |
| Push / PR | None (no `push`, no `pull_request`) | None |

The ADO pipeline is **manual-trigger-only for now**; its header notes a
daily schedule will be wired once the pipeline has been smoke-tested
against the live workspace. On GitHub the daily cron is the primary path,
with `workflow_dispatch` for on-demand runs.

---

## GitHub Actions: `sentinel-document.yml`

### Concurrency, permissions and env

- `concurrency`: group `sentinel-document`, `cancel-in-progress: false`
  (a running snapshot is never cancelled by a newer trigger).
- `permissions`: `id-token: write` (OIDC), `contents: write` (push the
  rolling docs branch), `pull-requests: write` (open / refresh the PR),
  `actions: read`. Both write scopes are only ever exercised behind the
  private-repo guard.
- `env`: `PESTER_VERSION: 5.7.1`, `YAML_VERSION: 0.4.12`. Only
  `powershell-yaml` is actually installed (see the module step); the
  Pester pin is declared for consistency with the other workflows but the
  Documenter runs no tests.

### Workflow inputs (`workflow_dispatch`)

| Input | Type | Default | Effect |
| --- | --- | --- | --- |
| `include-preview` | boolean | `false` | Passes `-IncludePreview` to the collector (Content Hub product packages, summary rules, pricings, data lake feature flag). |
| `open-pull-request` | boolean | `true` | Whether to open / refresh the rolling docs PR after the artefact is uploaded. On a scheduled run the PR always opens (subject to the private-repo guard). |

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
   with `client-id: secrets.AZURE_DOCUMENTER_CLIENT_ID`,
   `tenant-id: secrets.AZURE_TENANT_ID`,
   `subscription-id: secrets.AZURE_SUBSCRIPTION_ID`.
5. **Run Sentinel inventory collector** (`azure/powershell@v3`,
   `azPSVersion: latest`). Sets `SENTINEL_RG` and `SENTINEL_WORKSPACE`
   from repo variables, parses `include-preview`, then runs
   `./Tools/Documenter/Export-SentinelInventory.ps1` with
   `-SubscriptionId`, `-ResourceGroup`, `-WorkspaceName` and
   `-IncludePreview:$includePreview`.
6. **Render Markdown report** (`shell: pwsh`). Runs
   `./Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1`
   `-WorkspaceName '${{ vars.SENTINEL_WORKSPACE }}'`.
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
| `AZURE_DOCUMENTER_CLIENT_ID` | Entra app id of the **read-only documenter SP**, separate from the deploy SP. |
| `AZURE_TENANT_ID` | Entra tenant. |
| `AZURE_SUBSCRIPTION_ID` | Default subscription for OIDC login and passed as `-SubscriptionId`. |
| `GITHUB_TOKEN` | Built-in token for the rolling-PR action. |

Required repository **variables** (non-secret): `SENTINEL_RG`,
`SENTINEL_WORKSPACE`.

Authentication is **OIDC** via the `azure-login-oidc` composite action
(no stored client secret). The documenter SP needs a federated credential
trusting subject `repo:<owner>/<repo>:ref:refs/heads/main` with audience
`api://AzureADTokenExchange`, and the read-only role set documented in the
[tool doc](../Tools/Documenter/Sentinel-Documenter.md): Microsoft
Sentinel Reader and Log Analytics Reader (workspace scope), Reader
(resource-group scope), Monitoring Reader and Reader (subscription scope).

### Outputs

- **Artefact** `sentinel-docs-<workspace>-<runId>` (`SecurityDocs/`,
  30-day retention). Always produced.
- **Rolling PR** from `auto/sentinel-docs/<workspace>` into `main`,
  force-pushed each run (no growing history of tenant snapshots). Default
  on, disable per-run with `open-pull-request: false`.

---

## Azure DevOps: `Sentinel-Documenter.yml`

`trigger: none`, `pr: none`. Manual runs only.

### Parameters (queue-time)

| Parameter | Type | Default | Effect |
| --- | --- | --- | --- |
| `includePreview` | boolean | `false` | Compiled to the `flagIncludePreview` variable (`-IncludePreview` or empty), passed to the collector. |
| `openPullRequest` | boolean | `true` | Condition on the "Push docs branch and open / refresh PR" step. |
| `prerenderChartsToPng` | boolean | `true` | **ADO-only.** Gates the Mermaid-to-PNG steps. ADO Repos preview does not render Mermaid fences or inline SVG, so charts are pre-rendered to PNG. GitHub renders Mermaid natively and has no equivalent. |
| `playbookResourceGroup` | string | `""` | Optional override; when set, passed to the collector as `-PlaybookResourceGroup`. Blank means enumerate playbooks from the workspace RG. |

### Variables

- `- group: sentinel-deployment` (shared with the deploy and drift
  pipelines) supplies `azureSubscriptionId`, `sentinelResourceGroup`,
  `sentinelWorkspaceName`, `sentinelRegion`.
- `serviceConnection: sc-sentinel-as-code`.
- `SuppressAzurePowerShellBreakingChangeWarnings: true`.
- `pesterVersion: 5.7.1`, `yamlVersion: 0.4.12` (kept in sync with
  `Tools/Documenter/Documenter.psd1` and the PR-validation workflow).
- `flagIncludePreview` (compile-time `${{ if }}` mapping of the
  `includePreview` parameter).
- `docsBranch: auto/sentinel-docs/$(sentinelWorkspaceName)`,
  `targetBranch: main` (bot-managed, not hand-edited).

### Stage `Document` / job `Run`

`pool: ubuntu-latest`, `timeoutInMinutes: 30`. Steps in order:

1. **`checkout: self`** with `persistCredentials: true` (exposes
   `System.AccessToken` to the git CLI so the later push can reach the
   ADO repo as the Build Service identity).
2. **Install pinned PowerShell modules** (`PowerShell@2`, inline). Installs
   `powershell-yaml` at `$(yamlVersion)` only (no Pester).
3. **Run collector** (`AzurePowerShell@5`, `azureSubscription:
   $(serviceConnection)`, `azurePowerShellVersion: LatestVersion`). Runs
   `Export-SentinelInventory.ps1` with `SubscriptionId`, `ResourceGroup`,
   `WorkspaceName`, optionally `IncludePreview` (when
   `flagIncludePreview` is set) and optionally `PlaybookResourceGroup`.
4. **Run renderer** (`PowerShell@2`, inline). Runs
   `Convert-SentinelInventoryToMarkdown.ps1 -WorkspaceName
   $(sentinelWorkspaceName)`.
5. **Mermaid pre-render** (only when `prerenderChartsToPng == true`):
   `UseNode@1` (Node 20), install `@mermaid-js/mermaid-cli@11`, then run
   `Convert-MermaidToImage.ps1 -Root .../SecurityDocs -Format png`.
6. **Stage `SecurityDocs/` for artefact publish** (`PowerShell@2`).
   Copies the workspace tree into
   `$(Build.ArtifactStagingDirectory)/sentinel-docs`; fails if
   `SecurityDocs/` was not produced.
7. **Publish artefact** (`PublishPipelineArtifact@1`, artifact name
   `sentinel-docs`, `publishLocation: pipeline`).
8. **Push docs branch and open / refresh PR** (`bash`), with
   `condition: and(succeeded(), eq('${{ parameters.openPullRequest }}', 'true'))`
   and `env: AZURE_DEVOPS_EXT_PAT: $(System.AccessToken)`. Resets
   `$(docsBranch)` from the latest `$(targetBranch)` tip, force-adds
   `SecurityDocs/`, commits, `git push --force-with-lease`, then uses
   `az repos pr create` / `az repos pr update` to open or refresh a
   review-only PR into `$(targetBranch)`.

### Secrets and auth

Authentication is the ADO **service connection** `sc-sentinel-as-code`
(consumed by the `AzurePowerShell@5` collector step) carrying the same
read-only role set as the GitHub documenter SP: Microsoft Sentinel Reader
and Log Analytics Reader (workspace scope), Reader (resource-group scope),
Monitoring Reader and Reader (subscription scope). The Azure Retail Prices
API used for cost estimation is anonymous and needs no grant. The git push
and PR calls use the pipeline's built-in `System.AccessToken`, not the
service connection.

### Outputs

- **Artefact** `sentinel-docs` (the `SecurityDocs/<workspace>/` tree).
  Always produced.
- **Rolling PR** from `auto/sentinel-docs/<workspace>` into `main` in the
  private ADO repo, force-pushed each run. Default on, disable per-run
  with `openPullRequest: false`. Safe in ADO because the checkout sets
  `origin` to the private ADO repo, never GitHub, so a force-add push
  cannot reach a public mirror.

---

## GitHub / ADO mapping and asymmetries

| Aspect | GitHub (`sentinel-document.yml`) | ADO (`Sentinel-Documenter.yml`) |
| --- | --- | --- |
| Trigger | Daily cron 06:00 UTC + `workflow_dispatch` | Manual only (`trigger: none`) |
| Identity | Dedicated read-only documenter SP via OIDC (`AZURE_DOCUMENTER_CLIENT_ID`) | Service connection `sc-sentinel-as-code` |
| Privacy enforcement | Unconditional guard step; scheduled runs skipped on public repos, manual fails fast | Relies on ADO repos being private by default |
| Config source | Repo secrets + repo variables (`SENTINEL_RG`, `SENTINEL_WORKSPACE`) | Variable group `sentinel-deployment` |
| Preview toggle | `include-preview` input | `includePreview` parameter |
| PR toggle | `open-pull-request` input | `openPullRequest` parameter |
| Mermaid handling | Rendered natively; no pre-render | `prerenderChartsToPng` (default on) converts fences to PNG |
| Playbook RG override | Not exposed | `playbookResourceGroup` parameter |
| Collector task | `azure/powershell@v3` | `AzurePowerShell@5` |
| Module install | `setup-pwsh-modules` composite action | Inline `PowerShell@2` step |
| Extra git guard | "Confirm `SecurityDocs/` is not git-tracked" step | None (origin is the private ADO repo) |
| PR mechanism | `peter-evans/create-pull-request@v8` | `git push` + `az repos pr create` / `update` |
| Artefact name | `sentinel-docs-<workspace>-<runId>` | `sentinel-docs` |

Both pipelines share the same rolling-branch convention
(`auto/sentinel-docs/<workspace>`, force-pushed into `main`) and the same
review-only PR intent (merging would commit tenant configuration
permanently).

---

## See also

- [Sentinel Documenter](../Tools/Documenter/Sentinel-Documenter.md) -
  operating guide: what the collector gathers, the rendered sections, the
  gap analysis, and full topology options.
- [Documenter Renderer Design](../Tools/Documenter/Documenter-Renderer-Design.md) -
  renderer internals and the chart / Mermaid-safety system.
- [Pipelines overview](README.md) - the full set of seven ADO
  pipelines and seven GitHub workflows, and where this one sits.
- [Sentinel Word Report](../Tools/Documenter/Sentinel-Word-Report.md) -
  the ADO-only pipeline that renders the Documenter Markdown to `.docx`.
