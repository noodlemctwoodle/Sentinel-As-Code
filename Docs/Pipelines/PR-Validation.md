# PR Validation

The PR-validation gate is the merge guard for `main`. It runs a set of
offline (and one OIDC-authenticated) checks against every pull request so
that broken content, templates, or a stale dependency manifest cannot land.

Two implementations exist and share the same underlying scripts:

| CI system | File | Shape |
| --- | --- | --- |
| GitHub Actions | [`.github/workflows/pr-validation.yml`](../../.github/workflows/pr-validation.yml) | Five independent jobs, each its own required status check |
| Azure DevOps | [`Pipelines/Sentinel-PR-Validation.yml`](../../Pipelines/Sentinel-PR-Validation.yml) | One stage, one job, two gates (Pester + dependency manifest) |

The two are deliberately asymmetric. The GitHub workflow is the richer of
the pair; the ADO pipeline covers the two gates that need no Azure
authentication. The [GitHub vs Azure DevOps](#github-vs-azure-devops) section
below spells out exactly what each covers.

This page documents pipeline mechanics only. For what the invoked scripts
actually do, see [Pester Tests](../Tests/Pester-Tests.md) (the test
suite `validate` runs) and [Dependency Manifest](../Tools/Dependency-Manifest.md)
(the drift gate). The one-off setup for the OIDC-authenticated `arm-validate`
job is in [PR Validation Gate Setup](../Deploy/PR-Validation-Setup.md).

---

## GitHub Actions: `pr-validation.yml`

### Triggers

| Event | Detail |
| --- | --- |
| `pull_request` | Target branch `main`; activity types `opened`, `synchronize`, `reopened`, `ready_for_review` |
| `push` | Branch `main` (CI baseline; catches admin-override, force-push and squash-merge edge cases where a direct push reaches `main`) |
| `workflow_dispatch` | Manual run against any branch |

There is **no `paths` / `paths-ignore` filter**. Every job runs on every
pull request and every push to `main`, regardless of which files changed.

### Concurrency

```yaml
concurrency:
  group: pr-validation-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
```

A new commit on a PR cancels the in-flight run for that PR (grouped by PR
number), so only the latest commit's status counts. Push-to-`main` runs fall
back to `github.ref` so they group per ref rather than colliding with PR runs.

### Workflow-level environment (version pins)

| Variable | Value | Used by |
| --- | --- | --- |
| `PESTER_VERSION` | `5.7.1` | `validate` (via the setup composite action) |
| `YAML_VERSION` | `0.4.12` | `validate`, `dependency-manifest` |

The `kql-validate` job additionally pins `KUSTO_LANGUAGE_VERSION` (`12.2.4`)
at job scope. The pins exist because this gate is a hard merge requirement:
a breaking release from PSGallery or NuGet must not be able to silently fail
the gate on an unrelated change. Bumping a pin is a one-line PR that re-runs
the gate against the new version before merging.

### Jobs

All five jobs run in parallel on `ubuntu-latest`. Each surfaces as its own
status check that the branch-protection ruleset can require independently.

#### 1. `validate` (Pester)

- **Auth:** none (offline).
- **Timeout:** 15 minutes.
- **Permissions:** `contents: read`, `checks: write`, `pull-requests: write`.
  `checks: write` is required by the results-publishing action to post
  per-test results to the check-run UI; without it the publish step 403s and
  marks the job red even on a clean test run.
- **Steps:**
  1. Checkout (`fetch-depth: 1`).
  2. [`./.github/actions/setup-pwsh-modules`](../../.github/actions/setup-pwsh-modules)
     with the pinned Pester + powershell-yaml versions.
  3. Run `Tools/Invoke-PRValidation.ps1` with `-InstallModules:$false` (the
     composite action already installed the modules). This is the single
     cross-platform entrypoint that both CI systems call, so test discovery,
     report emission and exit-code logic live in one place.
  4. Publish the results to the PR check UI (runs `if: always()`, so failed
     tests are visible with per-test granularity rather than a bare
     "validate failed").
  5. Upload the report directory as a run artefact (`if: always()`,
     30-day retention).
- **Output:** an **NUnit 2.5** XML report at
  `test-results/pester-results.xml`. (The workflow's inline comments say
  "JUnit XML" loosely; `Invoke-PRValidation.ps1` sets Pester's
  `OutputFormat = 'NUnitXml'`, and the publish action auto-detects the NUnit
  schema.)

#### 2. `bicep-build`

- **Auth:** none (`az bicep build` is fully offline).
- **Timeout:** 5 minutes.
- **What it does:** ensures the Bicep CLI is current (`az bicep install`),
  then compiles every `Infra/**/*.bicep` file to ARM JSON via
  `az bicep build --stdout`. Catches syntax errors, undefined parameter
  references, type mismatches and lint violations before they reach the
  deploy pipeline. Fails the job if any file fails to build.

#### 3. `arm-validate`

- **Auth:** **federated OIDC** against the deploy service principal (the
  only job that needs Azure). One-off setup:
  [PR Validation Gate Setup](../Deploy/PR-Validation-Setup.md).
- **Timeout:** 20 minutes.
- **Permissions:** `id-token: write` (for OIDC), `contents: read`.
- **Skip conditions** (evaluated in the first step, which sets a
  `should_skip` output):
  - **Fork PRs** cannot obtain an OIDC token (the federated subject
    mismatches), so the job no-ops with a warning telling maintainers to
    validate ARM templates manually.
  - If any of the OIDC secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
    `AZURE_SUBSCRIPTION_ID`) is empty, the job skips with a warning rather
    than failing the gate on missing configuration. Once the secrets are
    populated the next run exercises the job.
