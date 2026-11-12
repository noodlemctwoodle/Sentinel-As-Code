#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 25-mitre-coverage.md (part 3 of 3).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/MitreCoverage/Write-BlueprintMitreCoverageSectionPart3.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintMitreCoverageSectionPart3 {
    <#
    .SYNOPSIS
        Build the figures for and write 25-mitre-coverage.md (part 3 of 3).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $disabledOnlyTechniques = $Context.disabledOnlyTechniques
    $key = $Context.key
    $m = $Context.m
    $mitreHierarchy = $Context.mitreHierarchy
    $n = $Context.n
    $ruleAttackRows = $Context.ruleAttackRows
    $rulesEnabledCount = $Context.rulesEnabledCount
    $rulesWithoutTechnique = $Context.rulesWithoutTechnique
    $rulesWithSub = $Context.rulesWithSub
    $subTotalByParent = $Context.subTotalByParent
    $tacticCounts = $Context.tacticCounts
    $tactics = $Context.tactics
    $techNameById = $Context.techNameById

    # Build the headline tactic matrix from the same data.
    $mitreRowsRich = foreach ($t in $tactics) {
        $key = $t.sentinelShortName
        $tacticBucket = if ($mitreHierarchy.ContainsKey($key)) { $mitreHierarchy[$key] } else { @{} }
        $techCount = $tacticBucket.Count
        $subCount = 0
        foreach ($v in $tacticBucket.Values) { $subCount += $v.Subs.Count }
        $ruleCount = $tacticCounts[$key]
        $coverage = if ($ruleCount -eq 0) { 'None' } elseif ($ruleCount -lt 3) { 'Thin' } else { 'Covered' }
        [pscustomobject]@{
            ID = $t.id
            Tactic = $t.name
            EnabledRules = $ruleCount
            Techniques = $techCount
            SubTechniques = $subCount
            Coverage = $coverage
        }
    }
    $mitreTacticsTotal   = @($mitreRowsRich).Count
    $mitreTacticsCovered = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'Covered' }).Count
    $mitreTacticsThin    = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'Thin' }).Count
    $mitreTacticsNone    = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'None' }).Count
    $mitreTechTotal = @(@($mitreHierarchy.Values | ForEach-Object { $_.Keys }) | Sort-Object -Unique).Count
    $mitreSubTotal  = @(@($mitreHierarchy.Values | ForEach-Object { $_.Values } | ForEach-Object { $_.Subs.Keys }) | Sort-Object -Unique).Count

    # One table per tactic the rules reach: each technique, then its
    # sub-techniques, with the number of enabled rules on each. Rule names are
    # not listed here; the table at the end of the page carries every rule with
    # its mapping, so a technique's rules are a filter on that table.
    $detailSections = New-Object System.Text.StringBuilder
    $uncoveredTactics = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $tactics) {
        $key = $t.sentinelShortName
        if (-not $mitreHierarchy.ContainsKey($key) -or $mitreHierarchy[$key].Count -eq 0) {
            $uncoveredTactics.Add("[$($t.id) $($t.name)](https://attack.mitre.org/tactics/$($t.id)/)")
            continue
        }
        $techRows = foreach ($techId in ($mitreHierarchy[$key].Keys | Sort-Object)) {
            $bucket = $mitreHierarchy[$key][$techId]
            $subTotal = [int]$subTotalByParent[$techId]
            [pscustomobject]@{
                'Technique'              = Format-MitreTechniqueCell -Id $techId -Sub $false
                'Sub-technique'          = ''
                'Rules'                  = $bucket.Rules.Count
                'Sub-techniques covered' = $(if ($subTotal) { "$($bucket.Subs.Count) of $subTotal" } else { 'n/a' })
            }
            foreach ($subId in ($bucket.Subs.Keys | Sort-Object)) {
                [pscustomobject]@{
                    'Technique'              = ''
                    'Sub-technique'          = Format-MitreTechniqueCell -Id $subId -Sub $true
                    'Rules'                  = $bucket.Subs[$subId].Count
                    'Sub-techniques covered' = ''
                }
            }
        }
        [void]$detailSections.AppendLine("")
        [void]$detailSections.AppendLine("### $($t.id) · $($t.name)")
        [void]$detailSections.AppendLine("")
        [void]$detailSections.AppendLine((Format-BlueprintTable -Items $techRows -Columns 'Technique', 'Sub-technique', 'Rules', 'Sub-techniques covered'))
    }
    $uncoveredLine = if ($uncoveredTactics.Count) { "No enabled rule maps a technique in: $($uncoveredTactics -join ', ')." } else { 'Every tactic has at least one technique mapped by an enabled rule.' }

    # Build the bar-chart inputs from $mitreRowsRich (already sorted by tactic).
    # Short labels per tactic so x-axis fits 14 entries; full names live in the
    # matrix table below.
    $labelMap = @{
        'Reconnaissance' = 'Recon'; 'ResourceDevelopment' = 'ResDev'; 'InitialAccess' = 'Initial'
        'Execution' = 'Exec'; 'Persistence' = 'Persist'; 'PrivilegeEscalation' = 'PrivEsc'
        'DefenseEvasion' = 'DefEva'; 'CredentialAccess' = 'CredAcc'; 'Discovery' = 'Discov'
        'LateralMovement' = 'LatMov'; 'Collection' = 'Collect'; 'CommandAndControl' = 'C2'
        'Exfiltration' = 'Exfil'; 'Impact' = 'Impact'
    }
    $mitreAxis = ($tactics | ForEach-Object {
        $key = $_.sentinelShortName
        $lbl = if ($labelMap.ContainsKey($key)) { $labelMap[$key] } else { $key.Substring(0, [math]::Min(7, $key.Length)) }
        "`"$lbl`""
    }) -join ', '
    $mitreBars = ($mitreRowsRich | ForEach-Object { $_.EnabledRules }) -join ', '
    $mitreMax = 1
    foreach ($r in $mitreRowsRich) { if ($r.EnabledRules -gt $mitreMax) { $mitreMax = $r.EnabledRules } }
    $mitreYmax = [int]([math]::Ceiling(($mitreMax + 1) / 10.0)) * 10

    $mitreBody = @"
$(Format-Banner -Title "MITRE ATT&CK Coverage")

Coverage comes from every **enabled** Sentinel detection rule: its ``tactics``, its ``techniques`` and its ``subTechniques``. A sub-technique (such as ``T1078.004``) also counts towards its parent technique. Each technique sits under the tactics ATT&CK gives it, so a rule tagged with several tactics does not spread every technique across all of them. Every ID links to its entry on attack.mitre.org.

## Coverage shape: rules per tactic

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Enabled rules per MITRE tactic"
    x-axis [$mitreAxis]
$(Format-XyFullLabels @($tactics | ForEach-Object { $_.name }))
    y-axis "Enabled rules" 0 --> $mitreYmax
    bar [$mitreBars]
``````

**$mitreTacticsCovered Covered · $mitreTacticsThin Thin · $mitreTacticsNone None** of $mitreTacticsTotal tactics (Covered: three or more enabled rules; Thin: one or two). Enabled rules map **$mitreTechTotal** techniques and **$mitreSubTotal** sub-techniques.

## Tactic matrix

$(Format-BlueprintTable -Items $mitreRowsRich -Columns 'ID','Tactic','EnabledRules','Techniques','SubTechniques','Coverage')

## Technique and sub-technique breakdown

One table per tactic: each technique an enabled rule maps, then the sub-techniques mapped under it, with the number of enabled rules on each. **Sub-techniques covered** compares the sub-techniques mapped with the number ATT&CK defines for the technique (n/a when it defines none). To see which rules cover a technique, filter the rule table at the end of this page by its ID; the dashboard's ATT&CK grid shows the same coverage as a matrix.

$uncoveredLine
$($detailSections.ToString())
## Rules and their ATT&CK mapping

Every analytics rule, enabled first and then disabled, with the tactics, techniques and sub-techniques it maps, so a rule can be found by name or by an ATT&CK ID. The tables above count enabled rules only: **$rulesEnabledCount** of **$(@($ruleAttackRows).Count)** rules are enabled. $rulesWithoutTechnique enabled rules map no technique, so they count in the rules-per-tactic chart but not in the technique tables; $rulesWithSub map at least one sub-technique.$(if ($disabledOnlyTechniques) { " Enabling the disabled rules would add **$disabledOnlyTechniques** techniques that no enabled rule covers." })$(if ($rulesEnabledCount -and -not $rulesWithSub) { ' No enabled rule maps a sub-technique in this snapshot. Collections before release 26.10 did not read sub-techniques (every GA version of the rules API leaves them out); a new collection picks them up.' })

$(Format-BlueprintTable -Items $ruleAttackRows -Columns 'Rule', 'Status', 'Tactics', 'Techniques', 'Sub-techniques' -EmptyMessage '_No analytics rules._')

[MITRE coverage in Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/mitre-coverage) · [ATT&CK Enterprise (mitre.org)](https://attack.mitre.org/matrices/enterprise/)
"@

    Write-BlueprintSection '25-mitre-coverage.md' $mitreBody

    # Left in the render context for later sections.
    if (Get-Variable -Name 'bucket' -Scope 0 -ErrorAction Ignore) { $Context.bucket = $bucket }
    if (Get-Variable -Name 'key' -Scope 0 -ErrorAction Ignore) { $Context.key = $key }
    $Context.mitreRowsRich = $mitreRowsRich
    $Context.r = $r
    $Context.t = $t
    $Context.v = $v
}
