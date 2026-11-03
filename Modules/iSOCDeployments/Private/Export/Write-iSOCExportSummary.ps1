#Requires -Version 7.2

<#
.SYNOPSIS
    Log an export run's counts.

.DESCRIPTION
    Replaces the export summaries of Tools/Export-SentinelWorkbooks.ps1 and
    847ef86:Tools/Export-Playbooks.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Private/Export/Write-iSOCExportSummary.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-iSOCExportSummary {
    <#
    .SYNOPSIS
        Log what an export created, updated, left, skipped and failed.

    .PARAMETER Run
        The export run, its counts filled in.

    .EXAMPLE
        Write-iSOCExportSummary -Run $run
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run
    )

    Write-iSOCLog 'Export summary' -Level Section
    Write-iSOCLog "  Created:   $($Run.Created)"
    Write-iSOCLog "  Updated:   $($Run.Updated)"
    Write-iSOCLog "  Unchanged: $($Run.Unchanged)"
    Write-iSOCLog "  Skipped:   $($Run.Skipped)"
    Write-iSOCLog "  Failed:    $($Run.Failed)"
    if ($Run.WhatIf -gt 0) { Write-iSOCLog "  WhatIf:    $($Run.WhatIf)" }
    if ($Run.Warnings -gt 0) { Write-iSOCLog "  Items with warnings to act on before committing: $($Run.Warnings)" -Level Warning }
    if ($Run.Failed -gt 0) { Write-iSOCLog 'One or more items failed to export.' -Level Error }
}
