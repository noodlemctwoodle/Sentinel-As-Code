# PromptBooks - Microsoft Sentinel MCP prompts for GitHub Copilot

Runnable prompt books for the [Microsoft Sentinel MCP server](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-mcp-overview),
built for live demos in **VS Code + GitHub Copilot agent mode**.

Each file is a VS Code [prompt file](https://code.visualstudio.com/docs/agent-customization/prompt-files):
invoke it with `/<name>` in Copilot Chat, or just copy the prompt text out of it. Every
book carries a primary prompt, follow-ups that build a narrative, a *what good looks like*
section so you can tell live whether it worked, and demo notes covering the failure modes.

## Documentation

- **[Prompt Books](../../Docs/Content/Prompt-Books.md)** - full catalogue, the MCP tool
  reference, prompt-writing guidance, running orders and troubleshooting.

## Contents

**Data exploration** - `https://sentinel.microsoft.com/mcp/data-exploration`

| Prompt | Demonstrates | Cost |
| --- | --- | --- |
| [`lake-orientation`](DataExploration/lake-orientation.prompt.md) | `list_sentinel_workspaces`, `search_tables` - run this first | Free |
| [`risky-user-hunt`](DataExploration/risky-user-hunt.prompt.md) | The full search-to-query loop, with self-correcting KQL | Free |
| [`signin-failure-triage`](DataExploration/signin-failure-triage.prompt.md) | `query_lake` classifying spray vs stuffing vs broken service account | Free |
| [`analyze-user-entity`](DataExploration/analyze-user-entity.prompt.md) | `analyze_user_entity` - one-click compromise verdict | **SCUs** |
| [`analyze-url-entity`](DataExploration/analyze-url-entity.prompt.md) | `analyze_url_entity` - bulk IOC verdicts from a threat report | **SCUs** |
| [`retro-hunt-ioc-sweep`](DataExploration/retro-hunt-ioc-sweep.prompt.md) | Full-history IOC sweep - the retention story | Free |
| [`exposure-blast-radius`](DataExploration/exposure-blast-radius.prompt.md) | Graph tools - blast radius and attack paths | **Graph meter** |

**Triage** - `https://sentinel.microsoft.com/mcp/triage`

| Prompt | Demonstrates |
| --- | --- |
| [`incident-queue-triage`](Triage/incident-queue-triage.prompt.md) | `ListIncidents` - rank the queue and argue with the assigned severity |
| [`incident-deep-dive`](Triage/incident-deep-dive.prompt.md) | Incident to alerts to evidence to a committed verdict |
| [`file-hash-investigation`](Triage/file-hash-investigation.prompt.md) | The four Defender file tools, and the SHA-1 constraint |
| [`device-investigation`](Triage/device-investigation.prompt.md) | Five portal tabs collapsed into one endpoint briefing |
| [`user-investigation`](Triage/user-investigation.prompt.md) | Target, vector, cause or noise |
| [`cve-exposure-sweep`](Triage/cve-exposure-sweep.prompt.md) | "Are we exposed to this CVE" - and is it being exploited |

**Agent creation** - `https://sentinel.microsoft.com/mcp/security-copilot-agent-creation`

| Prompt | Demonstrates |
| --- | --- |
| [`build-triage-agent`](AgentCreation/build-triage-agent.prompt.md) | The full `search_for_tools` to `deploy_agent` chain |
| [`post-incident-report-agent`](AgentCreation/post-incident-report-agent.prompt.md) | Microsoft's own headline scenario - the reliable one |

**Sentinel-As-Code** - MCP plus this repository

| Prompt | Demonstrates |
| --- | --- |
| [`hunt-to-analytical-rule`](SentinelAsCode/hunt-to-analytical-rule.prompt.md) | Lake finding to committed rule YAML, with a 30-day fire count |
| [`validate-rule-against-lake`](SentinelAsCode/validate-rule-against-lake.prompt.md) | Do a rule's tables and columns actually exist here? |
| [`detection-gap-analysis`](SentinelAsCode/detection-gap-analysis.prompt.md) | What we detect vs what the lake holds, and where they disagree |

## Setup

**1. Add the MCP servers.** Copy [`mcp.json`](mcp.json) to `.vscode/mcp.json`:

```bash
cp Content/PromptBooks/mcp.json .vscode/mcp.json
```

`.vscode/` is git-ignored in this repo, which is why the template lives here. Reload VS
Code, then sign in when prompted with an account holding at least **Security Reader**.

You can also add servers one at a time via **Ctrl+Shift+P** -> `MCP: Add Server` ->
**HTTP** -> paste the URL. Any server ID works; nothing in these prompt files depends on it.

**2. Make the prompts discoverable.** Merge
[`vscode-settings.snippet.json`](vscode-settings.snippet.json) into `.vscode/settings.json`
so Copilot finds these folders. Without it the `/slash-commands` will not appear and you
will be copy-pasting instead - which still works, but is a worse demo.

**3. Set chat to Agent mode.** MCP tools are only available in agent mode.

**4. Verify.** Open Copilot Chat, click **Configure Tools**, and confirm the Sentinel
servers are listed with their tools.

### Optional: scope tools per prompt

None of these files pin a `tools:` list, deliberately. A prompt file that names an MCP
server which is not registered yet produces
`Unknown tool '<server>/*' will be ignored (promptValidator.unknownExtensionOrMcpServerReference)`
in the editor, and a squiggle in every file is a poor way to start a demo. Without the
key, the prompt simply uses whatever tools are enabled in chat.

Once your servers are registered and you know their IDs, scoping is worth adding back.
Microsoft's troubleshooting guidance is that models pick tools badly when too many
semantically overlapping ones are enabled, and per-prompt scoping is the documented
mitigation. Add one line to the frontmatter, matching your own server IDs:

```yaml
tools: ['sentinel-data-exploration/*']       # DataExploration/ and SentinelAsCode/
tools: ['sentinel-triage/*']                 # Triage/
tools: ['sentinel-agent-creation/*']         # AgentCreation/
```

The `SentinelAsCode/` prompts also touch the repo, so they want
`['sentinel-data-exploration/*', 'search/codebase', 'edit/applyPatch', 'terminal/run']`.

The cheaper alternative, and the one to use if you are presenting in an hour: leave the
frontmatter alone and disable the collections you are not using in **Configure Tools**.

## Prerequisites by collection

| | Data exploration | Triage | Agent creation |
| --- | --- | --- | --- |
| Sentinel data lake | Required | - | - |
| Defender portal onboarding | Graph tools only | Required | - |
| Security Copilot | Entity analyzer only | - | Required |
| Minimum role | Security Reader | Your existing permissions | Security Copilot access |

## Writing your own

Microsoft's guidance, and it holds up: **be specific**. Their own contrast is worth
internalising -

> `For user <UPN>, baseline their network, file, sign-in, and device events over 90 days
> and compare with +/- 10 minutes to find anomalies or suspicious activities to help me
> triage the severity and priority of this alert.`

beats

> `What is risky about <UPN>?`

Four more that earn their place in a prompt:

- **Name the workspace ID.** With several workspaces connected, tools will otherwise pick
  between them turn to turn.
- **Say `in my graph`** for graph tools, or they answer from the lake instead.
- **Say `render the results as returned exactly from the tool`** for the entity analyzer,
  or the client re-summarises a verdict that was already a summary.
- **Say `Use 'default' as the workspaceId.`** to reach system tables, which have no
  workspace ID of their own.

## Notes

- Prompt files are recognised in VS Code, Visual Studio and JetBrains. They are **not**
  recognised on github.com or by Copilot CLI - see
  [GitHub Copilot Setup](../../Docs/GitHub/GitHub-Copilot.md) for the full platform matrix.
- These are demo scripts, not deployable Sentinel content. Nothing here is picked up by the
  deploy pipelines.
- Docs: https://learn.microsoft.com/azure/sentinel/datalake/sentinel-mcp-overview
