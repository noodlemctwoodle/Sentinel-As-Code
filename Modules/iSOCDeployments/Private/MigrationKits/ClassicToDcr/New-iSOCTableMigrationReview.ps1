#Requires -Version 7.2

<#
.SYNOPSIS
    Build the result Get-iSOCTableMigrationImpact returns.

.DESCRIPTION
    An iSOCDeployments.TableMigrationReview: the workspace, the classic
    tables, their impact, their solutions and the alias resolution.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/New-iSOCTableMigrationReview.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCTableMigrationReview {
    <#
    .SYNOPSIS
        Build the result Get-iSOCTableMigrationImpact returns.

    .DESCRIPTION
        An iSOCDeployments.TableMigrationReview. Context holds the
        workspace's SubscriptionId, ResourceGroupName and WorkspaceName, the
        names report.json and report.html use. DirectCount and
        IndirectCount total the dependents across the tables. Every list is
        a list, even with one entry.

    .PARAMETER Context
        SubscriptionId, ResourceGroupName and WorkspaceName.

    .PARAMETER ClassicTables
        The classic tables.

    .PARAMETER Impacts
        The impact of each table.

    .PARAMETER SolutionMatches
        The solutions of each table.

    .PARAMETER AliasResolution
        resolvedAliases, skippedAliases and warnings.

    .OUTPUTS
        [pscustomobject] Context, ClassicTables, Impacts, SolutionMatches,
        AliasResolution, DirectCount and IndirectCount.

    .EXAMPLE
        New-iSOCTableMigrationReview -Context $info
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; changes nothing.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [AllowEmptyCollection()]
        [object[]] $ClassicTables = @(),

        [AllowEmptyCollection()]
        [object[]] $Impacts = @(),

        [AllowEmptyCollection()]
        [object[]] $SolutionMatches = @(),

        $AliasResolution
    )

    $direct = 0
    $indirect = 0
    foreach ($impact in $Impacts) {
        $direct += [int]$impact.TotalImpacted
        $indirect += [int]$impact.TotalIndirect
    }

    [pscustomobject]@{
        PSTypeName      = 'iSOCDeployments.TableMigrationReview'
        Context         = $Context
        ClassicTables   = @($ClassicTables)
        Impacts         = @($Impacts)
        SolutionMatches = @($SolutionMatches)
        AliasResolution = $AliasResolution
        DirectCount     = $direct
        IndirectCount   = $indirect
    }
}
