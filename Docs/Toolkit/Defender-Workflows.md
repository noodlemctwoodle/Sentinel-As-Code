# Defender XDR Workflows

The Sentinel as Code Toolkit (VS Code extension) gives you a set of commands for
working with Microsoft Defender XDR custom detections as repository content. It
**formats, validates, and converts** detection files in the editor. It does
**not** authenticate to a Defender tenant and it does **not** deploy anything.
Deployment is the Sentinel-as-Code pipeline's job (see
[Defender Custom Detection Rules](../Content/Defender-Custom-Detections.md)).

The split is deliberate: you shape and check detection files locally with the
Toolkit, commit repository-ready YAML, and let the CI/CD pipeline acquire a
Graph token and push the rules to Defender XDR.

## What the Toolkit does (and does not do)

| The Toolkit does | The Toolkit does not |
|------------------|----------------------|
| Format a portal export into repository-ready YAML | Sign in to a Defender tenant |
| Validate a detection against the authoring schema | Read or list rules from Graph |
| Convert repo YAML to deployable Graph JSON, and back | Create, update, or delete rules |
| Suggest a PascalCase filename and target folder | Deploy anything |

Everything the Toolkit produces is a file on disk. Nothing leaves the editor.

## The Defender commands

Run these from the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`). Every
Defender command title carries the `Defender-As-Code:` prefix.

| Command | What it does |
|---------|--------------|
| Defender-As-Code: Format Custom Detection for Repo | Turn a portal JSON export (or a Graph response, or YAML) in the active editor into a repository-ready YAML file, and suggest a PascalCase filename for `Content/DefenderCustomDetections/`. |
| Defender-As-Code: Validate as Custom Detection | Validate the active file against the repository authoring schema, flagging missing required fields, bad enums, malformed MITRE technique IDs, and runtime/read-only fields that should not be committed. |
| Defender-As-Code: Convert Custom Detection YAML to JSON | Reshape repository YAML into a deployable Microsoft Graph `detectionRule` JSON body. |
| Defender-As-Code: Convert Custom Detection JSON to YAML | Reshape a Graph `detectionRule` JSON export into clean repository YAML. |
| Defender-As-Code: Generate Custom Detection Template | Scaffold a fresh detection YAML from the bundled template (see [Templates](Templates.md)). |

The first four are covered below. For scaffolding a new rule from scratch, see
[Templates](Templates.md).

## Format Custom Detection for Repo

Use this when you have built and tested a rule in the Defender portal and want to
bring it into the repository.

1. Open a Defender XDR custom detection export in the editor. This can be a
   portal JSON export, a raw Graph `detectionRule` response, or an existing YAML
   file.
2. Run **Defender-As-Code: Format Custom Detection for Repo**.
3. The Toolkit rewrites the content as YAML in the clean authoring schema,
   dropping the portal and Graph runtime/read-only fields that must not be
   committed (for example server-assigned identifiers and last-run metadata).
4. Save the result under [`Content/DefenderCustomDetections/`](../../Content/DefenderCustomDetections)
   using the suggested PascalCase filename.

The output uses the canonical field order (see
[Schemas and Validation](Schemas-and-Validation.md)) so the file is ready to
validate and commit without further tidying.

## Validate as Custom Detection

Validate the active file against the bundled `defender-custom-detection-schema.json`,
the authoring contract described in
[Defender Custom Detection Rules](../Content/Defender-Custom-Detections.md).

Run **Defender-As-Code: Validate as Custom Detection** and read the findings in
the Problems panel. The validator checks:

| Check | Rule |
|-------|------|
| Required fields present | `displayName`, `queryCondition.queryText`, `schedule.period`, and `detectionAction.alertTemplate` with `title`, `severity`, `category`, `mitreTechniques` |
| Severity enum | one of `informational`, `low`, `medium`, `high` (lowercase) |
| Schedule enum | one of `0` (NRT), `1H`, `3H`, `12H`, `24H` |
| MITRE technique format | each entry matches `^T[0-9]{4}(\.[0-9]{3})?$` (for example `T1059` or `T1059.001`) |
| Impacted asset shape | each entry has `@odata.type` (one of the three impacted-asset types) and `identifier`, and nothing else |
| Response action shape | each entry has a valid `@odata.type` and `identifier`, with only `isolationType` or `deviceGroupNames` as extras |
| No stray fields | the schema is closed (`additionalProperties: false`), so any runtime/read-only field carried over from a portal export is flagged |

The last check is the important one when you paste a portal or Graph export
directly: those payloads carry runtime and read-only properties that are not
part of the authoring schema, and the validator surfaces every one so you can
strip it (or run **Format Custom Detection for Repo**, which strips them for
you).

> **Authoring vs deploy:** the Toolkit schema requires `mitreTechniques`, but
> the deploy script does not enforce it. Author to the schema and always include
> `mitreTechniques` so validation passes. See the deploy-time notes in
> [Defender Custom Detection Rules](../Content/Defender-Custom-Detections.md#yaml-schema).

## Convert YAML to JSON

**Defender-As-Code: Convert Custom Detection YAML to JSON** reshapes a
repository YAML detection into the deployable Microsoft Graph `detectionRule`
JSON body, the same shape the Graph Security API accepts on a POST or PATCH.

The conversion keeps the authoring fields (`displayName`, `isEnabled`,
`queryCondition`, `schedule`, `detectionAction`) and drops any runtime/read-only
fields, so the JSON it emits is a clean request body. You do not normally commit
this JSON: the repository stores Defender detections as YAML, and the pipeline
performs its own conversion at deploy time. Use this command to inspect exactly
what would be sent to Graph, or to hand a payload to another tool.

## Convert JSON to YAML

**Defender-As-Code: Convert Custom Detection JSON to YAML** is the reverse: it
takes a Graph `detectionRule` JSON export and produces clean repository YAML in
the authoring schema, dropping runtime/read-only fields and applying the
canonical field order. The YAML/JSON pair round-trips cleanly.

This overlaps with **Format Custom Detection for Repo**; the practical
difference is intent. Reach for **Convert JSON to YAML** when your starting point
is specifically a Graph `detectionRule` JSON body, and for **Format Custom
Detection for Repo** when you have any portal export and want the suggested
filename and target folder as well.

## Where the files live

Formatted and scaffolded detections belong under
[`Content/DefenderCustomDetections/`](../../Content/DefenderCustomDetections),
one YAML file per rule, optionally organised into category subfolders. The
`displayName` must be unique across the whole tree, because the pipeline upserts
rules by `displayName`. The folder layout, schema, response-action catalogue, and
deployment behaviour are all documented in
[Defender Custom Detection Rules](../Content/Defender-Custom-Detections.md).

## Related

- [Defender Custom Detection Rules](../Content/Defender-Custom-Detections.md) - the full authoring contract, field reference, and deployment behaviour.
- [Templates](Templates.md) - scaffolding a new detection with **Generate Custom Detection Template**.
- [Schemas and Validation](Schemas-and-Validation.md) - how the bundled schemas drive validation and the canonical field order.
