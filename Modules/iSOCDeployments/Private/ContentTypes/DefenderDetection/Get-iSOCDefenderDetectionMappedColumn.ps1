#Requires -Version 7.6

<#
.SYNOPSIS
    The query result columns a detection's mappings and actions depend
    on.

.DESCRIPTION
    Copied from Get-DetectionMappedColumn
    (Deploy/content/Deploy-DefenderDetections.ps1), which
    Tests/Test-DefenderDetectionYaml.Tests.ps1 uses to check every column a
    rule names is one its query mentions.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Get-iSOCDefenderDetectionMappedColumn.ps1
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

function Get-iSOCDefenderDetectionMappedColumn {
    <#
    .SYNOPSIS
        Return each column named by a rule's entity mappings, automated
        actions and custom details, once.

    .PARAMETER Rule
        The rule in the current Graph shape.

    .OUTPUTS
        [string[]] The column names, in the order first named.

    .EXAMPLE
        Get-iSOCDefenderDetectionMappedColumn -Rule $item.Rule
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Rule
    )

    $columns = [System.Collections.Generic.List[string]]::new()
    $action = $Rule['detectionAction']
    $template = if ($action -is [System.Collections.IDictionary]) { $action['alertTemplate'] } else { $null }

    $collections = @()
    if ($template -is [System.Collections.IDictionary] -and $template['entityMappings'] -is [System.Collections.IDictionary]) {
        $collections += @($template['entityMappings'].Values)
    }
    if ($action -is [System.Collections.IDictionary] -and $action['automatedActions'] -is [System.Collections.IDictionary]) {
        $collections += @($action['automatedActions'].Values)
    }
    foreach ($entry in @($collections | ForEach-Object { $_ })) {
        if (-not ($entry -is [System.Collections.IDictionary])) { continue }
        foreach ($key in $entry.Keys) {
            if ($key -like '*Column' -and -not [string]::IsNullOrWhiteSpace([string]$entry[$key])) { $columns.Add([string]$entry[$key]) }
        }
    }
    if ($template -is [System.Collections.IDictionary] -and $template['customDetails'] -is [System.Collections.IDictionary]) {
        foreach ($value in $template['customDetails'].Values) { if ($value) { $columns.Add([string]$value) } }
    }

    @($columns | Select-Object -Unique)
}
