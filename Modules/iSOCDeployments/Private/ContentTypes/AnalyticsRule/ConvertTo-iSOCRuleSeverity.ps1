#Requires -Version 7.2

<#
.SYNOPSIS
    Spell an analytics rule severity the way the API and rule files do.

.DESCRIPTION
    Copied from Convert-Severity (Tools/Test-SentinelRuleDrift.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCRuleSeverity.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCRuleSeverity {
    <#
    .SYNOPSIS
        high becomes High, and the same for Medium, Low and Informational.

    .DESCRIPTION
        In any case. Anything else comes back as given; nothing comes back
        for an empty value.

    .PARAMETER Value
        The severity.

    .OUTPUTS
        [string]

    .EXAMPLE
        ConvertTo-iSOCRuleSeverity 'high'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    switch ($Value.ToLowerInvariant()) {
        'high' { return 'High' }
        'medium' { return 'Medium' }
        'low' { return 'Low' }
        'informational' { return 'Informational' }
    }
    $Value
}
