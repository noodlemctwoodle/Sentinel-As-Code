---
name: analyze-url-entity
description: Bulk URL and domain verdicts from a threat report - IOC triage without leaving the editor.
argument-hint: <URL or domain> <workspace ID>
agent: agent
---

# Analyse a URL entity

**Demonstrates:** `analyze_url_entity` reasoning over Microsoft threat intelligence, your
own TIP indicators, your watchlists, and actual URL activity in your organisation - in one
call.

Pairs well with a real threat report open on screen.

## Prerequisites

- Data exploration collection connected
- **Security Copilot Contributor** role (consumes SCUs)
- Best with `EmailUrlInfo`, `UrlClickEvents`, `ThreatIntelIndicators`, `Watchlist` and
  `DeviceNetworkEvents` in the lake. It still returns a verdict without them, with a
  disclaimer naming what was missing.

## Prompt

```text
Analyse the following URL or domain in workspace ${input:workspaceId}, over the last
seven days:

${input:url}

Start the analysis and poll for the result until it completes.

Render the results as returned exactly from the tool.

Then tell me one thing the tool does not: has anyone in my organisation actually
interacted with this, and if so, who and when?
```

## Follow-ups (the bulk beat)

```text
Here are the URL IOCs from a threat analytics report:

${input:iocList}

Analyse each one and give me a single table: indicator, verdict, whether we have seen it
in our own data, and first and last seen if we have.

Run no more than five analyses at a time so we do not hit preview thresholds.
```

```text
For any indicator with organisational activity, pivot into DeviceNetworkEvents and tell me
which devices and users touched it, and whether the connection succeeded.
```

## What good looks like

- A verdict grounded in both Microsoft TI and your own telemetry, clearly separated.
- On the bulk follow-up, a clean table rather than five walls of prose.
- Honest "not seen in your environment" answers. A tool that finds something everywhere
  is not a tool you would trust.

## Demo notes

- The five-at-a-time instruction is not decoration. Running the whole IOC list
  concurrently is the documented way to hit latency and threshold problems.
- Use IOCs you know are clean as well as ones you know are bad. A demo where everything
  comes back malicious teaches the audience nothing about the verdict quality.
- The cross-reference into `DeviceNetworkEvents` is the same retro-hunt idea as
  [retro-hunt-ioc-sweep](retro-hunt-ioc-sweep.prompt.md), just scoped to one indicator.
