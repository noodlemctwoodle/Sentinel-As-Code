#Requires -Version 7.6

<#
.SYNOPSIS
    The names a let statement introduces in a query.

.DESCRIPTION
    A let binding shadows a stored function of the same name for the rest of
    the query, so its name there is a local, not a parser reference.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlLetBoundName.ps1
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

function Get-iSOCKqlLetBoundName {
    <#
    .SYNOPSIS
        The names a let statement introduces in a query.

    .DESCRIPTION
        A let binding shadows a stored function of the same name for the
        rest of the query, so an occurrence of that name is a local and not
        a reference to a parser. The set is case-sensitive, as KQL names are.

    .PARAMETER Text
        The code text, from Get-iSOCKqlCodeText.

    .OUTPUTS
        [System.Collections.Generic.HashSet[string]]

    .EXAMPLE
        Get-iSOCKqlLetBoundName -Text 'let Recent = T | take 5; Recent'
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[string]])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Text
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ([string]::IsNullOrEmpty($Text)) { return , $names }
    foreach ($m in [regex]::Matches($Text, '(?<![A-Za-z0-9_])let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=')) {
        [void]$names.Add($m.Groups[1].Value)
    }
    , $names
}