- **Steps (when not skipped):**
  1. Checkout.
  2. [`./.github/actions/azure-login-oidc`](../../.github/actions/azure-login-oidc)
     with the three OIDC secrets.
  3. For every `Content/Playbooks/**/*.json` template, call
     `Test-AzResourceGroupDeployment` against the resource group named in the
     `PR_VALIDATION_RESOURCE_GROUP` repository variable, passing a set of stub
     parameter values (only the parameters each template actually declares are
     forwarded). This is a **template-validation call against the ARM
     deployment-validation API** - `Test-AzResourceGroupDeployment` has **no
     `-WhatIf` parameter** and creates nothing. It catches malformed ARM
     templates, missing required parameters and schema-version mismatches.
     Any validation error fails the job.
- **Required repo variable:** `PR_VALIDATION_RESOURCE_GROUP` (the job errors
  out with a pointer to the setup runbook if it is unset).

#### 4. `kql-validate`

- **Auth:** none (offline).
- **Timeout:** 10 minutes.
- **What it does:** builds a throwaway .NET probe project that pulls the
  `Microsoft.Azure.Kusto.Language` NuGet package (pinned via
  `KUSTO_LANGUAGE_VERSION`, cached by version + OS key), loads
  `Kusto.Language.dll`, then parses the KQL from:
  - `Content/AnalyticalRules/**`, `Content/HuntingQueries/**`,
    `Content/Parsers/**` (YAML `query` field);
  - `Content/SummaryRules/**` (JSON `query` field);
  - `Content/DefenderCustomDetections/**` (YAML `queryCondition.queryText`).

  Each query is parsed with `KustoCode.Parse` and checked for
  `GetSyntaxDiagnostics()`. This is a **syntax-level** check only (no
  workspace schema), so it catches unmatched parentheses, unknown keywords,
  missing pipe operators and malformed literals, but not column-existence
  errors. Any syntax diagnostic fails the job.

#### 5. `dependency-manifest`

- **Auth:** none (offline; reads YAML/JSON only).
- **Timeout:** 5 minutes.
- **Steps:**
  1. Checkout.
  2. `setup-pwsh-modules` with `install-pester: 'false'` (this gate consumes
     only powershell-yaml).
  3. `Tools/Build-DependencyManifest.ps1 -Mode Verify`, which walks the
     content, re-runs the discovery extractors, and compares the result
     against the on-disk `dependencies.json`. Any drift fails the job with a
     fix message.
- **Author fix for drift:** run
  `./Tools/Build-DependencyManifest.ps1 -Mode Generate` locally and commit
  the regenerated manifest, or wait for the daily dependency-update workflow
  to open an auto-PR. See [Dependency Manifest](../Tools/Dependency-Manifest.md).

### Composite actions consumed

| Action | Purpose |
| --- | --- |
| [`.github/actions/setup-pwsh-modules`](../../.github/actions/setup-pwsh-modules) | Cache + pin-install Pester and powershell-yaml (exact versions); `install-pester: 'false'` skips Pester for YAML-only jobs |
| [`.github/actions/azure-login-oidc`](../../.github/actions/azure-login-oidc) | Federated Azure login via `Azure/login@v3`; used only by `arm-validate` |

### Secrets and repository variables

| Kind | Name | Consumed by |
| --- | --- | --- |
| Secret | `AZURE_CLIENT_ID` | `arm-validate` (OIDC) |
| Secret | `AZURE_TENANT_ID` | `arm-validate` (OIDC) |
| Secret | `AZURE_SUBSCRIPTION_ID` | `arm-validate` (OIDC) |
| Repo variable | `PR_VALIDATION_RESOURCE_GROUP` | `arm-validate` (target RG for template validation) |

The other four jobs consume no secrets or variables.

### Artefacts and outputs

- `validate` publishes the NUnit 2.5 report to the PR check UI and uploads
  `test-results/` as run artefact `pester-results-<run_id>` (30-day retention).
- No other job produces an artefact; their outputs are the pass/fail status
  check and the annotated log.

### Wiring as a required gate

After each job has run at least once, add the checks under
**Repo Settings -> Rules -> Rulesets -> Main Branch Protection -> Require
status checks to pass**: `validate`, `bicep-build`, `kql-validate`,
`dependency-manifest`, and `arm-validate` (the last only after the OIDC
setup in [PR Validation Gate Setup](../Deploy/PR-Validation-Setup.md) is complete).
Once required, the merge button stays disabled until every required check
reports success against the PR's latest commit.

