#Requires -Version 7.6

<#
.SYNOPSIS
    Rewrite the quoted identifier forms ['Name'] and ["Name"] as a bare name.

.DESCRIPTION
    Runs before string literals are removed, so a function named in its
    quoted form is still seen as a reference.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Expand-iSOCKqlQuotedIdentifier.ps1
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

function Expand-iSOCKqlQuotedIdentifier {
    <#
    .SYNOPSIS
        Rewrite the quoted identifier forms ['Name'] and ["Name"] as a bare
        name.

    .DESCRIPTION
        KQL quotes a name with special characters, or one that clashes with
        a keyword, as ['Name'] or ["Name"], and the form is legal for any
        name. Rewriting it as a bare name keeps the reference when string
        literals are removed next. A bracket after a name, ')' or ']' is an
        index into a value (parse_json(x)["foo"], Properties['bar']), not a
        quoted name, and is left alone, so its key does not become a name.

    .PARAMETER Text
        The KQL text.

    .OUTPUTS
        [string] The text with each quoted name bare, or '' for no text.

    .EXAMPLE
        Expand-iSOCKqlQuotedIdentifier -Text "['My Parser'] | take 1"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    [regex]::Replace($Text, '(?<![A-Za-z0-9_)\]])\[\s*([''"])([A-Za-z_][A-Za-z0-9_]*)\1\s*\]', ' $2 ')
}
