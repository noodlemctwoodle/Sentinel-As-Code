#Requires -Version 7.2

<#
.SYNOPSIS
    Stop a command before it starts when its step cannot run here.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Assert-iSOCPrerequisite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Assert-iSOCPrerequisite {
    <#
    .SYNOPSIS
        Throw, naming every missing requirement and how to install it.

    .PARAMETER Step
        The steps the command is about to run.

    .EXAMPLE
        Assert-iSOCPrerequisite -Step Connect
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Step
    )

    $missing = @(foreach ($requirement in Get-iSOCRequirement) {
            if (-not $requirement.Required) { continue }
            if (@($requirement.Step | Where-Object { $_ -in $Step }).Count -eq 0) { continue }
            $result = Test-iSOCRequirement -Requirement $requirement
            if (-not $result.Found) { "$($result.Name): $($result.Detail)" }
        })
    if ($missing.Count -gt 0) {
        throw "This machine is missing what $($Step -join ' and ') needs. $($missing -join ' ')"
    }
}
