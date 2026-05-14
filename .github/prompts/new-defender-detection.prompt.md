---
description: Bootstraps a Defender XDR custom detection rule YAML using Advanced Hunting tables.
argument-hint: <one-line detection scenario>
agent: agent
tools: ['search/codebase', 'edit/applyPatch', 'terminal/run']
---

# New Defender XDR custom detection

Bootstrap a fresh Defender XDR custom detection rule under
`DefenderCustomDetections/<Category>/<DetectionName>.yaml`.

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
- **Schedule** — `"0"` for near-real-time, otherwise an ISO 8601
  duration (`"PT1H"`, `"P1D"`).
- **Impacted asset type** — what the detection emits as the affected
  entity. Common: `deviceId`, `accountObjectId`, `mailbox`, `url`.

## Steps

1. **Pick a category folder.** Existing structure:
   - `DefenderCustomDetections/Email/` — EmailEvents-based
   - `DefenderCustomDetections/Endpoint/` — Device*-based
   - `DefenderCustomDetections/Identity/` — IdentityLogon /
     IdentityDirectory-based
   - `DefenderCustomDetections/CloudApps/` — CloudAppEvents-based
   - `DefenderCustomDetections/Office365/` — OfficeActivity-based
   If a fitting folder doesn't exist, ask before creating one.

2. **Pick a file name.** PascalCase, descriptive of the detection.

3. **Write the YAML** following the schema in
   [`.github/instructions/defender-detections.instructions.md`](../instructions/defender-detections.instructions.md).

   Required fields:
   - `displayName`
   - `isEnabled` (Defender uses `isEnabled`, not `enabled`)
   - `queryCondition.queryText`
   - `schedule.period`
   - `detectionAction.alertTemplate.{title, description, severity, category, mitreTechniques, impactedAssets}`
   - `detectionAction.organizationalScope`
   - `detectionAction.responseActions`

4. **Write the KQL** using Defender XDR Advanced Hunting tables.
   **Do not use Sentinel tables** (`SecurityAlert`, `SigninLogs`,
   `AzureActivity`) — those don't exist in Advanced Hunting.

5. **Set up `impactedAssets`** so the column reference matches what
   the query projects:

   ```yaml
   impactedAssets:
     - identifier: deviceId
       '@odata.type': '#microsoft.graph.security.impactedDeviceAsset'
   ```

   The query must `project` a column named `DeviceId` for this to
   resolve. See the table in the path-scoped instruction file for
   the common identifier shapes.

6. **Run the schema test:**
   ```powershell
   Invoke-Pester -Path Tests/Test-DefenderDetectionYaml.Tests.ps1
   ```

   Defender XDR detections are NOT in `dependencies.json` (different
   deploy stage with its own table catalogue). Skip the dep-manifest
   step.

7. **Stage** the new YAML.

## Hard rules

- **`isEnabled: true|false`** — not `enabled`, not `status`.
- **Lowercase severity**: `high`, `medium`, `low`, `informational`.
- **No response actions without explicit consent.** Adding
  `isolateDevice`, `forceUserPasswordReset`, `restrictExecution`,
  etc. requires the deploy SP to have the matching action permission
  and admin-approved consent. Ask the user before adding any
  response action.