---

## Azure DevOps: `Sentinel-PR-Validation.yml`

### Triggers

Both a `pr` trigger and a CI `trigger`, each scoped to `main` with the same
path filter:

```yaml
paths:
  include:
    - Content/AnalyticalRules
    - Content/HuntingQueries
    - Modules
    - Deploy
    - Tools
    - Tests
    - dependencies.json
    - Pipelines/Sentinel-PR-Validation.yml
```

- `pr` runs the pipeline automatically against PR commits (even before the
  branch policy is wired up).
- `trigger` provides a green baseline on push to `main`.

Unlike the GitHub workflow, the ADO pipeline **does** filter by path: it only
runs when one of the listed paths changes.

### Variables

| Variable | Value |
| --- | --- |
| `testResultsFile` | `$(Build.SourcesDirectory)/test-results/pester-results.xml` |

### Stage and job

One stage (`Validate`, display name "PR Validation") with one job
(`RunPRValidation`) on `vmImage: ubuntu-latest`, timeout 15 minutes. No
Azure authentication - every gate here is offline.

Steps, in order:

1. **Checkout** `self` with `fetchDepth: 1`.
2. **Install Pester and powershell-yaml** (inline `pwsh`): installs Pester
   (minimum `5.0.0`) if a suitable version is not already present, plus
   powershell-yaml if missing. Note this is a **minimum-version** install,
   not the exact pin the GitHub composite action enforces.
3. **Run PR validation**: calls `Tools/Invoke-PRValidation.ps1` with
   `-RepoPath`, `-TestResultsPath "$(testResultsFile)"` and
   `-InstallModules:$false` - the same entrypoint the GitHub `validate` job
   uses.
4. **Verify dependency manifest**: `Tools/Build-DependencyManifest.ps1
   -Mode Verify`; logs an error and exits non-zero on drift. This is the ADO
   equivalent of the GitHub `dependency-manifest` job.
5. **Publish Pester results** (`condition: always()`): `PublishTestResults@2`
   with `testResultsFormat: NUnit` against `$(testResultsFile)`.
   `failTaskOnFailedTests: false` because the Pester step has already exited
   non-zero on failure.
6. **Upload Pester report** (`condition: always()`): `PublishPipelineArtifact@1`
   uploads `test-results/` as `pester-results-$(Build.BuildId)`.

### Wiring as a required gate

Configure a build-validation branch policy under **Project Settings -> Repos
-> Repositories -> `<repo>` -> Policies -> Branch policies for `main`**:
Build pipeline `Sentinel-PR-Validation`, trigger Automatic, requirement
Required, expiration "Immediately when `main` is updated". Once required, the
PR's Complete button stays disabled until the pipeline reports success against
the latest commit.

---

## GitHub vs Azure DevOps

| Aspect | GitHub `pr-validation.yml` | ADO `Sentinel-PR-Validation.yml` |
| --- | --- | --- |
| Gates | 5 jobs: `validate`, `bicep-build`, `arm-validate`, `kql-validate`, `dependency-manifest` | 2 gates in one job: Pester (`Invoke-PRValidation.ps1`) + dependency manifest |
| Bicep / ARM / KQL checks | Yes (`bicep-build`, `arm-validate`, `kql-validate`) | **Not present** |
| Azure auth | `arm-validate` uses OIDC; rest offline | None (all gates offline) |
| Path filter | None (runs on every PR / push to `main`) | Path-filtered on both `pr` and `trigger` |
| PR trigger scope | `opened`, `synchronize`, `reopened`, `ready_for_review` | `pr` branches `main` |
| Module install | Exact pins via `setup-pwsh-modules` (Pester `5.7.1`, powershell-yaml `0.4.12`) | Inline; Pester minimum `5.0.0`, powershell-yaml latest |
| Test report | NUnit 2.5 XML (published to check UI + artefact) | NUnit 2.5 XML (published via `PublishTestResults@2` + artefact) |
| Concurrency | Cancels superseded PR runs | Handled by ADO's own PR-run behaviour |

The headline asymmetry: the ADO pipeline covers only the two authentication-free
gates. The Bicep-build, ARM-template and KQL syntax checks exist on GitHub only.
Both pipelines share `Tools/Invoke-PRValidation.ps1` and
`Tools/Build-DependencyManifest.ps1`, so the Pester and dependency-manifest
gates behave identically across the two.

---

## Related documentation

- [Pipelines overview](README.md) - the full set of pipelines and their GitHub parity.
- [PR Validation Gate Setup](../Deploy/PR-Validation-Setup.md) - one-off OIDC + required-check setup for `arm-validate`.
- [Pester Tests](../Tests/Pester-Tests.md) - the test suite the `validate` gate runs.
- [Dependency Manifest](../Tools/Dependency-Manifest.md) - what the dependency-manifest drift gate checks.
