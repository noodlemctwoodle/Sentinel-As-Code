#Requires -Version 7.6

<#
.SYNOPSIS
    Log what a compare found.

.DESCRIPTION
    Copied from Write-DriftSummary (Tools/Test-SentinelRuleDrift.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/Write-iSOCDriftSummary.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-iSOCDriftSummary {
    <#
    .SYNOPSIS
        A warning for every drifted and orphan rule, then the counts.

    .PARAMETER Drift
        From Compare-iSOCContent.

    .OUTPUTS
        None.

    .EXAMPLE
        Write-iSOCDriftSummary -Drift $drift
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Drift
    )

    foreach ($item in @($Drift.Items | Where-Object { $_.State -in 'PortalEdit', 'ContentHubCustomised' })) {
        Write-iSOCLog "DRIFT [$($item.Source)] '$($item.Name)' ($($item.ResourceName)): modified fields = $(@($item.Modifications | ForEach-Object { $_.Field }) -join ', ')" -Level Warning
    }
    foreach ($item in @($Drift.Items | Where-Object { $_.State -eq 'PortalOnly' })) {
        Write-iSOCLog "ORPHAN '$($item.Name)' ($($item.ResourceName)): no source of truth; created or detached in the portal." -Level Warning
    }

    $summary = $Drift.Summary
    Write-iSOCLog 'Drift summary:' -Level Section
    Write-iSOCLog "  Total deployed rules : $($summary.totalDeployed)"
    Write-iSOCLog "  ContentHub clean     : $($summary.contentHubClean)"
    Write-iSOCLog "  ContentHub drift     : $($summary.contentHubDrift)"
    Write-iSOCLog "  Custom clean         : $($summary.customClean)"
    Write-iSOCLog "  Custom drift         : $($summary.customDrift)"
    Write-iSOCLog "  Orphan rules         : $($summary.orphan)"
    Write-iSOCLog "  Managed (excluded)   : $($summary.managed)"
    Write-iSOCLog "  Skipped              : $($summary.skipped)"
}
