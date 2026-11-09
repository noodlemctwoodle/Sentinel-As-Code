#Requires -Version 7.6

<#
.SYNOPSIS
    Delete the objects a dependency fixture plan marks for removal: rules, then saved searches, then tables.

.DESCRIPTION
    Only provably owned objects; a classic table is migrated first only with
    -MigrateBeforeRemove, and an unmarked one deleted only with
    -RemoveUnmarkedTable.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Invoke-iSOCFixtureRemoval.ps1
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

function Invoke-iSOCFixtureRemoval {
    <#
    .SYNOPSIS
        Delete the objects a dependency fixture plan marks for removal:
        rules, then saved searches, then tables.

    .DESCRIPTION
        The reverse of creation. Rules first, the only objects that run, so
        a failure part way never leaves a live rule on a half-removed chain;
        then the hunting query, strays and parsers, outermost first; then
        the tables. Only rows the plan marks DELETE go (others the plan
        marks SKIP are reported); an object already gone is fine.

        A table is read again before it goes. One that is still Classic
        cannot be deleted by the Tables API: it is left with a warning
        unless -MigrateBeforeRemove, which migrates it (one-way) first. A
        table with the fixture's name but no marker column is left unless
        -RemoveUnmarkedTable, which deletes it anyway and can delete someone
        else's table. Every migration and delete asks ShouldProcess; each
        failure is a warning and counted.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Fixture
        From Get-iSOCDependencyFixturePlan -ForRemoval.

    .PARAMETER MigrateBeforeRemove
        Migrate a Classic table so it can be deleted.

    .PARAMETER RemoveUnmarkedTable
        Delete a fixture-named table without the marker column.

    .OUTPUTS
        [pscustomobject] Removed, Skipped and Failed.

    .EXAMPLE
        Invoke-iSOCFixtureRemoval -Context $ctx -Fixture $fixture -MigrateBeforeRemove
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $Fixture,

        [switch] $MigrateBeforeRemove,

        [switch] $RemoveUnmarkedTable
    )

    $markerColumn = (Get-iSOCDependencyFixtureSetting).MarkerColumnName
    $removed = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $rows = @($Fixture.Rows)

    Write-iSOCLog 'Removing fixture' -Level Section
    $deleteRows = {
        param($Selected, $ApiVersion, $Label)
        foreach ($row in $Selected) {
            if ($row.Action -ne 'DELETE') {
                if ($row.Action -eq 'SKIP') {
                    Write-iSOCLog "SKIP (not owned): $($row.ResourceId)" -Level Warning
                    $skipped.Add($row.ResourceId)
                }
                continue
            }
            try {
                if ($PSCmdlet.ShouldProcess($row.ResourceId, "Delete fixture $Label")) {
                    Invoke-iSOCRestRequest -Method DELETE -Path $row.ResourceId -ApiVersion $ApiVersion -AllowNotFound | Out-Null
                    Write-iSOCLog "Deleted $Label $($row.Name)." -Level Success
                    $removed.Add($row.ResourceId)
                }
            }
            catch {
                Write-iSOCLog "Failed to delete $($row.ResourceId): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
                $failed.Add($row.ResourceId)
            }
        }
    }

    & $deleteRows @($rows | Where-Object { $_.Type -eq 'AlertRule' }) (Get-iSOCApiVersion SecurityInsights) 'analytics rule'
    $savedOrder = @($rows | Where-Object { $_.Type -eq 'HuntingQuery' }) + @($rows | Where-Object { $_.Type -eq 'SavedSearch' }) + @($rows | Where-Object { $_.Type -eq 'Parser' } | Sort-Object -Property Name -Descending)
    & $deleteRows $savedOrder (Get-iSOCApiVersion SavedSearches) 'saved search'

    foreach ($row in ($rows | Where-Object { $_.Type -eq 'Table' })) {
        $tableName = $row.Name
        if ($row.Action -eq 'ABSENT') {
            Write-iSOCLog "$tableName does not exist (already removed)." -Level Success
            continue
        }
        if ($row.Action -eq 'SKIP') {
            if (-not $RemoveUnmarkedTable) {
                Write-iSOCLog "$tableName exists but carries no '$markerColumn' column, so this fixture cannot prove it owns it. Left alone." -Level Warning
                Write-iSOCLog "If you are certain it is yours, re-run with -RemoveUnmarkedTable. That switch can delete somebody else's table." -Level Warning
                $skipped.Add($row.ResourceId)
                continue
            }
            Write-iSOCLog "$tableName carries no ownership marker. -RemoveUnmarkedTable was passed, so it will be deleted anyway." -Level Warning
        }

        try {
            $apiVersion = Get-iSOCApiVersion OperationalInsights
            $detail = Invoke-iSOCRestRequest -Method GET -Path $row.ResourceId -ApiVersion $apiVersion -AllowNotFound
            if ($null -eq $detail) {
                Write-iSOCLog "$tableName does not exist (already removed)." -Level Success
                continue
            }
            $subType = [string](Get-iSOCPropertyValue -InputObject $detail -Path 'properties.schema.tableSubType')
            if ($subType -eq 'Classic') {
                if (-not $MigrateBeforeRemove) {
                    Write-iSOCLog "$tableName is still a Classic table, which the Tables API cannot delete." -Level Warning
                    Write-iSOCLog 'Re-run with -MigrateBeforeRemove to migrate it (one-way) and then delete, or delete it in the Azure portal.' -Level Warning
                    $skipped.Add($row.ResourceId)
                    continue
                }
                if (-not $PSCmdlet.ShouldProcess("$($Context.WorkspaceName)/$tableName", 'Migrate (irreversible) then delete')) { continue }
                Write-iSOCLog 'Migrating the Classic table so it becomes deletable. This is one-way.' -Level Warning
                Invoke-iSOCRestRequest -Method POST -Path "$($row.ResourceId)/migrate" -ApiVersion $apiVersion | Out-Null
            }
            if ($PSCmdlet.ShouldProcess("$($Context.WorkspaceName)/$tableName", 'Delete fixture table')) {
                Invoke-iSOCRestRequest -Method DELETE -Path $row.ResourceId -ApiVersion $apiVersion -AllowNotFound | Out-Null
                Write-iSOCLog "Deleted $tableName." -Level Success
                $removed.Add($row.ResourceId)
            }
        }
        catch {
            Write-iSOCLog "Failed to remove $tableName : $($_.Exception.Message.Split([char]10)[0])" -Level Warning
            $failed.Add($row.ResourceId)
        }
    }

    Write-iSOCLog 'Removal summary' -Level Section
    Write-iSOCLog "  Removed : $($removed.Count)"
    Write-iSOCLog "  Skipped : $($skipped.Count)"
    Write-iSOCLog "  Failed  : $($failed.Count)"
    if ($failed.Count -gt 0) { Write-iSOCLog 'One or more objects could not be removed. See the warnings above.' -Level Warning }
    [pscustomobject]@{ Removed = $removed.ToArray(); Skipped = $skipped.ToArray(); Failed = $failed.ToArray() }
}
