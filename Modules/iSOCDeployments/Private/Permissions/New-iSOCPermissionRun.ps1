#Requires -Version 7.6

<#
.SYNOPSIS
    A permission command's result, counted.

.DESCRIPTION
    Shared by the playbook and runbook permission commands.

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/New-iSOCPermissionRun.ps1
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

function New-iSOCPermissionRun {
    <#
    .SYNOPSIS
        Build the run a permission command returns, and log its summary.

    .PARAMETER Results
        The permission results.

    .PARAMETER Started
        When the command started.

    .PARAMETER Extra
        More properties for the run, such as Assignments.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.PermissionRun: Results, the counts
        Assigned, Removed, Unchanged, Skipped, Failed and WhatIf, Duration,
        ExitCode (1 when anything failed), and the extra properties.

    .EXAMPLE
        New-iSOCPermissionRun -Results $results -Started $started
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory and logs; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Results,

        [Parameter(Mandatory)]
        [datetime] $Started,

        [hashtable] $Extra = @{}
    )

    $count = { param([string] $Outcome) @($Results | Where-Object { $_.Outcome -eq $Outcome }).Count }
    $run = [ordered]@{
        PSTypeName = 'iSOCDeployments.PermissionRun'
        Results    = @($Results)
        Assigned   = & $count 'Assigned'
        Removed    = & $count 'Removed'
        Unchanged  = & $count 'Unchanged'
        Skipped    = & $count 'Skipped'
        Failed     = & $count 'Failed'
        WhatIf     = & $count 'WhatIf'
        Duration   = (Get-Date) - $Started
    }
    $run.ExitCode = [int]($run.Failed -gt 0)
    foreach ($key in $Extra.Keys) { $run[$key] = $Extra[$key] }

    Write-iSOCLog 'Summary' -Level Section
    foreach ($name in 'Assigned', 'Removed', 'Unchanged', 'Skipped', 'Failed', 'WhatIf') {
        if ($run[$name] -gt 0 -or $name -in 'Assigned', 'Failed') { Write-iSOCLog ('  {0,-10} {1}' -f "${name}:", $run[$name]) }
    }
    if ($run.Failed -gt 0) { Write-iSOCLog 'Some role assignments failed. The identity running this needs Owner or User Access Administrator on the scopes.' -Level Error }
    [pscustomobject]$run
}
