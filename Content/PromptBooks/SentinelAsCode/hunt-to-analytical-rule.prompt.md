---
name: hunt-to-analytical-rule
description: Turn a lake finding into a committed analytics rule - the beat that closes the loop back into this repo.
argument-hint: <workspace ID> <what you found>
agent: agent
---

# Hunt to analytical rule

**Demonstrates:** the whole point of running these demos in *this* repo. Hunt in the lake
with MCP, then commit the finding as version-controlled detection content. Ad-hoc hunt
becomes standing coverage, in one conversation.

Run this immediately after
[risky-user-hunt](../DataExploration/risky-user-hunt.prompt.md) or
[signin-failure-triage](../DataExploration/signin-failure-triage.prompt.md), while the
finding is still on screen.

## Prerequisites

- Data exploration collection connected
- This repository open in VS Code

## Prompt

```text
I found this in the data lake (workspace ${input:workspaceId}):

${input:finding}

Turn it into an analytics rule for this repository.

1. Validate it first. Query the lake to confirm the pattern is real, and tell me roughly
   how many times it would have fired over the last 30 days. If that number is absurd, say
   so and tighten the logic before we go any further.

2. Read .github/instructions/analytical-rules.instructions.md and
   .github/instructions/kql-queries.instructions.md so you follow this repo's schema
   rather than a generic one.

3. Look at two or three existing rules under Content/AnalyticalRules/ to match the house
   style.

4. Write the rule to Content/AnalyticalRules/<SourceFolder>/<RuleName>.yaml. Generate a
   fresh GUID for the id. Pick the source folder from the primary data table.

5. Regenerate the dependency manifest and run the schema tests:
   ./Tools/Build-DependencyManifest.ps1 -Mode Generate
   Invoke-Pester -Path Tests/Test-AnalyticalRuleYaml.Tests.ps1
   Invoke-Pester -Path Tests/Test-DependencyManifest.Tests.ps1

Do not commit. Show me the rule and the test output.
```

## Follow-ups

```text
That fire count is too high. Tighten it without losing the true positives - and tell me
explicitly what class of detection I am giving up.
```

```text
Add entityMappings for every column that should become a Sentinel entity. Without those
the alerts will not correlate into incidents properly.
```

```text
Write the entity mappings and then query the lake to prove every mapped column is
populated. A mapping to a mostly-null column is worse than no mapping.
```

## What good looks like

- The 30-day fire count comes back *before* any YAML is written. A rule authored without
  it is a rule nobody will keep enabled.
- The YAML uses `enabled: true|false`, not `status:`, and PascalCase tactics. Those are
  the two schema mistakes generic models make against this repo.
- Both Pester test files pass.
- The last follow-up catches null-heavy entity mappings, which is the same class of bug as
  the null-key problem in the Spark notebooks.

## Demo notes

- This is the beat that differentiates a Sentinel-As-Code demo from a Sentinel MCP demo.
  The finding does not evaporate when the chat window closes - it becomes a pull request.
- If the audience is engineering-heavy, run `git diff` afterwards. A reviewable diff is a
  more persuasive artefact than any chat transcript.
- The fire-count validation step is what separates this from a rule generator. Keep it in
  even when time is tight.
