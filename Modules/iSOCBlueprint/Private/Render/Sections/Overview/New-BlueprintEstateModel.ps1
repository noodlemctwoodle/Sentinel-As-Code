#Requires -Version 7.6

<#
.SYNOPSIS
    Build the estate model: families, ingestion, detection, alerts and incidents.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Overview/New-BlueprintEstateModel.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# Source families -> ingestion -> detection -> alerts -> incidents: the
# numbers behind the estate flow on 00 and 01 and the pipeline table. Null
# safe; every input may be empty.
function New-BlueprintEstateModel {
    $enabledRefs = @($ruleTableRefs | Where-Object { $_.Enabled -eq $true })
    $referenced = @{}
    foreach ($r in $enabledRefs) { foreach ($t in @($r.Tables)) { if ($t) { $referenced[[string]$t] = $true } } }
    foreach ($t in $customDetectionTableSet.Keys) { $referenced[$t] = $true }
    $byFamily = [ordered]@{}
    $tablesActive = 0; $tablesCovered = 0
    foreach ($t in $tablesWithData) {
        $name = [string]$t.DataType
        if (-not $name) { continue }
        $gb = ConvertTo-BlueprintNumber $t.BillableLast30d
        if ($gb -le 0) { continue }
        # Seen: data in the lookback. Active (still receiving data): some
        # in the recent window; coverage is counted among the active ones.
        $isActive = (ConvertTo-BlueprintNumber $t.BillableLast7d) -gt 0
        if ($isActive) { $tablesActive++ }
        $fam = Get-TableFamily -Table $name
        if (-not $byFamily.Contains($fam)) { $byFamily[$fam] = [pscustomobject]@{ Category = $fam; Tables = 0; Gb = 0.0; CoveredGb = 0.0; Covered = 0 } }
        $byFamily[$fam].Tables++
        $byFamily[$fam].Gb += $gb
        if ($referenced.ContainsKey($name)) { if ($isActive) { $tablesCovered++ }; $byFamily[$fam].Covered++; $byFamily[$fam].CoveredGb += $gb }
    }
    $sources = @($byFamily.Values | Sort-Object -Property Gb -Descending)
    $totalGb = 0.0; $coveredGb = 0.0
    foreach ($src in $sources) { $totalGb += $src.Gb; $coveredGb += $src.CoveredGb }
    $ruleAlerts = [long]0
    foreach ($f in $rulesFired) { $ruleAlerts += [long](ConvertTo-BlueprintNumber $f.Alerts) }
    # Fired, of the enabled Scheduled and NRT rules (by rule id, or by name
    # for an alert without one), as the ring says: a rule disabled or deleted
    # since it fired is not one of them.
    $queryRuleKeys = @{}
    foreach ($r in @($enabledRules | Where-Object { $_.kind -in @('Scheduled', 'NRT') })) {
        $queryRuleKeys[([string](Get-BlueprintRawProperty $r 'name' '')).ToLowerInvariant()] = $true
        $dn = [string](Get-BlueprintRawProperty $r.properties 'displayName' '')
        if ($dn) { $queryRuleKeys["name:$dn"] = $true }
    }
    $firedEnabled = @($rulesFired | Where-Object {
        if (-not $_) { return $false }
        $k = ([string](Get-BlueprintRawProperty $_ 'AlertRuleId' '')).ToLowerInvariant(); if ($k -match '/') { $k = ($k -split '/')[-1] }
        if ($k) { $queryRuleKeys.ContainsKey($k) } else { $queryRuleKeys.ContainsKey("name:$([string](Get-BlueprintRawProperty $_ 'AlertName' ''))") }
    }).Count
    # Every alert from every product, so alerts and incidents count the same
    # things (in a workspace joined to the Defender portal every incident is
    # a Defender XDR one, whichever product raised its alerts); the rules'
    # own alerts when the volumes were not captured.
    $alerts = [long]0
    foreach ($v in @($ruleVolumesAll | Where-Object { $_ })) { $alerts += [long](ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $v 'Alerts' 0)) }
    if ($alerts -le 0) { $alerts = $ruleAlerts }
    $incidents = if ($incSummary -and $incSummary.PSObject.Properties['Count'])  { [int](ConvertTo-BlueprintNumber $incSummary.Count) }  else { 0 }
    $closed    = if ($incSummary -and $incSummary.PSObject.Properties['Closed']) { [int](ConvertTo-BlueprintNumber $incSummary.Closed) } else { 0 }
    # First-party alerts by family: raised inside Defender XDR, Entra ID
    # Protection, Defender for Identity or Defender for Cloud, so they read
    # no workspace table and sit beside the family instead of in coverage.
    $productAgg = [ordered]@{}
    foreach ($v in @($ruleVolumesAll | Where-Object { $_ })) {
        $prod = [string](Get-BlueprintRawProperty $v 'ProductName' '')
        if (-not $prod -or $prod -match 'Sentinel') { continue }
        $famName = Get-ProductFamily -Product $prod
        $key = "$famName|$prod"
        if (-not $productAgg.Contains($key)) { $productAgg[$key] = [pscustomobject]@{ Family = $famName; Product = $prod; Alerts = [long]0; Detections = 0 } }
        $productAgg[$key].Alerts += [long](ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $v 'Alerts' 0))
        $productAgg[$key].Detections++
    }
    [pscustomobject]@{
        Sources             = $sources
        ProductAlerts       = @($productAgg.Values | Sort-Object { -$_.Alerts })
        CustomDetectionsCaptured = $customDetectionsCaptured
        CustomDetectionsTotal    = @($customDetectionsRaw | Where-Object { $_ }).Count
        CustomDetectionsEnabled  = @($customDetectionRefs | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'Enabled' $false) -eq $true }).Count
        TablesSeen          = @($tablesWithData | Where-Object { $_ -and (ConvertTo-BlueprintNumber $_.BillableLast30d) -gt 0 }).Count
        TablesActive        = $tablesActive
        TablesCovered       = $tablesCovered
        TotalGb             = [math]::Round($totalGb, 2)
        CoveredGb           = [math]::Round($coveredGb, 2)
        UncoveredGb         = [math]::Round($totalGb - $coveredGb, 2)
        TemplatesApplicable = @(
            $templateTableRefs |
                Where-Object { $_.Deprecated -ne $true -and -not (Test-TemplateRetired -Map $templateSolutionMap -TemplateId ([string]$_.TemplateId)) }
        ).Count
        RulesEnabled        = $enabledRules.Count
        RulesQueryEnabled   = @($enabledRules | Where-Object { $_.kind -in @('Scheduled', 'NRT') }).Count
        RulesFired          = $firedEnabled
        Alerts              = $alerts
        RuleAlerts          = $ruleAlerts
        XdrAlerts           = [long](($productAgg.Values | Measure-Object -Property Alerts -Sum).Sum)
        Incidents           = $incidents
        IncidentsClosed     = $closed
        IncidentsOpen       = [math]::Max(0, $incidents - $closed)
    }
}
