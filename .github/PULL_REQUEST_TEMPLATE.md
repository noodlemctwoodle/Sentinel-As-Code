<!--
Thanks for contributing to Sentinel-As-Code. This template is checked
automatically by the "PR Template Validation" status check. Sections
marked (required) MUST contain real content or the check fails and the
PR cannot merge. Replace the guidance in each comment with your own
words; do not delete the required headings. Optional sections can be
removed if they do not apply.

What the automated check enforces:
  - Summary, Why, What does this change do?, and Testing each hold a
    real description (not just the placeholder comment).
  - At least one "Type of change" box is ticked with [x].
  - The required headings are still present.

Convention notes (per .github/copilot-instructions.md and AGENTS.md):
  - en-GB spelling (analyse, behaviour, customise, prioritise)
  - No em-dashes (—) in new prose; hyphens (-) or parenthetical phrasing instead
  - No AI / LLM references in commit messages or PR descriptions
  - No Co-Authored-By trailers for AI tools
-->

## Summary

<!--
(required) One or two sentences: what does this PR deliver, in plain
terms? Keep it short - the detail goes in the sections below.
-->

## Why is this change needed?

<!--
(required) The motivation. What problem, gap, risk, or request drove
this change? What was wrong, missing, or painful before it?

For new detection content, name the threat scenario / use case and why
it matters. For a pipeline change, say what was failing or fragile.
Link the issue / incident / request if there is one.
-->

## What does this change do?

<!--
(required) Describe the change itself. What did you actually add or
alter, and how does it work? Mention the approach or design decision
if it is not obvious from the diff.

For content, name the table(s) / data source the query drives off. For
pipeline changes, say which platforms are touched (GitHub / ADO / both).
-->

## What does this fix or affect?

<!--
Optional. Bugs fixed, issues closed (use "Fixes #123"), behaviour that
changes, and anything downstream that is impacted. Call out breaking
changes loudly. Write "No behavioural change" if that is the case.
-->

## Type of change

<!-- (required) Tick at least one box with [x]. -->

- [ ] feat - new capability
- [ ] fix - bug fix
- [ ] refactor - restructure without behavioural change
- [ ] perf - measurable performance improvement
- [ ] docs - documentation only
- [ ] test - Pester / schema test changes
- [ ] chore - dependency bump, version pin, file rename
- [ ] ci - workflow / pipeline change
- [ ] tune - analytical-rule threshold / severity / filter change

## Files changed (high level)

<!--
Optional. Bullet list of the meaningful changes, grouped logically.
Don't paste a `git diff --stat`; describe intent.

Example:
- AnalyticalRules/AzureActivity/<Name>.yaml - new rule for <scenario>
- dependencies.json - regenerated to include the new rule
- Tests/Test-X.Tests.ps1 - added one assertion for <case>
-->

## Pre-merge checklist

<!--
The PR-validation gate enforces most of these automatically; tick
them when you've confirmed locally so reviewers know what was run.
-->

- [ ] **Pester suite** passes locally (`./Tools/Invoke-PRValidation.ps1 -RepoPath .`)
- [ ] **Bicep build** passes locally if Bicep changed (`az bicep build --file Infra/sentinel/main.bicep --stdout > /dev/null`)
- [ ] **`dependencies.json` regenerated** if KQL content changed (`./Tools/Build-DependencyManifest.ps1 -Mode Generate`)
- [ ] **Cross-platform parity** maintained if pipelines/workflows changed (ADO + GitHub both updated)
- [ ] **Path-scoped instructions** still match the touched content type's schema
- [ ] **No secrets** in committed files (env vars, hardcoded tokens, connection strings)
- [ ] **Commit messages** follow conventional-commit format (type(scope): subject + detailed body)
- [ ] **Documentation** updated if the change affects user-visible behaviour

## Testing

<!--
(required) What did you do to confirm the change works?

For schema changes: which Pester suite did you run?
For pipeline changes: did you `workflow_dispatch` smoke test before
relying on the schedule?
For deploy-script changes: did you run with -WhatIf against a real
workspace? Which one?
-->

## Required PR-validation status checks

<!--
The Main Branch Protection ruleset requires these checks. They run
automatically when you open the PR. None should be skipped without
explicit reviewer agreement.
-->

- `template` - PR description matches the template (this file)
- `validate` - Pester suite under Tests/
- `bicep-build` - `az bicep build` against Infra/**/*.bicep
- `arm-validate` - Test-AzResourceGroupDeployment -WhatIf for playbooks (OIDC)
- `kql-validate` - Microsoft.Azure.Kusto.Language parser across all queries
- `dependency-manifest` - dependencies.json drift gate

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
