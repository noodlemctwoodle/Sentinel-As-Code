# Graph API Migrations

Upcoming Microsoft Graph `security` API changes that affect how the
[Sentinel as Code Toolkit](README.md) models Microsoft Defender XDR custom
detections. Tracked here so the Toolkit's schema, templates, and converters can
be migrated ahead of the removal dates, and so authors know which fields are on
a deprecation path.

This page was migrated from the Toolkit repository's `docs/` folder. The file
paths below (`schemas/`, `templates/`, `src/`) refer to the Toolkit repository,
not this one. See also [Defender Workflows](Defender-Workflows.md) and the
repository [Defender Custom Detections](../Content/Defender-Custom-Detections.md)
schema.

> Source: Microsoft Graph beta reference (`microsoft.graph.security`), verified 2026-07-09.

## Status (2026-10-23)

Microsoft removed the deprecated fields on 2026-10-01. **This repository is
migrated**: the 33 rules under `Content/DefenderCustomDetections/` use the
current shape, `Deploy/content/Deploy-DefenderDetections.ps1` sends it (and
translates any file still in the old shape, with a warning), and the CI suite
rejects the old field names. Rules also carry a client-provided `id`, which
Graph now requires when a rule is created. The repository schema and the
old-to-new field table are in
[Defender Custom Detections](../Content/Defender-Custom-Detections.md#moving-a-rule-from-the-old-shape).

**The Toolkit is not migrated yet.** Its schema, template, converters and
validator below still model the old fields, so the Toolkit flags files in the
current shape until the plan below is carried out.

## Deprecations (removed on 2026-10-01)

| Current shape (used by the Toolkit) | Replacement | Notes |
|---|---|---|
| `detectionAction.responseActions` and all 17 `responseAction` derived types | `detectionAction.automatedActions` (grouped via `automatedActionSet`) | The custom-detection template catalogues every current `responseAction`. Migration means re-mapping each to an `automatedAction`. |
| `detectionRule.isEnabled` (boolean) | `detectionRule.status` (`detectionRuleStatus` enum) | Boolean flag becomes an enum. |
| `ruleSchedule.period` (`0`, `1H`, `3H`, `12H`, `24H`) | `ruleSchedule.frequency` (ISO 8601: `PT1H`, `PT3H`, `PT12H`, `P1D`) | No documented API frequency for NRT. |
| `alertTemplate.category` and `alertTemplate.mitreTechniques` | `alertTemplate.tactics` (`mitreTactic` with `techniques` and `subTechniques`) | Category becomes the tactic; sub-techniques nest under their parent. |
| `organizationalScope.scopeNames` and `scopeType` | `organizationalScope.deviceGroups` | |
| `queryCondition.lastModifiedDateTime`, `detectorId`, `lastRunDetails`, `schedule.nextRunDateTime` | none | Read-only or removed. |
| (no `id` on create) | `detectionRule.id`, client-provided and required on create | New rules need an id in the file. |
| `alertTemplate.impactedAssets` and the `impacted*Asset` derived types | `alertTemplate.entityMappings` and the `entityMapping` derived types | Entity-mapping shape changes. |

## Where the Toolkit depends on the current shape

- `schemas/defender-custom-detection-schema.json` - models `isEnabled`, `queryCondition`, `schedule`, `detectionAction.alertTemplate` (with `impactedAssets`) and `detectionAction.responseActions`.
- `templates/custom-detection.template.yaml` - uses `isEnabled`, `impactedAssets`, and the full `responseActions` catalogue.
- `src/defender/services/defenderXdrService.ts` - `formatRuleForRepo` and the convert methods pass `responseActions` and `impactedAssets` through unchanged.
- `src/validation/defenderDetectionValidator.ts` - requires `isEnabled`; treats `responseActions` / `impactedAssets` as arrays.

## Migration plan (Toolkit, outstanding)

1. Extend the schema and validator to accept `automatedActions`, `status`, and `entityMappings` alongside the current fields (dual-read during the transition).
2. Update `defenderXdrService` conversion to emit the new shape.
3. Switch `templates/custom-detection.template.yaml` to `automatedActions` / `status` / `entityMappings`.
4. Remove the deprecated fields once tenants no longer accept the old shape.
