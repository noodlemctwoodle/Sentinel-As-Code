#Requires -Version 7.2

<#
.SYNOPSIS
    Validate handler for parsers.

.DESCRIPTION
    The check Deploy-CustomParsers (Deploy/content/Deploy-CustomContent.ps1)
    makes before it sends a parser, with the same message.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Parser/Test-iSOCParser.ps1
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

function Test-iSOCParser {
    <#
    .SYNOPSIS
        Say why a parser cannot be sent, if it cannot.

    .DESCRIPTION
        A parser needs id, name, functionAlias and query, none of them
        blank. A parser that fails is skipped by deploy, as it is today.

    .PARAMETER Item
        A repository item from Read-iSOCParserRepo.

    .OUTPUTS
        [string] The problem; nothing when the parser can be sent.

    .EXAMPLE
        $issues = @(Test-iSOCParser -Item $item)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if ($Item.ParseError) { return "YAML does not parse: $($Item.ParseError)" }
    $parser = $Item.Data
    if ($parser -isnot [System.Collections.IDictionary]) { return 'the file does not hold a YAML mapping' }

    $requiredFields = @('id', 'name', 'functionAlias', 'query')
    $missingFields = @($requiredFields | Where-Object { -not $parser.Contains($_) -or [string]::IsNullOrWhiteSpace($parser[$_]) })
    if ($missingFields.Count -gt 0) { return "missing required fields: $($missingFields -join ', ')" }
}
