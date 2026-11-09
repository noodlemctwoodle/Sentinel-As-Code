#Requires -Version 7.6

<#
.SYNOPSIS
    Write the review as report.html, a self-contained page.

.DESCRIPTION
    The data goes into the module's report template as one escaped JSON
    literal; the page renders it in the browser and runs nothing else.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Write-iSOCTableMigrationHtml.ps1
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

function Write-iSOCTableMigrationHtml {
    <#
    .SYNOPSIS
        Write the review as report.html, a self-contained page.

    .DESCRIPTION
        The template is Resources/ClassicToDcr/report.html.template. The
        data (when it was made, the workspace, the totals, the tables, their
        impact, their solutions and the alias resolution, so the page shows
        where the dependency lists stop) replaces {{DATA_JSON}} as one
        escaped JavaScript string. The page loads nothing from elsewhere.

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

    .PARAMETER TemplatePath
        The template. Defaults to the module's own.

    .EXAMPLE
        Write-iSOCTableMigrationHtml -Tables $t -Impacts $i -SolutionMatches $m -Context $review.Context -OutDir ./migration-report -AliasResolution $review.AliasResolution
    #>
    [CmdletBinding()]
    param(
        $Tables,

        $Impacts,

        $SolutionMatches,

        $Context,

        [Parameter(Mandatory)]
        [string] $OutDir,

        $AliasResolution,

        [string] $TemplatePath = (Join-Path $script:iSOCDeploymentsRoot 'Resources/ClassicToDcr/report.html.template')
    )

    $template = Get-Content -LiteralPath $TemplatePath -Raw

    $data = [ordered]@{
        GeneratedAt     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Subscription    = $Context.SubscriptionId
        ResourceGroup   = $Context.ResourceGroupName
        Workspace       = $Context.WorkspaceName
        TotalTables     = $Tables.Count
        TotalImpacted   = ($Impacts | Measure-Object -Property TotalImpacted -Sum).Sum
        TotalIndirect   = ($Impacts | Measure-Object -Property TotalIndirect -Sum).Sum
        Tables          = $Tables
        Impacts         = $Impacts
        SolutionMatches = $SolutionMatches
        AliasResolution = $AliasResolution
    }

    $dataJson = ($data | ConvertTo-Json -Depth 20 -Compress)
    $html = $template.Replace('{{DATA_JSON}}', (ConvertTo-iSOCJsStringLiteral -Value $dataJson))

    $outFile = Join-Path $OutDir 'report.html'
    $html | Out-File -FilePath $outFile -Encoding utf8
    Write-iSOCLog "HTML report: $outFile" -Level Success
}
