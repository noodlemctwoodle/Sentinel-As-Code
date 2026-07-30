---
name: analyze-user-entity
description: One-click user verdict from the entity analyzer - the "is this account compromised?" beat.
argument-hint: <Entra object ID> <workspace ID>
agent: agent
---

# Analyse a user entity

**Demonstrates:** `analyze_user_entity` plus `get_entity_analysis`. This is the tool that
replaces twenty minutes of manual context gathering with a single call, and it is the
easiest beat to land with a SOC audience.

## Prerequisites

- Data exploration collection connected
- **Security Copilot Contributor** role. This tool consumes Security Compute Units (SCUs),
  unlike the rest of the data exploration collection.
- Required tables in the lake: `AlertEvidence`, `SigninLogs`, `CloudAppEvents`,
  `IdentityInfo`. The tool errors and names what is missing if any are absent.
- Better with `AADNonInteractiveUserSignInLogs` and `BehaviorAnalytics`, but works without.

## Prompt

```text
Analyse the user with Microsoft Entra object ID ${input:objectId} in workspace
${input:workspaceId}.

Use an analysis window of the last seven days.

Start the analysis, then poll for the result until it completes. If the first poll times
out, poll again rather than giving up.

Render the results as returned exactly from the tool. Do not summarise, re-rank or
reformat the analyzer's verdict.
```

## Follow-ups

```text
Now, in your own words, tell me what a tier 1 analyst should do in the next ten minutes
based on that verdict. Be specific about the action, not the theory.
```

```text
Which single piece of evidence in that analysis is doing the most work? If it turned out
to be wrong, would the verdict change?
```

## What good looks like

- A verdict with supporting insights: authentication patterns, behavioural anomalies,
  organisational activity.
- The raw analyzer output, not a paraphrase. If the model summarises anyway, that is the
  cue to point at the `render the results as returned exactly from the tool` line.
- The analysis takes a couple of minutes. Talk over it.

## Demo notes

- **Entra object ID, not UPN.** On-premises-only Active Directory users are not supported.
- **Seven days is the maximum window.** Longer windows are rejected; the cap exists to
  protect accuracy.
- Run at most five analyses concurrently. Beyond that, latency climbs and you risk hitting
  preview thresholds mid-demo.
- Have the object ID on your clipboard before you start. Hunting for it live kills the
  pace, and this is a prompt where the pause is already long enough.
- This is the only data-exploration prompt in the book that costs SCUs. Worth saying out
  loud if cost governance is in the room.
