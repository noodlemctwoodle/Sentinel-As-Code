#Requires -Version 7.6

<#
.SYNOPSIS
    Write the review as report.json.

.DESCRIPTION
    Every key keeps its meaning: TotalImpacted and the per-type lists are
    direct dependents, the Indirect lists those through parsers.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Write-iSOCTableMigrationJson.ps1
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

function Write-iSOCTableMigrationJson {
    <#
    .SYNOPSIS
        Write the review as report.json.

    .DESCRIPTION
        generatedAt, subscription, resourceGroup, workspace, classicTables,
        impactAnalysis, solutionMatches and, when given,
        parserAliasResolution. In impactAnalysis, TotalImpacted and the
        seven per-type lists are the direct dependents, the Indirect lists
        those through parsers, and TotalAffected both.

    .PARAMETER Tables
        The classic tables.

    .PARAMETER Impacts
        The impact of each table.

    .PARAMETER SolutionMatches
        The solutions of each table.

    .PARAMETER Context
        SubscriptionId, ResourceGroupName and WorkspaceName.

    .PARAMETER OutDir
        The folder to write to.

    .PARAMETER AliasResolution
        resolvedAliases, skippedAliases and warnings.

    .EXAMPLE
        Write-iSOCTableMigrationJson -Tables $t -Impacts $i -SolutionMatches $m -Context $review.Context -OutDir ./migration-report -AliasResolution $review.AliasResolution
    #>
    [CmdletBinding()]
    param(
        $Tables,

        $Impacts,

        $SolutionMatches,

        $Context,

        [Parameter(Mandatory)]
        [string] $OutDir,

        $AliasResolution
    )

    $combined = [ordered]@{
        generatedAt     = (Get-Date).ToString('o')
        subscription    = $Context.SubscriptionId
        resourceGroup   = $Context.ResourceGroupName
        workspace       = $Context.WorkspaceName
        classicTables   = $Tables
        impactAnalysis  = $Impacts
        solutionMatches = $SolutionMatches
    }
    if ($AliasResolution) { $combined['parserAliasResolution'] = $AliasResolution }
    $combined | ConvertTo-Json -Depth 20 | Out-File -FilePath (Join-Path $OutDir 'report.json') -Encoding utf8
}
