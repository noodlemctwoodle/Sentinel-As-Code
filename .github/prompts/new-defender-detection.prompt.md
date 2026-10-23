---
description: Bootstraps a Defender XDR custom detection rule YAML using Advanced Hunting tables.
argument-hint: <one-line detection scenario>
agent: agent
tools: ['search/codebase', 'edit/applyPatch', 'terminal/run']
---

# New Defender XDR custom detection

Bootstrap a fresh Defender XDR custom detection rule under
`Content/DefenderCustomDetections/<Category>/<DetectionName>.yaml`.

## When to use this vs an analytical rule

- **Defender XDR custom detection** — table comes from the Defender
  XDR Advanced Hunting schema (`DeviceEvents`, `EmailEvents`,
  `IdentityLogonEvents`, etc.). Deploys via Microsoft Graph Security
  API (beta) to Defender XDR.
- **Sentinel analytical rule** — table comes from the Sentinel
  workspace (`SecurityAlert`, `SigninLogs`, `AzureActivity`).
  Deploys via the Sentinel REST API.

If the threat scenario uses Defender's Advanced Hunting tables, it's
a Defender custom detection. If it uses Sentinel-side tables, it's
an analytical rule (`/new-analytical-rule`).

## Inputs to gather

- **Detection scenario** — one-line summary.
- **Defender XDR table** — `DeviceProcessEvents`, `EmailEvents`,
  `IdentityLogonEvents`, `CloudAppEvents`, etc.
- **Severity** — lowercase: `high`, `medium`, `low`,
  `informational`. (Different from analytical rules, which are
  PascalCase.)
- **Schedule** - an ISO 8601 `frequency`: `PT1H`, `PT3H`, `PT12H` or
  `P1D` (NRT is portal-only).
- **Entities** - what the detection attaches to the alert (a device,
  an account, a mailbox), and which query columns identify them
  (`DeviceId`, `AccountObjectId`, `RecipientEmailAddress`).

## Steps

1. **Pick a category folder.** Existing structure:
   - `Content/DefenderCustomDetections/Email/` — EmailEvents-based
   - `Content/DefenderCustomDetections/Endpoint/` — Device*-based
   - `Content/DefenderCustomDetections/Identity/` — IdentityLogon /
     IdentityDirectory-based
   - `Content/DefenderCustomDetections/CloudApps/` — CloudAppEvents-based
   - `Content/DefenderCustomDetections/Office365/` — OfficeActivity-based
   If a fitting folder doesn't exist, ask before creating one.

2. **Pick a file name.** PascalCase, descriptive of the detection.

3. **Write the YAML** following the schema in
   [`.github/instructions/defender-detections.instructions.md`](../instructions/defender-detections.instructions.md).

   Required fields:
   - `id` (lowercase kebab-case, unique; Graph needs it to create the rule)
   - `displayName`
   - `status` (`enabled` or `disabled`)
   - `queryCondition.queryText`
   - `schedule.frequency`
   - `detectionAction.alertTemplate.{title, description, severity, tactics, entityMappings}`
   - `detectionAction.automatedActions` only when the user asks for actions

4. **Write the KQL** using Defender XDR Advanced Hunting tables.
   **Do not use Sentinel tables** (`SecurityAlert`, `SigninLogs`,
   `AzureActivity`) — those don't exist in Advanced Hunting.

5. **Set up `entityMappings`** with columns the query projects:

   ```yaml
   entityMappings:
     hosts:
       - deviceIdColumn: DeviceId
         nameColumn: DeviceName
   ```

   The query must `project` `DeviceId` and `DeviceName` for this to
   resolve. See the table in the path-scoped instruction file for
   the common column mappings.

6. **Run the schema test:**
   ```powershell
   Invoke-Pester -Path Tests/Test-DefenderDetectionYaml.Tests.ps1
   ```

   Defender XDR detections are NOT in `dependencies.json` (different
   deploy stage with its own table catalogue). Skip the dep-manifest
   step.

7. **Stage** the new YAML.

## Hard rules

- **`status: enabled|disabled`** - not `isEnabled` (removed from Graph
  on 2026-10-01) and not `enabled`.
- **Never use the retired field names** `schedule.period`, `category`,
  `mitreTechniques`, `impactedAssets` or `responseActions`.
- **Lowercase severity**: `high`, `medium`, `low`, `informational`.
- **No automated actions without explicit consent.** Adding
  `isolateDevices`, `forceUserPasswordResets`, `restrictAppExecutions`,
  etc. requires the deploy SP to have the matching action permission
  and admin-approved consent. Ask the user before adding any
  automated action.
