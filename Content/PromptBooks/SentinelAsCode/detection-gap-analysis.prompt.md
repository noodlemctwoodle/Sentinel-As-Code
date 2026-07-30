---
name: detection-gap-analysis
description: Compare what this repo detects against what the lake actually shows - find the coverage you think you have.
argument-hint: <workspace ID> [MITRE tactic to focus on]
agent: agent
---

# Detection gap analysis

**Demonstrates:** MCP reading your detection library and your telemetry together, and
telling you where they disagree. The closing beat for a technical audience.

Three kinds of gap, and they need different fixes:

1. **Data you have, detection you do not** - the fixable gap
2. **Detection you have, data you do not** - the false-confidence gap, and the dangerous one
3. **Neither** - the honest gap, which is a roadmap item

## Prerequisites

- Data exploration collection connected
- This repository open in VS Code

## Prompt

```text
Compare this repository's detection coverage against what my data lake actually contains,
for workspace ${input:workspaceId}.

1. Read every rule under Content/AnalyticalRules/ and every query under
   Content/HuntingQueries/. Build a picture of what tables and MITRE techniques we cover.

2. Search my lake's table catalogue for what data I actually have.

3. Produce three lists:
   - Tables with meaningful data that NO rule or hunting query touches
   - Rules or queries referencing tables that are absent or empty in my lake
   - MITRE techniques with neither coverage nor the data to build it

${input:focus}

For the first list, rank by how much detection value the table would unlock, not by row
count. A high-volume table nobody should alert on is not a gap.

Be specific about what you could not determine, and why.
```

## Follow-ups

```text
Take the top three uncovered tables. For each, propose one concrete detection and show me
the KQL. Query the lake first to confirm the pattern actually exists in my data.
```

```text
For rules referencing absent tables: is the fix to onboard a connector, or to delete a
rule that was never going to fire here? Give me a recommendation per rule, not a list of
options.
```

```text
Which single data source, if onboarded, would close the most technique gaps?
```

## What good looks like

- Three genuinely distinct lists. Collapsing them into "gaps" loses the whole point.
- The false-confidence list is the uncomfortable one and usually the most valuable.
- The "single data source" answer should name one connector with a defensible reason.

## Demo notes

- The false-confidence gap is the finding that changes behaviour. A rule referencing a
  table with no data is worse than no rule at all, because it appears on the coverage
  dashboard as green.
- Pairs with [`demo18_mitre_attack_coverage.ipynb`](../../SparkNotebooks/demos/demo18_mitre_attack_coverage.ipynb),
  which renders the same idea as a tactic-by-technique heatmap. Run the notebook for the
  picture, this prompt for the reasoning.
- Use the `${input:focus}` argument to scope to one tactic when time is short. A full sweep
  across the whole library takes a while and the audience stops reading.
