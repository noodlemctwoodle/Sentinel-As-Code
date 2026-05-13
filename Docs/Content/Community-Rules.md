# Community Rules

Community-contributed analytics rules live under
[`AnalyticalRules/Community/`](../../AnalyticalRules/Community/), organised by
contributor. They follow the same YAML schema as in-house Custom rules
(see [Analytical Rules](Analytical-Rules.md)) but ship with deliberately
restrictive deployment defaults so manual review precedes any production
enablement.

## Deployment behaviour

| Property | Default | Why |
| --- | --- | --- |
| **Opt-in** | Skipped unless explicitly included | Pipeline parameter `Skip Community Detections` defaults to `true`; uncheck to include them in a deploy run |
| **Disabled at deploy time** | `enabled: false` regardless of the YAML's `enabled` field | Rules are evaluated by the deployer and forced disabled in [`Deploy-CustomContent.ps1:1155`](../../Scripts/Deploy-CustomContent.ps1). Reviewers enable individual rules in the Sentinel portal after deployment |
| **Drift detection** | Same as Custom rules | If someone enables a community rule and edits its KQL in the portal, the daily drift detector picks it up and PRs the change back to the YAML |

This combination — opt-in at deploy time, disabled by default once
deployed — means community contributions ship as inert content until a
human turns them on.

## Folder structure

```
AnalyticalRules/Community/
└── {ContributorName}/
    └── {Category}/
        └── {RuleName}.yaml
```

Each contributor maintains their own top-level folder. The `{Category}`
sub-grouping mirrors the parent `AnalyticalRules/{Category}/` convention so
the import is self-organising.

## Current sources

### David Alonso — Threat Hunting Rules

- **Repository:** [Dalonso-Security-Repo](https://github.com/davidalonsod/Dalonso-Security-Repo)
- **Author:** [@davidalonsod](https://github.com/davidalonsod)
- **License:** [The Unlicense](https://unlicense.org/) (public domain)
- **Path:** [`AnalyticalRules/Community/Dalonso/`](../../AnalyticalRules/Community/Dalonso/)
- **Import script:** [`Scripts/Import-CommunityRules.ps1`](../../Scripts/Import-CommunityRules.ps1)

Full credit for the detection logic, KQL queries, and rule design belongs
to David Alonso.

The folder is fully managed by the import script — running it (re)clones
the upstream repo, normalises every rule, and writes:

| Output | Path | Purpose |
| --- | --- | --- |
| Rule YAMLs | `AnalyticalRules/Community/Dalonso/{Category}/*.yaml` | Deployable detections |
| Auto-generated summary | [`Docs/Community/Dalonso.md`](../Community/Dalonso.md) | Per-category rule listings, last-sync date, source commit. **Not hand-edited** — regenerated each run alongside this governance doc |
| Manifest | `AnalyticalRules/Community/Dalonso/import-manifest.json` | Content-hash per file for drift-vs-upstream detection (operational artifact, stays next to the rules) |

Latest counts (regenerated on each import; the auto-generated README is
the live source of truth):

| Category | Rule count |
| --- | ---: |
| AzureActivity | 12 |
| CommonSecurityLog | 37 |
| DNSEvents | 17 |
| NonInteractiveSigninLogs | 23 |
| SigninLogs | 22 |
| **Total (as of 2026-03-26)** | **111** |

## Adding a new contributor

1. **Confirm the licence is compatible.** Public-domain licences (Unlicense,
   CC0) and permissive open-source licences (MIT, BSD, Apache 2.0) are
   straightforward. Copyleft licences (GPL family) need a deliberate
   decision before incorporating.

2. **Create the folder structure**:

   ```
   AnalyticalRules/Community/{ContributorName}/{Category}/{RuleName}.yaml
   ```

3. **Author each YAML** following the schema in
   [Analytical Rules](Analytical-Rules.md). The `enabled` field is ignored
   at deploy time for community rules — they are always force-disabled —
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

6. **Test the deploy** by unchecking the `Skip Community Detections`
   pipeline parameter on a manual run. Verify rules appear in Sentinel as
   disabled.

## Updating an existing source

The Custom drift detector compares deployed state against repo YAML — it
does **not** compare repo YAML against external upstream sources. Pulling
upstream changes is its own workflow.

### Sources with an import script

For Dalonso, the dedicated importer handles everything:

```powershell
# Standard import (YAML-native folders only)
./Scripts/Import-CommunityRules.ps1

# Include ARM-template-based KQL folders
./Scripts/Import-CommunityRules.ps1 -IncludeKqlConversion

# Preview without writing files
./Scripts/Import-CommunityRules.ps1 -DryRun
```

The script clones the upstream repo, applies the project's normalisation
(forces `enabled: false`, prepends attribution to descriptions, merges
required tags, expands short trigger operators), and rewrites every YAML
in the target folder. It also regenerates [`Docs/Community/Dalonso.md`](../Community/Dalonso.md)
(the auto-generated rule listing, sibling to this governance doc) and
`import-manifest.json` (the content-hash manifest, kept next to the
rules) so all metadata always matches what was just imported.

Override the auto-derived destinations with `-OutputPath` and `-DocsPath`
when onboarding a new contributor, e.g.:

```powershell
./Scripts/Import-CommunityRules.ps1 `
    -OutputPath ./AnalyticalRules/Community/NewContributor `
    -DocsPath   ./Docs/Community/NewContributor.md
```

When `-DocsPath` is omitted, the script derives it from the leaf folder
name of `-OutputPath` — e.g. `…/Community/Dalonso` →
`Docs/Community/Dalonso.md`.

The PR review then becomes "look at what changed since last import" — the
import-manifest's content hashes make stale rules and new rules
self-evident in `git diff`.

See [`Scripts/Import-CommunityRules.ps1`](../../Scripts/Import-CommunityRules.ps1)
header for the full parameter reference.

### Sources without an import script

If a contributor doesn't have a bulk importer:

1. Pull the latest from the upstream repository
2. Diff against the current `AnalyticalRules/Community/{ContributorName}/`
   contents
3. Apply changes (new rules, modified KQL, removed rules)
4. Update the **Last synced** date noted next to the source above
5. Commit and PR

If the manual diff becomes impractical, the Dalonso importer
(`Scripts/Import-CommunityRules.ps1`) is a working reference
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
`AnalyticalRules/Community/**`.

Copilot tooling for community rules:

- Slash command `/review-rule` (VS Code) — review imported community
  content against the schema before enabling
- Agent `Sentinel-As-Code: Content Editor` — general edits
- Agent `Sentinel-As-Code: KQL Engineer` — optimise community-imported
  query bodies

See [GitHub Copilot setup](../Development/GitHub-Copilot.md) for the full layout.

## Related docs

- [Analytical Rules](Analytical-Rules.md) — YAML schema applies identically
  to community rules
- [Sentinel Drift Detection](../Operations/Sentinel-Drift-Detection.md) — what happens
  when an enabled community rule is edited in the portal
