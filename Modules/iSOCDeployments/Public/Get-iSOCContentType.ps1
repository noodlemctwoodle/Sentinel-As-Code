#Requires -Version 7.6

<#
.SYNOPSIS
    Get-iSOCContentType: the content types the module knows and what it can
    do with each.

.NOTES
    File:         Modules/iSOCDeployments/Public/Get-iSOCContentType.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentType {
    <#
    .SYNOPSIS
        List the registered content types, in deploy order.

    .DESCRIPTION
        Each content type says where its files live in the repository, how
        they reach the workspace (endpoint, scope, collection and API
        version), what names an item, the order types deploy in, what
        happens when a dependency is missing, and its capabilities: Deploy,
        Export, Compare, Sync and Dependencies. The names are what
        -ContentType takes on the other commands.

        Docs/Modules/iSOCDeployments/Content-Types.md has the same list with
        what each capability covers.

    .PARAMETER Name
        Content type names or wildcard patterns. Without it every type is
        listed. A name that matches nothing is an error.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ContentType objects.

    .EXAMPLE
        Get-iSOCContentType

        Lists every content type with its folder, endpoint and capabilities.

    .EXAMPLE
        (Get-iSOCContentType -Name AnalyticsRule).Fields

        Shows which fields a compare looks at for analytics rules, and how.
    #>
    [CmdletBinding()]
    [OutputType('iSOCDeployments.ContentType')]
    param(
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [string[]] $Name
    )

    Get-iSOCContentTypeDefinition -Name $Name
}
