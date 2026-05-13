---
name: Playbooks
description: ARM template requirements for Logic App playbooks under Playbooks/.
applyTo: "Playbooks/**/*.json"
---

# Playbook authoring (Logic App ARM templates)

Logic App playbooks deployed via ARM template under
`Playbooks/<Trigger-Type>/<Name>.json`. Trigger-type folders are:

- `Alert/` — playbooks triggered by analytical rule alerts
- `Entity/` — entity-trigger playbooks (run from an entity timeline)
- `Incident/` — incident-trigger playbooks
- `Module/` — sub-flow modules invoked by other playbooks
- `Other/` — manual-trigger or scheduled playbooks
- `Template/` — *not deployed* — sample templates only
- `Watchlist/` — playbooks that mutate watchlists

Full schema in [`Docs/Content/Playbooks.md`](../../Docs/Content/Playbooks.md).

## Required ARM-template structure

```jsonc
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "metadata": {
    "title": "<Playbook-Name>",
    "description": "<one-line description>",
    "lastUpdateTime": "DD-MM-YYYY",
    "entities": [],
    "tags": ["<Trigger-Type>", "Source: Sentinel-As-Code"],
    "support": { "tier": "community" },
    "author": { "name": "<author>" }
  },
  "parameters": {
    "PlaybookName":              { "defaultValue": "<Name>",  "type": "string" },
    "AutomationResourceGroup":   { "defaultValue": "",        "type": "string" },
    "SentinelWorkpaceName":      { "defaultValue": "",        "type": "string" },
    "SentinelResourceGroupName": { "defaultValue": "",        "type": "string" },
    "SubscriptionId":            { "defaultValue": "",        "type": "string" }
    // Add playbook-specific parameters below
  },
  "variables": { ... },
  "resources": [ ... ]
}
```

## Hard rules

1. **`metadata.tags` must include `"Source: Sentinel-As-Code"`.**
   `Set-PlaybookPermissions.ps1` only assigns roles to playbooks
   carrying this tag. Untagged playbooks are ignored by the post-
   deploy RBAC step.
2. **Use the auto-injected parameters by name.** The deploy script
   injects values for `AutomationResourceGroup`,
   `SentinelWorkpaceName` (note the typo — preserved for backward
   compat), `SentinelWorkspaceName` (correctly spelled, also accepted),
   `SentinelResourceGroupName`, `SubscriptionId`, `PlaybookName`. Use
   these via `[parameters('PlaybookName')]` etc. — don't hand-edit
   them at deploy time.
3. **Truncate `PlaybookName` defaults to ≤64 chars.** Logic App
   resource names are limited to 64 characters; the deploy script
   truncates automatically but a default that's already short avoids
   surprises.
4. **Module playbooks must deploy first.** Files under `Playbooks/Module/`
   are sub-flows that other playbooks invoke. The deploy script
   orders them first automatically — but if module A depends on
   module B, B must come before A alphabetically (the script's
   secondary ordering hint).
5. **Files under `Playbooks/Template/` do not deploy.** That folder
   is for in-repo reference templates only. Don't put real playbooks
   there.
6. **Use system-assigned managed identity** for connections to
   Sentinel, Defender, Graph, Key Vault. Avoid user-credential
   connections in repo-managed playbooks.
7. **Never embed secrets.** Use Key Vault references for runtime
   secrets. The connector identity needs `Key Vault Secrets User` —
   `Set-PlaybookPermissions.ps1` grants this when the playbook
   references the Key Vault you supply via `-KeyVaultName`.

## After editing

1. Run schema tests:
   ```powershell
   Invoke-Pester -Path Tests/Test-PlaybookArm.Tests.ps1
   ```
2. The `arm-validate` PR-validation job runs
   `Test-AzResourceGroupDeployment -WhatIf` against your file
   automatically — fix any ARM-template errors locally first via
   `az deployment group validate` if you want a faster feedback loop.

## Post-deploy permission grant

After deploy, `Scripts/Set-PlaybookPermissions.ps1` runs separately
(not in the deploy pipeline) under a higher-privilege identity. It
inspects each playbook's workflow content and grants the playbook's
managed identity the minimum role set it needs. New connector types
or HTTP-action endpoints may require updating that script — see
[`Docs/Deployment/Scripts.md`](../../Docs/Deployment/Scripts.md#set-playbookpermissionsps1)
for the role mapping.

## Cross-references

- Full schema + connector mapping: [`Docs/Content/Playbooks.md`](../../Docs/Content/Playbooks.md)
- Permission script: [`Docs/Deployment/Scripts.md#set-playbookpermissionsps1`](../../Docs/Deployment/Scripts.md#set-playbookpermissionsps1)
- Tests: [`Tests/Test-PlaybookArm.Tests.ps1`](../../Tests/Test-PlaybookArm.Tests.ps1)
