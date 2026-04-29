# GitHub Copilot Setup

How GitHub Copilot is configured for this repo and how to use the
custom instructions, chat modes, and prompts shipped with it.

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
| Custom chat modes | Persona configurations for VS Code Copilot Chat | [`.github/chatmodes/`](../../.github/chatmodes/) |
| Reusable prompts | Slash-command templates for repeatable tasks | [`.github/prompts/`](../../.github/prompts/) |

## File inventory

### Repo-wide

- [`.github/copilot-instructions.md`](../../.github/copilot-instructions.md)
  — repo conventions (en-GB, no em-dashes, commit-message format,
  hard rules), repository layout, where-to-look table.
- [`AGENTS.md`](../../AGENTS.md) — cross-tool agent guidance.
  Recognised by GitHub Copilot, Claude, Gemini, Cursor and others
  that look for `AGENTS.md` at the repo root.

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

### Custom chat modes (`.github/chatmodes/`)

Personas you can switch into in VS Code Copilot Chat.

| Mode | Purpose |
| --- | --- |
| `repo-explorer.chatmode.md` | **Understand.** Explains repo architecture, content flow, where things live. Read-only. |
| `rule-author.chatmode.md` | **Build.** Authors new analytical rules, hunting queries, Defender detections end-to-end. |
| `content-editor.chatmode.md` | **Edit.** General-purpose edits across any content type with the right post-edit tests. |
| `rule-tuner.chatmode.md` | **Adjust.** Tunes thresholds, severity, query filters on existing rules without changing detection intent. |
| `code-explainer.chatmode.md` | **Explain.** Walks through PowerShell, KQL, ARM, workflows in plain prose. Read-only. |

### Reusable prompts (`.github/prompts/`)

Slash commands you can invoke in chat.

| Prompt | What it does |
| --- | --- |
| `/new-analytical-rule` | Bootstraps a fresh `AnalyticalRules/<Source>/<Name>.yaml` |
| `/new-hunting-query` | Bootstraps a fresh `HuntingQueries/<Source>/<Name>.yaml` |
| `/new-defender-detection` | Bootstraps a fresh `DefenderCustomDetections/<Category>/<Name>.yaml` |
| `/new-pester-test` | Bootstraps a Pester 5 test using the AST-extraction pattern |
| `/review-rule` | Reviews a rule against schema + KQL + convention rules |
| `/regenerate-deps` | Runs `Build-DependencyManifest -Mode Generate` and explains the diff |

## How Copilot picks up the files

| File | Loaded by | When |
| --- | --- | --- |
| `.github/copilot-instructions.md` | GitHub Copilot (VS Code, github.com chat, code review) | Every chat in this workspace |
| `.github/instructions/*.instructions.md` | Same | Automatically, when the file you're editing matches the `applyTo` glob |
| `.github/prompts/*.prompt.md` | VS Code Copilot Chat (also Visual Studio + JetBrains IDEs) | When you type `/<filename-without-extension>` in chat |
| `.github/chatmodes/*.chatmode.md` | VS Code Copilot Chat | When you switch the chat mode dropdown |
| `AGENTS.md` | Multi-agent tools (Claude, Gemini, Cursor) and GitHub Copilot Coding Agent | When the tool starts a session in this repo |

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

### To add a new chat mode

1. Create `.github/chatmodes/<name>.chatmode.md` with frontmatter:

   ```markdown
   ---
   name: Display name
   description: One-line description.
   tools: ['search/codebase', 'edit/applyPatch', 'terminal/run']
   ---
   ```

2. Restart VS Code Chat to pick up the new mode in the dropdown.

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

3. Invoke with `/<filename-without-extension>` in chat.

## Conventions followed

The customisations align with the latest GitHub Copilot standards
as of April 2026:

- **File extensions**: `.instructions.md`, `.prompt.md`,
  `.chatmode.md` (the `.agent.md` rename is in progress in VS Code
  but `.chatmode.md` is still the documented format on
  github.com).
- **Frontmatter**: YAML at file start, terminated by `---`. Keys
  use the schema documented at
  [code.visualstudio.com/docs/copilot/customization/custom-instructions](https://code.visualstudio.com/docs/copilot/customization/custom-instructions).
- **`applyTo` globs**: comma-separated, relative to repo root.
- **Tool names**: namespaced format (`search/codebase`,
  `edit/applyPatch`, `terminal/run`, `web/fetch`).

## Validation

There's no Pester suite for the Copilot files (they're plain
Markdown). The lightest sanity check is YAML-frontmatter parse:

```powershell
foreach ($f in (Get-ChildItem .github/instructions, .github/chatmodes, .github/prompts -Recurse -File)) {
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
- [VS Code Copilot customisation overview](https://code.visualstudio.com/docs/copilot/customization/overview)
- [`github/awesome-copilot`](https://github.com/github/awesome-copilot) — community-maintained collection of Copilot customisations
