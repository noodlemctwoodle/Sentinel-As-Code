#Requires -Version 7.6

<#
.SYNOPSIS
    Log a community import's counts.

.DESCRIPTION
    Replaces the summary at the end of Invoke-Main (Tools/Import-CommunityRules.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Write-iSOCCommunityImportSummary.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-iSOCCommunityImportSummary {
    <#
    .SYNOPSIS
        Log what a community import created, updated, left and skipped.

    .PARAMETER Run
        The import run, its counts filled in.

    .EXAMPLE
        Write-iSOCCommunityImportSummary -Run $run
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run
    )

    Write-iSOCLog 'Import Complete' -Level Section
    Write-iSOCLog "  Created:   $($Run.Created)"
    Write-iSOCLog "  Updated:   $($Run.Updated)"
    Write-iSOCLog "  Unchanged: $($Run.Unchanged)"
    if ($Run.WhatIf -gt 0) { Write-iSOCLog "  WhatIf:    $($Run.WhatIf)" }
    if ($Run.Skipped -gt 0) { Write-iSOCLog "  Skipped:   $($Run.Skipped)" -Level Warning }
    if (@($Run.IdChanges).Count -gt 0) { Write-iSOCLog "  Ids not the upstream's: $(@($Run.IdChanges).Count)" }
}
