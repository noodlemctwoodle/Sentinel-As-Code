#Requires -Version 7.2

<#
.SYNOPSIS
    The names a KQL body could resolve to a workspace entity, case-sensitive.

.DESCRIPTION
    Quoted names are made bare, then comments, strings, cross-cluster
    references, member access, assignment targets and let-bound locals are
    removed before the names are read.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlReferenceIdentifierSet.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCKqlReferenceIdentifierSet {
    <#
    .SYNOPSIS
        The names a KQL body could resolve to a workspace entity,
        case-sensitive.

    .DESCRIPTION
        Quoted names are made bare (Expand-iSOCKqlQuotedIdentifier), then
        comments and strings (Get-iSOCKqlCodeText), cross-cluster references,
        member access and assignment targets
        (ConvertTo-iSOCKqlNameSearchText) and let-bound locals are taken out,
        and what is left is split into names.

        The set is ordinal: KQL names are case-sensitive, so officeparser
        does not call a parser aliased OfficeParser. This differs on purpose
        from Test-iSOCKqlTableReference, which ignores case: that decides
        direct hits, where a case slip is nearly always meant as the table,
        while this feeds the parser chains, where one false hit spreads to
        every later hop.

    .PARAMETER Text
        One or more KQL bodies.

    .OUTPUTS
        [System.Collections.Generic.HashSet[string]]

    .EXAMPLE
        Get-iSOCKqlReferenceIdentifierSet -Text 'OfficeParser | where X == 1'
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[string]])]
    param(
        [AllowNull()]
        [string[]] $Text
    )

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($t in @($Text)) {
        if ([string]::IsNullOrEmpty($t)) { continue }

        $code = Get-iSOCKqlCodeText -Text (Expand-iSOCKqlQuotedIdentifier -Text $t)
        $bound = Get-iSOCKqlLetBoundName -Text $code

        foreach ($token in ((ConvertTo-iSOCKqlNameSearchText -Text $code) -split '[^A-Za-z0-9_]+')) {
            if ($token -and -not $bound.Contains($token)) { [void]$set.Add($token) }
        }
    }
    , $set
}
