# GitHub Copilot Setup

How GitHub Copilot is configured for this repo and how to use the
custom instructions, agents, and prompts shipped with it.

## What's wired up

This repo ships a complete GitHub Copilot customisation set, aligned
with the latest standards documented at
[docs.github.com/copilot/customizing-copilot](https://docs.github.com/copilot/customizing-copilot)
and [code.visualstudio.com/docs/copilot/customization](https://code.visualstudio.com/docs/copilot/customization/overview).

| Layer | Purpose | Where |
| --- | --- | --- |
| Repo-wide instructions | Conventions every chat in this workspace follows | [`.github/copilot-instructions.md`](../../.github/copilot-instructions.md) |
| Cross-tool agent guidance | Recognised by GitHub Copilot, Claude, Gemini, Cursor | [`AGENTS.md`](../../AGENTS.md) |
| Path-scoped instructions | Per-folder authoring rules, loaded automatically by `applyTo` glob | [`.github/instructions/`](../../.github/instructions/) |
| Custom agents | Persona configurations recognised across github.com + every IDE | [`.github/agents/`](../../.github/agents/) |
| Reusable prompts | Slash-command templates for repeatable tasks (VS Code / VS / JetBrains) | [`.github/prompts/`](../../.github/prompts/) |

## Platform support matrix

Where each layer is recognised:

| Layer | github.com Chat | github.com cloud agent | github.com code review | VS Code | Visual Studio | JetBrains | Copilot CLI |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `copilot-instructions.md` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `instructions/*.instructions.md` | code-review only | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `agents/*.agent.md` | ✅ | ✅ | n/a | ✅ | ✅ | ✅ | ✅ |
| `prompts/*.prompt.md` | ❌ | ❌ | n/a | ✅ | ✅ | ✅ | ❌ |
| `AGENTS.md` (root) | n/a | ✅ | n/a | ✅ | ✅ | ✅ | ✅ |

**Why no `chatmodes/`?** The legacy VS Code-only `.chatmode.md`
format has been superseded by `.agent.md` under
[`.github/agents/`](../../.github/agents/), which works on
github.com **and** in every IDE. We migrated the chat modes to
agents in commit `<TBD>`. If you're working from an older clone,
delete the legacy `.github/chatmodes/` folder; it's no longer used.

## File inventory

### Repo-wide

- [`.github/copilot-instructions.md`](../../.github/copilot-instructions.md)
  — repo conventions (en-GB, no em-dashes, commit-message format,
  hard rules), repository layout, where-to-look table.
- [`AGENTS.md`](../../AGENTS.md) — cross-tool agent guidance.
  Recognised by GitHub Copilot Coding Agent, Claude, Gemini, Cursor
  and others that look for `AGENTS.md` at the repo root.

### Path-scoped instructions (`.github/instructions/`)

Loaded automatically when you edit a file matching the `applyTo`
glob in the frontmatter.

| File | applies to | Covers |
| --- | --- | --- |
| `analytical-rules.instructions.md` | `AnalyticalRules/**/*.yaml` | Schema, field conventions, post-edit checklist |
| `hunting-queries.instructions.md` | `HuntingQueries/**/*.yaml` | Hunting-vs-analytical decision, schema |
| `defender-detections.instructions.md` | `DefenderCustomDetections/**/*.yaml` | Schema, table-set difference, response actions |
| `watchlists.instructions.md` | `Watchlists/**` | Folder layout, alias-equality rule, cross-validation |
| `playbooks.instructions.md` | `Playbooks/**/*.json` | ARM template structure, trigger-type folders, MSI tag |
| `pester-tests.instructions.md` | `Tests/**/*.ps1` | AST-extraction pattern, mocking conventions |
| `powershell-scripts.instructions.md` | `Scripts/**/*.ps1`, `Modules/**/*.psm1`, `Modules/**/*.psd1` | Style, Sentinel.Common usage, foot-gun list |
| `kql-queries.instructions.md` | Any file with embedded KQL | KQL conventions, discovery-friendly patterns |
| `workflows.instructions.md` | `.github/workflows/**`, `.github/actions/**`, `Pipelines/**/*.yml` | ADO-as-source-of-truth, composite actions, schedule alignment |

### Custom agents (`.github/agents/`)

Persona configurations recognised across github.com (Chat + cloud
agent) and every supported IDE (VS Code, Visual Studio, JetBrains,
Eclipse, Xcode), plus Copilot CLI.

| Agent | Purpose |
| --- | --- |
| `repo-explorer.agent.md` | **Understand.** Explains repo architecture, content flow, where things live. Read-only. |
| `rule-author.agent.md` | **Build.** Authors new analytical rules, hunting queries, Defender detections end-to-end. |
| `content-editor.agent.md` | **Edit.** General-purpose edits across any content type with the right post-edit tests. |
| `rule-tuner.agent.md` | **Adjust.** Tunes thresholds, severity, query filters on existing rules without changing detection intent. |
| `code-explainer.agent.md` | **Explain.** Walks through PowerShell, KQL, ARM, workflows in plain prose. Read-only. |

#### How to invoke

- **github.com Chat / cloud agent**: pick the agent from the
  agents dropdown at https://github.com/copilot/agents (after the
  agent's `.agent.md` is merged into `main`).
- **VS Code Copilot Chat**: pick the agent from the chat-mode
  dropdown.
- **Copilot CLI**: `gh copilot agent <name> "<your prompt>"`.

### Reusable prompts (`.github/prompts/`)

VS Code / Visual Studio / JetBrains slash commands. Not available
on github.com Chat.

| Prompt | What it does |
| --- | --- |
| `/new-analytical-rule` | Bootstraps a fresh `AnalyticalRules/<Source>/<Name>.yaml` |
| `/new-hunting-query` | Bootstraps a fresh `HuntingQueries/<Source>/<Name>.yaml` |
| `/new-defender-detection` | Bootstraps a fresh `DefenderCustomDetections/<Category>/<Name>.yaml` |
| `/new-pester-test` | Bootstraps a Pester 5 test using the AST-extraction pattern |
| `/review-rule` | Reviews a rule against schema + KQL + convention rules |
| `/regenerate-deps` | Runs `Build-DependencyManifest -Mode Generate` and explains the diff |

The same content is captured (in less interactive form) by the
matching agents — so if you're on github.com Chat, invoke the
`rule-author` agent and it will follow the same workflow as
`/new-analytical-rule`.

## Updating the customisations

### To add a new path-scoped instruction file

1. Create `.github/instructions/<name>.instructions.md` with frontmatter:

   ```markdown
   ---
   name: Display name
   description: Short description shown on hover.
   applyTo: "<glob1>,<glob2>"
   ---
   ```

2. Body is plain Markdown. Copilot loads it on top of
   `copilot-instructions.md` whenever the file you're editing
   matches the `applyTo` glob.

### To add a new custom agent

1. Create `.github/agents/<name>.agent.md` with frontmatter:

   ```markdown
   ---
   description: One-line description (required).
   tools: ['search/codebase', 'edit/applyPatch', 'terminal/run']
   ---
   ```

   Optional frontmatter keys:
   - `name` — display name (defaults to filename)
   - `model` — preferred model (e.g. `gpt-5`, `claude-sonnet-4`)
   - `target` — restrict to one platform: `vscode` or
     `github-copilot`. Omit for cross-platform.
   - `mcp-servers`, `metadata`, `disable-model-invocation`,
     `user-invocable` — see the
     [GitHub custom-agent reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
     for the full schema.

2. Body is plain Markdown — the persona's instructions. 30,000-
   character limit.

3. Commit and merge to `main`. The agent appears in the
   github.com agent dropdown after the merge; in VS Code it
   appears in the chat-mode dropdown after a chat reload.

### To add a new prompt

1. Create `.github/prompts/<name>.prompt.md` with frontmatter:

   ```markdown
   ---
   description: One-line description.
   argument-hint: <hint shown in the chat input>
   agent: agent | ask | plan
   tools: ['search/codebase', 'edit/applyPatch']
   ---
   ```

2. Body is the prompt template. Variables: `${input:name}`,
   `${selection}`, `${file}`. Tool refs: `#tool:<name>`.

3. Invoke with `/<filename-without-extension>` in chat. Only
   available in IDE clients (VS Code / VS / JetBrains).

## Conventions followed

The customisations align with the latest GitHub Copilot standards
as of April 2026:

- **File extensions**: `.instructions.md`, `.prompt.md`,
  `.agent.md` (the cross-platform format that supersedes
  `.chatmode.md`).
- **Folder layout**: `.github/instructions/`,
  `.github/agents/`, `.github/prompts/`.
- **Frontmatter**: YAML at file start, terminated by `---`. Keys
  use the schema documented at
  [docs.github.com/en/copilot/reference/custom-agents-configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
  and
  [code.visualstudio.com/docs/copilot/customization/custom-instructions](https://code.visualstudio.com/docs/copilot/customization/custom-instructions).
- **`applyTo` globs**: comma-separated, relative to repo root.
- **Tool names**: namespaced format (`search/codebase`,
  `edit/applyPatch`, `terminal/run`, `web/fetch`).

## Validation

There's no Pester suite for the Copilot files (they're plain
Markdown). The lightest sanity check is YAML-frontmatter parse:

```powershell
foreach ($f in (Get-ChildItem .github/instructions, .github/agents, .github/prompts -Recurse -File)) {
    $content = Get-Content $f.FullName -Raw
    if ($content -notmatch '(?ms)^---\s*\n.*?\n---\s*\n') {
        Write-Warning "$($f.Name): missing or malformed frontmatter"
    }
}
```

When adding a new file, run that check.

## Cross-references

- [`Docs/README.md`](../README.md) — top-level doc index
- [`AGENTS.md`](../../AGENTS.md) — cross-tool agent guidance
- [`.github/copilot-instructions.md`](../../.github/copilot-instructions.md) — repo-wide instructions
- [GitHub Copilot custom instructions documentation](https://docs.github.com/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot)
- [GitHub custom agents reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [VS Code Copilot customisation overview](https://code.visualstudio.com/docs/copilot/customization/overview)
- [`github/awesome-copilot`](https://github.com/github/awesome-copilot) — community-maintained collection of Copilot customisations
