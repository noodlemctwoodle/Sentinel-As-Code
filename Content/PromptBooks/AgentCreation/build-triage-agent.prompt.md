---
name: build-triage-agent
description: Describe an agent in English and walk it through to a deployable Security Copilot definition.
argument-hint: <what the agent should do>
agent: agent
---

# Build a Security Copilot agent

**Demonstrates:** the full agent-creation chain - `search_for_tools`,
`start_agent_creation`, `compose_agent`, `get_evaluation`, `deploy_agent`.

The story is that SOC engineers spend weeks hand-building playbooks. This beat compresses
that to a conversation. Budget ten minutes; it is genuinely iterative and rushing it
undersells the point.

## Prerequisites

- Agent creation collection connected
  (`https://sentinel.microsoft.com/mcp/security-copilot-agent-creation`)
- **Microsoft Security Copilot** provisioned. This collection needs it, unlike the other two.
- Decide beforehand whether you will actually deploy, and to `User` or `Workspace` scope.

## Prompt

```text
I want to build a Security Copilot agent that does this:

${input:intent}

Work through it properly:
1. Search Security Copilot for tools, skills and agents that could serve this intent. Show
   me what you found and which ones you plan to use.
2. Start a new agent creation session with my problem statement.
3. Compose the agent definition YAML.
4. Retrieve the evaluation and show me the result.

Do NOT deploy anything yet. Show me the YAML and stop.

If you need decisions from me - trigger conditions, output format, which data sources -
ask rather than assuming. I would rather answer three questions than review a wrong agent.
```

## Follow-ups

```text
Walk me through that YAML section by section. What does each part actually do at runtime?
```

```text
Revise it: ${input:revision}. Keep the same session and edit the existing definition
rather than starting over.
```

```text
What would this agent do badly? Give me the failure modes before I deploy it, not after.
```

```text
Deploy it to User scope. The skillset name must exactly match the Name under Descriptor
in the definition YAML - confirm they match before you deploy.
```

## What good looks like

- The model asks clarifying questions on the first pass. An agent composed with no
  questions asked is usually an agent built on assumptions.
- Readable YAML with a clear descriptor, tool list and instructions.
- The failure-modes follow-up should produce real ones. If it says the agent is fine, push
  harder - that is the reviewer instinct you want to demonstrate.

## Demo notes

- Pass `compose_agent` the session ID from `start_agent_creation`, not the one from
  `search_for_tools`. They are different sessions and mixing them is the documented
  mistake.
- Deploying is a real change to your Security Copilot workspace. Use `User` scope for a
  demo unless you have decided otherwise.
- If you have an existing agent YAML, add it to the chat context and the compose step will
  edit it rather than generating from scratch. That is a better demo for an audience that
  already has agents.
