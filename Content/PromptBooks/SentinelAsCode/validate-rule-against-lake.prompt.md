---
name: validate-rule-against-lake
description: Check a committed rule against real data - do its tables and columns exist, and would it ever fire?
argument-hint: <path to a rule YAML> <workspace ID>
agent: agent
---

# Validate a rule against the lake

**Demonstrates:** MCP as a test harness. Schema tests prove a rule is well-formed. Only
real data proves it would ever fire.

Every repo accumulates rules referencing tables nobody onboarded and columns that were
renamed two connector versions ago. This finds them.

## Prerequisites

- Data exploration collection connected
- This repository open in VS Code

## Prompt

```text
Read ${input:rulePath} and validate it against my actual data lake, workspace
${input:workspaceId}.

Check, in this order:
1. Does every table the query references exist in my workspace? Use the table catalogue.
2. Does every column the query references exist on those tables, with a compatible type?
3. Run the rule's KQL against the lake over the last 30 days. How many times would it have
   fired?
4. For every column in entityMappings, what percentage of matching rows actually have a
   value? A mapping to a mostly-null column will not correlate.

Give me a verdict per check: pass, fail, or cannot determine. "Cannot determine" is a
valid answer - do not guess to fill the table.

If the query will not run as written, show me the error and the smallest change that fixes
it.
```

## Follow-ups

```text
Do the same for every rule in Content/AnalyticalRules/${input:folder}/. One row per rule:
tables exist, columns exist, 30-day fire count, verdict. Rank worst first.
```

```text
For anything that failed, tell me whether the fix is to change the rule or to onboard a
data source. Those go to different people.
```

```text
Which of these rules has fired zero times in 30 days AND references a table with no data
at all? That is the difference between a quiet rule and a dead one.
```

## What good looks like

- Real fire counts, including zeros. A zero is information.
- Honest "cannot determine" for anything the model could not check, particularly custom
  tables and watchlist functions like `_GetWatchlist()`.
- The last follow-up separating quiet rules from dead rules. Those need different fixes and
  most coverage reviews conflate them.

## Demo notes

- Run the folder-wide sweep against a small folder first. `Content/AnalyticalRules/` as a
  whole is a lot of rules and a long wait.
- Rules using watchlist functions or parsers will often come back as "cannot determine".
  That is correct behaviour, not a gap - the lake does not resolve saved functions the way
  the analytics tier does.
- Expect to find at least one broken rule. Every repo has one, and finding it live is a
  better demo than a clean sweep.
