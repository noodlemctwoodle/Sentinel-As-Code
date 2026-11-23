#Requires -Version 7.6

<#
.SYNOPSIS
    Wait for each seeded fixture table to appear, and then to answer a query.

.DESCRIPTION
    Two separate events: the table resource appearing, and the query engine
    resolving its name, which is what a rule's validation needs.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Wait-iSOCFixtureQueryable.ps1
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

function Wait-iSOCFixtureQueryable {
    <#
    .SYNOPSIS
        Wait for each seeded fixture table to appear, and then to answer a
        query.

    .DESCRIPTION
        Two events with a gap between them. First the table appears through
        the Tables API, polled every 15 seconds with progress about once a
        minute; then the query engine resolves its name, which is what the
        analytics rule validator needs, tried with '<table> | take 1'. Each
        table has its own -TimeoutSeconds budget. A table that does not
        appear, or is not queryable, is a warning: the rules on it will
        probably fail to validate.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Fixture
        From Get-iSOCDependencyFixturePlan.

    .PARAMETER Seeded
        The tables posted to.

    .PARAMETER TimeoutSeconds
        The wait for each table.

    .EXAMPLE
        Wait-iSOCFixtureQueryable -Context $ctx -Fixture $fixture -Seeded $seed.Seeded -TimeoutSeconds 900
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $Fixture,

        [AllowEmptyCollection()]
        [string[]] $Seeded = @(),

        [Parameter(Mandatory)]
        [int] $TimeoutSeconds
    )

    $tables = @($Fixture.Plan.Table | Where-Object { $Seeded -contains $_.TableName })
    if ($tables.Count -eq 0) { return }

    Write-iSOCLog 'Waiting for the tables to become queryable' -Level Section
    Write-iSOCLog 'A table resource usually appears within a few minutes. Becoming resolvable by the query engine is separate and slower, and it is what the analytics rule validator needs.'

    $index = 0
    foreach ($table in $tables) {
        $index++
        $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
        $started = [datetime]::UtcNow
        $subType = $null
        $poll = 0
        while ([datetime]::UtcNow -lt $deadline) {
            try {
                $detail = Invoke-iSOCRestRequest -Method GET -Path "$($Fixture.WorkspaceBase)/tables/$($table.TableName)" -ApiVersion (Get-iSOCApiVersion OperationalInsights)
                $subType = [string](Get-iSOCPropertyValue -InputObject $detail -Path 'properties.schema.tableSubType')
                if (-not $subType) { $subType = 'Unknown' }
                if ($subType -ne 'Unknown') { break }
            } catch {
                Write-iSOCLog "Table $($table.TableName) not present yet: $($_.Exception.Message.Split([char]10)[0])" -Level Debug
            }
            $poll++
            if ($poll % 4 -eq 0) {
                $waited = [int]([datetime]::UtcNow - $started).TotalSeconds
                Write-iSOCLog ('  still waiting for {0} ({1} of {2}), {3}s elapsed of {4}s allowed' -f $table.TableName, $index, $tables.Count, $waited, $TimeoutSeconds)
            }
            Start-Sleep -Seconds 15
        }

        if (-not $subType -or $subType -eq 'Unknown') {
            Write-iSOCLog "$($table.TableName) did not appear within the timeout. The rules that depend on it will probably fail to validate." -Level Warning
            continue
        }
        Write-iSOCLog "$($table.TableName) is present. tableSubType = $subType."
        if ($subType -ne 'Classic') { Write-iSOCLog "Expected 'Classic' but got '$subType'. The Data Collector API should have produced a classic table." -Level Warning }

        $queryable = $false
        while ([datetime]::UtcNow -lt $deadline) {
            try {
                Invoke-iSOCAzLogQuery -WorkspaceId $Context.WorkspaceId -Query "$($table.TableName) | take 1" | Out-Null
                $queryable = $true
                break
            } catch {
                Write-iSOCLog "Table $($table.TableName) not queryable yet: $($_.Exception.Message.Split([char]10)[0])" -Level Debug
                Start-Sleep -Seconds 15
            }
        }
        if ($queryable) { Write-iSOCLog "$($table.TableName) is queryable." -Level Success }
        else { Write-iSOCLog "$($table.TableName) is not queryable yet. Rule creation may fail with 'Failed to resolve table or column expression named'." -Level Warning }
    }
}
