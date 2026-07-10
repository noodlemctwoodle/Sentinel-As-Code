# Community Rules

Community-contributed analytics rules live under
[`Content/AnalyticalRules/Community/`](../../Content/AnalyticalRules/Community), organised by
contributor. They follow the same YAML schema as in-house Custom rules
(see [Analytical Rules](Analytical-Rules.md)) but ship with deliberately
restrictive deployment defaults so manual review precedes any production
enablement.

## Deployment behaviour

| Property | Default | Why |
| --- | --- | --- |
| **Opt-in** | Skipped unless explicitly included | Both CI systems exclude community rules by default. The GitHub `sentinel-deploy.yml` workflow input `skip_custom_content_types` defaults to `community-detections`; the Azure DevOps `Sentinel-Deploy.yml` parameter `skipCommunityDetections` defaults to `true`. Clear the exclusion on a manual run to include them |
| **Disabled at deploy time** | `enabled: false` regardless of the YAML's `enabled` field | `Deploy-CustomContent.ps1` matches any file whose path contains a `Community` segment (`$isCommunityRule`) and force-sets `$ruleEnabled = $false` before the PUT, so community rules always deploy disabled. Reviewers enable individual rules in the Sentinel portal after deployment |
| **Drift detection** | Same as Custom rules | If someone enables a community rule and edits its KQL in the portal, the daily drift detector picks it up and PRs the change back to the YAML |

This combination (opt-in at deploy time, disabled by default once
deployed) means community contributions ship as inert content until a
human turns them on.

The two controls are independent. `SkipCommunityDetections` decides
whether community files are collected into the deploy run at all; the
`$isCommunityRule` force-disable applies to any community file that *is*
deployed, no matter what its own `enabled:` value says. The importer
already writes every rule with `enabled: false`, so the deployer's
force-disable is a second, path-based safety net rather than the only
guard.

## Folder structure

```
Content/AnalyticalRules/Community/
└── {ContributorName}/
    └── {Category}/
        └── {RuleName}.yaml
```

Each contributor maintains their own top-level folder. The `{Category}`
sub-grouping mirrors the parent `Content/AnalyticalRules/{Category}/` convention so
the import is self-organising.

## Current sources

### David Alonso - Threat Hunting Rules

