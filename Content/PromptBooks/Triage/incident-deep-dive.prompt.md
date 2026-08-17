---
name: incident-deep-dive
description: Take one incident apart - alerts, evidence, entities - and reach a defensible verdict.
argument-hint: <incident ID>
agent: agent
---

# Incident deep dive

**Demonstrates:** `GetIncidentById`, `ListAlerts`, `GetAlertByID` and the hunting tools
chained into one investigation. Run this straight after
[incident-queue-triage](incident-queue-triage.prompt.md) on whatever it ranked first.

## Prerequisites

- Triage collection connected
- An incident ID worth investigating

## Prompt

```text
Investigate incident ${input:incidentId} end to end.

1. Pull the incident with its alert data.
2. For every alert in it, pull the full alert detail including evidence entities.
3. Build me a single timeline of what happened, in order, with timestamps.
4. List every entity involved - users, devices, files, IPs, URLs - and say which ones are
   confirmed malicious, which are suspicious, and which are almost certainly benign.
5. Give me a verdict: true positive, false positive, or benign true positive. Commit to
   one and justify it.

If the evidence does not support a confident verdict, say what specific extra data you
would need. Do not pad a weak conclusion.
```

## Follow-ups

```text
Look up the advanced hunting table schemas you need, then run a hunting query to find any
other device or user that interacted with the entities from this incident in the last
seven days. Has this spread?
```

```text
Write the incident summary I would paste into the ticket. Analyst audience, no marketing
language, under 200 words, and lead with the verdict.
```

```text
If this is a true positive, what is the containment action and what is the blast radius of
taking it? I want to know what breaks if we isolate that device.
```

## What good looks like

- The model runs `FetchAdvancedHuntingTablesDetailedSchema` before writing hunting KQL.
  Skipping that step is the documented cause of malformed queries.
- A timeline with real timestamps, not "then the attacker moved laterally".
- A committed verdict. Hedging across all three options is the failure mode to push back on.

## Demo notes

- The ticket-summary follow-up is the one non-technical stakeholders react to. Keep it in.
- If the spread query returns nothing, that is a good outcome and worth narrating as
  containment already holding, rather than skipping past it.
