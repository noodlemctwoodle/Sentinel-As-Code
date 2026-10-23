#Requires -Version 7.2

<#
.SYNOPSIS
    What each step of iSOCDeployments needs on the machine running it.

.DESCRIPTION
    One definition per requirement: the PowerShell version and the
    PowerShell Gallery modules, with the steps each one serves. The module
    installs none of them; Test-iSOCDeploymentPrerequisite reports them and
    each command checks its own step before it starts.

    Steps:
      Connect   Connect-iSOCWorkspace
      Read      reading YAML content from the repository

    More steps join the table as the deploy, export, compare, sync and
    manifest commands land.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Get-iSOCRequirement.ps1
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

function Get-iSOCRequirement {
    <#
    .SYNOPSIS
        The requirement definitions, unevaluated.

    .OUTPUTS
        [pscustomobject] Name, Kind (PowerShell or Module), Step, Required,
        MinimumVersion and Hint (how to install it).

    .EXAMPLE
        Get-iSOCRequirement | Where-Object Step -contains 'Read'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $all = 'Connect', 'Read'
    $new = {
        param($Name, $Kind, $Step, $MinimumVersion, $Hint)
        [pscustomobject]@{
            Name           = $Name
            Kind           = $Kind
            Step           = @($Step)
            Required       = $true
            MinimumVersion = $MinimumVersion
            Hint           = $Hint
        }
    }

    & $new 'PowerShell' 'PowerShell' $all '7.2' 'Install PowerShell 7.2 or later: https://aka.ms/powershell'
    & $new 'Az.Accounts' 'Module' 'Connect' '2.0.0' 'Install-Module Az.Accounts -Scope CurrentUser, then sign in with Connect-AzAccount.'
    & $new 'powershell-yaml' 'Module' 'Read' '0.4.12' 'Install-Module powershell-yaml -RequiredVersion 0.4.12 -Scope CurrentUser'
}
