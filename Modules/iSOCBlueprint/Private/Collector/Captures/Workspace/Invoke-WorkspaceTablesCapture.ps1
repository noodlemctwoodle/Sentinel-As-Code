#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'workspace-tables': writes workspace-tables.json, search-jobs.json, restore-logs.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Workspace/Invoke-WorkspaceTablesCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Invoke-WorkspaceTablesCapture {
    <#
    .SYNOPSIS
        Capture 'workspace-tables': writes workspace-tables.json, search-jobs.json, restore-logs.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $workspaceResourceId = $Context.workspaceResourceId

    # 2025-02-01 carries schema.tableSubType (Classic or DCR-based),
    # lastPlanModifiedDate and the *AsDefault retention flags. A region or
    # cloud that does not serve it yet falls back to 2023-09-01.
    try {
        $tables = Invoke-SentinelRest -Path "$workspaceResourceId/tables" -ApiVersion $apiVersions.Tables
    } catch {
        Write-CaptureNote -Kind NotAvailable -Text "the Tables API $($apiVersions.Tables) is not served ($(Format-CaptureMessage (Get-CaptureErrorText $_))); used 2023-09-01."
        $tables = Invoke-SentinelRest -Path "$workspaceResourceId/tables" -ApiVersion '2023-09-01'
    }
    Save-Json -FileName 'workspace-tables.json' -Data $tables
    # Search jobs and restores leave _SRCH and _RST tables behind; they are
    # the record the maturity model (SAC-INV-02) and the search and restore
    # page read.
    $found = Get-SearchRestoreTable -Tables @($tables)
    Save-Json -FileName 'search-jobs.json' -Data @($found.SearchJobs)
    Save-Json -FileName 'restore-logs.json' -Data @($found.Restores)
}
