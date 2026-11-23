#Requires -Version 7.6

<#
.SYNOPSIS
    Whether a query names a table, as a whole word in any case.

.DESCRIPTION
    Test-iSOCKqlTableReference decides the direct dependents of a classic
    table in the migration review. It is a whole-word match that ignores case,
    on the query as written.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Test-iSOCKqlTableReference.ps1
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

function Test-iSOCKqlTableReference {
    <#
    .SYNOPSIS
        Whether a query names a table, as a whole word in any case.

    .DESCRIPTION
        The name matches when no letter, digit or underscore is on either
        side of it, so MyApp_CL does not match MyApp_CL_v2. Case is ignored:
        a table named in the wrong case is nearly always meant as that
        table, so reporting it errs on the safe side. Comments and strings
        are not removed first, so a table named only in a comment counts.

    .PARAMETER Query
        The KQL text. Empty or missing text names nothing.

    .PARAMETER TableName
        The table name.

    .OUTPUTS
        [bool]

    .EXAMPLE
        Test-iSOCKqlTableReference -Query 'MyApp_CL | take 1' -TableName MyApp_CL
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Query,

        [Parameter(Mandatory)]
        [string] $TableName
    )

    if (-not $Query) { return $false }
    $Query -match "(?i)(?<![a-zA-Z0-9_])$([regex]::Escape($TableName))(?![a-zA-Z0-9_])"
}
