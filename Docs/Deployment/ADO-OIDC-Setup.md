# Azure DevOps OIDC Service Connection Setup

How to wire up `sc-sentinel-as-code` as a workload-identity-federation
service connection so the ADO pipelines authenticate via OIDC instead
of a stored client secret. Mirrors the GitHub-side setup documented in
[PR-Validation-Setup.md](PR-Validation-Setup.md) — same service
principal, same role assignments, just an additional federated
credential trusting ADO's token issuer.

## Why OIDC, not a secret-based service connection

| Concern | Secret-based | OIDC federation |
| --- | --- | --- |
| Stored secret in ADO | Yes | None |
| Secret rotation | Every 1-2 years, manual | Never (per-job token, ~1h TTL) |
| Compromise blast radius | Long-lived secret leakage | One pipeline run |
| Conditional access friendly | Workarounds needed | First-class workload identity |
| Setup effort | Generate + paste secret + set rotation reminder | Trust ADO's issuer once |
| Parity with GitHub workflows | n/a | Same SP, two federated credentials |

OIDC has been GA in ADO since 2024 and is now the recommended
default. Don't pick "App registration with secret" unless you have
a specific reason.

## Two modes ADO offers

| Mode | When to use |
| --- | --- |
| **Workload identity federation (automatic)** | New SP. ADO creates the app registration and adds the federated credential automatically. Zero Entra-side touch. |
| **Workload identity federation (manual)** | Existing SP that GitHub OIDC already uses. Reuse the SP, add a second federated credential pointing at the ADO subject. |

For a Sentinel-As-Code repo that already runs on GitHub Actions: use
**manual mode** so the same SP serves both platforms.

## Prerequisites

