# Configuration

Every setting the Sentinel as Code Toolkit contributes lives under the
`sentinelAsCode.*` namespace. This page lists all 25 settings, grouped by the
feature they control, with each default and its effect, and documents how to
register custom data connectors so that unknown tables (including `_CL` custom
logs) are recognised by validation and by the **Populate Required Data
Connectors from Query** command.

The Toolkit authors and validates content in the editor; it does not deploy.
Deployment is this repository's pipeline. See the content authoring contract in
[Toolkit templates](Templates.md) and
[schemas and validation](Schemas-and-Validation.md).

## Where settings live

Toolkit settings are ordinary VS Code settings. You can change them two ways:

- **Settings UI** - open **Settings** (`Ctrl/Cmd+,`), search for `Sentinel as
  Code`, and edit the fields.
- **`settings.json`** - edit the JSON directly. User settings apply everywhere;
  workspace settings (`.vscode/settings.json` committed to the repository) apply
  to everyone who opens the repo and are the recommended place to pin
  team-wide behaviour.

All keys below are shown without the `sentinelAsCode.` prefix in the tables, but
you must include it in `settings.json` (for example
`sentinelAsCode.validation.onType`).

## Validation and formatting

Controls real-time validation, on-save behaviour, formatting, canonical field
ordering, and editor IntelliSense.

| Setting | Type | Default | Effect |
| --- | --- | --- | --- |
| `validation.enabled` | boolean | `true` | Enable automatic validation of Sentinel rules. When off, no diagnostics are produced. |
| `validation.onSave` | boolean | `true` | Validate a rule automatically when the file is saved. |
| `validation.onType` | boolean | `false` | Validate as you type. Off by default because it can impact performance on large files. |
| `validation.excludePatterns` | array of strings | `[]` | Glob patterns for files to exclude from validation. Matching files show no diagnostics. Supports `*`, `**`, `?`, and `{a,b}` alternation (for example `**/test/**`, `**/*.draft.yaml`, `**/.archive/**`). |
| `formatting.enabled` | boolean | `true` | Enable automatic formatting of Sentinel rules (canonical field order, ISO 8601 duration correction, structure tidy). |
| `fieldOrdering.enforceOrder` | boolean | `true` | Enforce the canonical field order for the detected rule type. |
| `fieldOrdering.showOrderHints` | boolean | `true` | Show field-ordering hints in diagnostics when fields are out of order. |
| `intellisense.enabled` | boolean | `true` | Enable IntelliSense for rule fields (field completion, tactics, techniques, connectors, enums, and hover help). |

Templates carry `{{PLACEHOLDER}}` tokens and are always skipped by validation,
regardless of `validation.excludePatterns`.

## MITRE ATT&CK

Controls which ATT&CK data the Toolkit loads and how strictly it validates the
`tactics` and `relevantTechniques` fields.

| Setting | Type | Default | Effect |
| --- | --- | --- | --- |
| `mitre.version` | string enum (`v16`, `v15`, `v14`) | `v16` | ATT&CK framework version used for validation. |
| `mitre.frameworks` | array enum (`enterprise`, `mobile`, `ics`) | `["enterprise", "mobile", "ics"]` | Which ATT&CK matrices to load and validate against. |
| `mitre.allowUnknownTactics` | boolean | `true` | Allow tactics not found in the loaded ATT&CK data. Shows an information message only rather than an error. |
| `mitre.allowUnknownTechniques` | boolean | `true` | Allow techniques not found in the loaded ATT&CK data. Shows an information message only rather than an error. |
| `mitre.strictValidation` | boolean | `false` | Require every tactic and technique to be present in the loaded ATT&CK data. When on, unknown items are reported as errors. This overrides the two `allowUnknown` settings. |

## Data connectors

