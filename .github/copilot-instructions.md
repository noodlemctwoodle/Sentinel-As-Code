# GitHub Copilot Instructions — Sentinel-As-Code

Repo-wide guidance for GitHub Copilot. Loaded automatically by Copilot
(VS Code, GitHub.com cloud agent, code review) on every chat request
in this workspace. Path-scoped instructions live under
[`.github/instructions/`](instructions) and stack on top of this file.

For the full Copilot setup map (agents, prompts, instructions),
see [`Docs/GitHub/GitHub-Copilot.md`](../Docs/GitHub/GitHub-Copilot.md).

---

## What this repo is

Sentinel-As-Code is a complete CI/CD solution for deploying Microsoft
Sentinel and Defender XDR content from a Git repo. It provisions
infrastructure (Bicep), deploys Content Hub solutions, custom analytical
rules, hunting queries, watchlists, playbooks, workbooks, parsers,
automation rules, summary rules, and Defender XDR custom detections.

Two equivalent CI/CD platforms are supported:

- **GitHub Actions** — under `.github/workflows/`
- **Azure DevOps Pipelines** — under `Pipelines/`. ADO is the default
  source of truth that GitHub workflows mirror, with documented
  platform-forced and one-direction-first divergences allowed. See
  [`instructions/workflows.instructions.md`](instructions/workflows.instructions.md)
  Hard rule 1 for the full carve-out policy.

Start any unfamiliar task by reading [`Docs/README.md`](../Docs/README.md).

## Repository layout (where things live)

| Folder | Contents | Authoring guide |
| --- | --- | --- |
| `Content/AnalyticalRules/` | Custom Sentinel analytical rules (YAML) | [Docs/Content/Analytical-Rules.md](../Docs/Content/Analytical-Rules.md) |
| `Content/HuntingQueries/` | Custom hunting queries (YAML) | [Docs/Content/Hunting-Queries.md](../Docs/Content/Hunting-Queries.md) |
| `Content/DefenderCustomDetections/` | Defender XDR custom detections (YAML) | [Docs/Content/Defender-Custom-Detections.md](../Docs/Content/Defender-Custom-Detections.md) |
| `Content/Watchlists/` | Reusable data lists (`watchlist.json` + `data.csv` per alias) | [Docs/Content/Watchlists.md](../Docs/Content/Watchlists.md) |
| `Content/Playbooks/` | Logic App playbooks (ARM templates, JSON) | [Docs/Content/Playbooks.md](../Docs/Content/Playbooks.md) |
| `Content/Workbooks/` | Workbook gallery JSON | [Docs/Content/Workbooks.md](../Docs/Content/Workbooks.md) |
| `Content/Parsers/` | KQL parser/function YAMLs | [Docs/Deploy/Scripts.md](../Docs/Deploy/Scripts.md#deploy-customcontentps1) |
| `Content/SummaryRules/` | Summary-rule JSON | [Docs/Content/Summary-Rules.md](../Docs/Content/Summary-Rules.md) |
| `Content/AutomationRules/` | Sentinel automation rules (JSON) | [Docs/Content/Automation-Rules.md](../Docs/Content/Automation-Rules.md) |
| `Infra/` | Subscription-scoped infra templates | [Docs/Infra/Bicep.md](../Docs/Infra/Bicep.md) |
| `Modules/Sentinel.Common/` | Shared deployer + KQL discovery helpers (PowerShell module) | [Docs/Deploy/Scripts.md](../Docs/Deploy/Scripts.md) |
| `Deploy/` | Content + infra deployment scripts and `sentinel-deployment.config` | [Docs/Deploy/Scripts.md](../Docs/Deploy/Scripts.md) |
| `Tools/` | CI / maintenance / reporting scripts (manifest, drift, PR validation, Documenter) | [Docs/Deploy/Scripts.md](../Docs/Deploy/Scripts.md) |
| `Tests/` | Pester suites (schema + module unit tests) | [Docs/Tests/Pester-Tests.md](../Docs/Tests/Pester-Tests.md) |
| `dependencies.json` | Auto-derived content dependency graph | [Docs/Tools/Dependency-Manifest.md](../Docs/Tools/Dependency-Manifest.md) |

## Conventions you must follow

### Language and style

- **Spelling**: en-GB throughout (analyse, behaviour, customise,
  organisation, prioritise, recognise). Existing tooling produces en-US
  output — when editing tool output that uses en-US, leave the existing
  text alone but write any new prose in en-GB.
- **No em-dashes** (`—`) in user-visible prose unless they already
  exist in the file you're editing. Prefer hyphens (`-`) or
  parenthetical phrasing.
- **No emojis** in code, commit messages, or files unless the file
  already uses them. Documentation can use them sparingly when they
  add real meaning (e.g. status icons in tables).

### File headers

Every new PowerShell / Bicep / YAML / JSON file should carry a header
that includes the full repo-relative path and a creation date in
DD/MM/YYYY format. Example:

```powershell
#
# Sentinel-As-Code/Deploy/Foo.ps1
#
# Created by <author> on DD/MM/YYYY.
#
```

For YAML / JSON files where a comment header isn't natural (e.g. data
files), skip the header — but for hand-authored content like analytical
rules, include a brief metadata block at the top of the file.

### Commit messages

Conventional commit format: `type(scope): brief description`.

- **Types**: `feat`, `fix`, `refactor`, `perf`, `style`, `docs`,
  `test`, `chore`, `ci`, `build`, `revert`
- **Scope examples**: `(modules)`, `(scripts)`, `(workflows)`,
  `(deps)`, `(rules)`, `(playbooks)`, `(testing)`, `(deploy)`,
  `(drift)`
- **Body**: explain *why* (business / technical justification), *what*
  changed (file list with reasons), how it was tested. Multi-paragraph
  bodies are normal here; trivial one-liners are not.

