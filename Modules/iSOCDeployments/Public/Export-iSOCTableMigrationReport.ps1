#Requires -Version 7.2

<#
.SYNOPSIS
    Write a table migration review as CSV, JSON and a self-contained HTML report.

.DESCRIPTION
    Export-iSOCTableMigrationReport writes the reports
    Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1 wrote.

.NOTES
    File:         Modules/iSOCDeployments/Public/Export-iSOCTableMigrationReport.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Export-iSOCTableMigrationReport {
    <#
    .SYNOPSIS
        Write a table migration review as CSV, JSON and a self-contained HTML
        report.

    .DESCRIPTION
        Into the folder, which is made when it is missing:

          tables.csv            a row per classic table
          impact.csv            a row per dependent, direct or through a
                                parser, with the chain
          solution-matches.csv  a row per table and Content Hub solution
          report.json           all of it, with the alias resolution
          report.html           a page to share: each table's dependents,
                                its solutions, where the dependency lists
                                stop, and the commands to preview and
                                migrate it

        The page loads nothing from elsewhere and runs nothing. A review
        with no classic tables writes nothing. With -WhatIf nothing is
        written.

    .PARAMETER InputObject
        The review, from Get-iSOCTableMigrationImpact.

    .PARAMETER Path
        The folder to write to. Defaults to migration-report in the current
        folder.

    .OUTPUTS
        [System.IO.FileInfo] The files written.

    .EXAMPLE
        Get-iSOCTableMigrationImpact | Export-iSOCTableMigrationReport -Path ./reports/2026-11

        Assesses the connected workspace and writes the five reports.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $InputObject,

        [string] $Path = (Join-Path (Get-Location).Path 'migration-report')
    )

    process {
        if ($InputObject.PSObject.TypeNames -notcontains 'iSOCDeployments.TableMigrationReview') {
            throw '-InputObject must be the review Get-iSOCTableMigrationImpact returns.'
        }
        if (@($InputObject.ClassicTables).Count -eq 0) {
            Write-iSOCLog 'The review found no classic tables, so no report is written.'
            return
        }

        $names = 'tables.csv', 'impact.csv', 'solution-matches.csv', 'report.json', 'report.html'
        if (-not $PSCmdlet.ShouldProcess($Path, "Write $($names -join ', ')")) { return }
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
        Write-iSOCLog 'Export reports' -Level Section
        Write-iSOCLog "Output directory: $Path" -Level Success

        $report = @{
            Tables          = $InputObject.ClassicTables
            Impacts         = $InputObject.Impacts
            SolutionMatches = $InputObject.SolutionMatches
            OutDir          = $Path
        }
        Write-iSOCTableMigrationCsv @report
        Write-iSOCLog "CSV files written to $Path" -Level Success
        Write-iSOCTableMigrationJson @report -Context $InputObject.Context -AliasResolution $InputObject.AliasResolution
        Write-iSOCLog "JSON report: $(Join-Path $Path 'report.json')" -Level Success
        Write-iSOCTableMigrationHtml @report -Context $InputObject.Context -AliasResolution $InputObject.AliasResolution

        foreach ($name in $names) { Get-Item -LiteralPath (Join-Path $Path $name) }
    }
}
