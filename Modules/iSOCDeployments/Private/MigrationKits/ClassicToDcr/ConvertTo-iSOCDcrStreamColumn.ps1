#Requires -Version 7.6

<#
.SYNOPSIS
    Turn a table's columns into DCR stream declaration columns, and say which cannot be carried.

.DESCRIPTION
    Reserved, hidden and non-letter-initial columns are dropped with the
    reason; TimeGenerated is always declared.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/ConvertTo-iSOCDcrStreamColumn.ps1
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

function ConvertTo-iSOCDcrStreamColumn {
    <#
    .SYNOPSIS
        Turn a table's columns into DCR stream declaration columns, and say
        which cannot be carried.

    .DESCRIPTION
        Dropped, each with its reason:

          - the names a stream may not declare: TenantId, Type, UniqueId,
            Title, id, MG, ManagementGroupName, SourceSystem (in any case)
          - a name that does not start with a letter, such as the classic
            artefacts _ResourceId_s and _table_s, which therefore stop
            receiving data
          - a hidden column

        Each column kept is declared with Get-iSOCDcrColumnType, string when
        it has no type. TimeGenerated is put first when the table does not
        have it, since the destination needs it.

    .PARAMETER SchemaColumn
        The table's columns, from the Tables API.

    .OUTPUTS
        [pscustomobject] Columns (name and type) and Dropped (Name and
        Reason).

    .EXAMPLE
        $conversion = ConvertTo-iSOCDcrStreamColumn -SchemaColumn $detail.Columns
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $SchemaColumn
    )

    $reserved = @('TenantId', 'Type', 'UniqueId', 'Title', 'id', 'MG', 'ManagementGroupName', 'SourceSystem')
    $columns = [System.Collections.Generic.List[pscustomobject]]::new()
    $dropped = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($column in $SchemaColumn) {
        if (-not $column) { continue }
        $name = $column.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $reason = $null
        if ($reserved -contains $name) {
            $reason = 'reserved column name'
        }
        elseif ($name -notmatch '^[A-Za-z]') {
            $reason = 'stream column names must start with a letter'
        }
        else {
            $hiddenProperty = $column.PSObject.Properties['isHidden']
            if ($hiddenProperty -and $hiddenProperty.Value -eq $true) { $reason = 'hidden column' }
        }

        if ($reason) {
            $dropped.Add([pscustomobject]@{ Name = $name; Reason = $reason })
            continue
        }

        $typeProperty = $column.PSObject.Properties['type']
        $type = if ($typeProperty -and $typeProperty.Value) { [string]$typeProperty.Value } else { 'string' }
        $columns.Add([pscustomobject]@{
                name = $name
                type = Get-iSOCDcrColumnType -TableColumnType $type
            })
    }

    $declaredNames = @($columns | ForEach-Object { $_.name })
    if ($declaredNames -notcontains 'TimeGenerated') {
        $columns.Insert(0, [pscustomobject]@{ name = 'TimeGenerated'; type = 'datetime' })
    }

    [pscustomobject]@{
        Columns = $columns.ToArray()
        Dropped = $dropped.ToArray()
    }
}