**Never include in a commit message**:
- References to Claude, Anthropic, AI assistance, ChatGPT, Copilot, or
  any LLM. Including a `Co-Authored-By` trailer for an AI tool.
- "Generated with..." or similar phrases.
- Emojis (unless the existing log already uses them — it doesn't here).

### Pull requests

- Keep PRs small and atomic. Multiple related commits in one PR is
  fine; multiple unrelated changes is not.
- PR titles follow the same conventional-commit format as commit
  messages.
- The five-job PR-validation gate must pass: `validate`, `bicep-build`,
  `arm-validate`, `kql-validate`, `dependency-manifest`. See
  [Docs/Tests/Pester-Tests.md](../Docs/Tests/Pester-Tests.md).

## Hard rules (do not break)

1. **Never push to `main` directly.** All changes go through PRs.
2. **Never push to `auto/*` rolling branches.** Those are bot-managed
   (drift sync, dependency-manifest sync) and `--force-with-lease`
   pushed by their workflows.
3. **Never modify `dependencies.json` by hand.** It is auto-derived.
   To update it, edit the content that generates it and run
   `./Tools/Build-DependencyManifest.ps1 -Mode Generate`. The
   PR-validation `dependency-manifest` job will fail any hand-edit.
4. **Don't commit secrets.** Use OIDC federated credentials for Azure
   auth (already configured); use Key Vault references for runtime
   secrets in Logic App playbooks.
5. **Don't bypass the merge gate.** No `--no-verify` on commit, no
   `git push --force` on `main`.
6. **Don't widen role assignments without justification.** The deploy
   SP runs with `Contributor` + ABAC-conditioned `User Access
   Administrator`. Adding broader roles requires a documented reason.

## Authoring tasks — quick reference

| Goal | Read first | Then run |
| --- | --- | --- |
| Add a new analytical rule | [Docs/Content/Analytical-Rules.md](../Docs/Content/Analytical-Rules.md) | Agent `rule-author` (cross-platform) or prompt `/new-analytical-rule` (VS Code) |
| Add a hunting query | [Docs/Content/Hunting-Queries.md](../Docs/Content/Hunting-Queries.md) | Agent `rule-author` or prompt `/new-hunting-query` |
| Add a Defender XDR detection | [Docs/Content/Defender-Custom-Detections.md](../Docs/Content/Defender-Custom-Detections.md) | Agent `rule-author` or prompt `/new-defender-detection` |
| Add a Pester test | [Docs/Tests/Pester-Tests.md](../Docs/Tests/Pester-Tests.md) | Prompt `/new-pester-test` (VS Code) |
| Tune an existing rule | n/a | Agent `rule-tuner` |
| Understand the repo | [Docs/README.md](../Docs/README.md) | Agent `repo-explorer` |
| Edit / diagnose a pipeline | [Docs/Pipelines/README.md](../Docs/Pipelines/README.md) | Agent `pipeline-engineer` |
| Add or refactor a function in `Sentinel.Common` | [Docs/Deploy/Scripts.md](../Docs/Deploy/Scripts.md) | Agent `powershell-engineer` |
| Edit a Bicep template | [Docs/Infra/Bicep.md](../Docs/Infra/Bicep.md) | Agent `bicep-engineer` |
| Optimise a KQL query | [`.github/instructions/kql-queries.instructions.md`](instructions/kql-queries.instructions.md) | Agent `kql-engineer` |
| Add coverage for an untested script / refactor a Pester suite | [Docs/Tests/Pester-Tests.md](../Docs/Tests/Pester-Tests.md) | Agent `test-engineer` |
| Security-review a playbook / script / workflow | n/a | Agent `security-reviewer` |
| Triage a drift auto-PR | [Docs/Tools/Sentinel-Drift-Detection.md](../Docs/Tools/Sentinel-Drift-Detection.md) | Agent `drift-engineer` |
| Investigate why dependencies.json is wrong / extend the discovery extractor | [Docs/Tools/Dependency-Manifest.md](../Docs/Tools/Dependency-Manifest.md) | Agent `dependencies-engineer` |
| Refresh the dependency manifest | [Docs/Tools/Dependency-Manifest.md](../Docs/Tools/Dependency-Manifest.md) | Prompt `/regenerate-deps` (or agent `dependencies-engineer` for non-trivial issues) |

## Testing

Every PR runs the full Pester suite (22 files: 19 under `Tests/*.Tests.ps1`
plus 3 under `Tests/Documenter/`) plus the schema gates. `Invoke-PRValidation.ps1`
runs every suite and emits an NUnit 2.5 XML report. To run locally before
pushing:

```powershell
./Tools/Invoke-PRValidation.ps1 -RepoPath .
```

To run a specific suite:

```powershell
Invoke-Pester -Path Tests/Test-AnalyticalRuleYaml.Tests.ps1
```

Test-authoring conventions live in
[Docs/Tests/Pester-Tests.md](../Docs/Tests/Pester-Tests.md).
The repo uses an AST-extraction pattern (functions are extracted from
scripts and dot-sourced into the test scope) rather than running scripts
end-to-end. Read that doc before adding tests.

## When you're unsure

- For schema questions: read the relevant `Docs/Content/<Type>.md` first.
- For deploy-pipeline questions: read [Docs/Pipelines/README.md](../Docs/Pipelines/README.md).
- For test-authoring questions: read [Docs/Tests/Pester-Tests.md](../Docs/Tests/Pester-Tests.md).
- For dependency / discovery questions: read [Docs/Tools/Dependency-Manifest.md](../Docs/Tools/Dependency-Manifest.md).

If the docs disagree with the code, **the code is the source of
truth** and the docs need updating — flag it in your PR.