- **Repository:** [Dalonso-Security-Repo](https://github.com/davidalonsod/Dalonso-Security-Repo)
- **Author:** [@davidalonsod](https://github.com/davidalonsod)
- **License:** [The Unlicense](https://unlicense.org/) (public domain)
- **Path:** [`Content/AnalyticalRules/Community/Dalonso/`](../../Content/AnalyticalRules/Community/Dalonso)
- **Import script:** [`Tools/Import-CommunityRules.ps1`](../../Tools/Import-CommunityRules.ps1)

Full credit for the detection logic, KQL queries, and rule design belongs
to David Alonso.

The folder is fully managed by the import script. Running it (re)clones
the upstream repo, normalises every rule, and writes:

| Output | Path | Purpose |
| --- | --- | --- |
| Rule YAMLs | `Content/AnalyticalRules/Community/Dalonso/{Category}/*.yaml` | Deployable detections |
| Auto-generated summary | [`Docs/Content/Community/Dalonso.md`](Community/Dalonso.md) | Per-category rule listings, last-sync date, source commit. **Not hand-edited** (regenerated each run alongside this governance doc) |
| Manifest | `Content/AnalyticalRules/Community/Dalonso/import-manifest.json` | Content-hash per file for drift-vs-upstream detection (operational artifact, stays next to the rules) |

Latest counts (regenerated on each import; the auto-generated
[`Docs/Content/Community/Dalonso.md`](Community/Dalonso.md) README is the live
source of truth):

| Category | Rule count | Source path |
| --- | ---: | --- |
| AzureActivity | 12 | ARM (`-IncludeKqlConversion`) |
| CommonSecurityLog | 37 | YAML-native (default) |
| DNSEvents | 17 | YAML-native (default) |
| NonInteractiveSigninLogs | 23 | YAML-native (default) |
| SigninLogs | 22 | YAML-native (default) |
| **Total (as of 2026-03-26)** | **111** | |

The committed tree was produced by a two-step import: a default run for
the YAML-native categories, then a second run with `-IncludeKqlConversion`
to add **AzureActivity**. A plain `./Tools/Import-CommunityRules.ps1`
(YAML-native folders only) does **not** produce AzureActivity, because
those rules come from ARM `azuredeploy.json` templates in
`$script:ArmFolderMap`, not from the `$script:YamlFolderMap` categories a
default run walks. To reproduce the full table you must run both passes
(see [Sources with an import script](#sources-with-an-import-script)).

The importer's `$script:YamlFolderMap` also maps an **ADFSSignInLogs**
category, but the upstream folder currently yields no rules, so no
`ADFSSignInLogs` sub-folder exists in the committed tree. It is a
mapped-but-empty category rather than a missing one; it will populate
automatically if the upstream source gains ADFS rules.

## Adding a new contributor

1. **Confirm the licence is compatible.** Public-domain licences (Unlicense,
   CC0) and permissive open-source licences (MIT, BSD, Apache 2.0) are
   straightforward. Copyleft licences (GPL family) need a deliberate
   decision before incorporating.

2. **Create the folder structure**:

   ```
   Content/AnalyticalRules/Community/{ContributorName}/{Category}/{RuleName}.yaml
   ```

3. **Author each YAML** following the schema in
   [Analytical Rules](Analytical-Rules.md). The `enabled` field is ignored
   at deploy time for community rules (they are always force-disabled),
   so leave it unset or `true` and trust the deploy logic.

4. **Include attribution** in each rule's `description:` block, e.g.:

   ```yaml
   description: |
     Detects ... [author attribution if appropriate]
     Source: https://github.com/{author}/{repo}
   ```

5. **Add the contributor to the Current sources section above** with:
   - Source repository URL
   - Author handle
   - Licence
   - Path to their folder
   - Last-synced date and source commit
   - Per-category rule counts

6. **Test the deploy** by clearing the community exclusion on a manual
   run (Azure DevOps: uncheck `skipCommunityDetections`; GitHub: remove
   `community-detections` from the `skip_custom_content_types` input).
   Verify rules appear in Sentinel as disabled.

## Updating an existing source

The Custom drift detector compares deployed state against repo YAML; it
does **not** compare repo YAML against external upstream sources. Pulling
upstream changes is its own workflow.

### Sources with an import script

For Dalonso, the dedicated importer handles everything:

```powershell
# Standard import (YAML-native folders only:
# CommonSecurityLog, DNSEvents, NonInteractiveSigninLogs, SigninLogs)
./Tools/Import-CommunityRules.ps1

# Also convert the ARM-template folders (adds AzureActivity and the other
# $script:ArmFolderMap categories); required to reproduce the full tree
./Tools/Import-CommunityRules.ps1 -IncludeKqlConversion

# Preview without writing files (reports CREATE/UPDATE per rule)
./Tools/Import-CommunityRules.ps1 -DryRun
```

The script shallow-clones the upstream repo (`git clone --depth 1
--single-branch`) into a temp folder, applies the project's normalisation
in `Build-RuleYaml` (forces `enabled: false`, prepends the Dalonso
attribution paragraph to descriptions, merges the required tags, expands
short trigger operators such as `gt`/`lt` to `GreaterThan`/`LessThan`),
and rewrites every YAML in the target folder. It also regenerates
[`Docs/Content/Community/Dalonso.md`](Community/Dalonso.md) (the auto-generated
rule listing, written to `-DocsPath`) and `import-manifest.json` (the
content-hash manifest, kept next to the rules under `-OutputPath`) so all
metadata always matches what was just imported.

**Prerequisites.** The importer needs `git` 2.x on `PATH` and the
`powershell-yaml` module. `Initialize-YamlModule` installs
`powershell-yaml` at `CurrentUser` scope automatically if it is missing,
so no manual module setup is required.

**Two conversion paths.** The default run walks `$script:YamlFolderMap`
and normalises each source `*.yaml` directly. `-IncludeKqlConversion`
additionally walks `$script:ArmFolderMap`, where the source content is
ARM `azuredeploy.json` templates rather than YAML. `Get-ArmRulesFromFolder`
parses each template and `ConvertFrom-ArmAlertRule` maps every
`Microsoft.SecurityInsights/alertRules` resource into the same normalised
YAML shape. That ARM path applies its own fallbacks where fields are
absent: `severity` defaults to `Medium`, `kind` defaults to `Scheduled`,
and the rule `id` falls back to a fresh random GUID when neither
`alertRuleTemplateName` nor a usable identifier is present. Onboarding an
ARM-based contributor means reasoning about those defaults, not just the
YAML schema.

**Required fields and skips.** `Build-RuleYaml` enforces the five
mandatory fields (`id`, `name`, `kind`, `severity`, `query`) and throws if
any are missing or blank. The caller catches that, logs a warning, skips
the offending rule, and increments `$stats.Errors`, so a rule that
silently fails to import will show up as an error in the run summary
rather than as a partial write.

**Idempotent re-runs.** Every run hashes the normalised output with
SHA256 (`Get-ContentHash256`) and compares it against the file already on
disk, reporting `CREATE`, `UPDATE`, or `UNCHANGED` per rule and writing
the same hashes into `import-manifest.json` (alongside `sourceCommitSha`
and `importDate` for traceability). This is what makes the "PR review
becomes look at what changed" workflow work: unchanged rules produce no
diff at all, so only genuinely new or modified detections surface in
`git diff`.

`-OutputPath` and `-DocsPath` override the auto-derived destinations. When
`-DocsPath` is omitted, the script derives it from the leaf folder name of
`-OutputPath` (for example `.../Community/Dalonso` becomes
`Docs/Content/Community/Dalonso.md`):

```powershell
./Tools/Import-CommunityRules.ps1 `
    -OutputPath ./Content/AnalyticalRules/Community/NewContributor `
    -DocsPath   ./Docs/Content/Community/NewContributor.md
```

**This importer is Dalonso-specific, not a generic tool.** Overriding the
two path parameters is *not* enough to onboard a different contributor.
The attribution text (`$script:AttributionPrefix`), the required tags
(`$script:RequiredTags = @('Community','Dalonso','ThreatHunting')`), the
default `SourceRepo`, and both folder maps
(`$script:YamlFolderMap` / `$script:ArmFolderMap`, keyed to Dalonso's
exact upstream folder names) are hard-coded constants. Forking the script
for a new source means rewriting those constants, not just passing new
paths. See [Sources without an import script](#sources-without-an-import-script)
below.

The PR review then becomes "look at what changed since last import": the
import-manifest's content hashes make stale rules and new rules
self-evident in `git diff`.

See [`Tools/Import-CommunityRules.ps1`](../../Tools/Import-CommunityRules.ps1)
header for the full parameter reference.

### Sources without an import script

If a contributor doesn't have a bulk importer:

1. Pull the latest from the upstream repository
2. Diff against the current `Content/AnalyticalRules/Community/{ContributorName}/`
   contents
3. Apply changes (new rules, modified KQL, removed rules)
4. Update the **Last synced** date noted next to the source above
5. Commit and PR

If the manual diff becomes impractical, the Dalonso importer
(`Tools/Import-CommunityRules.ps1`) is a working reference
implementation to fork.

## Deploy + drift workflow for community rules

```
                  ┌─────────────────────────────────────┐
                  │  Manual upstream sync (this doc)    │
                  │  -> commit YAML changes             │
                  └─────────────────────────────────────┘
                                  │
                                  ▼
                  ┌─────────────────────────────────────┐
                  │  Deploy pipeline                    │
                  │  (Skip Community Detections = off)  │
                  │  -> rules deployed disabled         │
                  └─────────────────────────────────────┘
                                  │
                                  ▼
                  ┌─────────────────────────────────────┐
                  │  Reviewer enables relevant rules    │
                  │  in the Sentinel portal             │
                  └─────────────────────────────────────┘
                                  │
                                  ▼
                  ┌─────────────────────────────────────┐
                  │  Daily drift detector               │
                  │  picks up portal edits to enabled   │
                  │  community rules and PRs them back  │
                  │  (See Sentinel-Drift-Detection.md)  │
                  └─────────────────────────────────────┘
```

## Authoring with GitHub Copilot

Community rules use the analytical-rule schema, so the path-scoped
[`.github/instructions/analytical-rules.instructions.md`](../../.github/instructions/analytical-rules.instructions.md)
loads automatically when editing files under
`Content/AnalyticalRules/Community/**`.

Copilot tooling for community rules:

- Slash command `/review-rule` (VS Code): review imported community
  content against the schema before enabling
- Agent `Sentinel-As-Code: Content Editor`: general edits
- Agent `Sentinel-As-Code: KQL Engineer`: optimise community-imported
  query bodies

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.

## Related docs

- [Analytical Rules](Analytical-Rules.md): YAML schema applies identically
  to community rules
- [Sentinel Drift Detection](../Tools/Sentinel-Drift-Detection.md): what happens
  when an enabled community rule is edited in the portal
