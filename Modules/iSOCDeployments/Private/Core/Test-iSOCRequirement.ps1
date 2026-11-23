#Requires -Version 7.6

<#
.SYNOPSIS
    Evaluate one requirement on this machine.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Test-iSOCRequirement.ps1
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

function Test-iSOCRequirement {
    <#
    .SYNOPSIS
        Say whether one requirement is met, and where it was found.

    .PARAMETER Requirement
        One object from Get-iSOCRequirement.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Prerequisite: Name, Step, Required,
        Found, Version and Detail (where it was found, or the hint when it
        was not).

    .EXAMPLE
        Get-iSOCRequirement | ForEach-Object { Test-iSOCRequirement -Requirement $_ }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Requirement
    )

    $found = $false
    $version = $null
    $where = $null
    $minimum = if ($Requirement.MinimumVersion) { [version]$Requirement.MinimumVersion } else { $null }

    switch ($Requirement.Kind) {
        'PowerShell' {
            $current = $PSVersionTable.PSVersion
            $version = $current.ToString()
            $found = ($null -eq $minimum) -or ([version]('{0}.{1}.{2}' -f $current.Major, $current.Minor, $current.Patch) -ge $minimum)
            $where = "PowerShell $version"
        }
        'Module' {
            $module = Get-Module -ListAvailable -Name $Requirement.Name | Sort-Object Version -Descending | Select-Object -First 1
            if ($module) {
                $version = $module.Version.ToString()
                $found = ($null -eq $minimum) -or ($module.Version -ge $minimum)
                $where = $module.ModuleBase
            }
        }
        'Command' {
            $command = Get-Command -Name $Requirement.Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($command) {
                $where = $command.Source
                $text = try { & $command.Source --version 2>$null | Select-Object -First 1 } catch { $null }
                if ("$text" -match '(\d+\.\d+(\.\d+)?)') {
                    $version = $Matches[1]
                    $found = ($null -eq $minimum) -or ([version]$version -ge $minimum)
                } else {
                    $found = $null -eq $minimum
                }
            }
        }
    }

    $label = if ($minimum) { "$($Requirement.Name) $minimum+" } else { $Requirement.Name }
    [pscustomobject]@{
        PSTypeName = 'iSOCDeployments.Prerequisite'
        Name       = $label
        Step       = $Requirement.Step
        Required   = $Requirement.Required
        Found      = [bool]$found
        Version    = $version
        Detail     = if ($found) { $where } else { $Requirement.Hint }
    }
}
