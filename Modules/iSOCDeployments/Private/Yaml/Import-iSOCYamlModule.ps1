#Requires -Version 7.6

<#
.SYNOPSIS
    Load powershell-yaml the first time a command reads or writes YAML.

.DESCRIPTION
    The scripts this module replaces each installed powershell-yaml from the
    PowerShell Gallery when it was missing. The module installs nothing: it
    loads the version the requirement table names, and says how to install
    it when it is not there (MIGRATION.md edit E4).

.NOTES
    File:         Modules/iSOCDeployments/Private/Yaml/Import-iSOCYamlModule.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Import-iSOCYamlModule {
    <#
    .SYNOPSIS
        Make ConvertFrom-Yaml and ConvertTo-Yaml available, or say why not.

    .DESCRIPTION
        Does nothing when ConvertFrom-Yaml already resolves. Otherwise imports
        the newest installed powershell-yaml at or above the version in the
        requirement table, and throws with the install command when there is
        none.

    .EXAMPLE
        Import-iSOCYamlModule
    #>
    [CmdletBinding()]
    param()

    if (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue) { return }

    $requirement = Get-iSOCRequirement | Where-Object Name -EQ 'powershell-yaml' | Select-Object -First 1
    $minimum = [version]$requirement.MinimumVersion
    $installed = Get-Module -ListAvailable -Name powershell-yaml |
        Where-Object { $_.Version -ge $minimum } |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $installed) {
        throw "Reading YAML content needs powershell-yaml $minimum or later. $($requirement.Hint)"
    }
    Import-Module -Name $installed.Path -ErrorAction Stop
}
