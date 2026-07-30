---
name: file-hash-investigation
description: Full file verdict - reputation, prevalence, alerts and spread - with the SHA-1 gotcha handled up front.
argument-hint: <SHA-1 hash>
agent: agent
---

# File hash investigation

**Demonstrates:** `GetDefenderFileInfo`, `GetDefenderFileStatistics`,
`GetDefenderFileAlerts` and `GetDefenderFileRelatedMachines` chained on one indicator.

**Use a SHA-1 hash.** The four file tools do not agree on hash types: `GetDefenderFileInfo`
and `GetDefenderFileStatistics` accept SHA-1 or SHA-256, but `GetDefenderFileAlerts` and
`GetDefenderFileRelatedMachines` accept **SHA-1 only**. MD5 works nowhere. Hand the model a
SHA-256 and the chain half-completes, which is a confusing thing to debug on stage.

## Prerequisites

- Triage collection connected
- A SHA-1 hash with real prevalence in your tenant

## Prompt

```text
Investigate the file with SHA-1 hash ${input:sha1}.

Chain these together and show me each result:
1. File details - hashes, size, type, publisher, signer certificate, global prevalence,
   first and last seen.
2. Organisational prevalence - how many of my devices have seen it.
3. Every alert this file has generated in my organisation, historical and active.
4. Every device that encountered it.

Then answer three questions directly:
- Is this file malicious, and how confident are you?
- Is it spreading, holding steady, or already contained?
- What do I do in the next hour?

If any tool rejects the hash, tell me which one and why rather than silently skipping it.
```

## Follow-ups

```text
For the devices that encountered this file, pull their alerts and logged-on users. Is
there a common user, a common software build, or a common network segment?
```

```text
Check whether this hash is already in our threat indicators. If it is not and you believe
it should be, tell me what indicator action you would set and at what severity.
```

## What good looks like

- All four tools complete. A partial chain almost always means a SHA-256 was supplied.
- Global prevalence and organisational prevalence reported separately. A file that is
  common worldwide and rare here is a very different story from the reverse.
- A confidence statement, not a binary verdict.

## Demo notes

- Say the SHA-1 constraint out loud. It is a real API inconsistency, and audiences who
  build automation care about it more than they care about the verdict.
- A clean file makes a duller demo but a more honest one. Signed, prevalent, no alerts is
  exactly what the tool should say about a legitimate binary.
- If you need a SHA-1 from a SHA-256, the file-details tool resolves SHA-256 to SHA-1
  internally - run that first and read the SHA-1 out of the result.
