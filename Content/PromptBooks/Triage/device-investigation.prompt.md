---
name: device-investigation
description: Everything known about one endpoint - health, alerts, users, vulnerabilities, remediation state.
argument-hint: <device ID>
agent: agent
---

# Device investigation

**Demonstrates:** `GetDefenderMachine`, `GetDefenderMachineAlerts`,
`GetDefenderMachineLoggedOnUsers`, `GetDefenderMachineVulnerabilities` and
`ListDefenderRemediationActivities` assembled into a single endpoint picture.

The manual version of this is five portal tabs. That contrast is the demo.

## Prerequisites

- Triage collection connected
- A Defender for Endpoint device ID

## Prompt

```text
Give me the complete picture of device ${input:deviceId}.

Pull all of the following and present it as one briefing, not five tool dumps:
- Device details: OS, health status, risk score, exposure level
- Every security alert associated with it
- Every account that has signed in to it
- Discovered vulnerabilities with CVE IDs and severity
- Any remediation tasks targeting it, and their status

Then tell me:
- Is this device currently compromised, previously compromised, or clean?
- What is the highest-risk thing about it right now - and is that a vulnerability, an
  alert, or a user?
- What is the single next action?

Where the risk score and the actual evidence disagree, say so.
```

## Follow-ups

```text
Take the highest-severity CVE on this device. Which other devices in my tenant are
affected by it? I want the patch-priority picture, not just this one box.
```

```text
For the accounts that signed in here, pull their related alerts. Is this device the
problem, or is a user carrying the problem between devices?
```

## What good looks like

- One briefing, not five sections of raw tool output. If you get the latter, the
  "present it as one briefing" instruction needs to be firmer.
- The risk-score-versus-evidence disagreement is usually the most interesting line in the
  answer. A high exposure score driven entirely by unpatched software is a different
  conversation from one driven by active alerts.
- The device-versus-user follow-up reframes the investigation, and it is where lateral
  movement usually shows up.

## Demo notes

- Pick a device with some history. A freshly imaged laptop produces an accurate and very
  boring answer.
- The CVE fan-out uses `ListDefenderMachinesByVulnerability` and is the natural handover
  into [cve-exposure-sweep](cve-exposure-sweep.prompt.md) if you are running both.
