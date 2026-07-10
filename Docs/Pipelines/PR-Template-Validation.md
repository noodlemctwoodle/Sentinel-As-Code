# PR Template Validation

A **GitHub-only** required check that fails a pull request whose description does
not fill in [`.github/PULL_REQUEST_TEMPLATE.md`](../../.github/PULL_REQUEST_TEMPLATE.md),
so reviewers always get the context they need before a PR can merge.

- Workflow: [`.github/workflows/pr-template-validation.yml`](../../.github/workflows/pr-template-validation.yml)
- Rules: [`Tools/Test-PullRequestTemplate.ps1`](../../Tools/Test-PullRequestTemplate.ps1)
  (unit-tested by `Tests/Test-PullRequestTemplate.Tests.ps1`)

## Why GitHub-only

The PR body arrives in the GitHub Actions event payload, which the workflow hands
straight to the validator. Azure DevOps has no equivalent: an ADO build-validation
policy would have to fetch the PR description over the REST API, a fundamentally
different shape, so there is intentionally no `Pipelines/` mirror of this
workflow. It is one of the two GitHub-only workflows (the other is the nightly
E2E smoke test); see the [Pipelines index](README.md#github---ado-parity).

## Triggers

`pull_request` targeting `main`, on `opened`, `edited`, `reopened`,
`synchronize`, and `ready_for_review`. The `edited` event is what lets a
contributor fix the description in the GitHub UI and watch the check turn green
without pushing a new commit; `synchronize` keeps a result present on every new
head SHA so a required-check ruleset always has a status to gate on. Runs are
de-duplicated per PR with `concurrency` (`cancel-in-progress`).

## The `template` job

Runs on `ubuntu-latest` with `contents: read` only.

1. **Skip bot-authored PRs.** The check short-circuits to success when the PR
   author is a bot (`github.event.pull_request.user.type == 'Bot'`). The
   drift-sync and dependency-manifest auto-PRs are opened with `GITHUB_TOKEN`, so
   their author is `github-actions[bot]` and they skip. The skip is a step (not a
   job-level `if`) so the job still reports success and a required-check ruleset
   is not left waiting. The head branch name is deliberately **not** trusted as a
   skip condition, so a human cannot name a branch `auto/foo` to dodge the gate.
2. **Checkout the base ref (trusted validator).** The workflow checks out the
   base commit (`github.event.pull_request.base.sha`), not the PR head, so the
   validator always runs from `main`. This stops a PR from neutering its own gate
   by editing `Test-PullRequestTemplate.ps1` in the same change. A bootstrap
   guard skips gracefully on the (historical) PR that first introduced the
   validator, where the base ref did not yet have it.
3. **Validate the description.** The PR body is passed to the validator through an
   environment variable (never interpolated into the command line, so a body
   containing shell metacharacters cannot inject anything). The validator exits
   non-zero if any required section is empty or the `Type of change` section has
   no ticked box.

## What the validator requires

A PR description passes when it keeps the template's required prose sections and
fills each with real content: **Summary**, **Why is this change needed?**, **What
does this change do?**, and **Testing** - plus at least one ticked box under
**Type of change**. Other template sections (for example "What does this fix or
affect?", "Files changed", and the pre-merge checklist) are not enforced. Run the
same rules locally with:

```powershell
./Tools/Test-PullRequestTemplate.ps1 -Body (gh pr view <number> --json body --jq .body)
```

## Wiring as a required merge gate

After the check has run once, add it to branch protection so it blocks merge:
**Repo Settings > Rules > Rulesets > Main Branch Protection > Edit > Require
status checks to pass**, then add the `template` check.

## Related

- [PR Validation](PR-Validation.md) - the five-job Pester / Bicep / ARM / KQL /
  dependency-manifest merge gate that runs alongside this one.
- [Pipelines index](README.md) - shared concepts and the GitHub/ADO parity map.
