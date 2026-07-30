# Prompt Books - Microsoft Sentinel MCP prompts for GitHub Copilot

Reference for the 18 prompt books under [`Content/PromptBooks/`](../../Content/PromptBooks):
what each demonstrates, the MCP tools behind them, how to set them up, the running orders
for a live demo, and the failure modes worth knowing before you present.

These are demo assets, not deployable Sentinel content. Nothing here is picked up by the
deploy pipelines.

## What the Sentinel MCP server is

Microsoft Sentinel exposes scenario-focused collections of MCP tools over a hosted server,
authenticated with Microsoft Entra. Connect a compatible client (VS Code with GitHub
Copilot, Security Copilot, Copilot Studio, Microsoft Foundry) and you can query security
data in natural language without writing KQL or knowing the schema.

Three collections, three endpoints:

| Collection | Endpoint | What it does |
| --- | --- | --- |
| Data exploration | `https://sentinel.microsoft.com/mcp/data-exploration` | Search tables, query the lake, analyse entities, reason over graphs |
| Triage | `https://sentinel.microsoft.com/mcp/triage` | Incidents, alerts, Defender entity APIs, advanced hunting |
| Agent creation | `https://sentinel.microsoft.com/mcp/security-copilot-agent-creation` | Build and deploy Security Copilot agents |

## Setup

### 1. Register the MCP servers

Copy the shipped template to the git-ignored VS Code folder:

```bash
cp Content/PromptBooks/mcp.json .vscode/mcp.json
```

Reload VS Code and sign in when prompted. Alternatively, **Ctrl+Shift+P** ->
`MCP: Add Server` -> **HTTP** -> paste an endpoint URL -> give it a server ID.

`.vscode/` is git-ignored in this repo (see [`.gitignore`](../../.gitignore) line 5), which
is why the template lives under `Content/PromptBooks/` and gets copied rather than being
committed in place.

### 2. Make the prompts discoverable

Merge [`vscode-settings.snippet.json`](../../Content/PromptBooks/vscode-settings.snippet.json)
into `.vscode/settings.json`. VS Code only looks in `.github/prompts` by default, so
without `chat.promptFilesLocations` the `/slash-commands` will not appear.

If settings.json IntelliSense objects to the shape, check the Settings UI for what your VS
Code build expects. The key name is stable; the value shape has moved across releases.
Copy-paste out of the prompt files always works as a fallback.

### 3. Agent mode

MCP tools are only available in **agent mode**. Confirm with the **Configure Tools** icon
that the Sentinel servers appear with their tools listed.

## Catalogue

### Data exploration (7)

| Prompt | Tools exercised | Cost |
| --- | --- | --- |
| [`lake-orientation`](../../Content/PromptBooks/DataExploration/lake-orientation.prompt.md) | `list_sentinel_workspaces`, `search_tables` | Free |
| [`risky-user-hunt`](../../Content/PromptBooks/DataExploration/risky-user-hunt.prompt.md) | `search_tables`, `query_lake` | Free |
| [`signin-failure-triage`](../../Content/PromptBooks/DataExploration/signin-failure-triage.prompt.md) | `search_tables`, `query_lake` | Free |
| [`analyze-user-entity`](../../Content/PromptBooks/DataExploration/analyze-user-entity.prompt.md) | `analyze_user_entity`, `get_entity_analysis` | SCUs |
| [`analyze-url-entity`](../../Content/PromptBooks/DataExploration/analyze-url-entity.prompt.md) | `analyze_url_entity`, `get_entity_analysis` | SCUs |
| [`retro-hunt-ioc-sweep`](../../Content/PromptBooks/DataExploration/retro-hunt-ioc-sweep.prompt.md) | `search_tables`, `query_lake` | Free |
| [`exposure-blast-radius`](../../Content/PromptBooks/DataExploration/exposure-blast-radius.prompt.md) | `get_graph_context`, `find_blastradius`, `find_walkable_paths`, `find_exposure_perimeter` | Graph meter |

