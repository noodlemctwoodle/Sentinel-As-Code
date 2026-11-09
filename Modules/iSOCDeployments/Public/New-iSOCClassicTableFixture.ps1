#Requires -Version 7.6

<#
.SYNOPSIS
    Make a throwaway classic custom log table with synthetic data, to rehearse a migration on.

.DESCRIPTION
    New-iSOCClassicTableFixture replaces the create and stream paths of
    Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Public/New-iSOCClassicTableFixture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCClassicTableFixture {
    <#
    .SYNOPSIS
        Make a throwaway classic custom log table with synthetic data, to
        rehearse a migration on.

    .DESCRIPTION
        A migration to DCR-based cannot be undone, so it is rehearsed on a
        table nobody needs. Only the HTTP Data Collector API makes a genuine
        classic table: posting to it creates one with the _s, _d, _b and _g
        columns it infers from the fields. This reads the workspace key
        through the Az sign-in (it is never shown), posts synthetic records
        of each type, signed, and waits for the table to appear and reports
        its sub type, which should be Classic. With -Stream it keeps posting
        batches on an interval instead, as the legacy source in a cut-over
        test while the table is migrated and the new path started with
        Test-iSOCDcrIngestion.

        Microsoft ended support for the Data Collector API on 14 September
        2026. It still accepts data from clients using TLS 1.2 or later, but
        with no SLA, and that may end.

        Use a test workspace only: this writes real data and makes a real,
        billable table. Remove-iSOCClassicTableFixture deletes it.

    .PARAMETER TableName
        The table, for example SacMigrationTest. The API adds _CL; a name
        that has it already is taken without it.

    .PARAMETER RecordCount
        Records to post, or per batch with -Stream. 1 to 10000, default 50.

    .PARAMETER OdsEndpointSuffix
        The Data Collector host suffix. Defaults to the Az sign-in's cloud's
        (ods.opinsights.azure.com, .us or .cn).

    .PARAMETER TimeoutSeconds
        How long to wait for the table to appear, 30 to 1800. Default 300.
        Not used with -Stream.

    .PARAMETER Stream
        Post batches on an interval instead of once, without waiting for the
        table.

    .PARAMETER IntervalSeconds
        Seconds between batches with -Stream, 1 to 3600. Default 10.

    .PARAMETER DurationSeconds
        Stop streaming after this long.

    .PARAMETER BatchCount
        Stop streaming after this many batches, counting any that fail. With
        neither this nor -DurationSeconds, streaming runs until Ctrl-C.

    .PARAMETER Context
        The workspace, from Connect-iSOCWorkspace. Defaults to the
        connected one.

    .OUTPUTS
        [pscustomobject] TableName, LogType, RecordCount, SubType and
        WorkspaceId; with -Stream, TableName, LogType, BatchesSent,
        BatchesFailed and RecordsSent. Nothing under -WhatIf.

    .EXAMPLE
        New-iSOCClassicTableFixture -TableName SacMigrationTest

        Makes SacMigrationTest_CL with 50 records and reports its sub type.

    .EXAMPLE
        New-iSOCClassicTableFixture -TableName SacMigrationTest -Stream -RecordCount 5 -IntervalSeconds 15

        Streams five records every fifteen seconds as the legacy source.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_]+$')]
        [string] $TableName,

        [ValidateRange(1, 10000)]
        [int] $RecordCount = 50,

        [string] $OdsEndpointSuffix,

        [ValidateRange(30, 1800)]
        [int] $TimeoutSeconds = 300,

        [switch] $Stream,

        [ValidateRange(1, 3600)]
        [int] $IntervalSeconds = 10,

        [int] $DurationSeconds,

        [int] $BatchCount,

        [psobject] $Context
    )

    $ctx = Resolve-iSOCContext -Context $Context
    Assert-iSOCPrerequisite -Step Connect
    Write-iSOCLog 'Classic table fixture' -Level Section

    $logType = $TableName -replace '_CL$', ''
    $table = "${logType}_CL"
    $workspaceId = $ctx.WorkspaceId
    if (-not $OdsEndpointSuffix) { $OdsEndpointSuffix = Get-iSOCDataCollectorSuffix -Context $ctx }
    Write-iSOCLog "Workspace    : $($ctx.WorkspaceName)"
    Write-iSOCLog "Table        : $table"

    Write-iSOCLog 'Generating and posting synthetic data' -Level Section
    $sharedKey = Get-iSOCWorkspaceSharedKey -Context $ctx
    $ingestUri = "https://$workspaceId.$OdsEndpointSuffix/api/logs?api-version=2016-04-01"

    if ($Stream) {
        $limitText = @()
        if ($DurationSeconds) { $limitText += "$DurationSeconds s" }
        if ($BatchCount) { $limitText += "$BatchCount batches" }
        if ($limitText.Count -eq 0) { $limitText = @('until Ctrl-C') }
        Write-iSOCLog "Streaming    : $RecordCount records every ${IntervalSeconds}s ($($limitText -join ', '))"

        if (-not $PSCmdlet.ShouldProcess("$($ctx.WorkspaceName)/$table", "Stream via Data Collector API ($($limitText -join ', '))")) {
            Write-iSOCLog 'Skipped streaming (WhatIf).' -Level Warning
            return
        }
        $streamed = Invoke-iSOCFixtureStream -IngestUri $ingestUri -WorkspaceId $workspaceId -SharedKey $sharedKey -LogType $logType -Table $table `
            -RecordCount $RecordCount -IntervalSeconds $IntervalSeconds -DurationSeconds $DurationSeconds -BatchCount $BatchCount
        return [pscustomobject]@{ TableName = $table; LogType = $logType; BatchesSent = $streamed.BatchesSent; BatchesFailed = $streamed.BatchesFailed; RecordsSent = $streamed.RecordsSent }
    }

    Write-iSOCLog "Records      : $RecordCount"
    if (-not $PSCmdlet.ShouldProcess("$($ctx.WorkspaceName)/$table", "Post $RecordCount records via Data Collector API")) {
        Write-iSOCLog 'Skipped posting (WhatIf). No table poll will run.' -Level Warning
        return
    }
    $records = New-iSOCFixtureRecord -Count $RecordCount -ReferenceTime ([datetime]::UtcNow)
    Send-iSOCDataCollectorBatch -IngestUri $ingestUri -WorkspaceId $workspaceId -SharedKey $sharedKey -LogType $logType -Record $records
    Write-iSOCLog "Posted $RecordCount records to $table." -Level Success

    Write-iSOCLog 'Waiting for the table to appear' -Level Section
    Write-iSOCLog 'The table resource usually appears within a few minutes. Data becomes queryable separately and can take longer on first ingestion.'
    $subType = Wait-iSOCFixtureTable -Context $ctx -Table $table -TimeoutSeconds $TimeoutSeconds

    if ($subType) {
        Write-iSOCLog "Table $table is present. tableSubType = $subType." -Level Success
        if ($subType -ne 'Classic') {
            Write-iSOCLog "Expected 'Classic' but got '$subType'. The Data Collector API should have produced a classic table." -Level Warning
        }
        else {
            Write-iSOCLog 'Ready. Point Invoke-iSOCClassicTableMigration at this table to test the migration.' -Level Success
        }
    }
    else {
        Write-iSOCLog "Table did not appear within $TimeoutSeconds seconds. First-time creation can be slow; re-check with Invoke-iSOCClassicTableMigration -ListOnly shortly." -Level Warning
    }

    [pscustomobject]@{
        TableName   = $table
        LogType     = $logType
        RecordCount = $RecordCount
        SubType     = $subType
        WorkspaceId = $workspaceId
    }
}
