#Requires -Version 7.2

<#
.SYNOPSIS
    Turn a schema's raw column list into checked columns and the schema-wide findings.

.DESCRIPTION
    Names are compared with case, as Analytics and Basic tables compare them.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Resolve-iSOCTableSchema.ps1
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

function Resolve-iSOCTableSchema {
    <#
    .SYNOPSIS
        Turn a schema's raw column list into checked columns and the
        schema-wide findings.

    .DESCRIPTION
        Each entry's type is read from type, columnType or dataType
        (string when it has none, as Log Analytics itself falls back to)
        and turned into its Tables API type where it is one. Its
        description (from description, desc, comment, note or notes),
        display name and dataTypeHint are cleaned with
        ConvertTo-iSOCSafeText; any other key the entry carried is dropped.
        Each column carries its own issues (Get-iSOCColumnIssue).

        Then for the schema: a name repeated exactly is an error; names
        that differ only by case are a warning of Kind CaseCollision (two
        columns on an Analytics or Basic table, dropped rows on an
        Auxiliary one, which the caller then refuses); no TimeGenerated, or
        one that is not datetime, is an error with a Fix; more than 500
        columns is an error. Every comparison of names is with case, as
        PowerShell's defaults are not.

    .PARAMETER Column
        The entries of the schema's column list.

    .OUTPUTS
        [pscustomobject] Columns (a list) and SchemaIssues.

    .EXAMPLE
        $analysis = Resolve-iSOCTableSchema -Column @($spec.Columns)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Column
    )

    $setting = Get-iSOCTableSchemaSetting
    $resolved = [System.Collections.Generic.List[pscustomobject]]::new()
    $schemaIssues = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($entry in $Column) {
        if ($null -eq $entry) { continue }

        $name = if ($entry.PSObject.Properties['name']) { [string]$entry.name } else { '' }

        $declaredType = ''
        foreach ($key in @('type', 'columnType', 'dataType')) {
            if ($entry.PSObject.Properties[$key] -and $entry.PSObject.Properties[$key].Value) {
                $declaredType = [string]$entry.PSObject.Properties[$key].Value
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($declaredType)) { $declaredType = 'string' }

        $canonical = Get-iSOCTableColumnType -DeclaredType $declaredType

        $columnDescription = ''
        foreach ($key in @('description', 'desc', 'comment', 'note', 'notes')) {
            if ($entry.PSObject.Properties[$key] -and $entry.PSObject.Properties[$key].Value) {
                $columnDescription = ConvertTo-iSOCSafeText -Text ([string]$entry.PSObject.Properties[$key].Value)
                break
            }
        }

        $displayName = if ($entry.PSObject.Properties['displayName']) { ConvertTo-iSOCSafeText -Text ([string]$entry.displayName) -MaxLength 128 } else { '' }
        $hint = if ($entry.PSObject.Properties['dataTypeHint']) { ConvertTo-iSOCSafeText -Text ([string]$entry.dataTypeHint) -MaxLength 32 } else { '' }

        $resolved.Add([pscustomobject]@{
                Name         = if ($name) { $name.Trim() } else { $name }
                Type         = if ($canonical) { $canonical } else { $declaredType }
                DeclaredType = $declaredType
                Description  = $columnDescription
                DisplayName  = $displayName
                DataTypeHint = $hint
                Issues       = @(Get-iSOCColumnIssue -Name $name -DeclaredType $declaredType -DataTypeHint $hint)
            })
    }

    $named = @($resolved | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) })

    foreach ($group in @($named | Group-Object -Property Name -CaseSensitive | Where-Object { $_.Count -gt 1 })) {
        $schemaIssues.Add([pscustomobject]@{ Severity = 'Error'; Message = "duplicate column name '$($group.Name)' appears $($group.Count) times." })
    }

    $caseCollisions = @($named |
            Group-Object -Property { $_.Name.ToLowerInvariant() } |
            Where-Object { $_.Count -gt 1 -and @($_.Group | Group-Object -Property Name -CaseSensitive).Count -gt 1 })

    foreach ($group in $caseCollisions) {
        $names = (@($group.Group | ForEach-Object { $_.Name }) | Sort-Object -Unique -CaseSensitive) -join ', '
        $schemaIssues.Add([pscustomobject]@{
                Severity = 'Warning'
                Message  = "column names differ only by case: $names. Analytics and Basic tables treat these as separate columns; an Auxiliary table drops rows because of them."
                Kind     = 'CaseCollision'
            })
    }

    $names = @($resolved | ForEach-Object { $_.Name })
    if ($names -notcontains 'TimeGenerated') {
        $schemaIssues.Add([pscustomobject]@{ Severity = 'Error'; Message = 'no TimeGenerated column. Every custom table needs one, of type datetime.'; Fix = 'AddTimeGenerated' })
    }
    else {
        $timeGenerated = @($resolved | Where-Object { $_.Name -eq 'TimeGenerated' })[0]
        if ($timeGenerated.Type -ne 'dateTime') {
            $schemaIssues.Add([pscustomobject]@{ Severity = 'Error'; Message = "TimeGenerated is declared '$($timeGenerated.DeclaredType)'. It must be datetime."; Fix = 'FixTimeGeneratedType' })
        }
    }

    if ($resolved.Count -gt $setting.MaxColumnCount) {
        $schemaIssues.Add([pscustomobject]@{ Severity = 'Error'; Message = "$($resolved.Count) columns; a Log Analytics table is capped at $($setting.MaxColumnCount)." })
    }

    [pscustomobject]@{
        Columns      = $resolved
        SchemaIssues = $schemaIssues.ToArray()
    }
}
