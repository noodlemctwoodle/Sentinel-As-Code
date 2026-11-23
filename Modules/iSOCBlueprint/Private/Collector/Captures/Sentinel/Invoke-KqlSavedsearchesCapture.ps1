#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'kql-savedsearches': writes kql-savedsearches.json, hunting-queries.json, parsers-functions.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-KqlSavedsearchesCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-KqlSavedsearchesCapture {
    <#
    .SYNOPSIS
        Capture 'kql-savedsearches': writes kql-savedsearches.json, hunting-queries.json, parsers-functions.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $workspaceResourceId = $Context.workspaceResourceId

    $all = Invoke-SentinelRest -Path "$workspaceResourceId/savedSearches" -ApiVersion $apiVersions.OperationalInsights
    Save-Json -FileName 'kql-savedsearches.json' -Data $all

    if ($all) {
        # StrictMode-safe property access, savedSearch records do not all carry
        # 'functionAlias' on their PSObject, so a bare $_.properties.functionAlias
        # throws under StrictMode 'Latest'. Use HasMember-style probing.
        $hunting = @($all | Where-Object {
            $cat = $null
            if ($_.properties -and ($_.properties.PSObject.Properties.Name -contains 'category')) {
                $cat = $_.properties.category
            }
            $cat -eq 'Hunting Queries'
        })
        $parsers = @($all | Where-Object {
            $cat = $null; $alias = $null
            if ($_.properties) {
                if ($_.properties.PSObject.Properties.Name -contains 'category')      { $cat   = $_.properties.category }
                if ($_.properties.PSObject.Properties.Name -contains 'functionAlias') { $alias = $_.properties.functionAlias }
            }
            ($cat -eq 'Functions') -or $alias
        })
        Save-Json -FileName 'hunting-queries.json'  -Data $hunting
        Save-Json -FileName 'parsers-functions.json' -Data $parsers
    }
}
