#Requires -Version 7.6

<#
.SYNOPSIS
    Delete a classic table fixture, migrating it first when it is still classic.

.DESCRIPTION
    Remove-iSOCClassicTableFixture replaces New-ClassicTableFixture.ps1 -Remove.

.NOTES
    File:         Modules/iSOCDeployments/Public/Remove-iSOCClassicTableFixture.ps1
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

function Remove-iSOCClassicTableFixture {
    <#
    .SYNOPSIS
        Delete a classic table fixture, migrating it first when it is still
        classic.

    .DESCRIPTION
        The Tables API cannot delete a Classic table (a DELETE is refused
        with HTTP 400), so the table is read first. A table that is gone is
        reported as such. A Classic one is left with a warning unless
        -MigrateBeforeRemove, which migrates it to DCR-based (one-way) so it
        can be deleted. Then the table is deleted. Both steps ask
        confirmation (ConfirmImpact High), and -WhatIf changes nothing.

    .PARAMETER TableName
        The table; _CL is added when it is missing.

    .PARAMETER MigrateBeforeRemove
        Migrate a table that is still Classic, so it can be deleted.

    .PARAMETER Context
        The workspace, from Connect-iSOCWorkspace. Defaults to the
        connected one.

    .OUTPUTS
        [pscustomobject] TableName and Outcome: Removed, NotFound,
        StillClassic or Skipped.

    .EXAMPLE
        Remove-iSOCClassicTableFixture -TableName SacMigrationTest -MigrateBeforeRemove

        Migrates the fixture if it is still classic, then deletes it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_]+$')]
        [string] $TableName,

        [switch] $MigrateBeforeRemove,

        [psobject] $Context
    )

    $ctx = Resolve-iSOCContext -Context $Context
    Assert-iSOCPrerequisite -Step Connect
    Write-iSOCLog 'Classic table fixture' -Level Section
    $table = "$($TableName -replace '_CL$', '')_CL"
    $tablePath = "$($ctx.WorkspaceResourceId)/tables/$table"
    Write-iSOCLog "Workspace    : $($ctx.WorkspaceName)"
    Write-iSOCLog "Table        : $table"
    Write-iSOCLog 'Removing fixture table' -Level Section

    $result = { param($Outcome) [pscustomobject]@{ TableName = $table; Outcome = $Outcome } }
    $detail = Invoke-iSOCRestRequest -Method GET -Path $tablePath -ApiVersion (Get-iSOCApiVersion OperationalInsights) -AllowNotFound
    if ($null -eq $detail) {
        Write-iSOCLog "$table does not exist (already removed)." -Level Success
        return (& $result 'NotFound')
    }

    $subType = [string](Get-iSOCPropertyValue -InputObject $detail -Path 'properties.schema.tableSubType')
    if (-not $subType) { $subType = 'Unknown' }
    if ($subType -eq 'Classic') {
        if (-not $MigrateBeforeRemove) {
            Write-iSOCLog "$table is still a Classic table, which the Tables API cannot delete." -Level Warning
            Write-iSOCLog 'Re-run with -MigrateBeforeRemove to migrate it (one-way) and then delete, or delete it in the Azure portal.' -Level Warning
            return (& $result 'StillClassic')
        }
        if (-not $PSCmdlet.ShouldProcess("$($ctx.WorkspaceName)/$table", 'Migrate (irreversible) then delete')) {
            return (& $result 'Skipped')
        }
        Write-iSOCLog 'Migrating the Classic table so it becomes deletable. This is one-way.' -Level Warning
        Invoke-iSOCRestRequest -Method POST -Path "$tablePath/migrate" -ApiVersion (Get-iSOCApiVersion OperationalInsights) | Out-Null
    }

    if (-not $PSCmdlet.ShouldProcess("$($ctx.WorkspaceName)/$table", 'Delete fixture table')) {
        return (& $result 'Skipped')
    }
    Invoke-iSOCRestRequest -Method DELETE -Path $tablePath -ApiVersion (Get-iSOCApiVersion OperationalInsights) | Out-Null
    Write-iSOCLog "Deleted $table." -Level Success
    & $result 'Removed'
}
