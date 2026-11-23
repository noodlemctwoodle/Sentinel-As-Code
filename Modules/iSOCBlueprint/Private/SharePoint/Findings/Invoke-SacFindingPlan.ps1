#Requires -Version 7.6

<#
.SYNOPSIS
    Apply a findings plan: add, update and resolve items.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Findings/Invoke-SacFindingPlan.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-SacFindingPlan {
    <#
    .SYNOPSIS
        Apply a findings plan to the list in one batch.

    .PARAMETER Plan
        Output of Get-FindingSyncPlan.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan)

    if ($Plan.Count -eq 0) { return }
    $summary = ($Plan | Group-Object Action | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '
    if (-not $PSCmdlet.ShouldProcess($script:SacFindingsListUrl, "Apply findings plan ($summary)")) { return }

    $batch = New-PnPBatch
    foreach ($step in $Plan) {
        if ($step.Action -eq 'Add') {
            Add-PnPListItem -List $script:SacFindingsListUrl -Values $step.Values -Batch $batch
        } else {
            Set-PnPListItem -List $script:SacFindingsListUrl -Identity $step.ItemId -Values $step.Values -Batch $batch
        }
    }
    Invoke-PnPBatch -Batch $batch -StopOnException
}
