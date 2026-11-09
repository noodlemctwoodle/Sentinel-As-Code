#Requires -Version 7.2

<#
.SYNOPSIS
    Write a name in lower camel case, as Bicep names its symbols.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/ConvertTo-iSOCBicepCamelCase.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-09
    Version:      0.1.0
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCBicepCamelCase {
    <#
    .SYNOPSIS
        Return a name with its leading capitals lowered.

    .DESCRIPTION
        A name that starts with one capital has it lowered
        (MicrosoftSentinelConnectionName gives
        microsoftSentinelConnectionName). A leading run of capitals is an
        acronym and is lowered as a whole, apart from a last capital that
        starts the next word (VTEnrichment gives vtEnrichment, ARMId gives
        armId, URL gives url). Everything after it is kept, and a name that
        does not start with a capital is returned as it is.

    .PARAMETER Name
        The name.

    .OUTPUTS
        [string] The name in lower camel case.

    .EXAMPLE
        ConvertTo-iSOCBicepCamelCase -Name 'Office365ConnectionName'   # office365ConnectionName
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name
    )

    $leading = [regex]::Match($Name, '^[A-Z]+')
    if (-not $leading.Success) { return $Name }
    $length = $leading.Length
    if ($length -eq $Name.Length) { return $Name.ToLowerInvariant() }
    if ($length -gt 1 -and [char]::IsLower($Name[$length])) { $length-- }
    $Name.Substring(0, $length).ToLowerInvariant() + $Name.Substring($length)
}
