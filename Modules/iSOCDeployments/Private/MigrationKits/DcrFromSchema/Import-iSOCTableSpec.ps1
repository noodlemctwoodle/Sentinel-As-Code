#Requires -Version 7.6

<#
.SYNOPSIS
    Read a JSON table schema file into a table name, a column list and its optional defaults, whichever accepted shape it is in.

.DESCRIPTION
    A file that will not parse is repaired of known paste damage and read
    again, with a warning naming the repairs.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Import-iSOCTableSpec.ps1
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

function Import-iSOCTableSpec {
    <#
    .SYNOPSIS
        Read a JSON table schema file into a table name, a column list and
        its optional defaults, whichever accepted shape it is in.

    .DESCRIPTION
        Three shapes, tried in this order:

          1. { "tableName": "...", "columns": [ ... ] } (the table name may
             be under tableName, name or table, the columns under columns,
             schema or fields)
          2. the Tables API resource, { "properties": { "schema": { "name",
             "columns" } } }, so a table read from Azure can be fed back in
          3. a bare array of columns, the table name then coming from the
             caller (a single column, which ConvertFrom-Json unrolls to one
             object, is recognised before the table name is looked for)

        The optional defaults the file may carry (description, dcrName,
        location, plan, retentionInDays, totalRetentionInDays,
        transformKql) are returned as Extra. A file that will not parse is
        passed through Repair-iSOCJsonText and parsed once more, with a
        warning; when nothing could be repaired, or it still will not
        parse, the error says so. A file that parses but has no column
        list, an empty one, or entries without a name is refused, saying
        the command takes a schema, not a sample of the data.

    .PARAMETER Path
        The schema file.

    .OUTPUTS
        [pscustomobject] TableName (or null), Columns and Extra (an ordered
        dictionary).

    .EXAMPLE
        Import-iSOCTableSpec -Path ./schema.json
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Schema file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Schema file is empty: $Path"
    }

    try {
        $json = $raw | ConvertFrom-Json
    }
    catch {
        $repaired = Repair-iSOCJsonText -Text $raw
        if ($repaired.Applied.Count -eq 0) {
            throw "Schema file is not valid JSON ($Path): $($_.Exception.Message.Split([char]10)[0])"
        }
        try {
            $json = $repaired.Text | ConvertFrom-Json
        }
        catch {
            throw ("Schema file is not valid JSON ($Path), even after removing $($repaired.Applied -join ', '): " +
                $_.Exception.Message.Split([char]10)[0])
        }
        Write-iSOCLog "Schema file needed cleaning up before it would parse: removed $($repaired.Applied -join ', '). Fix the source file so this is not needed next time." -Level Warning
    }

    $name = $null
    $columns = $null
    $extra = [ordered]@{}

    if ($json -is [array]) {
        $columns = $json
    }
    else {
        $properties = $json.PSObject.Properties

        if ($properties['properties'] -and $properties['properties'].Value) {
            $inner = $properties['properties'].Value
            $schemaProperty = $inner.PSObject.Properties['schema']
            if (-not $schemaProperty -or -not $schemaProperty.Value) {
                throw "Schema file has a 'properties' block but no 'properties.schema' ($Path)."
            }

            $schema = $schemaProperty.Value
            $name = if ($schema.PSObject.Properties['name']) { [string]$schema.name } else { $null }
            $columns = if ($schema.PSObject.Properties['columns'] -and $null -ne $schema.PSObject.Properties['columns'].Value) { $schema.columns } else { $null }

            foreach ($key in @('description')) {
                if ($schema.PSObject.Properties[$key]) { $extra[$key] = $schema.$key }
            }
            foreach ($key in @('plan', 'retentionInDays', 'totalRetentionInDays')) {
                if ($inner.PSObject.Properties[$key]) { $extra[$key] = $inner.$key }
            }
        }
        elseif ($properties['name'] -and $properties['type'] -and -not $properties['columns'] -and -not $properties['tableName']) {
            $columns = @($json)
        }
        else {
            foreach ($key in @('tableName', 'name', 'table')) {
                if ($properties[$key] -and $properties[$key].Value) {
                    $name = [string]$properties[$key].Value
                    break
                }
            }
            foreach ($key in @('columns', 'schema', 'fields')) {
                if ($properties[$key] -and $null -ne $properties[$key].Value) {
                    $columns = $properties[$key].Value
                    break
                }
            }
            foreach ($key in @('description', 'dcrName', 'location', 'plan', 'retentionInDays', 'totalRetentionInDays', 'transformKql')) {
                if ($properties[$key]) { $extra[$key] = $properties[$key].Value }
            }
        }
    }

    if ($null -eq $columns) {
        throw ("Schema file has no column list ($Path). Expected " +
            "{ `"tableName`": `"MyTable_CL`", `"columns`": [ { `"name`": `"...`", `"type`": `"...`" } ] }. " +
            'This tool takes a schema, not a sample of the data.')
    }

    $columns = @($columns)
    if ($columns.Count -eq 0) {
        throw "Schema file declares an empty column list ($Path)."
    }

    $malformed = @($columns | Where-Object { $null -eq $_ -or -not $_.PSObject.Properties['name'] })
    if ($malformed.Count -gt 0) {
        throw ("$($malformed.Count) of $($columns.Count) entries in the column list have no 'name' property " +
            "($Path). Every column must be { `"name`": `"...`", `"type`": `"...`" }. " +
            'This tool takes a schema, not a sample of the data.')
    }

    [pscustomobject]@{
        TableName = $name
        Columns   = $columns
        Extra     = $extra
    }
}
