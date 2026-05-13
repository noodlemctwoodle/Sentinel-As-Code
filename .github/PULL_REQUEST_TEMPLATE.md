<!--
Thanks for contributing to Sentinel-As-Code. Fill the sections below.
Empty sections / unchecked boxes are fine — replace placeholder text
with your own. Remove sections that don't apply.

Convention notes (per .github/copilot-instructions.md and AGENTS.md):
  - en-GB spelling (analyse, behaviour, customise, prioritise)
  - No em-dashes (—) in new prose; hyphens or parenthetical phrasing instead
  - No AI / LLM references in commit messages or PR descriptions
  - No Co-Authored-By trailers for AI tools
-->

## Summary

<!--
One or two paragraphs. What does this PR do, and why?

If it adds new content (rule, hunting query, watchlist, playbook,
etc.), name the threat scenario / use case. If it changes pipeline
behaviour, mention which platforms (GitHub / ADO / both).
-->

## Type of change

<!-- Check all that apply -->

- [ ] feat — new capability
- [ ] fix — bug fix
- [ ] refactor — restructure without behavioural change
- [ ] perf — measurable performance improvement
- [ ] docs — documentation only
- [ ] test — Pester / schema test changes
- [ ] chore — dependency bump, version pin, file rename
- [ ] ci — workflow / pipeline change
- [ ] tune — analytical-rule threshold / severity / filter change

## Files changed (high level)

<!--
Bullet list of the meaningful changes, grouped logically.
Don't paste a `git diff --stat`; describe intent.

Example:
- AnalyticalRules/AzureActivity/<Name>.yaml — new rule for <scenario>
- dependencies.json — regenerated to include the new rule
- Tests/Test-X.Tests.ps1 — added one assertion for <case>
-->

## Pre-merge checklist

<!--
The PR-validation gate enforces most of these automatically; tick
them when you've confirmed locally so reviewers know what was run.
-->

- [ ] **Pester suite** passes locally (`./Scripts/Invoke-PRValidation.ps1 -RepoPath .`)
- [ ] **Bicep build** passes locally if Bicep changed (`az bicep build --file Bicep/main.bicep --stdout > /dev/null`)
- [ ] **`dependencies.json` regenerated** if KQL content changed (`./Scripts/Build-DependencyManifest.ps1 -Mode Generate`)
- [ ] **Cross-platform parity** maintained if pipelines/workflows changed (ADO + GitHub both updated)
- [ ] **Path-scoped instructions** still match the touched content type's schema
- [ ] **No secrets** in committed files (env vars, hardcoded tokens, connection strings)
- [ ] **Commit messages** follow conventional-commit format (type(scope): subject + detailed body)
- [ ] **Documentation** updated if the change affects user-visible behaviour

## Testing

<!--
What did you do to confirm the change works?

For schema changes: which Pester suite did you run?
For pipeline changes: did you `workflow_dispatch` smoke test before
relying on the schedule?
For deploy-script changes: did you run with -WhatIf against a real
workspace? Which one?
-->

## Required PR-validation status checks

<!--
The Main Branch Protection ruleset requires these five checks. They
run automatically when you open the PR. None should be skipped without
explicit reviewer agreement.
-->

- `validate` — Pester suite under Tests/
- `bicep-build` — `az bicep build` against Bicep/**/*.bicep
- `arm-validate` — Test-AzResourceGroupDeployment -WhatIf for playbooks (OIDC)
- `kql-validate` — Microsoft.Azure.Kusto.Language parser across all queries
- `dependency-manifest` — dependencies.json drift gate

## Related

<!--
Issues this PR closes (Fixes #N), companion PRs, supporting docs,
external links.

If this PR is one of several supporting a larger feature, link the
others.
-->

---

<!--
Reminder: when you squash-and-merge, GitHub will use the PR title
as the squashed commit message. Make sure the title follows
conventional-commit format too:

  feat(rules): add SuccessfulSigninFromTorExitNode

  fix(deploy): suppress Boolean leak from Dictionary.Remove

  refactor(ci): adopt azure-login-oidc composite at every call site
-->