### Triage (6)

| Prompt | Tools exercised |
| --- | --- |
| [`incident-queue-triage`](../../Content/PromptBooks/Triage/incident-queue-triage.prompt.md) | `ListIncidents`, `GetIncidentById` |
| [`incident-deep-dive`](../../Content/PromptBooks/Triage/incident-deep-dive.prompt.md) | `GetIncidentById`, `ListAlerts`, `GetAlertByID`, `RunAdvancedHuntingQuery` |
| [`file-hash-investigation`](../../Content/PromptBooks/Triage/file-hash-investigation.prompt.md) | `GetDefenderFileInfo`, `GetDefenderFileStatistics`, `GetDefenderFileAlerts`, `GetDefenderFileRelatedMachines` |
| [`device-investigation`](../../Content/PromptBooks/Triage/device-investigation.prompt.md) | `GetDefenderMachine`, `GetDefenderMachineAlerts`, `GetDefenderMachineLoggedOnUsers`, `GetDefenderMachineVulnerabilities` |
| [`user-investigation`](../../Content/PromptBooks/Triage/user-investigation.prompt.md) | `ListUserRelatedAlerts`, `ListUserRelatedMachines` |
| [`cve-exposure-sweep`](../../Content/PromptBooks/Triage/cve-exposure-sweep.prompt.md) | `ListDefenderMachinesByVulnerability`, `ListDefenderRemediationActivities` |

### Agent creation (2)

| Prompt | Tools exercised |
| --- | --- |
| [`build-triage-agent`](../../Content/PromptBooks/AgentCreation/build-triage-agent.prompt.md) | `search_for_tools`, `start_agent_creation`, `compose_agent`, `get_evaluation`, `deploy_agent` |
| [`post-incident-report-agent`](../../Content/PromptBooks/AgentCreation/post-incident-report-agent.prompt.md) | Same chain, on Microsoft's own sample scenario |

### Sentinel-As-Code (3)

MCP plus this repository. These are the ones that make the demo about *this* repo rather
than about Sentinel generally.

| Prompt | What it does |
| --- | --- |
| [`hunt-to-analytical-rule`](../../Content/PromptBooks/SentinelAsCode/hunt-to-analytical-rule.prompt.md) | Validates a lake finding, then writes it as rule YAML matching this repo's schema, regenerates `dependencies.json` and runs the Pester suite |
| [`validate-rule-against-lake`](../../Content/PromptBooks/SentinelAsCode/validate-rule-against-lake.prompt.md) | Checks a committed rule's tables, columns, 30-day fire count and entity-mapping null rates against real data |
| [`detection-gap-analysis`](../../Content/PromptBooks/SentinelAsCode/detection-gap-analysis.prompt.md) | Splits coverage gaps into fixable, false-confidence and honest |

## Tool reference

### Data exploration collection

| Tool | Purpose | Key parameters |
| --- | --- | --- |
| `list_sentinel_workspaces` | Workspace name and ID pairs. Run before anything else. | - |
| `search_tables` | Semantic search over the table catalogue, returns schemas | `query`, `workspaceId` |
| `query_lake` | Run one KQL query against a lake workspace | `query`, `workspaceId` |
| `analyze_user_entity` | Start an AI risk analysis for a user | Entra object ID, `startTime`, `endTime`, `workspaceId` |
| `analyze_url_entity` | Start an AI risk analysis for a URL or domain | URL, `startTime`, `endTime`, `workspaceId` |
| `get_entity_analysis` | Poll for analysis results | `analysisId` |
| `get_graph_context` | Valid node labels and properties. Run before other graph tools. | - |
| `find_blastradius` | Propagation paths from a node towards critical assets | `sourceName` |
| `find_walkable_paths` | Traversable connections between a source and target | `sourceName`, `targetName` |
| `find_exposure_perimeter` | Incoming connections to an entity | `targetName`, `minPathLength`, `maxPathLength` |
| `find_connected_nodes` | Paths between entities matching label criteria | `sourceNodeLabel`, `targetNodeLabel` |
| `find_nodes` | Entities matching criteria | `validNodeLabel`, `validNodeProperties` |

