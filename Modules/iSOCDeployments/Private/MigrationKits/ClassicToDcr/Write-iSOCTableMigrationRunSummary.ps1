#Requires -Version 7.6

<#
.SYNOPSIS
    Log what a migration run did, and what to do next for each rule it deployed.

.DESCRIPTION
    The counts, the failures, and for Direct rules the ingestion URL and the
    rehearsal command that sends a test stream.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Write-iSOCTableMigrationRunSummary.ps1
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

function Write-iSOCTableMigrationRunSummary {
    <#
    .SYNOPSIS
        Log what a migration run did, and what to do next for each rule it
        deployed.

    .DESCRIPTION
        The tables processed, migrated, deployed and failed, with each
        failure. For Direct rules that were deployed: whether the ingestion
        role still needs granting, each rule's ingestion URL (or that it has
        no endpoint), and the rehearsal command that sends a test stream to
        it.

    .PARAMETER Results
        The results, from Invoke-iSOCTableMigrationItem.

    .PARAMETER DcrKind
        Direct or TextLog.

    .PARAMETER DcrResourceGroupName
        The resource group the rules went in.

    .EXAMPLE
        Write-iSOCTableMigrationRunSummary -Results $results -DcrKind Direct -DcrResourceGroupName rg-dcr
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Results,

        [Parameter(Mandatory)]
        [string] $DcrKind,

        [Parameter(Mandatory)]
        [string] $DcrResourceGroupName
    )

    Write-iSOCLog ''
    Write-iSOCLog 'Summary' -Level Section
    $failed = @($Results | Where-Object { $_.Error })
    Write-iSOCLog "Processed : $($Results.Count)"
    Write-iSOCLog "Migrated  : $(@($Results | Where-Object { $_.Migrated }).Count)"
    Write-iSOCLog "Deployed  : $(@($Results | Where-Object { $_.Deployed }).Count)"
    if ($failed.Count -gt 0) {
        Write-iSOCLog "Failed    : $($failed.Count)" -Level Warning
        foreach ($f in $failed) { Write-iSOCLog "  $($f.TableName): $($f.Error)" -Level Warning }
    }

    $deployedResults = @($Results | Where-Object { $_.Deployed })
    if ($DcrKind -ne 'Direct' -or $deployedResults.Count -eq 0) { return }

    $anyGranted = @($deployedResults | Where-Object { @($_.Granted).Count -gt 0 }).Count -gt 0
    Write-iSOCLog ''
    if ($anyGranted) { Write-iSOCLog 'Next: the ingestion role is granted. Send data to:' }
    else { Write-iSOCLog 'Next: grant Monitoring Metrics Publisher on each DCR (re-run with -GrantIngestionRoleTo), then send to:' }

    foreach ($r in $deployedResults) {
        $stream = "Custom-$($r.TableName)"
        if ($r.Endpoint -and $r.ImmutableId) {
            Write-iSOCLog "  $($r.Endpoint)/dataCollectionRules/$($r.ImmutableId)/streams/${stream}?api-version=2023-01-01"
        } else {
            Write-iSOCLog "  $($r.TableName): no ingestion endpoint on the DCR (needs a Data Collection Endpoint)." -Level Warning
        }
    }

    Write-iSOCLog ''
    Write-iSOCLog 'For a test stream, Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1 builds and sends that POST for you:'
    foreach ($r in $deployedResults) {
        if ($r.DcrName) {
            Write-iSOCLog "  ./Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1 -DcrName $($r.DcrName) -DcrResourceGroupName $DcrResourceGroupName -Follow"
        }
    }
}
