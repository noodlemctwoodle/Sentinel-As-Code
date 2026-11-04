#Requires -Version 7.2

<#
.SYNOPSIS
    Every content type the module knows, checked and in deploy order.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Get-iSOCContentTypeRegistry.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.4.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentTypeRegistry {
    <#
    .SYNOPSIS
        Build the content type objects from their definitions.

    .DESCRIPTION
        Each type has a folder under Private/ContentTypes/ holding a
        Get-iSOC<Type>Definition function and the handlers it names. Deploy,
        export, compare, sync and the dependency manifest all walk this list,
        so they cannot disagree about where a type's files are or how its
        items are named. A definition that fails
        Test-iSOCContentTypeDefinition stops the module from using any type,
        since a half-registered type would be skipped without a word.

    .OUTPUTS
        [pscustomobject] One per type, with the type name
        iSOCDeployments.ContentType, sorted by DeployOrder.

    .EXAMPLE
        Get-iSOCContentTypeRegistry | Select-Object Name, DeployOrder
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $names = @('WorkspaceSetting', 'Parser', 'Watchlist', 'AnalyticsRule', 'HuntingQuery', 'Playbook', 'Workbook', 'AutomationRule', 'SummaryRule', 'DefenderDetection')

    $types = foreach ($name in $names) {
        $definition = & "Get-iSOC${name}Definition"
        $issues = @(Test-iSOCContentTypeDefinition -Definition $definition)
        if ($issues.Count -gt 0) {
            throw "Content type '$name' is defined wrongly: $($issues -join '; ')"
        }
        $type = [ordered]@{ PSTypeName = 'iSOCDeployments.ContentType' }
        foreach ($key in 'Name', 'DisplayName', 'RepoFolder', 'Layout', 'Format', 'FilePattern', 'Recurse', 'Endpoint',
            'Scope', 'CollectionPath', 'ApiVersion', 'IdentityKey', 'DeployOrder', 'SettleSeconds', 'MissingDependency', 'Capabilities',
            'Prerequisites', 'Handlers', 'Fields') {
            $type[$key] = $definition[$key]
        }
        [pscustomobject]$type
    }

    $types | Sort-Object DeployOrder, Name
}