### Triage collection

Incidents and alerts: `ListIncidents`, `GetIncidentById`, `ListAlerts`, `GetAlertByID`.

Hunting: `FetchAdvancedHuntingTablesOverview`, `FetchAdvancedHuntingTablesDetailedSchema`,
`RunAdvancedHuntingQuery`. Run the schema tool before writing KQL; it is the documented way
to avoid malformed queries.

Files: `GetDefenderFileInfo`, `GetDefenderFileStatistics`, `GetDefenderFileAlerts`,
`GetDefenderFileRelatedMachines`.

Devices: `GetDefenderMachine`, `GetDefenderMachineAlerts`, `GetDefenderMachineLoggedOnUsers`,
`GetDefenderMachineVulnerabilities`, `FindDefenderMachineByIp`.

Users: `ListUserRelatedAlerts`, `ListUserRelatedMachines`.

Vulnerabilities and remediation: `ListDefenderMachinesByVulnerability`,
`ListDefenderVulnerabilitiesBySoftware`, `ListDefenderRemediationActivities`,
`GetDefenderRemediationActivity`.

Indicators and investigations: `ListDefenderIndicators`, `ListDefenderInvestigations`,
`GetDefenderInvestigation`, `GetDefenderIpAlerts`, `GetDefenderIpStatistics`.

### Agent creation collection

`search_for_tools`, `start_agent_creation`, `compose_agent`, `get_evaluation`,
`deploy_agent`.

Pass `compose_agent` the session ID from `start_agent_creation`, not the one from
`search_for_tools`. They are different sessions.

## Prerequisites

| | Data exploration | Triage | Agent creation |
| --- | --- | --- | --- |
| Sentinel data lake | Required | - | - |
| Defender portal onboarding | Graph tools only | Required | - |
| Security Copilot | Entity analyzer only | - | Required |
| Minimum role | Security Reader | Your existing permissions | Security Copilot access |
| Extra roles | Security Copilot Contributor for entity analyzer; Exposure Management read for graph | - | - |

## Writing good prompts

Microsoft's own guidance is to be specific, and their contrast makes the point better than
any rule:

> `For user <UPN>, baseline their network, file, sign-in, and device events over 90 days
> and compare with +/- 10 minutes to find anomalies or suspicious activities to help me
> triage the severity and priority of this alert.`

beats

> `What is risky about <UPN>?`

Four incantations that change behaviour, all documented:

| Say this | Because |
| --- | --- |
| The workspace ID, explicitly | With several workspaces connected, tools pick between them turn to turn |
| `in my graph` | Scopes graph tools to the graph rather than the lake |
| `render the results as returned exactly from the tool` | Stops the client re-summarising an entity-analyzer verdict |
| `Use 'default' as the workspaceId.` | System tables have no workspace ID of their own |

Two more that are not Microsoft's but earn their place in every prompt in this book:

- **Ask for the reasoning, not just the answer.** "Show me each KQL query you run" turns a
  black box into a demo.
- **Force a commitment.** "Commit to one verdict and justify it" beats a model hedging
  across every option, which is the default failure mode on ambiguous evidence.

## Running orders

**15 minutes, mixed audience**

1. `lake-orientation` - no schema knowledge needed
2. `risky-user-hunt` - the model writes, breaks and fixes its own KQL
3. `analyze-user-entity` - one call replaces twenty minutes of context gathering
4. `hunt-to-analytical-rule` - and the finding becomes a pull request

**30 minutes, SOC audience**

1. `lake-orientation`
2. `incident-queue-triage` - it disagrees with your severities
3. `incident-deep-dive` - on whatever it ranked first
4. `file-hash-investigation` or `device-investigation` - follow the evidence
5. `analyze-user-entity` - the verdict
6. `retro-hunt-ioc-sweep` - have we ever seen this, not have we seen this recently

