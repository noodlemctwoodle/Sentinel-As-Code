---
name: risky-user-hunt
description: The flagship beat - find the top at-risk users and have the model explain its reasoning and its KQL.
argument-hint: <workspace ID> [number of users]
agent: agent
---

# Risky user hunt

**Demonstrates:** the full `search_tables` to `query_lake` orchestration loop. This is
Microsoft's own headline sample prompt, expanded so the model has to show its working.

The best moment in this demo is usually the model writing a KQL query, getting a semantic
error back, and correcting itself without being asked. Let that happen on screen.

## Prerequisites

- Data exploration collection connected
- Run [lake-orientation](lake-orientation.prompt.md) first to get your workspace ID

## Prompt

```text
Using workspace ID ${input:workspaceId}, find the top ${input:count:3} users that are most
at risk right now and explain why each one is at risk.

Work in this order and narrate as you go:
1. Search the table catalogue for tables covering user risk, sign-in behaviour and UEBA.
2. Tell me which tables you picked and why before you query anything.
3. Query the lake. Show me each KQL query you run.
4. For every user you surface, give me: the UPN, the specific signals that make them
   risky, when the behaviour started, and how confident you are.

Rank by actual evidence, not by whatever risk score happens to exist. If two users are
close, say so rather than inventing a tiebreak.
```

## Follow-ups

```text
Take the highest-risk user and pull their full sign-in timeline for the last seven days.
I want the source IPs, countries, applications and the success or failure outcome for
each. Flag anything that breaks their own established pattern.
```

```text
Now show me what a false positive would look like here. Which of these signals would fire
for a legitimate travelling executive, and what extra evidence would tell them apart?
```

```text
Write the KQL you would schedule as a Sentinel analytics rule to catch this pattern going
forward. Bound the time window and project a stable column set.
```

## What good looks like

- The model searches the catalogue twice: once with narrow terms, then broader.
- At least two `query_lake` calls, with the KQL visible in the response.
- Named users with per-user evidence, not a generic risk-score table dump.
- The last follow-up produces KQL you could realistically paste into
  `Content/AnalyticalRules/` (see [hunt-to-analytical-rule](../SentinelAsCode/hunt-to-analytical-rule.prompt.md)).

## Demo notes

- A quiet tenant returns thin results. Check the last seven days have sign-in volume
  before you present, and widen to thirty days in the prompt if not.
- If the model stalls picking tools, start a fresh chat. The documented cause is
  conversation context being favoured over tool invocation.
- Keep the KQL error-and-self-correct moment. Do not re-run to get a clean take - the
  recovery is the more interesting story.
