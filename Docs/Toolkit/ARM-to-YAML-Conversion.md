# ARM to YAML Conversion

The [Sentinel as Code Toolkit](https://marketplace.visualstudio.com/items?itemName=noodlemctwoodle.sentinelcodeguard) can decompile exported Microsoft Sentinel analytics rules from ARM template JSON into clean, repository-ready analytics-rule YAML. This lets you take rules that already exist in a workspace (exported from the portal, or captured in an ARM template) and bring them under source control in the format the Sentinel-as-Code pipeline expects.

The Toolkit only converts and validates the content locally. It does not connect to a tenant and it does not deploy anything; deployment remains the job of the Sentinel-as-Code pipeline. Converted files land in your working tree for you to review and commit.

## What It Converts

The command reads an ARM template and extracts every analytics rule resource it contains (type `Microsoft.OperationalInsights/workspaces/providers/alertRules`, the shape the Sentinel portal exports), converting each one into a separate analytics-rule YAML file that maps to the [Analytical Rules](../Content/Analytical-Rules.md) authoring contract.

- **Input:** an ARM deployment template (`.json`) containing one or more `alertRules` resources. The template must have a valid `$schema` and a `resources` array.
- **Output:** one analytics-rule `.yaml` file per rule, written alongside the source file by default (or to a configured output directory).
- **Rule kinds:** `Scheduled` and `NRT` are converted as such (ARM exports near-real-time rules as kind `NRT`; `NearRealTime` is accepted as an alias). NRT rules are written without `queryFrequency`, `queryPeriod`, `triggerOperator` or `triggerThreshold`, because Sentinel runs them on its own cadence. `MLBehaviorAnalytics` is kept as-is. Any other or missing `kind` is normalised to `Scheduled`.
- **MITRE techniques:** written under `relevantTechniques`, the canonical field for analytics rules. Sub-techniques from the ARM `subTechniques` property are folded into the same list (for example `T1078.004` rather than a bare `T1078`).
- **Skipped resources:** any resource that is not an analytics rule resource of the type above, or that has no `displayName`, is ignored. Templates that declare rules as `Microsoft.SecurityInsights/alertRules` extension resources are not recognised.

### Single vs Bulk

There is one command for both cases; the behaviour depends on how many rules the template holds:

- **Single rule** - a template with one `alertRules` resource produces one YAML file.
- **Bulk** - a template with several `alertRules` resources produces one YAML file per rule in a single run. This is the common shape when a template was exported for a whole rule set rather than an individual rule.

## Running the Conversion

The command is **Sentinel-As-Code: Decompile ARM to YAML** (`sentinelAsCode.convertArmToYaml`). You can start it three ways, all gated on `sentinelAsCode.conversion.enabled` being `true`:

| How | Where |
|-----|-------|
| Command Palette | Open a `.json` ARM template, press `Ctrl+Shift+P` / `Cmd+Shift+P`, and run **Sentinel-As-Code: Decompile ARM to YAML** |
| Editor right-click | Right-click inside an open `.json` file and choose the command from the Sentinel-As-Code group |
| Explorer right-click | Right-click a `.json` file in the Explorer and choose the command |

If you run it from the Command Palette without a `.json` file open, you are asked to pick the template. Files are named with `conversion.defaultNamingStrategy` and written next to the source file, or to `conversion.outputDirectory` if set. The first converted file opens, and a summary lists any warnings.

## Naming Strategies

The naming strategy decides how each converted file is named. It comes from `sentinelAsCode.conversion.defaultNamingStrategy`; change the setting to use a different strategy.

| Strategy | File name | Notes |
|----------|-----------|-------|
| `displayName` (default) | Sanitised rule `displayName` | Human-readable; illegal filename characters are stripped |
| `ruleId` | The rule's GUID | Taken from the ARM resource name where a GUID is present, otherwise a new GUID is generated |
| `original` | `rule.yaml`, then `rule_2.yaml`, `rule_3.yaml` for subsequent rules | Positional naming, independent of the rule content |

All strategies write a `.yaml` extension.

## Validation and Correction During Conversion

Several checks and clean-ups run as part of the conversion. Each is controlled by a setting (see [Conversion Settings](#conversion-settings)) and reported in the summary.

- **MITRE correction** - when `validateMitreOnConversion` is on, tactics and techniques are validated and corrected against the Toolkit's bundled MITRE ATT&CK data. If a rule carries no usable tactic, a default is inserted and flagged with a warning so you know to replace it.
- **Entity-mapping validation** - when `validateEntityMappings` is on, each entity mapping in the source is checked: the entity type must be one Sentinel recognises, and every field mapping needs both an `identifier` and a `columnName`. Problems are reported as warnings. Separately, a rule with no entity mappings always receives a placeholder mapping, flagged with a warning to prompt you to set real column names.
- **Optional fields** - when `includeOptionalFields` is on, optional fields are written with sensible default values so the resulting YAML is complete rather than sparse.
- **Query formatting** - when `preserveQueryFormatting` is on, the original KQL layout from the ARM template is kept intact rather than reflowed.
- **Default version** - rules missing a `templateVersion` in the ARM template are given the value of `defaultVersion` (`1.0.0` by default).
- **Auto-format** - when `autoFormatAfterConversion` is on, each converted file is passed through the Toolkit's formatter (canonical field order, ISO 8601 duration correction, structure tidy) so it matches the repository style immediately.

Warnings never block the conversion. They surface in the summary dialog (when `showConversionSummary` is on) so you can address placeholders before committing.

## Conversion Settings

All conversion behaviour lives under the `sentinelAsCode.conversion.*` namespace. Set these in workspace or user settings.

| Setting | Default | Purpose |
|---------|---------|---------|
| `sentinelAsCode.conversion.enabled` | `true` | Enable ARM-to-YAML conversion and its menu entries |
| `sentinelAsCode.conversion.defaultNamingStrategy` | `"displayName"` | Default file-naming strategy: `original`, `displayName`, or `ruleId` |
| `sentinelAsCode.conversion.validateMitreOnConversion` | `true` | Validate and correct MITRE tactics and techniques during conversion |
| `sentinelAsCode.conversion.autoFormatAfterConversion` | `true` | Format converted files automatically after conversion |
| `sentinelAsCode.conversion.showConversionSummary` | `true` | Show a summary dialog with results and warnings |
| `sentinelAsCode.conversion.outputDirectory` | `""` | Output folder for converted files (empty = same directory as the source) |
| `sentinelAsCode.conversion.preserveQueryFormatting` | `true` | Preserve the original KQL query formatting |
| `sentinelAsCode.conversion.includeOptionalFields` | `true` | Include optional fields with default values |
| `sentinelAsCode.conversion.validateEntityMappings` | `true` | Warn about unrecognised entity types and incomplete field mappings |
| `sentinelAsCode.conversion.defaultVersion` | `"1.0.0"` | Version applied to rules missing `templateVersion` |

Example settings block:

```json
{
  "sentinelAsCode.conversion.defaultNamingStrategy": "displayName",
  "sentinelAsCode.conversion.outputDirectory": "Content/AnalyticalRules",
  "sentinelAsCode.conversion.autoFormatAfterConversion": true
}
```

## After Conversion

Converted files are ordinary analytics-rule YAML. Before committing:

1. Review each file against the [Analytical Rules](../Content/Analytical-Rules.md) contract, replacing any placeholder tactics or entity mappings that the summary flagged.
2. Confirm real-time validation shows no problems in the Problems panel (see [Schemas and Validation](Schemas-and-Validation.md)).
3. Move the files into the correct `Content/AnalyticalRules/<Source>/` folder if they were written elsewhere.

From there the rules follow the same path as any hand-authored content: the Sentinel-as-Code pipeline validates and deploys them.

## Related

- [Analytical Rules](../Content/Analytical-Rules.md) - the authoring contract for the YAML the conversion produces.
- [Templates](Templates.md) - starter templates for authoring rules from scratch.
- [Schemas and Validation](Schemas-and-Validation.md) - how the Toolkit validates the converted files.
