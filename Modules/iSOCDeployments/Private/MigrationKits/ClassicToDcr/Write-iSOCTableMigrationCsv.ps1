#Requires -Version 7.6

<#
.SYNOPSIS
    Write the review's tables.csv, impact.csv and solution-matches.csv.

.DESCRIPTION
    impact.csv has one row per dependent, direct or through parsers; every
    row carries every column.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Write-iSOCTableMigrationCsv.ps1
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

function Write-iSOCTableMigrationCsv {
    <#
    .SYNOPSIS
        Write the review's tables.csv, impact.csv and solution-matches.csv.

    .DESCRIPTION
        tables.csv has a row per classic table. impact.csv has a row per
        dependent: TableName, ContentType, Name and ResourceId first, where
        they always were, then DependencyKind, Via, ViaChain (the hops and
        the table, joined by ' -> '), Depth and ChainTruncated. Every row
        has every column, because Export-Csv takes the header from the first
        row. solution-matches.csv has a row per table and solution.

    .PARAMETER Tables
        The classic tables.

    .PARAMETER Impacts
        The impact of each table, from Get-iSOCTableImpactAnalysis.

    .PARAMETER SolutionMatches
        The solutions of each table, from Get-iSOCSolutionMatch.

    .PARAMETER OutDir
        The folder to write to.

    .EXAMPLE
        Write-iSOCTableMigrationCsv -Tables $review.ClassicTables -Impacts $review.Impacts -SolutionMatches $review.SolutionMatches -OutDir ./migration-report
    #>
    [CmdletBinding()]
    param(
        $Tables,

        $Impacts,

        $SolutionMatches,

        [Parameter(Mandatory)]
        [string] $OutDir
    )

    $Tables | Export-Csv -Path (Join-Path $OutDir 'tables.csv') -NoTypeInformation -Encoding UTF8

    $impactFlat = foreach ($i in $Impacts) {
        foreach ($type in 'AnalyticsRules', 'HuntingQueries', 'Parsers', 'SavedSearches', 'Workbooks', 'Playbooks', 'Dcrs') {
            foreach ($item in $i.$type) {
                [pscustomobject]@{
                    TableName      = $i.TableName
                    ContentType    = $type
                    Name           = $item.Name
                    ResourceId     = $item.ResourceId
                    DependencyKind = 'Direct'
                    Via            = ''
                    ViaChain       = ''
                    Depth          = 0
                    ChainTruncated = [bool]$i.ChainTruncated
                }
            }
            foreach ($item in $i."Indirect$type") {
                [pscustomobject]@{
                    TableName      = $i.TableName
                    ContentType    = $type
                    Name           = $item.Name
                    ResourceId     = $item.ResourceId
                    DependencyKind = 'Indirect'
                    Via            = $item.Via
                    ViaChain       = ((@($item.ViaChain) + $i.TableName) -join ' -> ')
                    Depth          = $item.Depth
                    ChainTruncated = [bool]$i.ChainTruncated
                }
            }
        }
    }
    $impactFlat | Export-Csv -Path (Join-Path $OutDir 'impact.csv') -NoTypeInformation -Encoding UTF8

    $matchFlat = foreach ($m in $SolutionMatches) {
        foreach ($s in $m.Solutions) {
            [pscustomobject]@{
                TableName      = $m.TableName
                SolutionName   = $s.SolutionName
                IsInstalled    = $s.IsInstalled
                IsInContentHub = $s.IsInContentHub
                GithubUrl      = $s.GithubUrl
            }
        }
    }
    $matchFlat | Export-Csv -Path (Join-Path $OutDir 'solution-matches.csv') -NoTypeInformation -Encoding UTF8
}
