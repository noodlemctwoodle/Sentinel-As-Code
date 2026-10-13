#Requires -Version 7.2

<#
.SYNOPSIS
    Work out which MITRE ATT&CK tactics, techniques and sub-techniques each
    Sentinel analytics rule covers, and where it lands in the matrix.

.DESCRIPTION
    The Markdown renderer's MITRE page (25) and the SharePoint dashboard's
    ATT&CK grid both read this, so the two agree.

    A rule lists its tactics (PascalCase, the catalogue's sentinelShortName)
    and its techniques (T####). Its sub-techniques (T####.###) come in their
    own subTechniques array, which only the preview alertRules API returns;
    older snapshots and some rules list them in techniques instead, so both
    are read, and a sub-technique implies its parent. Each technique goes
    under the rule's tactics that ATT&CK lists for it; when the rule names
    none of those, under the technique's own ATT&CK tactics; when the
    catalogue does not know the technique, under the rule's tactics. A rule
    tagged Initial Access and Credential Access that maps T1110 Brute Force
    therefore puts it under Credential Access only.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-AttackCoverage.ps1
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

# Keeps the file help above from being read as the help of the function below.

function Get-RuleAttackId {
    <#
    .SYNOPSIS
        A rule's ATT&CK ids: parent techniques and sub-techniques,
        upper-case and de-duplicated, with every sub-technique's parent
        added.

    .PARAMETER Rule
        One alertRules object as the collector saves it.

    .OUTPUTS
        [pscustomobject] Techniques (T####) and SubTechniques (T####.###).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] $Rule)

    $p = $Rule.properties
    $raw = @()
    foreach ($name in 'techniques', 'subTechniques') {
        if ($p -and $p.PSObject.Properties.Name -contains $name) { $raw += @($p.$name) }
    }
    $ids = @($raw | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() } | Where-Object { $_ -match '^T\d{4}(\.\d{3})?$' })
    $subs = @($ids | Where-Object { $_ -match '\.' } | Sort-Object -Unique)
    $bases = @(@($ids | Where-Object { $_ -notmatch '\.' }) + @($subs | ForEach-Object { ($_ -split '\.')[0] }) | Sort-Object -Unique)
    [pscustomobject]@{ Techniques = $bases; SubTechniques = $subs }
}

function Get-AttackCoverage {
    <#
    .SYNOPSIS
        Every rule's ATT&CK mapping and the matrix cells it covers.

    .PARAMETER Rules
        alertRules objects as the collector saves them, enabled and
        disabled alike; Enabled on each output rule says which is which.

    .PARAMETER Catalogue
        mitre-attack.json: tactics with sentinelShortName, techniques with
        tacticsSentinel and, for a sub-technique, parentId.

    .OUTPUTS
        [pscustomobject] with:
        - Rules: one row per rule, sorted by name: Index, Name, Enabled,
          Kind, Severity, Tactics (PascalCase), Techniques, SubTechniques.
        - Cells: tactic short name -> technique id -> @{ Rules = indices of
          the rules covering it; Subs = sub-technique id -> indices }.
        - SubTotals: technique id -> the number of sub-techniques ATT&CK
          defines for it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Rules,
        [AllowNull()] $Catalogue
    )

    $techTacticsById = @{}
    $subTotals = @{}
    foreach ($t in @($(if ($Catalogue) { $Catalogue.techniques }))) {
        if (-not $t -or -not $t.id) { continue }
        $techTacticsById[[string]$t.id] = @($t.tacticsSentinel | Where-Object { $_ })
        if ($t.PSObject.Properties.Name -contains 'parentId' -and $t.parentId) {
            $subTotals[[string]$t.parentId] = 1 + [int]$subTotals[[string]$t.parentId]
        }
    }

    $sorted = @($Rules | Where-Object { $_ -and $_.properties } |
            Sort-Object { [string]$_.properties.displayName }, { [string]$_.name })
    $rows = [System.Collections.Generic.List[object]]::new()
    $cells = [ordered]@{}
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $r = $sorted[$i]
        $p = $r.properties
        $tactics = @($p.tactics | Where-Object { $_ } | ForEach-Object { [string]$_ })
        $ids = Get-RuleAttackId -Rule $r
        $rows.Add([pscustomobject]@{
                Index         = $i
                Name          = [string]$p.displayName
                Enabled       = [bool]$p.enabled
                Kind          = [string]$r.kind
                Severity      = $(if ($p.PSObject.Properties.Name -contains 'severity') { [string]$p.severity } else { '' })
                Tactics       = $tactics
                Techniques    = $ids.Techniques
                SubTechniques = $ids.SubTechniques
            })
        foreach ($base in $ids.Techniques) {
            $attackTactics = @($techTacticsById[$base] | Where-Object { $_ })
            $placed = if ($attackTactics.Count) { @($tactics | Where-Object { $attackTactics -contains $_ }) } else { @($tactics) }
            if (-not $placed.Count) { $placed = $attackTactics }
            $subsHere = @($ids.SubTechniques | Where-Object { $_ -like "$base.*" })
            foreach ($tac in $placed) {
                if (-not $cells.Contains($tac)) { $cells[$tac] = [ordered]@{} }
                if (-not $cells[$tac].Contains($base)) {
                    $cells[$tac][$base] = @{ Rules = [System.Collections.Generic.List[int]]::new(); Subs = [ordered]@{} }
                }
                $cell = $cells[$tac][$base]
                if (-not $cell.Rules.Contains($i)) { $cell.Rules.Add($i) }
                foreach ($sub in $subsHere) {
                    if (-not $cell.Subs.Contains($sub)) { $cell.Subs[$sub] = [System.Collections.Generic.List[int]]::new() }
                    if (-not $cell.Subs[$sub].Contains($i)) { $cell.Subs[$sub].Add($i) }
                }
            }
        }
    }
    [pscustomobject]@{ Rules = $rows.ToArray(); Cells = $cells; SubTotals = $subTotals }
}