**30 minutes, detection engineering audience**

1. `lake-orientation`
2. `detection-gap-analysis` - the false-confidence gap usually lands hardest
3. `validate-rule-against-lake` - on whatever it flagged
4. `hunt-to-analytical-rule` - close the loop
5. `build-triage-agent` - if Security Copilot is provisioned

**Cost-sensitive demo:** stay in the data exploration collection and skip
`analyze-user-entity`, `analyze-url-entity` (SCUs) and `exposure-blast-radius` (graph
meter). Everything else is free.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Unknown tool '<server>/*' will be ignored` in a prompt file | `tools:` frontmatter naming an MCP server that is not registered | The shipped files carry no `tools:` key for this reason. If you added one, register the server with that exact ID or drop the line. |
| Tools never get called | Overlapping tools, weak model, or context favoured over tool use | Disable collections you are not using; pick a newer reasoning model; start a fresh chat |
| Results come from the wrong workspace | Several workspaces connected | Name the workspace ID in the prompt |
| Intermittent `HTTP 404 Resource not found` | Token refresh bug | Remove the MCP server, restart VS Code, add it again |
| Consistent `HTTP 404` when adding the server | Tenant not registered, or no data lake workspace access | Check data lake onboarding and your role |
| `HTTP 403 Unauthorized to access account` | Client does not support MCP auth | Update VS Code |
| No results at all | Table absent, query too narrow, invalid workspace ID, or missing permission | Broaden the search; re-run `list_sentinel_workspaces`; check Lake explorer |
| Guest sign-in authenticates against the wrong tenant | Known VS Code issue; triage tools do not support multi-tenancy | Add an `x-mcp-client-tenant-id` header to the server definition, or use a home-tenant account |
| Default workspace missing from the list | System tables have no workspace ID | Add `Use 'default' as the workspaceId.` to the prompt |

To collect evidence for a support case, use the VS Code **Chat Debug View** (three dots in
the Copilot chat sidebar -> **Show Chat Debug View** -> **Export All as JSON**).

## Known limits

**Entity analyzer**

- `analyze_user_entity` caps the analysis window at **seven days**
- Entra object IDs only. On-premises-only AD users are unsupported.
- Requires `AlertEvidence`, `SigninLogs`, `CloudAppEvents` and `IdentityInfo` in the lake
- Run at most **five** analyses concurrently

**Triage collection**

- Cannot query the data lake. Use the data exploration collection for long history.
- Cannot choose a workspace
- No guest or delegated access; home tenant only
- File tools disagree on hash types: `GetDefenderFileInfo` and `GetDefenderFileStatistics`
  take SHA-1 or SHA-256; `GetDefenderFileAlerts` and `GetDefenderFileRelatedMachines` take
  **SHA-1 only**. MD5 works nowhere. Supply SHA-1 when chaining.

**Graph tools**

- Preview; subject to change
- Identity lookups do not accept UPNs
- Put the entity type before the name (`device zava-fin-01`)
- Invoke the graph meter, so they cost money

## Related

- [Spark Notebooks](Spark-Notebooks.md) - the same hunts as PySpark notebooks. `demo13`
  is the notebook twin of `retro-hunt-ioc-sweep`; `demo18` pairs with
  `detection-gap-analysis`.
- [GitHub Copilot Setup](../GitHub/GitHub-Copilot.md) - the repo's own Copilot
  customisations and the platform support matrix for prompt files
- [Analytical Rules](Analytical-Rules.md) - the schema `hunt-to-analytical-rule` writes to
- Microsoft docs: [MCP overview](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-mcp-overview),
  [tool collections](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-mcp-tools-overview),
  [VS Code setup](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-mcp-use-tool-visual-studio-code),
  [best practices and troubleshooting](https://learn.microsoft.com/azure/sentinel/datalake/troubleshoot-sentinel-mcp)
