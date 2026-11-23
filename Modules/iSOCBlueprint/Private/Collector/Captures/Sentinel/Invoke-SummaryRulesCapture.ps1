#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'summary-rules': writes summary-rules.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-SummaryRulesCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-SummaryRulesCapture {
    <#
    .SYNOPSIS
        Capture 'summary-rules': writes summary-rules.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $workspaceResourceId = $Context.workspaceResourceId

    # Summary rules are owned by the OperationalInsights provider, not Sentinel
    #, the API path is `.../workspaces/<ws>/summaryLogs`, not the Content Hub
    # `.../contentTemplates?$filter=contentKind eq 'SummaryRule'` (which would
    # only return installable templates, not deployed rule instances). The
    # earlier implementation queried the wrong endpoint AND gated the call on
    # -IncludePreview, so production runs without that switch returned nothing
    # regardless of how many summary rules the workspace actually has.
    $sr = Invoke-SentinelRest -Path "$workspaceResourceId/summaryLogs" -ApiVersion '2023-01-01-preview'
    Save-Json -FileName 'summary-rules.json' -Data $sr
}
