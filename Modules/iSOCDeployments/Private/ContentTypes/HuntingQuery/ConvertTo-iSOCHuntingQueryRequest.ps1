#Requires -Version 7.6

<#
.SYNOPSIS
    ToRequest handler for hunting queries: the body deploy sends.

.DESCRIPTION
    Copied from the body builder inside Deploy-CustomHuntingQueries
    (Deploy/content/Deploy-CustomContent.ps1), unchanged in what it sends.
    Tests/iSOCDeployments/HuntingQuery.Tests.ps1 runs both over every query
    in Content/HuntingQueries/ and compares the requests.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/HuntingQuery/ConvertTo-iSOCHuntingQueryRequest.ps1
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

function ConvertTo-iSOCHuntingQueryRequest {
    <#
    .SYNOPSIS
        Build the saved search request body for one hunting query file.

    .DESCRIPTION
        Builds { properties } as Deploy-CustomContent.ps1 does: the category
        is Hunting Queries, and the description, tactics, techniques and
        the file's own tags become saved search tags. Tactics are joined
        with commas; techniques are split into parent techniques and a
        separate subTechniques tag. The function reads nothing outside the
        item and sends nothing.

    .PARAMETER Item
        A repository item from Read-iSOCHuntingQueryRepo that passed
        Test-iSOCHuntingQuery.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Request: ContentType, Identity,
        ResourceName (the id as written) and Body.

    .EXAMPLE
        $request = ConvertTo-iSOCHuntingQueryRequest -Item $item
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $hq = $Item.Data

    # Build tags array for the saved search
    $tags = @()

    if ($hq.Contains('description') -and -not [string]::IsNullOrWhiteSpace($hq['description'])) {
        $tags += @{ name = "description"; value = $hq['description'] }
    }
    if ($hq.Contains('tactics') -and $hq['tactics']) {
        $tacticsValue = ([array]$hq['tactics']) -join ','
        $tags += @{ name = "tactics"; value = $tacticsValue }
    }
    if ($hq.Contains('techniques') -and $hq['techniques']) {
        $allTechs = [array]$hq['techniques']
        # Parent techniques (T####)
        $techniquesValue = ($allTechs | ForEach-Object { ($_ -split '\.')[0] } | Select-Object -Unique) -join ','
        $tags += @{ name = "techniques"; value = $techniquesValue }
        # Sub-techniques (T####.###) as separate tag
        $subTechsValue = ($allTechs | Where-Object { $_ -match '\.' } | Select-Object -Unique) -join ','
        if ($subTechsValue) {
            $tags += @{ name = "subTechniques"; value = $subTechsValue }
        }
    }
    if ($hq.Contains('tags') -and $hq['tags']) {
        foreach ($tag in $hq['tags']) {
            $tags += @{ name = $tag['name']; value = $tag['value'] }
        }
    }

    $properties = @{
        category    = "Hunting Queries"
        displayName = $hq['name']
        query       = $hq['query']
    }

    if ($tags.Count -gt 0) {
        $properties.tags = $tags
    }

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.Request'
        ContentType  = $Item.ContentType
        Identity     = $Item.Identity
        ResourceName = [string]$hq['id']
        Body         = @{
            properties = $properties
        }
    }
}
