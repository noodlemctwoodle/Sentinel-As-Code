# Schemas and Validation

The Sentinel as Code Toolkit ships seven JSON schemas that define the authoring
contract for every content type in this repository. The extension binds each
schema to the folder where that content lives, then validates your files in real
time as you edit them. Problems appear in the VS Code Problems panel, fields
auto-complete as you type, and MITRE ATT&CK tactics and techniques are checked
against the framework data bundled with the extension.

These schemas are the source of truth for the field-level authoring contracts
documented under [`Docs/Content/`](../Content). Where a content doc describes a
field, its type, whether it is required, its allowed values or its position in
the canonical order, that description comes from the schema on this page. The
Toolkit authors and validates content; it does not deploy it. Deployment is this
repository's pipeline
([`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1)).

For how to install the extension and scaffold content from templates, see
[Templates](Templates.md).

## The seven bundled schemas

Each schema maps one-to-one to a content type, a repository folder and an
authoring doc. All seven are JSON Schema draft-07 files under the extension's
`schemas/` directory.

| Schema file | Content type | Repository folder | Authoring doc |
| --- | --- | --- | --- |
| `sentinel-analytics-rule-schema.json` | Analytics rules (Scheduled, NRT) | [`Content/AnalyticalRules/`](../../Content/AnalyticalRules) | [Analytical Rules](../Content/Analytical-Rules.md) |
| `sentinel-hunting-query-schema.json` | Hunting queries | [`Content/HuntingQueries/`](../../Content/HuntingQueries) | [Hunting Queries](../Content/Hunting-Queries.md) |
| `sentinel-automation-rule-schema.json` | Automation rules | [`Content/AutomationRules/`](../../Content/AutomationRules) | [Automation Rules](../Content/Automation-Rules.md) |
| `sentinel-parser-schema.json` | Parsers (saved KQL functions) | [`Content/Parsers/`](../../Content/Parsers) | [Parsers](../Content/Parsers.md) |
| `sentinel-summary-rule-schema.json` | Summary rules | [`Content/SummaryRules/`](../../Content/SummaryRules) | [Summary Rules](../Content/Summary-Rules.md) |
| `sentinel-watchlist-schema.json` | Watchlist metadata (`watchlist.json`) | [`Content/Watchlists/`](../../Content/Watchlists) | [Watchlists](../Content/Watchlists.md) |
| `defender-custom-detection-schema.json` | Defender XDR custom detections | [`Content/DefenderCustomDetections/`](../../Content/DefenderCustomDetections) | [Defender Custom Detections](../Content/Defender-Custom-Detections.md) |

Analytics rules, hunting queries, parsers and Defender detections are authored as
YAML. Summary rules, automation rules and watchlists are stored as JSON on disk,
and the Toolkit authors them as commented YAML, then converts them to JSON with its
Convert Content YAML to JSON command (see
[Templates](Templates.md)). The schema for each type validates the on-disk
format shown above.

## How schemas bind to folders

The extension registers each schema against a set of file-path globs through the
`contributes.jsonValidation` contribution in its manifest. When you open or save
a file whose path matches one of these globs, VS Code applies the bound schema
automatically. No per-workspace configuration is needed.

| Schema | File-path globs |
| --- | --- |
| `sentinel-analytics-rule-schema.json` | `*.sentinel.yaml`, `*.sentinel.yml`, `**/AnalyticalRules/**/*.yaml` |
| `sentinel-hunting-query-schema.json` | `**/HuntingQueries/**/*.yaml`, `**/HuntingQueries/**/*.yml` |
| `sentinel-parser-schema.json` | `**/Parsers/**/*.yaml`, `**/Parsers/**/*.yml` |
| `sentinel-summary-rule-schema.json` | `**/SummaryRules/**/*.json` |
| `sentinel-automation-rule-schema.json` | `**/AutomationRules/**/*.json` |
| `sentinel-watchlist-schema.json` | `**/Watchlists/**/watchlist.json` |
| `defender-custom-detection-schema.json` | `**/DefenderCustomDetections/**/*.yaml`, `**/DefenderCustomDetections/**/*.yml` |

Two things follow from this table:

- A file placed in the matching folder is validated against the correct schema
  wherever the repository is cloned, because the globs match on path, not on an
  absolute location.
- Any file named `*.sentinel.yaml` or `*.sentinel.yml` is validated as an
  analytics rule regardless of folder. Those extensions also opt the file into
  the `sentinel-rule` language mode, which adds syntax highlighting and snippets
  on top of schema validation. Plain `.yaml` and `.yml` files are still
  recognised by their folder and content.

## What each schema enforces

The schemas validate structure, not deployment behaviour. In broad terms each
one checks:

- **Required fields** are present. For example, an analytics rule requires `id`,
  `name`, `description`, `severity`, `requiredDataConnectors`, `tactics`,
  `query`, `version` and `kind`; a Scheduled rule additionally requires
  `queryFrequency`, `queryPeriod`, `triggerOperator` and `triggerThreshold`.
- **Types and enumerations** are correct. Severity must be one of
  `Informational`, `Low`, `Medium`, `High`; `kind` must be `Scheduled` or `NRT`;
  a summary rule `binSize` must be one of the allowed minute values.
- **Patterns** match. GUID fields must be valid GUIDs, ISO 8601 durations must
  match the `PT5M` / `P1D` shape, MITRE technique IDs must match `T####` or
  `T####.###`, and a summary rule `destinationTable` must end in `_CL`.
- **Unknown fields** are rejected. Six of the seven schemas set
  `additionalProperties: false`, so a mistyped or unsupported field is flagged as
  an error. The parser schema is the exception: it permits additional properties.

Field-by-field detail for each type lives in the authoring doc linked in the
table above. Do not duplicate it here; the schema and the content doc are kept in
step.

## Real-time validation

Validation runs inside the editor and reports through the standard VS Code
Problems panel. Each finding is anchored to the offending line so you can jump
straight to it.

- **On save.** Files are validated when you save them. Controlled by
  `sentinelAsCode.validation.onSave` (default `true`).
- **On type.** Optional live validation as you edit. Controlled by
  `sentinelAsCode.validation.onType` (default `false`, because continuous
  validation can affect performance on large files).
- **Master switch.** `sentinelAsCode.validation.enabled` (default `true`) turns
  all validation on or off.

### Rule-type-aware detection

The Toolkit works out which rule type a file is, and therefore which rules to
apply, from both its folder and its content. Folder location selects the bound
JSON schema (see the binding table). On top of that, the extension inspects the
file's fields so that any `.yaml` file that resembles a rule is recognised even
before it is filed into the canonical folder. This means a draft analytics rule
is validated as an analytics rule, a hunting query as a hunting query, and so on,
rather than everything being checked against a single generic schema.

## IntelliSense and hover

When `sentinelAsCode.intellisense.enabled` is `true` (the default), the editor
offers completion and hover help driven by the same schemas and reference data:

- **Field completion** for the fields valid on the current rule type, with the
  required and optional fields surfaced as you type.
- **Value completion** for enumerated fields (for example severity, `kind`,
  trigger operators), MITRE tactics and techniques, and known data-connector
  IDs.
- **Hover** shows the schema description for the field or value under the cursor,
  so you can read what a field means without leaving the editor.

## MITRE ATT&CK validation

Tactics and techniques are validated against MITRE ATT&CK data bundled with the
extension. The Toolkit supports three ATT&CK frameworks and a selectable version
line.

- **Frameworks.** `sentinelAsCode.mitre.frameworks` selects which framework data
  to load and validate against. The default loads all three: `enterprise`,
  `mobile` and `ics`. The mobile and ICS matrices ship as
  `data/mitre-mobile.json` and `data/mitre-ics.json`.
- **Version.** `sentinelAsCode.mitre.version` selects the ATT&CK version, one of
  `v16` (default), `v15` or `v14`. The bundled enterprise dataset is
  `data/mitre-v16.json`.
- **Strictness.** By default the Toolkit is permissive so that newer tactics and
  techniques are not blocked before the bundled data catches up:
  - `sentinelAsCode.mitre.allowUnknownTactics` (default `true`) and
    `sentinelAsCode.mitre.allowUnknownTechniques` (default `true`) report an
    unknown tactic or technique as an information message rather than an error.
  - `sentinelAsCode.mitre.strictValidation` (default `false`), when enabled,
    requires every tactic and technique to exist in the loaded MITRE data and
    reports anything else as an error.

Note that the JSON schemas still enforce the *shape* of these fields
independently of the MITRE data: technique IDs must match the `T####` /
`T####.###` pattern and tactic names the expected casing, regardless of the
strictness settings above.

## Exclude patterns

To stop validation running against files that are not finished content (drafts,
archives, test fixtures), set glob patterns in
`sentinelAsCode.validation.excludePatterns` (default `[]`, meaning nothing is
excluded). Matching files show no diagnostics.

The patterns support:

| Token | Meaning |
| --- | --- |
| `*` | Any run of characters within a single path segment |
| `**` | Any number of path segments |
| `?` | A single character |
| `{a,b}` | Alternation (matches `a` or `b`) |

Matching is case-insensitive on Windows. Example configuration:

```json
{
  "sentinelAsCode.validation.excludePatterns": [
    "**/test/**",
    "**/*.draft.yaml",
    "**/.archive/**"
  ]
}
```

## Templates are skipped automatically

Files scaffolded from the bundled templates carry `{{PLACEHOLDER}}` tokens (for
example `id: {{GUID}}`) that are not yet valid values. The Toolkit skips these
template files automatically, so an unfilled placeholder does not raise a wall of
errors before you have finished authoring. Once you replace the placeholders with
real values, normal validation applies.

## Settings reference

All settings live under the `sentinelAsCode.*` namespace in VS Code settings.

| Setting | Default | Purpose |
| --- | --- | --- |
| `validation.enabled` | `true` | Master switch for all validation. |
| `validation.onSave` | `true` | Validate on save. |
| `validation.onType` | `false` | Validate as you type. |
| `validation.excludePatterns` | `[]` | Globs for files to skip. |
| `intellisense.enabled` | `true` | Field, value and hover assistance. |
| `mitre.frameworks` | `["enterprise","mobile","ics"]` | ATT&CK matrices to load. |
| `mitre.version` | `"v16"` | ATT&CK version (`v16` / `v15` / `v14`). |
| `mitre.allowUnknownTactics` | `true` | Unknown tactic is info, not error. |
| `mitre.allowUnknownTechniques` | `true` | Unknown technique is info, not error. |
| `mitre.strictValidation` | `false` | Require all tactics/techniques to be known. |
| `connectors.validationMode` | `"permissive"` | How strictly connector IDs are checked (`strict` / `workspace` / `permissive`). |
| `connectors.customConnectors` | `[]` | Extra connector IDs treated as known. |

Formatting, field-ordering and conversion settings are covered in
[Templates](Templates.md), which is where the scaffolding and formatting commands
are documented.

## Source of truth

When a content authoring doc and its schema disagree, the schema wins and the doc
is corrected to match it. If you are unsure whether a field is required, what
values it accepts or where it sits in the canonical order, open the schema for
that content type or read the authoring doc it backs. The two are maintained
together.

Where the deploy pipeline genuinely diverges from a schema (for example a field
the schema allows that the deploy step ignores), the relevant content doc records
that as an explicit deploy-time note rather than hiding the mismatch.
