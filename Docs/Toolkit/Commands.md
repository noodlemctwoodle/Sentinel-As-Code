# Toolkit Commands

The Sentinel as Code Toolkit contributes 26 commands to VS Code. Every command is a Command Palette entry, grouped under one of two categories: **Sentinel-As-Code** (Sentinel content) or **Defender-As-Code** (Microsoft Defender XDR custom detections). A handful also appear on right-click menus or carry a keyboard shortcut.

The Toolkit authors and validates content; it does not deploy. Scaffolding, formatting, conversion and validation all happen locally in your editor, and the [Sentinel-As-Code pipeline](../../README.md) does the deployment.

## How To Run A Command

- **Command Palette:** press `Ctrl+Shift+P` (or `Cmd+Shift+P` on macOS), then type the category or title, for example `Sentinel-As-Code: New Hunting Query`.
- **Editor context menu:** right-click inside an open file. Menu entries appear only for files the command applies to (a `.sentinel.yaml` rule, a `.csv`, an ARM `.json`, and so on).
- **Explorer context menu:** right-click a file or folder in the Explorer sidebar.
- **Keyboard shortcut:** where one exists, it is listed in the tables below.

Palette entries are shown with their category prefix, exactly as they read in the palette (for example `Sentinel-As-Code: Fix Field Order`).

## Command Groups At A Glance

