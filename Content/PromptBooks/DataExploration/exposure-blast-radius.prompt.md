---
name: exposure-blast-radius
description: Graph tools - blast radius, attack paths and exposure perimeter in natural language.
argument-hint: <entity name, e.g. a device or critical asset>
agent: agent
---

# Exposure and blast radius

**Demonstrates:** the graph tools (`find_blastradius`, `find_walkable_paths`,
`find_exposure_perimeter`, `find_nodes`, `get_graph_context`). This is the "if this box
falls, what else falls" question, asked without writing a single graph query.

> Preview. Microsoft may change these tools substantially before release, and using them
> invokes the graph meter. Say both out loud if cost or stability is in the room.

## Prerequisites

- Data exploration collection connected
- Data lake onboarded to the **Defender portal** (graph tools require it)
- At least read-only access in Microsoft Security Exposure Management
- Critical assets classified, otherwise blast radius has nothing to aim at

## Prompt

```text
First, get the graph context so you know which node labels and properties are valid in my
graph. Show me the labels you can work with.

Then, in my graph: what is the blast radius of ${input:entity} if it were compromised?

For each propagation path you find:
- the full hop-by-hop path
- what makes each hop traversable (credential, permission, network reachability)
- which critical asset it terminates at
- the single change that would break the path

Rank the paths by how much damage they enable, not by how many hops they are.
```

## Follow-ups

```text
In my graph, list all walkable paths from ${input:entity} to my critical assets. Where a
path exists, tell me whether it is a design decision or an accident.
```

```text
In my graph, what is the exposure perimeter of my critical SQL servers? Show me the
incoming connections, limited to paths of three hops or fewer.
```

```text
Of everything you have shown me, what is the one change that removes the most paths? I
want the highest-leverage fix, not the longest list.
```

## What good looks like

- `get_graph_context` runs first. Without it the model guesses at labels and the later
  calls return nothing.
- Paths with named intermediate nodes, not a count.
- The "one change" answer should be specific and actionable. A generic "apply least
  privilege" means the graph data is too thin to be interesting.

## Demo notes

- **Say `in my graph`** in every prompt. It is the documented way to scope these tools to
  the graph rather than the lake, and it is the difference between a good answer and a
  confused one.
- **Identity lookups do not accept UPNs.** Use the display name or object ID.
- **Put the entity type before the name** when you specify one, for example
  `device zava-fin-01` rather than `zava-fin-01 device`.
- Graph tools invoke the graph meter. Unlike the rest of this collection, running them
  costs money. Keep the demo tight.