- An app registration (service principal) in the target Entra ID
  tenant. Easiest to create via `Scripts/Setup-ServicePrincipal.ps1`,
  which also grants the correct role set on the subscription:

  | Role | Scope | Why |
  | --- | --- | --- |
  | **Contributor** | Subscription | Bicep + Sentinel content + summary rules |
  | **User Access Administrator** (ABAC-conditioned) | Subscription | Playbook MSI role assignments (restricted to 5 roles) |
  | **Microsoft Sentinel Reader** | Workspace | Drift detect (read-only) |
  | **Security Administrator** (Entra ID) | Tenant | UEBA / Entity Analytics — optional |
  | **CustomDetection.ReadWrite.All** (Graph) | Tenant | Defender XDR detections |

  See [Scripts.md → Setup-ServicePrincipal.ps1](Scripts.md#setup-serviceprincipalps1)
  for the full bootstrap walkthrough.

> **Critical**: ADO will not let you save the service connection if
> the SP cannot see the target subscription. The SP must hold at
> least **Reader** on the subscription before you click Save.
> `Setup-ServicePrincipal.ps1` grants Contributor at subscription
> scope (which implies Reader), so this prerequisite is satisfied
> as part of the standard bootstrap. **If you skip the bootstrap
> script and try to wire up ADO first, the Save button fails with
> a generic permission error.**

## Step 1: create the ADO service connection (manual mode)

> ADO Project Settings → Service connections → New service connection
> → Azure Resource Manager → Identity type: **App registration or
> managed identity (manual)** → Credential: **Workload identity
> federation** → Continue

Fill in:

| Field | Value |
| --- | --- |
| Service Connection Name | `sc-sentinel-as-code` (matches `serviceConnection` variable in every Pipelines/*.yml) |
| Description | Optional |
| Environment | Azure Cloud (or AzureUSGovernment for gov tenants) |
| Directory (tenant) ID | Your Entra ID tenant GUID |
| Subscription Id | The target subscription GUID |
| Subscription Name | Friendly name |
| Service Principal Id | The existing SP's app (client) ID |

To find each value:

```bash
# Tenant ID (current login)
az account show --query tenantId -o tsv

# Subscription details (the test subscription you'll target)
az account show --subscription "<sub-name>" --query "{id:id,name:name}" -o table

# SP App ID — same one that GitHub Actions uses; either:
#   1. Look up by display name
az ad app list --display-name 'sentinel-as-code-deployer' --query "[0].appId" -o tsv

#   2. Or pull from your password manager (it's the value of the
#      AZURE_CLIENT_ID GitHub repo secret)
```

Click **Save**. ADO writes the connection and shows you two values
on the result page.

## Step 2: copy the federation Issuer + Subject

ADO displays two pieces of metadata:

- **Issuer**: typically `https://vstoken.dev.azure.com/<org-guid>`
- **Subject identifier**: `sc://<org-name>/<project-name>/<service-connection-name>`

For example:
```
https://vstoken.dev.azure.com/12345678-1234-1234-1234-123456789012
sc://sentinel-blog/Sentinel-As-Code (GitHub)/sc-sentinel-as-code
```

**Copy both.** ADO doesn't store them anywhere reachable later in
the UI; if you close the page without copying, you can re-derive
them but it's easier to copy now.

## Step 3: add the federated credential to the SP in Entra ID

> Entra ID → App registrations → `<your-SP-name>` → Certificates &
> secrets → Federated credentials → + Add credential → Select
> **Other issuer**

Fill in:

| Field | Value |
| --- | --- |
| Issuer | Paste from ADO (e.g. `https://vstoken.dev.azure.com/<org-guid>`) |
| Subject identifier | Paste from ADO (e.g. `sc://sentinel-blog/Sentinel-As-Code (GitHub)/sc-sentinel-as-code`) |
| Audience | `api://AzureADTokenExchange` (default) |
| Name | Descriptive — e.g. `ado-sentinel-as-code-test` |
| Description | Optional |

Click **Add**. The SP now trusts ADO's token issuer for the matching
subject claim.

## Step 4: verify the service connection

Back in ADO → Service connections → `sc-sentinel-as-code` → click
**Verify** at the top.

ADO performs a test token exchange. Green tick = federation is
working end-to-end. Red error = check that:

- The Issuer URL matches exactly (case + trailing slash matter)
- The Subject identifier matches exactly (case-sensitive; spaces in
  project name preserved)
- The SP has at least Reader on the subscription
- You're verifying the correct Audience (`api://AzureADTokenExchange`)

## Step 5: register the pipelines

Once Verify passes, register the five ADO pipelines (in this order
to keep the blast radius growing gradually):

1. `Pipelines/Sentinel-PR-Validation.yml` (offline; safest test)
2. `Pipelines/Sentinel-Dependency-Update.yml` (offline + Build Service git permissions)
3. `Pipelines/Sentinel-DCR-Inventory.yml`
4. `Pipelines/Sentinel-Drift-Detect.yml` (read-only against Sentinel)
5. `Pipelines/Sentinel-Deploy.yml` (full deploy; run with `flagWhatIf: true` first)

For each:

> ADO Pipelines → New pipeline → Azure Repos Git → `<repo>` →
> Existing Azure Pipelines YAML file → pick `/Pipelines/<name>.yml`
> → Save (do not run yet)

Then rename to drop the auto-generated prefix:

> Pipeline page → "..." menu → Rename/move → drop the
> `<repo-name> -` prefix so the pipeline list shows just
> `Sentinel-PR-Validation`, `Sentinel-Deploy`, etc.

## Step 6: configure the build-validation policy on `main`

> Project Settings → Repos → Repositories → `<repo>` → Policies →
> Branch policies for `main` → Build validation → + Add build policy

| Setting | Value |
| --- | --- |
| Build pipeline | `Sentinel-PR-Validation` |
| Path filter | `AnalyticalRules/*;HuntingQueries/*;Modules/*;Scripts/*;Tests/*;dependencies.json;Pipelines/Sentinel-PR-Validation.yml` |
| Trigger | Automatic |
| Policy requirement | Required |
| Build expiration | Immediately when source branch is updated |
| Display name | `PR Validation` |

After Save, every PR to `main` will block on this policy until the
pipeline reports success. The auto-PR pipelines
(`Sentinel-Drift-Detect`, `Sentinel-Dependency-Update`) produce PRs
that go through the same gate.

## Step 7: grant the Build Service identity git permissions

The two auto-PR pipelines push to a rolling
`auto/sentinel-drift-sync` / `auto/dependency-manifest-sync` branch
and open PRs via `az repos pr create`. They authenticate using
`System.AccessToken`, which is issued to the project-scoped
**Build Service identity**, NOT the service principal you wired
up in Step 1. The two identities are separate; granting the SP
roles in Azure does nothing for ADO repository write access.

### How to find the right identity

1. Open **Project Settings → Repos → Repositories → `<repo>` → Security**.
2. In the identity search box, type the project name, e.g.
   `Sentinel-As-Code (GitHub) Build Service`. The full identity
   shows up as `<Project Name> Build Service (<Org Name>)`.
3. If the search returns nothing, type `Build Service` alone — at
   least one project-scoped Build Service identity will exist.
4. **Tip**: when a pipeline run fails, the error log includes the
   identity GUID (e.g. `Build\4f9a0878-8c9c-4c9f-a7cb-5ee8476f1492`).
   That GUID is the underlying account; the search box shows the
   friendly name.

### Permissions to grant

Set each to **Allow** (not Inherit, not Not set — Allow explicitly):

| Permission | Required for | Underlying right (API name) |
| --- | --- | --- |
| **Contribute** | `git push` to any branch the pipeline writes | `GenericContribute` |
| **Create branch** | First-time creation of `auto/sentinel-drift-sync` and `auto/dependency-manifest-sync` | `CreateBranch` |
| **Contribute to pull requests** | `az repos pr create` and `az repos pr update` calls in the workflow | `PullRequestContribute` |

Do **not** grant `Force push (rewrite history and delete branches)`
or `Bypass policies when pushing` — the auto-PR pipelines use
`--force-with-lease` against their own bot-managed branches, which
works with just `Contribute`.

### Common error this rule catches

If you skip this step, the auto-PR pipelines fail at the
`git push` step with:

```
remote: TF401027: You need the Git 'GenericContribute' permission to perform this action.
remote: Details: identity 'Build\<guid>', scope 'repository'.
fatal: unable to access '...': The requested URL returned error: 403
```

`GenericContribute` is the API name for the **Contribute** UI
checkbox. Set it to Allow on the identity in the error message
and re-queue the pipeline.

### Verifying without waiting for the cron schedule

Both auto-PR pipelines have manual triggers — pick **Run pipeline**
from the pipeline page in ADO. The drift-detect pipeline accepts a
`reportOnly: true` parameter that runs the discovery without
attempting to commit, so you can split verification into two
phases:

1. First run with `reportOnly: true` to confirm the read path
   (Sentinel API auth, drift detection logic).
2. Second run without `reportOnly` to confirm the write path
   (`git push`, `az repos pr create`). This is what the
   GenericContribute permission unlocks.

## Verification checklist

After the steps above, confirm:

- [ ] `sc-sentinel-as-code` service connection exists with **Workload identity federation** as the credential type
- [ ] ADO Verify reports green
- [ ] Federated credential exists in Entra under the SP, pointing at the ADO subject
- [ ] All five pipelines appear under Pipelines → All
- [ ] Build-validation policy on `main` references `Sentinel-PR-Validation`
- [ ] Build Service identity has Contribute + Create branch + Contribute to pull requests
- [ ] Manual `Sentinel-PR-Validation` run completes (offline; should pass without auth)
- [ ] Manual `Sentinel-Deploy` run with `flagWhatIf: true` completes (exercises the OIDC auth path end-to-end)

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| ADO Save button is greyed out | Tenant ID, Subscription ID, or SP App ID empty / invalid | Re-derive each from the `az` commands above; verify the SP exists in the correct tenant |
| ADO Save returns generic permission error | SP has no role on the target subscription | Run `Scripts/Setup-ServicePrincipal.ps1` against that subscription, OR manually grant at minimum `Reader` at subscription scope before retrying |
| Verify fails with `AADSTS70021: No matching federated identity record found` | Issuer or Subject mismatch between ADO and the Entra federated credential | Re-copy both values from the ADO service connection's metadata page; trailing slash, case, and exact spacing all matter |
| Verify passes but pipeline run fails with `AzurePowerShell` step "Could not get OIDC token" | Build Service identity lacks "Use" permission on the service connection | Service connections → `sc-sentinel-as-code` → Security → grant the relevant pipeline / project Use permission |
| Auto-PR pipeline run fails at `git push` with `TF401027: You need the Git 'GenericContribute' permission` | Project-scoped Build Service identity missing `Contribute` on the repo | See Step 7 — grant Contribute + Create branch + Contribute to pull requests on the identity named in the error message (the GUID is the underlying account; search by friendly name `<Project> Build Service`) |
| Auto-PR pipeline succeeds at `git push` but fails at `az repos pr create` with `TF401027` | Same identity missing `Contribute to pull requests` (`PullRequestContribute`) | Add the missing permission per Step 7 |
| Auto-PR pipeline runs every time but never opens a PR | The script reports "no drift detected — working tree clean" and exits 0; this is the success path | Confirm by checking `reports/sentinel-drift-*.md` artefact published by the pipeline run; if the report says "no drift", everything is working |
| Auto-PR pipeline fails at `git push` | Build Service identity missing `Contribute` / `Create branch` | Re-check Step 7 |

## Related docs

- [Pipelines](Pipelines.md) — pipeline reference, variable group spec, service connection roles
- [Scripts → Setup-ServicePrincipal.ps1](Scripts.md#setup-serviceprincipalps1) — the one-shot SP role bootstrap (works regardless of credential type — secret-based, certificate, or OIDC federation)
- [PR-Validation-Setup.md](PR-Validation-Setup.md) — GitHub-side equivalent; mirror this one for the GitHub OIDC federated credential
- [GitHub Copilot setup](../Development/GitHub-Copilot.md) — `pipeline-engineer` agent owns CI/CD parity work