| Group | Commands |
|-------|----------|
| [Rule and content authoring](#rule-and-content-authoring) | Create Sentinel Rule Template, Generate Rule Template, Generate Standard Rule Template, Generate NRT Rule Template, Generate New Rule ID, Generate New IDs for All Rules |
| [Content scaffolding](#content-scaffolding) | New Sentinel-as-Code Content, New Hunting Query, New Parser, New Summary Rule, New Automation Rule, Create Watchlist from CSV, Convert Content YAML to JSON, Populate Required Data Connectors from Query |
| [ARM conversion](#arm-conversion) | Decompile ARM to YAML |
| [Validation and formatting](#validation-and-formatting) | Fix Field Order, Format Sentinel Rule, Format Sentinel Content, Validate Rule, Validate as Sentinel Analytics Rule, Bulk Maintenance and Validation |
| [Defender custom detections](#defender-custom-detections) | Generate Custom Detection Template, Format Custom Detection for Repo, Convert Custom Detection YAML to JSON, Convert Custom Detection JSON to YAML, Validate as Custom Detection |

## Rule And Content Authoring

Commands for creating a new analytics rule and for managing rule IDs. See [Templates](Templates.md) for the field order and placeholder tokens these commands write, and [Analytical Rules](../Content/Analytical-Rules.md) for the authoring contract.

| Palette title | What it does | Keybinding | Menus |
|---------------|--------------|------------|-------|
| `Sentinel-As-Code: Create Sentinel Rule Template...` | Scaffolds a new analytics rule into a chosen folder. Prompts for the rule type (standard scheduled or NRT) and writes a commented template with a fresh `id`. | - | Explorer (right-click a folder). Not shown in the Command Palette. |
| `Sentinel-As-Code: Generate Rule Template` | Inserts a standard scheduled-rule template into the active editor. | - | Palette |
| `Sentinel-As-Code: Generate Standard Rule Template` | Produces the standard scheduled-rule template body. Surfaced through the Create Sentinel Rule Template flow rather than the palette. | - | Hidden from palette |
| `Sentinel-As-Code: Generate NRT Rule Template` | Produces the Near-Real-Time (NRT) rule template body. Surfaced through the Create Sentinel Rule Template flow rather than the palette. | - | Hidden from palette |
| `Sentinel-As-Code: Generate New Rule ID` | Replaces the `id` (GUID) of the rule in the active file with a newly generated one. Use this after copying an existing rule so the new file has a unique identifier. | - | Editor and Explorer (`.yaml`/`.yml`) |
| `Sentinel-As-Code: Generate New IDs for All Rules` | Regenerates the `id` for every rule across the workspace in one pass. Useful when forking a rule set. | - | Palette |

## Content Scaffolding

Commands for creating each non-analytics content type. Every content type is scaffolded as commented YAML, and the scaffolder asks where to save it rather than prompting for each field. Analytics rules, hunting queries and parsers deploy as that YAML, while summary rules, automation rules and watchlists are authored as YAML and then converted with **Convert Content YAML to JSON**, which writes the JSON the pipeline stores beside the source, keeping its base name (a summary or automation rule becomes `<name>.json`; a watchlist's `watchlist.yaml` becomes `watchlist.json`). See [Templates](Templates.md) for details.

| Palette title | What it does | Keybinding | Menus |
|---------------|--------------|------------|-------|
| `Sentinel-As-Code: New Sentinel-as-Code Content...` | Single entry point for scaffolding any content type. Pick a type, then choose where to save it. The two types with more than one source add a second step: Analytics Rule offers Standard, NRT or Decompile from an ARM template; Watchlist offers a blank template or one built from the active CSV/TSV. | - | Palette and Explorer (right-click a folder) |
| `Sentinel-As-Code: New Hunting Query` | Scaffolds a hunting-query YAML file from the template. See [Hunting Queries](../Content/Hunting-Queries.md). | - | Palette |
| `Sentinel-As-Code: New Parser` | Scaffolds a parser (KQL function) YAML file from the template. See [Parsers](../Content/Parsers.md). | - | Palette |
| `Sentinel-As-Code: New Summary Rule` | Scaffolds a summary rule as commented YAML. Author the field values, then run **Convert Content YAML to JSON** to produce the `.json` the pipeline stores. See [Summary Rules](../Content/Summary-Rules.md). | - | Palette |
| `Sentinel-As-Code: New Automation Rule` | Scaffolds an automation rule as commented YAML. Author the field values, then run **Convert Content YAML to JSON** to produce the `.json` the pipeline stores. See [Automation Rules](../Content/Automation-Rules.md). | - | Palette |
| `Sentinel-As-Code: Create Watchlist from CSV` | Turns a `.csv` or `.tsv` file into a watchlist under `Content/Watchlists/<alias>/`, writing a `watchlist.yaml` template plus the data file. Set `watchlistAlias` and `itemsSearchKey` in the YAML, then run **Convert Content YAML to JSON** to produce the `watchlist.json` the pipeline deploys. See [Watchlists](../Content/Watchlists.md). | - | Editor (`.csv`/`.tsv`) and Palette (with a `.csv`/`.tsv` open) |
| `Sentinel-As-Code: Convert Content YAML to JSON` | Converts an authored summary rule, automation rule or watchlist YAML into the JSON the pipeline stores, writing a `.json` beside the source with the same base name (a rule becomes `<name>.json`; a `watchlist.yaml` becomes `watchlist.json`). See [Templates](Templates.md). | - | Editor and Explorer (`.yaml`/`.yml`), and Palette |
| `Sentinel-As-Code: Populate Required Data Connectors from Query` | Reads the KQL tables referenced by the rule's query and fills in `requiredDataConnectors` from the bundled Content Hub mapping. Unknown `_CL` tables are registered into a workspace-local `.sentinel-connectors.json`. | - | Editor (`.yaml`/`.yml`) and Palette (with a `.yaml`/`.yml` open) |

## ARM Conversion

Decompiles exported Microsoft Sentinel ARM templates back into the Toolkit's YAML authoring format. See [ARM to YAML Conversion](ARM-to-YAML-Conversion.md) for naming strategies and the full conversion behaviour.

| Palette title | What it does | Keybinding | Menus |
|---------------|--------------|------------|-------|
| `Sentinel-As-Code: Decompile ARM to YAML` | Converts one or more `Microsoft.SecurityInsights/alertRules` resources from an ARM `.json` template into rule YAML. Applies the configured naming strategy, corrects MITRE tactics and techniques, validates entity mappings and (optionally) auto-formats the result. | - | Editor and Explorer (`.json`), and Palette. All three require `sentinelAsCode.conversion.enabled` (the default). |

## Validation And Formatting

Commands for keeping content well-formed: correct field order, canonical formatting, and on-demand validation against the bundled schemas. Real-time validation also runs automatically (on save, and optionally as you type); these commands let you trigger it manually. See [Schemas and Validation](Schemas-and-Validation.md).

| Palette title | What it does | Keybinding | Menus |
|---------------|--------------|------------|-------|
| `Sentinel-As-Code: Fix Field Order` | Reorders the fields of the active rule into the canonical order without otherwise reformatting. | `Ctrl+Shift+F` (`Cmd+Shift+F` on macOS), active only on `.sentinel.yaml`/`.sentinel.yml` files | Editor (`.sentinel.yaml`/`.yml`) and Palette (with a `.yaml` open) |
| `Sentinel-As-Code: Format Sentinel Rule` | Applies full canonical formatting to an analytics rule: field order, ISO 8601 duration correction and structure tidy-up. | See note below | Editor (`.sentinel.yaml`/`.yml`) and Palette (with a `.yaml` open) |
| `Sentinel-As-Code: Format Sentinel Content (Auto-detect)` | Formats any supported content type by auto-detecting whether the file is a rule, hunting query, parser, or JSON content, then applying the matching formatter. | See note below | Editor (`.yaml`/`.yml`/`.json`) and Palette (with one open) |
| `Sentinel-As-Code: Validate Rule (Auto-detect Type)` | Validates the active file against the schema for its detected type and reports problems in the Problems panel. | - | Palette |
| `Sentinel-As-Code: Validate as Sentinel Analytics Rule` | Forces validation against the analytics-rule schema, regardless of auto-detection. Useful when a file's type is ambiguous. | - | Palette |
| `Sentinel-As-Code: Bulk Maintenance & Validation` | Runs validation and maintenance across the whole workspace in one pass (bulk field-order fixes, ID checks and validation). | - | Palette |

**Format Document note:** the Toolkit registers a document formatter for Sentinel content folders (`AnalyticalRules/`, `HuntingQueries/`, `Parsers/`, `SummaryRules/`, `AutomationRules/`, `Watchlists/`, `Workbooks/`, `Playbooks/`) and for any `.sentinel.yaml`/`.sentinel.yml` file. Because of this, VS Code's built-in **Format Document** command (`Shift+Alt+F`, or `Shift+Option+F` on macOS) runs the same auto-detecting formatter as `Format Sentinel Content`. Only `Fix Field Order` has a dedicated Toolkit keybinding; the format commands rely on the built-in Format Document shortcut and their palette entries.

## Defender Custom Detections

Commands for authoring Microsoft Defender XDR custom detections and moving them between the repo YAML format and the deployable Graph JSON format. These appear under the **Defender-As-Code** category. See [Defender Workflows](Defender-Workflows.md) and [Defender Custom Detections](../Content/Defender-Custom-Detections.md).

| Palette title | What it does | Keybinding | Menus |
|---------------|--------------|------------|-------|
| `Defender-As-Code: Generate Custom Detection Template` | Scaffolds a new custom-detection YAML file from the template. | - | Palette |
| `Defender-As-Code: Format Custom Detection for Repo` | Takes a detection exported from the Defender portal and reshapes it into the repo's canonical YAML (field order and structure). | - | Palette |
| `Defender-As-Code: Convert Custom Detection YAML to JSON` | Converts a repo detection YAML into the deployable Graph `detectionRules` JSON, dropping runtime and read-only fields on the way out. | - | Palette |
| `Defender-As-Code: Convert Custom Detection JSON to YAML` | Converts a Graph detection JSON back into the repo YAML authoring format. | - | Palette |
| `Defender-As-Code: Validate as Custom Detection` | Validates the active file against the Defender custom-detection schema and flags runtime or read-only fields that should not be authored by hand. | - | Palette |

## Context Menu Reference

For quick reference, the commands that appear on right-click menus and the file types they apply to:

| Command | Editor context menu | Explorer context menu |
|---------|---------------------|-----------------------|
| Fix Field Order | `.sentinel.yaml` / `.sentinel.yml` | - |
| Format Sentinel Rule | `.sentinel.yaml` / `.sentinel.yml` | - |
| Format Sentinel Content (Auto-detect) | `.yaml` / `.yml` / `.json` | - |
| Generate New Rule ID | `.yaml` / `.yml` | `.yaml` / `.yml` |
| Decompile ARM to YAML | `.json` (conversion enabled) | `.json` (conversion enabled) |
| Create Watchlist from CSV | `.csv` / `.tsv` | - |
| Populate Required Data Connectors from Query | `.yaml` / `.yml` | - |
| Convert Content YAML to JSON | `.yaml` / `.yml` | `.yaml` / `.yml` |
| New Sentinel-as-Code Content... | - | Folders |
| Create Sentinel Rule Template... | - | Folders |

## Related Documentation

- [Templates](Templates.md) - the field order and placeholder tokens the scaffolding commands write.
- [Schemas and Validation](Schemas-and-Validation.md) - what the validate and format commands check against.
- [ARM to YAML Conversion](ARM-to-YAML-Conversion.md) - full behaviour of Decompile ARM to YAML.
- [Defender Workflows](Defender-Workflows.md) - the end-to-end Defender authoring and conversion flow.
- [Configuration](Configuration.md) - the `sentinelAsCode.*` settings that change how these commands behave.
