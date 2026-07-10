# Sentinel as Code Toolkit

The Sentinel as Code Toolkit is a VS Code extension for authoring Microsoft
Sentinel and Microsoft Defender XDR detection-as-code content. It turns the
editor into an authoring environment: real-time validation, IntelliSense,
formatting, starter templates, and ARM-to-YAML conversion for the same content
types this repository deploys.

The Toolkit is a separate project (repository
[`noodlemctwoodle/Sentinel-As-Code-Toolkit`](https://github.com/noodlemctwoodle/Sentinel-As-Code-Toolkit)),
but its schemas and templates are the authoring contract for the content in this
repository. These pages document what a user does with the extension.

| Concern | Where |
| --- | --- |
| Marketplace | [`noodlemctwoodle.sentinelcodeguard`](https://marketplace.visualstudio.com/items?itemName=noodlemctwoodle.sentinelcodeguard) |
| Display name | Sentinel as Code Toolkit |
| Publisher | `noodlemctwoodle` |
| Version | 26.7.1 |
| Requires | Visual Studio Code 1.125 or later |
| Feedback / issues | [Sentinel-As-Code issue tracker](https://github.com/noodlemctwoodle/Sentinel-As-Code/issues) |

## Author here, the pipeline deploys

The Toolkit **authors and validates** content; it does **not** deploy anything to
a tenant. There is no authentication to Azure or Microsoft Graph, no PUT to a
workspace, and no export from a live environment. Its job is to produce clean,
schema-correct files that are ready to commit to a Git-based Sentinel deployment.

Deployment is the job of the Sentinel-As-Code pipeline. The boundary is:

- **Toolkit (in the editor):** scaffold from templates, validate against the
  bundled schemas and MITRE ATT&CK data, format to canonical shape, decompile
  ARM into YAML, convert Defender detections between formats.
- **Pipeline (in CI/CD):** authenticate, validate at deploy time, and push the
  committed content into Microsoft Sentinel and Defender XDR. See
  [Pipelines](../Pipelines/README.md) and [Scripts](../Deploy/Scripts.md).

## Requirements

- Visual Studio Code 1.125 or later.
- Familiarity with the Microsoft Sentinel analytics rule schema (KQL and MITRE
  ATT&CK).

## Installation

- **From the Marketplace** - open the Extensions view, search for **Sentinel as
  Code Toolkit**, and install; or install directly from the
  [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=noodlemctwoodle.sentinelcodeguard)
  (extension id `noodlemctwoodle.sentinelcodeguard`).
- **From VSIX** - obtain the `.vsix`, open the Command Palette, and run
  **Extensions: Install from VSIX...**.

## Relationship to this repository

This repository is the deployment target the Toolkit is built for. The Toolkit's
schemas and templates define the authoring contract, and each content type this
repository deploys maps to a bundled schema and template:

| Content type | Repository folder | Toolkit schema |
| --- | --- | --- |
| Analytics rule | [`Content/AnalyticalRules/`](../../Content/AnalyticalRules) | `sentinel-analytics-rule-schema.json` |
| Hunting query | [`Content/HuntingQueries/`](../../Content/HuntingQueries) | `sentinel-hunting-query-schema.json` |
| Parser | [`Content/Parsers/`](../../Content/Parsers) | `sentinel-parser-schema.json` |
| Summary rule | [`Content/SummaryRules/`](../../Content/SummaryRules) | `sentinel-summary-rule-schema.json` |
| Automation rule | [`Content/AutomationRules/`](../../Content/AutomationRules) | `sentinel-automation-rule-schema.json` |
| Watchlist | [`Content/Watchlists/`](../../Content/Watchlists) | `sentinel-watchlist-schema.json` |
| Defender custom detection | [`Content/DefenderCustomDetections/`](../../Content/DefenderCustomDetections) | `defender-custom-detection-schema.json` |

When a content authoring doc in this repository disagrees with the Toolkit schema
or template, the Toolkit is the source of truth and the doc is corrected to
match. See the per-type docs under [Content authoring](../Content) and the
[schemas and validation](Schemas-and-Validation.md) reference.

## Language mode and file conventions

Rules are plain YAML, and the Toolkit auto-detects Sentinel content by shape, so
any `.yaml`/`.yml` file works with validation, IntelliSense, and formatting. No
special filename is required.

The dedicated `.sentinel.yaml` / `.sentinel.yml` extensions are an **opt-in**: a
file with one of these extensions is placed in the bundled `sentinel-rule`
language mode, which additionally enables the TextMate syntax highlighting,
snippets, and schema validation shipped with the Toolkit. Plain `.yaml`/`.yml`
files remain auto-detected by content and do not require the language mode.

## Feedback and issues

The Toolkit repository has GitHub Issues **disabled**. All Toolkit bug reports and
feature requests go to the Sentinel-As-Code repository issue tracker:

- **[github.com/noodlemctwoodle/Sentinel-As-Code/issues](https://github.com/noodlemctwoodle/Sentinel-As-Code/issues)**

## Licence

The extension is released under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
from the next release onward, matching this repository's relicence. Releases up to
and including `26.7.1` were published under the MIT License and remain available
under those terms.

## In this section

| Doc | What it covers |
| --- | --- |
| [Commands](Commands.md) | Every command the extension contributes, grouped by task, with palette titles and keybindings |
| [Templates](Templates.md) | The bundled starter templates, canonical field order, and which content types are authored as YAML and converted to JSON with **Convert Content YAML to JSON** |
| [Schemas and Validation](Schemas-and-Validation.md) | The seven bundled schemas, how validation is triggered, and MITRE ATT&CK multi-framework checking |
| [Configuration](Configuration.md) | Every `sentinelAsCode.*` setting, its default, and the custom-connectors file |
| [ARM to YAML Conversion](ARM-to-YAML-Conversion.md) | Decompiling `Microsoft.SecurityInsights/alertRules` ARM templates into clean analytics-rule YAML |
| [Defender Workflows](Defender-Workflows.md) | Formatting, validating, and converting Defender XDR custom detections for the repository |
| [Graph API Migrations](Graph-API-Migrations.md) | Upcoming Microsoft Graph `security` API deprecations that affect Defender custom detections, with the migration plan and removal date |
