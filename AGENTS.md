# AGENTS.md

Cross-tool agent guidance for Sentinel-As-Code. Recognised by GitHub
Copilot, Claude, Gemini, Cursor, and other agentic coding tools that
look for `AGENTS.md` at the repo root.

This file is a thin pointer — every agent / tool should follow the
canonical instructions in
[`.github/copilot-instructions.md`](./.github/copilot-instructions.md).

## TL;DR for agents

1. **Read [`.github/copilot-instructions.md`](./.github/copilot-instructions.md) first.**
   It carries the conventions (en-GB spelling, no em-dashes,
   commit-message format, no AI co-author trailers, etc.) that the rest
   of the docs assume.
2. **Read [`Docs/README.md`](./Docs/README.md) second.** It is the
   table of contents for every concern in the repo.
3. **Path-scoped instructions** under
   [`.github/instructions/`](./.github/instructions/) carry per-folder
   schema rules and conventions. Copilot loads them automatically based
   on the file you're editing; other agents should read the matching
   `<area>.instructions.md` before editing files in that area.
4. **Reusable prompts** under [`.github/prompts/`](./.github/prompts/)
   are slash commands for repeatable tasks (new rule, new test,
   review-a-rule, regenerate-deps). Copilot exposes them in chat;
   other agents can read them as task templates.
5. **Custom agents** under [`.github/agents/`](./.github/agents/)
   are persona configurations recognised by GitHub Copilot Chat
   (github.com), Copilot cloud agent, Copilot CLI, VS Code,
   JetBrains, Eclipse, and Xcode. Use the matching agent for the
   task: `repo-explorer`, `rule-author`, `content-editor`,
   `rule-tuner`, `code-explainer`, `pipeline-engineer`. Other
   agentic tools can treat the `.agent.md` files as role
   definitions.

## Hard rules

- **Never push to `main` directly.** All changes via PR.
- **Never push to `auto/*` branches.** Bot-managed.
- **Never hand-edit `dependencies.json`.** Auto-derived. Run
  `./Scripts/Build-DependencyManifest.ps1 -Mode Generate` instead.
- **Never include AI / LLM references in commit messages or
  `Co-Authored-By` trailers.** This includes Claude, Anthropic,
  ChatGPT, Copilot, etc.
- **Never use em-dashes (—) in new prose.** Use hyphens or
  parenthetical phrasing.
- **Always run Pester locally before pushing**: `./Scripts/Invoke-PRValidation.ps1`.

## What to do for common tasks

| You want to... | Read | Use |
| --- | --- | --- |
| Add a Sentinel analytical rule | [Docs/Content/Analytical-Rules.md](./Docs/Content/Analytical-Rules.md) | Agent `rule-author` (works on github.com + VS Code) or prompt `/new-analytical-rule` (VS Code) |
| Add a hunting query | [Docs/Content/Hunting-Queries.md](./Docs/Content/Hunting-Queries.md) | Agent `rule-author` or prompt `/new-hunting-query` |
| Add a Defender XDR detection | [Docs/Content/Defender-Custom-Detections.md](./Docs/Content/Defender-Custom-Detections.md) | Agent `rule-author` or prompt `/new-defender-detection` |
| Add a Pester test | [Docs/Development/Pester-Tests.md](./Docs/Development/Pester-Tests.md) | Prompt `/new-pester-test` (VS Code) |
| Tune an existing rule's threshold / severity | The rule file itself | Agent `rule-tuner` |
| Understand how a piece of the repo works | [Docs/README.md](./Docs/README.md) | Agent `repo-explorer` |
| Explain a rule's KQL | The rule file | Agent `code-explainer` |
| Edit a workflow / pipeline, port an ADO change to GH, or diagnose a CI/CD failure | [Docs/Deployment/Pipelines.md](./Docs/Deployment/Pipelines.md) | Agent `pipeline-engineer` |
| Refresh `dependencies.json` | [Docs/Operations/Dependency-Manifest.md](./Docs/Operations/Dependency-Manifest.md) | Prompt `/regenerate-deps` |

## Test before you ship

Always run the Pester suite locally before opening a PR:

```powershell
./Scripts/Invoke-PRValidation.ps1 -RepoPath .
```

Five-job CI gate on every PR to `main`:

- `validate` — Pester suites
- `bicep-build` — `az bicep build`
- `arm-validate` — Test-AzResourceGroupDeployment -WhatIf (OIDC)
- `kql-validate` — Microsoft.Azure.Kusto.Language parser
- `dependency-manifest` — `dependencies.json` drift gate

A failing gate blocks merge. See
[Docs/Development/Pester-Tests.md](./Docs/Development/Pester-Tests.md).
