---
name: retro-hunt-ioc-sweep
description: Sweep an IOC set across the full lake history - the retention story that the analytics tier cannot tell.
argument-hint: <workspace ID>
agent: agent
---

# Retro-hunt IOC sweep

**Demonstrates:** the data lake's actual differentiator. The analytics tier is cost-bound
to roughly ninety days. The lake holds up to twelve years. A fresh threat report drops and
you can ask "have we ever seen this?" instead of "have we seen this recently?".

This is the conversational twin of
[`demo13_retrohunt_ioc_sweep.ipynb`](../../SparkNotebooks/demos/demo13_retrohunt_ioc_sweep.ipynb).
Run the notebook when you want to show the engineering; run this when you want to show the
speed.

## Prerequisites

- Data exploration collection connected
- `DeviceNetworkEvents`, `DeviceFileEvents` or `DeviceProcessEvents` in the lake

## Prompt

```text
Using workspace ID ${input:workspaceId}, sweep the following indicators across the FULL
history available in the data lake. Do not restrict to the last 30 or 90 days - the whole
point of this exercise is the long tail.

File hashes (SHA256):
${input:hashes}

IP addresses:
${input:ips}

Domains or URLs:
${input:domains}

For every indicator that hits, give me:
- indicator and type
- first seen and last seen (full timestamps)
- total hit count
- how many distinct devices
- which table it came from

Sort by first seen, oldest first. Explicitly list the indicators that did NOT hit - a
clean sweep is a result, not an empty response.

Before you query, check which of the Device tables actually exist in this workspace and
tell me which ones you are sweeping.
```

## Follow-ups

```text
Take the indicator with the earliest first-seen date. Reconstruct what happened on that
device around that timestamp - processes, network, logons - and tell me whether this was
the initial foothold.
```

```text
How far back does our data actually go for each of these tables? If an indicator shows no
hits, I want to know whether that means "clean" or "we have no data from that period".
```

## What good looks like

- The model checks table availability before sweeping, rather than assuming.
- Explicit no-hit reporting. The most common demo failure is a confident-sounding empty
  response that the audience reads as "clean".
- First-seen dates meaningfully older than ninety days. If everything is recent, the
  retention story does not land and you should pick different indicators.

## Demo notes

- The last follow-up is the honest one and it is worth keeping. "No hits" and "no data"
  are different answers, and an audience that has been burned by a SIEM will ask.
- Keep the indicator list short, five to ten. A long list makes the sweep slow without
  making the point any better.
- If you have no known-bad indicators, use ones from a public threat report and expect a
  clean sweep. Narrate it as the good outcome, because it is.