Controls how the Toolkit validates the `connectorId` values in a rule's
`requiredDataConnectors`. See [Custom connectors](#custom-connectors) below for
the workspace connector file and how these settings interact with it.

| Setting | Type | Default | Effect |
| --- | --- | --- | --- |
| `connectors.validationMode` | string enum (`strict`, `workspace`, `permissive`) | `permissive` | How strictly connector IDs are validated. `strict` allows only connectors from the bundled catalogue; `workspace` also allows connectors defined in the workspace `.sentinel-connectors.json`; `permissive` allows any valid connector ID format (recommended). |
| `connectors.customConnectors` | array of strings | `[]` | Additional connector IDs to treat as known, listed inline in settings. Useful for a handful of custom IDs without maintaining a connector file. |

## ARM to YAML conversion

Controls the **Convert ARM to YAML** decompile of
`Microsoft.SecurityInsights/alertRules` and how the resulting YAML is named,
formatted, and validated.

| Setting | Type | Default | Effect |
| --- | --- | --- | --- |
| `conversion.enabled` | boolean | `true` | Enable ARM template to YAML conversion. |
| `conversion.defaultNamingStrategy` | string enum (`original`, `displayName`, `ruleId`) | `displayName` | How converted files are named: `original` keeps the source filename with a `.yaml` extension; `displayName` uses the rule's `displayName`; `ruleId` uses the rule's unique identifier. |
| `conversion.validateMitreOnConversion` | boolean | `true` | Validate and correct ATT&CK tactics and techniques during conversion. |
| `conversion.autoFormatAfterConversion` | boolean | `true` | Automatically format converted YAML using the Toolkit's formatter. |
| `conversion.showConversionSummary` | boolean | `true` | Show a summary dialog with warnings and results after conversion. |
| `conversion.outputDirectory` | string | `""` | Custom output directory for converted files. Empty means write next to the source file. |
| `conversion.preserveQueryFormatting` | boolean | `true` | Preserve the original KQL query formatting in the converted YAML. |
| `conversion.includeOptionalFields` | boolean | `true` | Include optional fields with default values in the converted YAML. |
| `conversion.validateEntityMappings` | boolean | `true` | Validate entity types and identifiers during conversion. |
| `conversion.defaultVersion` | string | `"1.0.0"` | Default version applied to rules that have no `templateVersion` in the ARM template. |

## Custom connectors

Analytics rules declare the connectors they depend on in
`requiredDataConnectors`. The Toolkit ships a Content Hub connector catalogue
(631 connectors covering 744 tables) that maps Log Analytics tables to the
connector that provides them. When your workspace uses connectors or tables the
catalogue does not know about (a private or codeless connector, or a custom
`_CL` log table), you register them so that validation and the
**Populate Required Data Connectors from Query** command recognise them.

There are two mechanisms, and you can use either or both:

1. **`connectors.customConnectors` setting** - a flat list of connector IDs to
   treat as known. Best for a small number of IDs you just want validation to
   accept. These carry no table mappings, so they do not help the Populate
   command match a query's tables.
2. **A workspace `.sentinel-connectors.json` file** - a JSON catalogue at the
   workspace root, in the same shape as the bundled connector data. It maps
   connector IDs to the tables they provide, so both validation and the Populate
   command can match tables to connectors. This is the richer option and is what
   the Populate command writes to when you register a custom table inline.

### How `validationMode` interacts

- `strict` - only IDs in the bundled catalogue are accepted. Custom IDs from
  either mechanism above are still needed for the Populate command to match, but
  strict mode reports any unknown ID as invalid.
- `workspace` - IDs from the bundled catalogue and from
  `.sentinel-connectors.json` are accepted.
- `permissive` (default) - any well-formed connector ID is accepted, so
  validation never flags an unknown ID. You still benefit from registering
  custom tables because the Populate command uses the table-to-connector mapping
  to fill `requiredDataConnectors` automatically.

### The `.sentinel-connectors.json` shape

The file lives at the root of your workspace folder. It has a top-level list of
connectors, each with the tables it provides. The list key may be either
`connectors` or `tablesByConnector` (both are read; a new file created by the
Toolkit uses `connectors`). Each entry uses these fields:

```json
{
  "connectors": [
    {
      "connectorId": "AcmePlatform",
      "connectorTitle": "Acme Platform",
      "descriptionMarkdown": "In-house Acme security telemetry.",
      "publisher": "Custom",
      "source": "",
      "tables": [
        "AcmeAudit_CL",
        "AcmeSignIn_CL"
      ]
    }
  ]
}
```

Field notes:

- `connectorId` (required) - the ID written into a rule's
  `requiredDataConnectors`. Legacy files may use `id` instead; both are read.
- `connectorTitle` - a human-readable name shown in pickers. Legacy `name` or
  `displayName` are also read.
- `tables` - the list of Log Analytics tables the connector provides. A single
  table may be a bare string; legacy files may use `dataTypes` instead.
- `descriptionMarkdown`, `publisher`, `source` - optional metadata. When the
  Toolkit creates or extends the file it fills these with sensible defaults
  (`publisher: "Custom"`, empty description and source) so every field is present
  and editable.

### How Populate Required Data Connectors reads and writes it

The **Sentinel-As-Code: Populate Required Data Connectors from Query** command
(available from the Command Palette on an open analytics rule) reads the rule's
`query`, extracts the Log Analytics tables, and fills
`requiredDataConnectors`:

1. For each table that the bundled catalogue and any registered custom
   connectors recognise, the command resolves the connector. When a table is
   provided by more than one connector, it prompts you to choose which one to
   require (the best match is suggested first).
2. For each unknown custom table (typically a `_CL` table), it offers to
   register it: **Add as "<name>"** (using the table name with the `_CL` suffix
   removed as the connector ID), **Add with a different connector id**, or
   **Skip**. Choosing to add writes the table under that connector ID into
   `.sentinel-connectors.json` at the workspace root, creating or merging the
   file. Tables are kept sorted and de-duplicated within each connector entry.
3. The command then writes the resolved connectors into
   `requiredDataConnectors`, reorders the rule to canonical field order, and
   saves the edit. Registered custom tables are reloaded so they are recognised
   for the rest of the session.

If no workspace folder is open, the command cannot save
`.sentinel-connectors.json`; it still adds the table to the current rule and
warns you.

This is how `_CL` tables get registered inline: you never have to hand-write the
connector file first. Run the command, choose **Add** for each unknown table,
and the Toolkit creates the entry for you. You can then open
`.sentinel-connectors.json` and refine the title, description, or publisher.

## Sample `settings.json`

A workspace `.vscode/settings.json` that keeps the defaults but tightens a few
things (validate on type, enforce known connectors from the workspace file, and
list two custom connector IDs inline):

```json
{
  "sentinelAsCode.validation.enabled": true,
  "sentinelAsCode.validation.onSave": true,
  "sentinelAsCode.validation.onType": true,
  "sentinelAsCode.validation.excludePatterns": [
    "**/.archive/**",
    "**/*.draft.yaml"
  ],
  "sentinelAsCode.formatting.enabled": true,
  "sentinelAsCode.fieldOrdering.enforceOrder": true,
  "sentinelAsCode.fieldOrdering.showOrderHints": true,
  "sentinelAsCode.intellisense.enabled": true,
  "sentinelAsCode.mitre.version": "v16",
  "sentinelAsCode.mitre.frameworks": ["enterprise", "mobile", "ics"],
  "sentinelAsCode.mitre.strictValidation": false,
  "sentinelAsCode.connectors.validationMode": "workspace",
  "sentinelAsCode.connectors.customConnectors": [
    "AcmePlatform",
    "AcmeEdge"
  ],
  "sentinelAsCode.conversion.enabled": true,
  "sentinelAsCode.conversion.defaultNamingStrategy": "displayName",
  "sentinelAsCode.conversion.autoFormatAfterConversion": true
}
```

## Related

- [Toolkit templates](Templates.md) - the scaffolds each content type is
  authored from.
- [Schemas and validation](Schemas-and-Validation.md) - the bundled schemas and
  how validation binds to repository folders.
- [Analytical Rules](../Content/Analytical-Rules.md) - the content type whose
  `requiredDataConnectors` the connector settings and file support.
