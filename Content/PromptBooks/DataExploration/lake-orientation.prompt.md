---
name: lake-orientation
description: Opening demo beat - list data lake workspaces, then discover which tables actually hold the signal you need.
argument-hint: <what you want to find, e.g. "identity risk and sign-in anomalies">
agent: agent
---

# Lake orientation

**Demonstrates:** `list_sentinel_workspaces` then `search_tables`. The point of this beat
is that nobody has to know the schema any more - you describe the signal in English and
the model finds the tables.

**Run this first.** Every other data-exploration prompt in this book assumes you already
know your workspace ID.

## Prerequisites

- Data exploration collection connected (`https://sentinel.microsoft.com/mcp/data-exploration`)
- Security Reader, Security Operator or Security Administrator
- Workspace onboarded to the Microsoft Sentinel data lake

## Prompt

```text
List every Microsoft Sentinel data lake workspace I have access to, with the workspace
name and ID for each.

Then, for the workspace I am most likely to be demoing against, search the table catalogue
for tables relevant to: ${input:signal:identity risk and sign-in anomalies}

For each table you find, give me:
- the table name
- one sentence on what it holds
- the three or four columns I would actually pivot on

Do not run any queries yet. Just show me the map.
```

## Follow-ups

```text
Now show me the full schema for the two tables you rated most useful, and tell me which
one is the better starting point for a hunt and why.
```

```text
Which of those tables are lake-tier only, and which are also in the analytics tier? If you
cannot tell from the catalogue, say so rather than guessing.
```

## What good looks like

- A list of workspaces with real IDs (not placeholders).
- Four to eight tables, typically including `SigninLogs`, `AADUserRiskEvents`,
  `BehaviorAnalytics` and `AADNonInteractiveUserSignInLogs` for the default input.
- No KQL executed. If the model jumps straight to `query_lake`, that is a talking point
  about tool scoping, not a failure.

## Demo notes

- If `list_sentinel_workspaces` returns nothing useful, or you need the system tables
  database, add `Use 'default' as the workspaceId.` to the prompt.
- Note the workspace ID out loud and paste it into later prompts. The documented failure
  mode is tools silently picking a different workspace between turns.
- Ask the audience to name a signal and re-run the search live. It holds up better than
  the scripted input and takes about fifteen seconds.
