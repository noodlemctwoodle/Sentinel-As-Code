#Requires -Version 7.6

<#
.SYNOPSIS
    ToRequest handler for parsers: the body deploy sends.

.DESCRIPTION
    Copied from the body builder inside Deploy-CustomParsers
    (Deploy/content/Deploy-CustomContent.ps1), unchanged in what it sends.
    Tests/iSOCDeployments/Parser.Tests.ps1 runs both over every parser in
    Content/Parsers/ and compares the requests.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Parser/ConvertTo-iSOCParserRequest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCParserRequest {
    <#
    .SYNOPSIS
        Build the saved search request body for one parser file.

    .DESCRIPTION
        Builds { etag, properties } as Deploy-CustomContent.ps1 does: the
        etag is '*' so an existing function is overwritten; the category
        defaults to Sentinel Parsers; the saved search version is 2, which
        makes it a function; function parameters are passed when the file
        has them. The function reads nothing outside the item and sends
        nothing.

    .PARAMETER Item
        A repository item from Read-iSOCParserRepo that passed
        Test-iSOCParser.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Request: ContentType, Identity,
        ResourceName (the id as written) and Body.

    .EXAMPLE
        $request = ConvertTo-iSOCParserRequest -Item $item
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $parser = $Item.Data

    $properties = @{
        category      = if ($parser.Contains('category')) { $parser['category'] } else { 'Sentinel Parsers' }
        displayName   = $parser['name']
        query         = $parser['query']
        functionAlias = $parser['functionAlias']
        version       = 2
    }

    if ($parser.Contains('functionParameters') -and -not [string]::IsNullOrWhiteSpace($parser['functionParameters'])) {
        $properties.functionParameters = $parser['functionParameters']
    }

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.Request'
        ContentType  = $Item.ContentType
        Identity     = $Item.Identity
        ResourceName = [string]$parser['id']
        Body         = @{
            etag       = '*'
            properties = $properties
        }
    }
}
