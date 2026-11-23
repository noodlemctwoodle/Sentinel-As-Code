#Requires -Version 7.6

<#
.SYNOPSIS
    Works out which tables each workspace function reaches.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Rule/Get-SdlFunctionReach.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SdlFunctionReach {
    <#
    .SYNOPSIS
        Works out which tables each workspace function reaches.

    .DESCRIPTION
        Matches each function's cleaned body against the table list,
        then follows the functions it calls (parsers calling parsers)
        to a fixed point, so a function reaches every table any
        function under it reads.

    .PARAMETER Function
        Function rows from Get-SdlFunctionInventory.

    .PARAMETER TableUniverse
        The table names to look for.

    .OUTPUTS
        [hashtable] Keyed by function alias; each value has Function,
        Clean, Tables (a set) and Calls.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([hashtable])]
    param (
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Function = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$TableUniverse = @()
    )

    $reach = @{}
    foreach ($entry in $Function) {
        if (-not $entry.QueryBody) {
            continue
        }
        $reach[$entry.FunctionAlias] = [pscustomobject]@{
            Function = $entry
            Clean    = Get-KqlCodeText -Text $entry.QueryBody
            Tables   = [System.Collections.Generic.HashSet[string]]::new()
            Calls    = [System.Collections.Generic.List[string]]::new()
        }
    }
    foreach ($alias in @($reach.Keys)) {
        $info = $reach[$alias]
        foreach ($table in $TableUniverse) {
            if (Test-KqlIdentifier -CleanText $info.Clean -Name $table) {
                [void]$info.Tables.Add($table)
            }
        }
        foreach ($other in @($reach.Keys)) {
            if ($other -ne $alias -and (Test-KqlCall -CleanText $info.Clean -Alias $other)) {
                $info.Calls.Add($other)
            }
        }
    }
    # Repeat until a full pass adds nothing. Table sets only grow and are
    # finite, so this ends, cycles between functions included.
    do {
        $changed = $false
        foreach ($info in @($reach.Values)) {
            foreach ($called in $info.Calls) {
                foreach ($table in @($reach[$called].Tables)) {
                    if ($info.Tables.Add($table)) {
                        $changed = $true
                    }
                }
            }
        }
    } while ($changed)
    return $reach
}
