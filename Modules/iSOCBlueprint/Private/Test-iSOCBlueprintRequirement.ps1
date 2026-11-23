#Requires -Version 7.6

<#
.SYNOPSIS
    Evaluate one requirement definition on this machine

.DESCRIPTION
    One of the helpers beside Get-iSOCBlueprintRequirement.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Test-iSOCBlueprintRequirement.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCBlueprintRequirement {
    <#
    .SYNOPSIS
        Evaluate one requirement definition on this machine.

    .PARAMETER Requirement
        One object from Get-iSOCBlueprintRequirement.

    .OUTPUTS
        [pscustomobject] Name, Step, Required, Found, Version and Detail
        (where it was found, or the hint when it was not).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [pscustomobject] $Requirement)

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
        'Tool' {
            $cmd = $null
            foreach ($name in $Requirement.Command) {
                $cmd = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($cmd) { break }
            }
            if (-not $cmd -and $Requirement.Name -eq 'LibreOffice') {
                $mac = '/Applications/LibreOffice.app/Contents/MacOS/soffice'
                if (Test-Path -LiteralPath $mac) { $where = $mac; $found = $true }
            }
            if ($cmd) {
                $where = $cmd.Source
                $found = $true
                if ($Requirement.Name -eq 'python3 with uno') {
                    & $cmd.Source -c 'import uno' 2>$null | Out-Null
                    $found = ($LASTEXITCODE -eq 0)
                    if (-not $found) { $where = $null }
                }
            }
        }
    }

    $label = if ($minimum) { "$($Requirement.Name) $minimum+" } else { $Requirement.Name }
    [pscustomobject]@{
        PSTypeName = 'iSOCBlueprint.Prerequisite'
        Name       = $label
        Step       = $Requirement.Step
        Required   = $Requirement.Required
        Found      = [bool]$found
        Version    = $version
        Detail     = if ($found) { $where } else { $Requirement.Hint }
    }
}
