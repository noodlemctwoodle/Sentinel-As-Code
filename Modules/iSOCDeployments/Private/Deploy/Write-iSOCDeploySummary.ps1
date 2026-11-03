#Requires -Version 7.2

<#
.SYNOPSIS
    Report a deployment run and return its result.

.DESCRIPTION
    Replaces Write-DeploymentSummary (Deploy/content/Deploy-CustomContent.ps1).
    The table has one row per content type deployed; rules sent disabled
    count as deployed and unchanged items as skipped, as they did, and a
    -WhatIf run shows what would deploy instead of counting it deployed
    (MIGRATION.md edit E12). The exit code is for the pipeline step to
    pass on, since the module never exits.

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Write-iSOCDeploySummary.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-iSOCDeploySummary {
    <#
    .SYNOPSIS
        Log the per-type counts and return the run's result.

    .PARAMETER Run
        The deployment run.

    .PARAMETER ContentType
        The content types the run deployed, in order.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.DeployRun: Deployed, Skipped,
        Failed, WhatIf, Duration, ExitCode (1 when anything failed, else 0)
        and Results.

    .EXAMPLE
        Write-iSOCDeploySummary -Run $run -ContentType $types
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [psobject[]] $ContentType
    )

    $count = {
        param($Results, [string[]] $Outcomes)
        @($Results | Where-Object { $_.Outcome -in $Outcomes }).Count
    }

    $width = 15
    foreach ($type in $ContentType) { $width = [Math]::Max($width, $type.Name.Length) }
    Write-iSOCLog ''
    Write-iSOCLog 'Deployment summary' -Level Section
    Write-iSOCLog ('=' * 60)
    foreach ($type in $ContentType) {
        $results = @($Run.Results | Where-Object { $_.ContentType -eq $type.Name })
        $deployed = & $count $results 'Deployed', 'DeployedDisabled'
        $skipped = & $count $results 'Skipped', 'Unchanged'
        $failed = & $count $results 'Failed'
        $whatIf = & $count $results 'WhatIf'
        $status = if ($failed -gt 0) { 'PARTIAL' } elseif ($deployed -gt 0) { 'OK' } elseif ($whatIf -gt 0) { 'WHATIF' } else { 'SKIPPED' }
        $would = if ($whatIf -gt 0) { "  Would deploy: $whatIf" } else { '' }
        Write-iSOCLog "  $($type.Name.PadRight($width)) Deployed: $deployed  Skipped: $skipped  Failed: $failed$would  [$status]"
    }

    $all = @($Run.Results)
    $result = [pscustomobject]@{
        PSTypeName = 'iSOCDeployments.DeployRun'
        Deployed   = & $count $all 'Deployed', 'DeployedDisabled'
        Skipped    = & $count $all 'Skipped', 'Unchanged'
        Failed     = & $count $all 'Failed'
        WhatIf     = & $count $all 'WhatIf'
        Duration   = (Get-Date) - $Run.Started
        ExitCode   = 0
        Results    = $all
    }
    if ($result.Failed -gt 0) { $result.ExitCode = 1 }

    Write-iSOCLog ('=' * 60)
    $would = if ($result.WhatIf -gt 0) { "  Would deploy: $($result.WhatIf)" } else { '' }
    Write-iSOCLog "  $('TOTAL'.PadRight(15)) Deployed: $($result.Deployed)  Skipped: $($result.Skipped)  Failed: $($result.Failed)$would"
    Write-iSOCLog "  Duration: $($result.Duration.ToString('hh\:mm\:ss'))"
    if ($result.Failed -gt 0) { Write-iSOCLog "$($result.Failed) item(s) failed to deploy. Review errors above." -Level Error }
    elseif ($result.Deployed -gt 0) { Write-iSOCLog 'All items deployed successfully.' -Level Success }
    $result
}
