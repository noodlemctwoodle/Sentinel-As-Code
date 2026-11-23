#Requires -Version 7.6

<#
.SYNOPSIS
    Stop a command before it starts when its step cannot run here.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Assert-iSOCPrerequisite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

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

    .PARAMETER Name
        Requirements by name as well, such as the Prerequisites a content
        type lists.

    .PARAMETER Purpose
        What the requirements are for, as the error names it; the steps
        joined with 'and' when it is not given.

    .EXAMPLE
        Assert-iSOCPrerequisite -Step Connect

    .EXAMPLE
        Assert-iSOCPrerequisite -Name Az.Resources -Purpose 'deploying playbooks'
    #>
    [CmdletBinding()]
    param(
        [string[]] $Step = @(),

        [string[]] $Name = @(),

        [string] $Purpose
    )

    $missing = @(foreach ($requirement in Get-iSOCRequirement) {
            if (-not $requirement.Required) { continue }
            if (@($requirement.Step | Where-Object { $_ -in $Step }).Count -eq 0 -and $requirement.Name -notin $Name) { continue }
            $result = Test-iSOCRequirement -Requirement $requirement
            if (-not $result.Found) { "$($result.Name): $($result.Detail)" }
        })
    if ($missing.Count -gt 0) {
        $what = if ($Purpose) { $Purpose } else { $Step -join ' and ' }
        throw "This machine is missing what $what needs. $($missing -join ' ')"
    }
}
