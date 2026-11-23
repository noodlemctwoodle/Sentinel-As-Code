#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 87-azure-monitor-agents.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/AzureMonitorAgents/Write-BlueprintAzureMonitorAgentsSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintAzureMonitorAgentsSection {
    <#
    .SYNOPSIS
        Build the figures for and write 87-azure-monitor-agents.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $found = $Context.found
    $m = $Context.m
    $n = $Context.n
    $t = $Context.t

    # Section 87 — Azure Monitor Agents (TOC 4.5)
    $amaAgents = Read-BlueprintRawArray 'ama-agents.json'
    $agentRows = $amaAgents | ForEach-Object {
        [pscustomobject]@{
            Computer = $_.Computer
            OS       = $_.OS
            Version  = $_.Version
            Resource = $_.Resource
            LastSeen = Format-DateUtc $_.LastHeartbeat
        }
    }

    # AMA vs MMA migration status by machine type.
    $migration = Read-BlueprintRawArray 'ama-mma-migration.json'
    $migrationRows = $migration | ForEach-Object {
        [pscustomobject]@{
            MachineType     = $_.MachineType
            MachineCount    = $_.MachineCount
            MMACount        = $_.MMACount
            AMACount        = $_.AMACount
            MigrationStatus = $_.MigrationStatus
        }
    }
    # Chart inputs. When the total agent count is < 3 the renderer skips the
    # chart entirely — 1-vs-0 splits are visually meaningless. Otherwise emit
    # a grouped bar with AMA and MMA per machine type.
    $totalAgents = 0
    foreach ($r in $migrationRows) { $totalAgents += [int]$r.MachineCount }
    $agentChartBlock = if ($totalAgents -ge 3 -and $migrationRows.Count -gt 0) {
        $mtAxis = ($migrationRows | ForEach-Object { "`"$($_.MachineType)`"" }) -join ', '
        $amaArr = ($migrationRows | ForEach-Object { [int]$_.AMACount }) -join ', '
        $mmaArr = ($migrationRows | ForEach-Object { [int]$_.MMACount }) -join ', '
        $yMax = 1
        foreach ($r in $migrationRows) {
            $t = [int]$r.AMACount + [int]$r.MMACount
            if ($t -gt $yMax) { $yMax = $t }
        }
        @"

``````mermaid
xychart-beta
    title "Agent fleet: AMA vs MMA per machine type"
    x-axis [$mtAxis]
    y-axis "Machines" 0 --> $($yMax + 1)
    bar "AMA" [$amaArr]
    bar "MMA" [$mmaArr]
``````

Two bars per machine type: AMA first, MMA second. A workspace mid-migration shows MMA bars sitting alongside AMA; a fully-migrated workspace has zero MMA bars across the board.
"@
    } else {
        "`n> **Agent migration:** $(Format-BlueprintPlural $totalAgents 'agent') heartbeating; chart suppressed because the count is too small for a meaningful visual. The migration-status table below carries the per-machine detail."
    }

    $heartbeatMixRows = @(Read-BlueprintRawArray 'agent-heartbeat-mix.json' | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{
                OSType    = $_.OSType
                Agent     = $(switch ([string]$_.Category) { 'Direct Agent' { 'Direct Agent (MMA, legacy)' } 'SCOM Agent' { 'SCOM Agent (legacy)' } default { $_ } })
                Version   = $_.Version
                OSVersion = $_.OSVersion
                Computers = Format-BlueprintCount $_.Computers
                LastSeen  = Format-DateUtc $_.LastSeen
            }
        })

    Write-BlueprintSection '87-azure-monitor-agents.md' (@"
$(Format-Banner -Title "Azure Monitor Agents  (TOC 4.5)")

Agents heartbeating into the workspace over the last {lookback}, derived from the ``Heartbeat`` table. Each row is a distinct ``SourceComputerId``.
$agentChartBlock

$(Format-BlueprintTable -Items $agentRows -Columns 'Computer','OS','Version','Resource','LastSeen')

## AMA vs MMA migration status

Per-machine-type breakdown of agent migration progress. ``Direct Agent`` counts the legacy MMA; ``Azure Monitor Agent`` counts the modern AMA. Migration state is **Completed** when only AMA records exist for a category, **In Progress** when both exist, and **Not Started** otherwise.

$(Format-BlueprintTable -Items @($migrationRows | ForEach-Object { [pscustomobject]@{ MachineType = $_.MachineType; MachineCount = (Format-BlueprintCount $_.MachineCount); MMACount = (Format-BlueprintCount $_.MMACount); AMACount = (Format-BlueprintCount $_.AMACount); MigrationStatus = $_.MigrationStatus } }) -Columns 'MachineType','MachineCount','MMACount','AMACount','MigrationStatus')

## Agent heartbeat mix

Machines by operating system, agent and agent version over the last {lookback}. A ``Direct Agent`` or ``SCOM Agent`` row is the legacy Log Analytics agent, retired on 31 Aug 2024 ([SAC-PLT-03]); the version column shows how far behind each fleet is.

$(Format-BlueprintTable -Items $heartbeatMixRows -Columns 'OSType','Agent','Version','OSVersion','Computers','LastSeen' -EmptyMessage (Get-BlueprintEmptyMessage 'agent-heartbeat-mix.json' '_No heartbeats in the last {lookback}._'))

[Migrate from Log Analytics agent to Azure Monitor agent (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-migration)
[Azure Monitor Agent overview (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/agents/agents-overview)
"@)
}
