---
name: post-incident-report-agent
description: Microsoft's own headline agent-creation scenario - a cross-product post-incident report agent.
argument-hint: (no arguments)
agent: agent
---

# Post-incident report agent

**Demonstrates:** agent creation on the scenario Microsoft uses as its own example, so it
is the one most likely to compose cleanly on stage. Use this when you want the beat to
work rather than to explore.

Run [build-triage-agent](build-triage-agent.prompt.md) first if you want to show the
iterative conversation; run this one if you want the polished result.

## Prerequisites

- Agent creation collection connected
- Microsoft Security Copilot provisioned
- Ideally Defender, Purview and Sentinel incidents present, since the agent spans all three

## Prompt

```text
Create an agent that generates a comprehensive post-incident report from Microsoft
Defender, Microsoft Purview, and Microsoft Sentinel incidents; aggregates incident
summaries, detailed insights, entities, and alerts; and provides actionable remediation
steps.

Search for the relevant tools first, then start the session and compose the definition.
Show me the evaluation result.

Stop before deploying.
```

## Follow-ups

```text
Add a section to the report that names the detection gap: what would have caught this
earlier, and did we have the data to catch it?
```

```text
Constrain the output to two pages. A post-incident report nobody reads has no value.
```

```text
Who is the audience for this report - analyst, SOC manager, or exec? Rewrite the
instructions so it is unambiguously written for a SOC manager.
```

## What good looks like

- Tool discovery finds Defender, Purview and Sentinel incident skills.
- A definition with distinct sections for summary, entities, alerts and remediation.
- The detection-gap follow-up is the one worth keeping. It turns a reporting agent into a
  feedback loop, and it is the natural bridge to
  [detection-gap-analysis](../SentinelAsCode/detection-gap-analysis.prompt.md).

## Demo notes

- Verbatim from Microsoft's documentation, so if this one fails to compose you have an
  environment problem rather than a prompt problem. Useful as a diagnostic.
- The two-page constraint gets a laugh from anyone who has read a real post-incident
  report. Keep it.
