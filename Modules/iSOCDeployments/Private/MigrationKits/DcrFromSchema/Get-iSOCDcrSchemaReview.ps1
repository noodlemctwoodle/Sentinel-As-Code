#Requires -Version 7.2

<#
.SYNOPSIS
    Check the schema, and the table it would update when there is one, before anything is written.

.DESCRIPTION
    The live table is read for two guards Azure applies anyway, so a failure
    to read it is a warning, not a stop.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Get-iSOCDcrSchemaReview.ps1
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

function Get-iSOCDcrSchemaReview {
    <#
    .SYNOPSIS
        Check the schema, and the table it would update when there is one,
        before anything is written.

    .DESCRIPTION
        The columns are checked and repaired (Resolve-iSOCTableSchema, then
        Invoke-iSOCSchemaRepair over its columns), and the case-only name
        collisions kept for the plan check. Then the live table is read:
        when that fails, two warnings say why and which guards are skipped,
        and the run goes on. A table that exists is a warning; a classic one
        stops the run (a DCR cannot target it; Invoke-iSOCClassicTableMigration
        migrates it), as does a column whose live type differs. New columns
        and columns only the live table has are reported. Finally the
        stream columns are made, with a warning naming any guid column
        declared string and cast back.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Spec
        The schema file, from Import-iSOCTableSpec.

    .PARAMETER TableName
        The table name.

    .OUTPUTS
        [pscustomobject] Columns, CaseCollisions and StreamColumns.

    .EXAMPLE
        $review = Get-iSOCDcrSchemaReview -Context $ctx -Spec $spec -TableName 'MyApp_CL'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $Spec,

        [Parameter(Mandatory)]
        [string] $TableName
    )

    Write-iSOCLog 'Schema review' -Level Section

    $analysis = Resolve-iSOCTableSchema -Column @($Spec.Columns)
    $columns = @(Invoke-iSOCSchemaRepair -Column $analysis.Columns.ToArray())
    if ($columns.Count -eq 0) {
        throw 'The schema has no columns left. Nothing to create.'
    }

    $caseCollisions = @((Resolve-iSOCTableSchema -Column $columns).SchemaIssues | Where-Object { $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'CaseCollision' })

    $existingTable = $null
    try {
        $existingTable = Get-iSOCWorkspaceTableSchema -Context $Context -Table $TableName
    }
    catch {
        $reason = ($_.Exception.Message -replace '\s+', ' ').Trim()
        Write-iSOCLog "Could not read the existing table: $reason" -Level Warning
        Write-iSOCLog 'Continuing without it. Two checks are skipped for this run: whether the table is a Classic table a DCR cannot target, and whether any column type differs from the live table. Azure rejects both regardless, so the risk is a less clear error later rather than a bad deployment.' -Level Warning
    }

    if ($existingTable) {
        Write-iSOCLog "Table $TableName already exists in this workspace (subtype $($existingTable.SubType))." -Level Warning

        if ($existingTable.SubType -eq 'Classic') {
            throw ("$TableName is a classic (MMA / Data Collector API) table. A DCR cannot target one " +
                '(InvalidOutputTable). Migrate it first with Invoke-iSOCClassicTableMigration.')
        }

        $diff = Compare-iSOCTableSchema -DesiredColumn $columns -ExistingColumn $existingTable.Columns
        if ($diff.Conflicts.Count -gt 0) {
            throw ("The live table's column types differ from the schema, and a column type cannot be changed " +
                "after creation: $($diff.Conflicts -join '; '). Align the schema file with the live table, " +
                'or use a new table name.')
        }
        if ($diff.Added.Count -gt 0) {
            Write-iSOCLog "Adding $($diff.Added.Count) new column(s): $($diff.Added -join ', ')."
        }
        if ($diff.OnlyLive.Count -gt 0) {
            Write-iSOCLog "The live table has $($diff.OnlyLive.Count) column(s) the schema does not mention; they are left alone and will not appear in the DCR stream: $($diff.OnlyLive -join ', ')." -Level Warning
        }
    }

    $streamColumns = @(ConvertTo-iSOCSchemaStreamColumn -Column $columns)
    $guidColumns = @($columns | Where-Object { $_.Type -eq 'guid' })
    if ($guidColumns.Count -gt 0) {
        Write-iSOCLog "$($guidColumns.Count) guid column(s) declared as string in the stream and cast back in the transform: $(@($guidColumns.Name) -join ', ')." -Level Warning
    }

    [pscustomobject]@{
        Columns        = $columns
        CaseCollisions = $caseCollisions
        StreamColumns  = $streamColumns
    }
}
