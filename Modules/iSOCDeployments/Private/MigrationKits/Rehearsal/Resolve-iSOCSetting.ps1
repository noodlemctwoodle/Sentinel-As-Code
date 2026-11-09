#Requires -Version 7.6

<#
.SYNOPSIS
    The first value given: the parameter, else each named setting from the environment or the .env file.

.DESCRIPTION
    For each name in order, the environment's value wins over the file's.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Resolve-iSOCSetting.ps1
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

function Resolve-iSOCSetting {
    <#
    .SYNOPSIS
        The first value given: the parameter, else each named setting from
        the environment or the .env file.

    .DESCRIPTION
        A value passed explicitly wins. Otherwise each name is tried in
        order, and for each the environment's value wins over the file's,
        so an exported variable always beats the file. Nothing is written to
        the environment.

    .PARAMETER Explicit
        The parameter's value.

    .PARAMETER EnvName
        The setting names, in order.

    .PARAMETER File
        The .env file's settings, from Import-iSOCDotEnv.

    .OUTPUTS
        [string] The value; nothing when none is set.

    .EXAMPLE
        Resolve-iSOCSetting -Explicit $TenantId -EnvName DCR_INGEST_TENANT_ID, AZURE_TENANT_ID -File $settings
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Explicit,

        [Parameter(Mandatory)]
        [string[]] $EnvName,

        [hashtable] $File = @{}
    )

    if (-not [string]::IsNullOrWhiteSpace($Explicit)) { return $Explicit }
    foreach ($name in $EnvName) {
        $value = [System.Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($value) -and $File.ContainsKey($name)) { $value = [string]$File[$name] }
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    $null
}
