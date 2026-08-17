---
name: signin-failure-triage
description: Turn a raw sign-in failure spike into a triaged summary - password spray, credential stuffing or a broken service account.
argument-hint: <workspace ID> [hours to look back]
agent: agent
---

# Sign-in failure triage

**Demonstrates:** `query_lake` doing analyst work, not just retrieval. The model has to
separate three failure shapes that look identical in a count-by-hour chart.

## Prerequisites

- Data exploration collection connected
- `SigninLogs` in the lake (`AADNonInteractiveUserSignInLogs` improves it)

## Prompt

```text
Using workspace ID ${input:workspaceId}, find sign-in failures in the last
${input:hours:24} hours and give me a triaged summary.

Do not just count failures. Classify what you find into these shapes and tell me which
ones are actually present:
- Password spray: many accounts, few attempts each, from a small set of source IPs
- Credential stuffing: many accounts, many attempts, wide IP spread
- A single account under brute force
- A broken service account or expired credential looping

For each shape you find, give me the accounts involved, the source IPs and countries, the
Entra error codes, and whether any attempt eventually succeeded.

Treat these error codes as success: 0, 50125, 50140, 70043, 70044. Everything else is a
failure. A null error code is a failure, not a success.

End with a single sentence: which of these, if any, would you wake someone up for?
```

## Follow-ups

```text
For any account that failed repeatedly and then succeeded, show me exactly what happened
after the successful sign-in. Did the session do anything?
```

```text
Compare this 24 hour window against the same window seven days ago. Is this volume actually
abnormal for us, or is it Tuesday?
```

## What good looks like

- A classification, not a table of counts. If you only get counts, push with
  "which shape is this, and what evidence rules out the others?"
- Correct handling of the success codes. The model should not report `50125`
  (sign-in interrupted) as a failure.
- The "would you wake someone up" answer should be a defensible no on most tenants.

## Demo notes

- The explicit error-code list is deliberate. Without it the model tends to treat
  `ResultType != 0` as failure, which over-counts by a wide margin on real tenants.
- The seven-day comparison follow-up is the one that lands with SOC managers. It shows
  the lake making "is this normal for us" a one-line question.
