# PR Validation Gate Setup

The PR-validation gate ([`.github/workflows/pr-validation.yml`](../../.github/workflows/pr-validation.yml))
runs four jobs on every pull request to `main`:

| Job | Auth needed | What it catches |
| --- | --- | --- |
| `validate` | None | Pester suite regressions + content YAML/JSON schema breakage |
| `bicep-build` | None | Bicep syntax errors and parameter type mismatches in `Bicep/*.bicep` |
| `arm-validate` | **OIDC** | Malformed playbook ARM templates, missing required parameters |
| `kql-validate` | None | KQL syntax errors across analytical rules / hunting queries / parsers / summary rules |

The first two and the last work offline. **`arm-validate` needs Azure
authentication** because `Test-AzResourceGroupDeployment -WhatIf` calls the
ARM deployment-validation API against a real resource group with a real
workspace. This page is the one-off setup runbook for that.

## Overview

| Step | What | Where |
| --- | --- | --- |
| 1 | Deploy the test workspace | `Bicep/test/main.bicep` to a dedicated test RG |
| 2 | Create the federated credential on the deploy SP | Entra ID / `az ad app federated-credential create` |
| 3 | Add the secrets to the repo | GitHub Repo Settings → Secrets and variables → Actions |
| 4 | Add `arm-validate` to the required checks | GitHub Repo Settings → Rules → Rulesets |

End-to-end this is about 15 minutes of manual work, paid once.

## Step 1: deploy the test workspace

The ARM What-If job validates each playbook against an empty Sentinel-enabled
workspace. The workspace is the only Azure resource this gate needs, and it
ingests no data by design — it exists only as a deployment target.

```bash
# Pick names. The defaults below are reasonable; substitute as you wish.
RG_NAME="rg-sentinel-pr-validation"
RG_LOCATION="uksouth"
WORKSPACE_NAME="law-sentinel-pr-test"

# Create the resource group
az group create --name "$RG_NAME" --location "$RG_LOCATION"

# Deploy the test workspace
az deployment group create \
  --name pr-validation-test-workspace \
  --resource-group "$RG_NAME" \
  --template-file Bicep/test/main.bicep \
  --parameters workspaceName="$WORKSPACE_NAME"
```

Expected cost: ~£0/month. Free-tier Log Analytics caps daily ingestion at
1 GB, the workspace ingests nothing, and Sentinel onboarding has no
standalone cost.

## Step 2: create the federated credential

The `arm-validate` job authenticates as your existing deploy service
principal (the one your `Sentinel-Deploy.yml` workflow already uses) via
OIDC federation. Federation lets GitHub Actions short-lived tokens stand
in for client secrets — no secrets to rotate.

```bash
# Get the SP's app registration ID (the one already used by Sentinel-Deploy.yml)
APP_OBJECT_ID=$(az ad app show --id "$AZURE_CLIENT_ID" --query id -o tsv)

# Add a federated credential scoped to PRs against main
az ad app federated-credential create \
  --id "$APP_OBJECT_ID" \
  --parameters '{
    "name": "github-pr-validation",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:noodlemctwoodle/Sentinel-As-Code:pull_request",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

The `subject: repo:noodlemctwoodle/Sentinel-As-Code:pull_request` clause
restricts the federation to PR events on this repo only. PRs on forks
authenticate against the fork repo's subject, not this one, and so they
will not get a token — fork PRs run the offline jobs only.

The deploy SP needs **Reader** on the test RG (which the validation job
uses) plus **Contributor** to actually exercise the `-WhatIf` deploy. The
existing Sentinel-Deploy SP is usually already a Contributor on this
subscription, in which case there is nothing more to grant. If you are
using a least-privilege model, add Reader + Test ARM Deployment Validator
on the test RG specifically.

## Step 3: add secrets to the repo

The workflow reads three values from secrets/variables:

| Name | Type | Value |
| --- | --- | --- |
| `AZURE_CLIENT_ID` | Repository secret | The deploy SP's Application (client) ID |
| `AZURE_TENANT_ID` | Repository secret | Entra ID tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Repository secret | Subscription ID containing the test RG |
| `PR_VALIDATION_RESOURCE_GROUP` | Repository variable | Name of the test RG (e.g. `rg-sentinel-pr-validation`) |

`AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` are the
same secrets the deploy workflow already uses, so the federated credential
piggybacks on the existing identity — no new SP to manage.

`PR_VALIDATION_RESOURCE_GROUP` is set as a repository **variable** (not a
secret), since the RG name is non-sensitive.

## Step 4: add `arm-validate` to required checks

Once the workflow has run on at least one PR (so GitHub registers the
job name), add it to the existing branch-protection ruleset:

> Repo Settings → Rules → Rulesets → Main Branch Protection → Edit
>
> Under "Require status checks to pass" → Add checks
>
> Required: `arm-validate`

Apply the same to `bicep-build`, `kql-validate`, and `dependency-manifest`
once they have run.

## Composite actions

Two composite actions live under `.github/actions/` and are reused by
every workflow that needs them. Use them in new workflows instead of
inlining the patterns again:

- `./.github/actions/azure-login-oidc` — federated OIDC login wrapper.
  Replaces the six-line `Azure/login@v2` block at every call site with
  a four-line invocation. Defaults `enable-AzPSSession: true` because
  most call sites use both the `az` CLI and Az PowerShell. Pass
  `enable-azps-session: 'false'` for CLI-only jobs to slightly reduce
  auth-step time.

- `./.github/actions/setup-pwsh-modules` — Pester + powershell-yaml
  cache + pinned install + verify pattern. Replaces ~30-line install
  blocks. Pass `install-pester: 'false'` for jobs that only consume
  YAML (e.g. the `dependency-manifest` gate). Default version pins
  match the workflow-level `PESTER_VERSION` / `YAML_VERSION` env vars
  the existing workflows define.

When wiring up a new workflow that needs Azure auth or PowerShell
modules, use these. Don't inline `Azure/login@v2` or `Install-Module`
in fresh code — the composite actions are the single source of truth
for both patterns.

After this, every PR's merge button stays disabled until all required
gates pass.

## What if a fork PR can't authenticate?

Fork PRs cannot get an OIDC token for the upstream's federated credential
(the `subject` claim mismatches), so `arm-validate` skips on fork PRs.
The workflow handles this gracefully: the offline jobs still run and
report status; `arm-validate` is marked as not required for fork PRs by
the ruleset. Maintainers reviewing fork PRs validate ARM templates
manually as part of code review.

If you want to run `arm-validate` against a fork PR, either:

- Re-target the PR to a maintainer-controlled branch first, then onto
  `main` after the gate passes; or
- Run the workflow manually via `workflow_dispatch` against the fork's
  branch from the maintainer's checkout.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `arm-validate` step fails with `AADSTS70021: No matching federated identity record found` | Federated credential subject doesn't match the PR's repo | Recheck step 2's `subject` value matches `repo:{owner}/{repo}:pull_request` exactly |
| `arm-validate` step fails with `Resource group 'rg-sentinel-pr-validation' not found` | Test RG hasn't been deployed yet (step 1) | Run the `az group create` + `az deployment group create` from step 1 |
| `bicep-build` fails for an unchanged Bicep file | A `bicep` minor-version bump shipped a new lint rule | Pin a specific Bicep version in the workflow's `setup-bicep` step |
| `kql-validate` fails on a query that runs fine in the portal | The Microsoft.Azure.Kusto.Language parser is stricter than the runtime engine in some edge cases | If the query is genuinely valid, raise an issue and we'll exempt the rule via a comment-driven opt-out |
