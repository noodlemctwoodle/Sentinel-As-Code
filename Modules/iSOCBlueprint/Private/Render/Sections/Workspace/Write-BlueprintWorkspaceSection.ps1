#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 80-workspace.md (part 1 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Workspace/Write-BlueprintWorkspaceSection.ps1
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
function Write-BlueprintWorkspaceSection {
    <#
    .SYNOPSIS
        Build the figures for and write 80-workspace.md (part 1 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $connectors = $Context.connectors
    $enabledRules = $Context.enabledRules
    $operationalTables = $Context.operationalTables
    $workspace = $Context.workspace
    $workspaceTables = $Context.workspaceTables

    # ---------------------------------------------------------------------------
    # Section: 80 — workspace
    # ---------------------------------------------------------------------------
    $features = $workspace.properties.features
    $wsCreated = $workspace.properties.createdDate
    $wsAgeDays = if ($wsCreated) {
        [int]([math]::Floor(((Get-Date).ToUniversalTime() - [datetime]$wsCreated).TotalDays))
    } else { $null }
    $wsAgeWarning = if ($null -ne $wsAgeDays -and $wsAgeDays -lt (Get-BlueprintWindow).Days) {
        ' _(The workspace is younger than the {lookback} the captures read, so figures over that window cover only its life so far.)_'
    } else { '' }
    $wsDefaultDcr = $null
    if ($workspace.properties.PSObject.Properties.Name -contains 'defaultDataCollectionRuleResourceId') {
        $wsDefaultDcr = $workspace.properties.defaultDataCollectionRuleResourceId
    }
    # Timeline-line dates. wsCreatedShort = yyyy-MM-dd for the workspace
    # creation event in the timeline diagram: the sort key and the visual's
    # machine-readable date; the timeline prints it as "14 Jun 2026".
    $wsCreatedShort = if ($wsCreated) { Get-IsoDay $wsCreated } else { 'unknown' }
    $todayShort = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)

    # Build the workspace + platform history timeline as a sorted list.
    # Mermaid `timeline` renders entries in source order — without an
    # explicit chronological sort the entries appeared in the order they
    # were declared in the heredoc, not by date. Each entry is a hashtable
    # with Date (yyyy-MM-dd) and Lines (one or more colon-suffixed strings).
    # Platform deprecation events pre-dating the workspace's creation are
    # filtered out — they're irrelevant historical context for a new
    # workspace (e.g. a 2026-created workspace doesn't need an MMA-retired
    # bullet from 2024).
    $timelineEvents = @()
    $timelineEvents += [pscustomobject]@{
        Date  = $wsCreatedShort
        Lines = @(
            "Workspace created ($(Format-WorkspaceSku $workspace.properties.sku.name), $($workspace.properties.retentionInDays)-day retention)",
            'First captured connector inventory'
        )
    }
    # Tables-in-use: operational subset (tables that have received billable
    # data in 90 days, plus CustomLog tables). The 800+ Microsoft-defined
    # schemas the workspace never ingested are catalogue, not deployment —
    # surfaced as a separate number to avoid misreading "836 tables in
    # catalogue" as "836 tables in use".
    $timelineEvents += [pscustomobject]@{
        Date  = $todayShort
        Lines = @(
            "This documentation generated ($(Format-BlueprintCount $wsAgeDays)-day-old workspace)",
            "$(Format-BlueprintPlural $enabledRules.Count 'rule') enabled · $(Format-BlueprintPlural $connectors.Count 'connector') · $(Format-BlueprintPlural $operationalTables.Count 'table') receiving data ($(Format-BlueprintCount $workspaceTables.Count) in catalogue)"
        )
    }

    if ($wsCreatedShort -ne 'unknown') {
        $timelineEvents = @($timelineEvents | Where-Object { $_.Date -ge $wsCreatedShort })
    }
    $timelineEvents = @($timelineEvents | Sort-Object Date)

    $timelineBody = ($timelineEvents | ForEach-Object {
            $lines = @($_.Lines)
            $first = "    $(Format-BlueprintDate $_.Date) : $($lines[0])"
            if ($lines.Count -gt 1) {
                $rest = @($lines[1..($lines.Count - 1)] | ForEach-Object { "                    : $_" })
                ($first + [Environment]::NewLine + ($rest -join [Environment]::NewLine))
            } else { $first }
        }) -join [Environment]::NewLine

    # The workspace's own history as data for the SharePoint graphic. Platform
    # retirements live on 02-deprecated-legacy-features.md and are not repeated.
    $workspaceAgeVisualLine = Format-VisualLine -Kind 'workspace-age' -Data ([ordered]@{
            created         = $(if ($wsCreatedShort -ne 'unknown') { $wsCreatedShort } else { $null })
            today           = $todayShort
            ageDays         = $(if ($null -ne $wsAgeDays) { [int]$wsAgeDays } else { $null })
            sku             = (Get-BlueprintSkuName ([string]$workspace.properties.sku.name))
            retentionDays   = [int]$workspace.properties.retentionInDays
            rulesEnabled    = $enabledRules.Count
            connectors      = @($connectors).Count
            tablesReceiving = @($operationalTables).Count
            tablesCatalogue = @($workspaceTables).Count
        })

    # Left in the render context for later sections.
    $Context.features = $features
    $Context.timelineBody = $timelineBody
    $Context.workspaceAgeVisualLine = $workspaceAgeVisualLine
    $Context.wsAgeDays = $wsAgeDays
    $Context.wsAgeWarning = $wsAgeWarning
    $Context.wsCreated = $wsCreated
    $Context.wsDefaultDcr = $wsDefaultDcr
}
