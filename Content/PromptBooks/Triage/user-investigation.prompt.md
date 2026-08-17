---
name: user-investigation
description: User-centric view - their alerts, their devices, and whether they are the target or the vector.
argument-hint: <user account ID>
agent: agent
---

# User investigation

**Demonstrates:** `ListUserRelatedAlerts` and `ListUserRelatedMachines`, plus hunting
queries to close the gaps. The counterpart to
[device-investigation](device-investigation.prompt.md): same investigation, pivoted on the
person instead of the box.

## Prerequisites

- Triage collection connected
- A user account ID

## Prompt

```text
Investigate the user account ${input:userId}.

Pull:
- Every security alert associated with this account
- Every device where they have active or recent sign-in sessions

Then work out which of these this is:
- The user is the TARGET (someone is attacking them)
- The user is the VECTOR (their account is being used to attack others)
- The user is the CAUSE (risky behaviour, not malice)
- Nothing is wrong (the alerts are noise)

Commit to one and give me the evidence. If the device list is wider than you would expect
for one person's role, flag it.
```

## Follow-ups

```text
Look up the advanced hunting schemas you need, then run a hunting query showing this
user's activity across all their devices in the last seven days, ordered by time. I want
to see whether the activity follows the user or stays with one device.
```

```text
Compare this user's device list against what you would expect for their role. Which of
these devices should they not be signing in to?
```

```text
If this account is compromised, which of those devices is the attacker most likely sitting
on right now, and why that one?
```

## What good looks like

- A committed classification. Target, vector, cause and noise call for four different
  responses, and refusing to choose is the unhelpful answer.
- The activity-follows-user-or-device distinction from the first follow-up is the single
  most useful output here.
- An honest "nothing is wrong" where that is true.

## Demo notes

- Works best on an account with a handful of alerts. A completely clean user gives you
  nothing to reason about; an account drowning in alerts buries the narrative.
- The triage collection cannot reach the data lake, so ninety-plus-day history is not
  available here. If someone asks for the long baseline, that is the cue to switch to
  [analyze-user-entity](../DataExploration/analyze-user-entity.prompt.md), which reasons
  over lake data instead.
