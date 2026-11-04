#Requires -Version 7.2

<#
.SYNOPSIS
    Seed each dependency fixture table through the Data Collector API.

.DESCRIPTION
    A table already there and owned is skipped unless -Reseed; the workspace
    key is read only once a post is allowed.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Invoke-iSOCFixtureSeed.ps1
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

function Invoke-iSOCFixtureSeed {
    <#
    .SYNOPSIS
        Seed each dependency fixture table through the Data Collector API.

    .DESCRIPTION
        Each table gets -RecordCount records (New-iSOCDependencyFixtureRecord)
        carrying the marker '<marker>|<run>', asking ShouldProcess. A table
        that already exists and is the fixture's is skipped unless -Reseed:
        posting again is billable and buys nothing. The workspace key is read
        only after the first post is allowed, so -WhatIf reads no key. A post
        that fails is a warning and counted.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Fixture
        From Get-iSOCDependencyFixturePlan.

    .PARAMETER RunId
        The run.

    .PARAMETER RecordCount
        Records per table.

    .PARAMETER OdsEndpointSuffix
        The Data Collector host suffix.

    .PARAMETER Reseed
        Post to owned tables that exist.

    .OUTPUTS
        [pscustomobject] Created, Skipped, Failed and Seeded (the tables
        posted to).

    .EXAMPLE
        Invoke-iSOCFixtureSeed -Context $ctx -Fixture $fixture -RunId $runId -RecordCount 5 -OdsEndpointSuffix ods.opinsights.azure.com
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $Fixture,

        [Parameter(Mandatory)]
        [string] $RunId,

        [Parameter(Mandatory)]
        [int] $RecordCount,

        [Parameter(Mandatory)]
        [string] $OdsEndpointSuffix,

        [switch] $Reseed
    )

    Write-iSOCLog 'Seeding classic tables' -Level Section
    Write-iSOCLog 'Microsoft ended support for the HTTP Data Collector API on 2026-09-14. It still accepts data from TLS 1.2 clients, with no SLA.' -Level Warning

    $created = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $seeded = [System.Collections.Generic.List[string]]::new()
    $ingestUri = "https://$($Context.WorkspaceId).$OdsEndpointSuffix/api/logs?api-version=2016-04-01"
    $markerValue = "$((Get-iSOCDependencyFixtureSetting).FixtureMarker)|$RunId"
    $sharedKey = $null

    foreach ($table in $Fixture.Plan.Table) {
        $row = $Fixture.Rows | Where-Object { $_.Type -eq 'Table' -and $_.Name -eq $table.TableName } | Select-Object -First 1
        if ($row -and $row.Action -eq 'UPDATE' -and -not $Reseed) {
            Write-iSOCLog "$($table.TableName) already exists and is marked as this fixture's. Skipping the seed (pass -Reseed to post again)."
            $skipped.Add($row.ResourceId)
            continue
        }
        if (-not $PSCmdlet.ShouldProcess("$($Context.WorkspaceName)/$($table.TableName)", "Post $RecordCount fixture records via Data Collector API")) {
            Write-iSOCLog "Skipped seeding $($table.TableName)." -Level Warning
            continue
        }
        if (-not $sharedKey) { $sharedKey = Get-iSOCWorkspaceSharedKey -Context $Context }

        $resource = "$($Fixture.WorkspaceBase)/tables/$($table.TableName)"
        try {
            $records = New-iSOCDependencyFixtureRecord -Count $RecordCount -ReferenceTime ([datetime]::UtcNow) -Marker $markerValue -ScenarioName $table.ScenarioName
            Send-iSOCDataCollectorBatch -IngestUri $ingestUri -WorkspaceId $Context.WorkspaceId -SharedKey $sharedKey -LogType $table.LogType -Record $records
            Write-iSOCLog "Posted $RecordCount records to $($table.TableName)." -Level Success
            $created.Add($resource)
            $seeded.Add($table.TableName)
        }
        catch {
            Write-iSOCLog "Failed to seed $($table.TableName): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
            $failed.Add($resource)
        }
    }
    [pscustomobject]@{ Created = $created.ToArray(); Skipped = $skipped.ToArray(); Failed = $failed.ToArray(); Seeded = $seeded.ToArray() }
}
