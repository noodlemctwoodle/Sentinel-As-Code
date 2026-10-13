#Requires -Version 7.2

<#
.SYNOPSIS
    Read the iSOCBlueprint migration map and engine edits for the migration
    suites.

.DESCRIPTION
    The Blueprint moves from Tools/Blueprint into the iSOCBlueprint module
    file by file. Modules/iSOCBlueprint/MIGRATION.md says where each file
    goes; Tests/iSOCBlueprint/Engine-Edits.psd1 says exactly how a copied
    file may differ from its source. These helpers parse both and compute
    the text a copied file must have, so the map test and the copy-drift
    test share one reading of them.

.NOTES
    File:         Tests/iSOCBlueprint/_helpers/Migration.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MigrationMap {
    <#
    .SYNOPSIS
        Parse the table in Modules/iSOCBlueprint/MIGRATION.md.

    .PARAMETER RepoRoot
        Repository root.

    .OUTPUTS
        One [pscustomobject] per row: Source, Action, Destination, Edits
        (string[]), Notes. Paths are repository-relative, backticks removed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $RepoRoot)

    $path = Join-Path $RepoRoot 'Modules/iSOCBlueprint/MIGRATION.md'
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -notmatch '^\|\s*`') { continue }
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim().Trim('`') })
        if ($cells.Count -ne 5) { throw "MIGRATION.md row does not have five cells: $line" }
        [pscustomobject]@{
            Source      = $cells[0]
            Action      = $cells[1]
            Destination = $cells[2]
            Edits       = @($cells[3] -split '\s*,\s*' | Where-Object { $_ })
            Notes       = $cells[4]
        }
    }
}

function Find-MigrationRow {
    <#
    .SYNOPSIS
        The map row that covers a repository-relative path, or $null.

    .DESCRIPTION
        A row covers a path when its source equals it, or when the source
        ends in '/**' and the path sits beneath that folder.

    .PARAMETER Map
        Rows from Get-MigrationMap.

    .PARAMETER Path
        Repository-relative path with forward slashes.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [object[]] $Map,
        [Parameter(Mandatory)] [string] $Path
    )

    foreach ($row in $Map) {
        if ($row.Source -eq $Path) { return $row }
        if ($row.Source.EndsWith('/**')) {
            $prefix = $row.Source.Substring(0, $row.Source.Length - 2)
            if ($Path.StartsWith($prefix, [StringComparison]::Ordinal) -or "$Path/" -eq $prefix) { return $row }
        }
    }
    return $null
}

function Get-BlueprintSourceFile {
    <#
    .SYNOPSIS
        Every file under Tools/Blueprint, as repository-relative paths.

    .DESCRIPTION
        A folder covered by a '/**' row is returned as one entry ending in
        '/**' rather than walked, so a locally built web part (node_modules,
        lib) cannot flood the list. Finder's .DS_Store files are ignored.

    .PARAMETER RepoRoot
        Repository root.

    .PARAMETER Map
        Rows from Get-MigrationMap.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [object[]] $Map
    )

    $trees = @($Map | Where-Object { $_.Source.EndsWith('/**') } | ForEach-Object { $_.Source.Substring(0, $_.Source.Length - 3) })
    $walk = {
        param([string] $Relative)
        $full = Join-Path $RepoRoot $Relative
        foreach ($item in Get-ChildItem -LiteralPath $full -Force) {
            $rel = "$Relative/$($item.Name)"
            if ($item.PSIsContainer) {
                if ($trees -contains $rel) { "$rel/**" } else { & $walk $rel }
            }
            elseif ($item.Name -ne '.DS_Store') { $rel }
        }
    }
    if (Test-Path -LiteralPath (Join-Path $RepoRoot 'Tools/Blueprint')) { & $walk 'Tools/Blueprint' }
}

function Get-EngineEdit {
    <#
    .SYNOPSIS
        Load Tests/iSOCBlueprint/Engine-Edits.psd1.

    .PARAMETER RepoRoot
        Repository root.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [string] $RepoRoot)

    Import-PowerShellDataFile -LiteralPath (Join-Path $RepoRoot 'Tests/iSOCBlueprint/Engine-Edits.psd1')
}

function Get-OrdinalCount {
    <#
    .SYNOPSIS
        How many times Find occurs in Text (ordinal, non-overlapping).

    .PARAMETER Text
        Text to search.

    .PARAMETER Find
        Text to count.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [string] $Find
    )

    $count = 0
    $at = $Text.IndexOf($Find, [StringComparison]::Ordinal)
    while ($at -ge 0) {
        $count++
        $at = $Text.IndexOf($Find, $at + $Find.Length, [StringComparison]::Ordinal)
    }
    return $count
}

function Get-ExpectedEngineText {
    <#
    .SYNOPSIS
        The text a copied engine file must have: its source with the
        header-path change and its listed edits applied.

    .DESCRIPTION
        Throws when an edit's text does not occur exactly once in the
        source, so a stale edit cannot pass silently.

    .PARAMETER SourceText
        The source file's text.

    .PARAMETER RelativePath
        The file's path relative to Tools/Blueprint, forward slashes.

    .PARAMETER EditDocument
        The hashtable from Get-EngineEdit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $SourceText,
        [Parameter(Mandatory)] [string] $RelativePath,
        [Parameter(Mandatory)] [hashtable] $EditDocument
    )

    $text = $SourceText
    $header = $EditDocument.HeaderPath
    if ((Split-Path -Leaf $RelativePath) -like $header.Include) {
        $found = [regex]::Matches($text, $header.Pattern).Count
        if ($found -ne 1) { throw "$($header.Id): expected one File: header in $RelativePath, found $found" }
        $text = [regex]::Replace($text, $header.Pattern, $header.Replace)
    }
    foreach ($edit in @($EditDocument.Edits | Where-Object { $_.File -eq $RelativePath })) {
        foreach ($change in @($edit.Changes)) {
            $found = Get-OrdinalCount -Text $text -Find $change.Find
            if ($found -ne 1) { throw "$($edit.Id): expected its text once in $RelativePath, found $found" }
            $text = $text.Replace($change.Find, $change.Replace)
        }
    }
    return $text
}

Export-ModuleMember -Function Get-MigrationMap, Find-MigrationRow, Get-BlueprintSourceFile, Get-EngineEdit, Get-OrdinalCount, Get-ExpectedEngineText
