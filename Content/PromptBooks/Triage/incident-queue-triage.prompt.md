---
name: incident-queue-triage
description: Point the model at the incident queue and make it argue for what to work first.
argument-hint: [number of incidents]
agent: agent
---

# Incident queue triage

**Demonstrates:** `ListIncidents` plus `GetIncidentById`. The opening beat for the triage
collection, and the one that maps most directly onto what a tier 1 analyst does at 09:00.

## Prerequisites

- Triage collection connected (`https://sentinel.microsoft.com/mcp/triage`)
- Microsoft Defender XDR, Defender for Endpoint, or Sentinel onboarded to the Defender portal
- Your own tenant. Guest and delegated access are not supported by this collection.

## Prompt

```text
List the last ${input:count:10} incidents in my tenant, newest first, and include the
underlying alert data.

Then triage them for me. Give me a ranked list, most urgent first, and for each incident:
- incident ID and title
- severity as assigned, and severity as YOU would assign it
- the entities involved
- one sentence on what is actually happening
- work it now / work it today / close it

Where your severity differs from the assigned severity, say why. That disagreement is the
interesting part.

Finish with the single incident you would hand to an analyst first, and what you would
tell them to check.
```

## Follow-ups

```text
Show me every incident currently sitting in New status that is more than 48 hours old.
Anything in there that should have been escalated?
```

```text
Of the incidents you would close, pick the one you are least confident about and argue the
opposite case. What would change your mind?
```

## What good looks like

- A ranking that does not simply mirror the assigned severity. If it does, the model is
  reading the severity field rather than the evidence.
- At least one disagreement with the assigned severity, with a stated reason.
- The "argue the opposite case" follow-up should produce a real counter-argument, not a
  hedge.

## Demo notes

- This collection cannot query the data lake. If you want long-history context mid-triage,
  switch to the data exploration collection - see
  [risky-user-hunt](../DataExploration/risky-user-hunt.prompt.md).
- You cannot choose a workspace with the triage tools. If your tenant has several, you get
  what you get.
- A quiet queue makes for a flat demo. Check you have ten incidents with real alert
  evidence before you present, and drop the count if not.
