#Requires -Version 7.2

<#
.SYNOPSIS
    Validate handler for Defender XDR custom detections.

.DESCRIPTION
    Copied from Test-DetectionRule (Deploy/content/Deploy-DefenderDetections.ps1),
    with the problems joined onto one line as the deployer logged them.
    Also checks each technique against its tactic in MITRE ATT&CK, which
    the deployer did not (MIGRATION.md E46).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Test-iSOCDefenderDetection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.0
    Last Updated: 2026-11-06
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCDefenderDetection {
    <#
    .SYNOPSIS
        Say why a detection cannot be sent, if it cannot.

    .DESCRIPTION
        A file that could not be read reports why (deploy fails it).
        Otherwise the rule in the current shape needs a displayName, a
        queryCondition.queryText, a schedule.frequency the service runs, a
        known status when it sets one, and an alertTemplate with a title, a
        known severity and at least one known tactic whose techniques and
        sub-techniques are well formed and, in MITRE ATT&CK, belong to that
        tactic (Get-iSOCDefenderDetectionAttackMap). Entity mapping collections and
        automated action members must be ones Graph knows, and every
        automated action entry needs the columns its member requires. Every
        problem is reported, joined by '; '; deploy skips the rule.

    .PARAMETER Item
        A repository item from Read-iSOCDefenderDetectionRepo.

    .OUTPUTS
        [string] The problems, on one line; nothing when the rule can be
        sent.

    .EXAMPLE
        $issues = @(Test-iSOCDefenderDetection -Item $item)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if ($Item.ParseError) { return [string]$Item.ParseError }

    $Rule = $Item.Rule
    $contract = Get-iSOCDefenderDetectionContract
    $attack = Get-iSOCDefenderDetectionAttackMap
    $issues = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace([string]$Rule['displayName'])) { $issues.Add("missing required field 'displayName'") }

    if (-not ($Rule['queryCondition'] -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace([string]$Rule['queryCondition']['queryText'])) {
        $issues.Add("missing required field 'queryCondition.queryText'")
    }

    if (-not ($Rule['schedule'] -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace([string]$Rule['schedule']['frequency'])) {
        $issues.Add("missing required field 'schedule.frequency'")
    }
    elseif (-not (ConvertTo-iSOCDefenderDetectionFrequency -Value ([string]$Rule['schedule']['frequency']))) {
        $issues.Add("invalid schedule.frequency '$($Rule['schedule']['frequency'])'; use PT1H, PT3H, PT12H or P1D")
    }

    if ($Rule.Contains('status') -and ([string]$Rule['status']) -notin $contract.ValidDetectionStatuses) {
        $issues.Add("invalid status '$($Rule['status'])'; use $($contract.ValidDetectionStatuses -join ' or ')")
    }

    $action = $Rule['detectionAction']
    $template = if ($action -is [System.Collections.IDictionary]) { $action['alertTemplate'] } else { $null }
    if (-not ($template -is [System.Collections.IDictionary])) {
        $issues.Add("missing required field 'detectionAction.alertTemplate'")
        return ($issues -join '; ')
    }

    foreach ($field in 'title', 'severity') {
        if ([string]::IsNullOrWhiteSpace([string]$template[$field])) { $issues.Add("alertTemplate missing required field '$field'") }
    }
    if ($template['severity'] -and ([string]$template['severity']) -notin $contract.ValidDetectionSeverities) {
        $issues.Add("invalid alertTemplate.severity '$($template['severity'])'; use $($contract.ValidDetectionSeverities -join ', ')")
    }

    $tactics = @($template['tactics'] | Where-Object { $null -ne $_ })
    if ($tactics.Count -eq 0) {
        $issues.Add("alertTemplate missing required field 'tactics'")
    }
    foreach ($tactic in $tactics) {
        if (-not ($tactic -is [System.Collections.IDictionary]) -or ([string]$tactic['tactic']) -notin $contract.ValidDetectionTactics) {
            $name = if ($tactic -is [System.Collections.IDictionary]) { $tactic['tactic'] } else { $tactic }
            $issues.Add("unknown tactic '$name'")
            continue
        }
        $tacticName = [string]$tactic['tactic']
        foreach ($technique in @($tactic['techniques'] | Where-Object { $null -ne $_ })) {
            $parent = [string]$technique['technique']
            $wellFormed = $parent -match '^T\d{4}(\.\d{3})?$'
            if (-not $wellFormed) { $issues.Add("invalid technique '$parent' under $tacticName") }
            $subs = [System.Collections.Generic.List[string]]::new()
            foreach ($sub in @($technique['subTechniques'] | Where-Object { $null -ne $_ })) {
                if ([string]$sub -notmatch "^$([regex]::Escape($parent))\.\d{3}$") { $issues.Add("sub-technique '$sub' does not belong to $parent") }
                else { $subs.Add([string]$sub) }
            }

            # Graph rejects a technique under a tactic it is not in. The
            # sub-techniques are checked once their technique passes, so
            # one misplaced technique is one problem.
            if (-not $attack -or -not $wellFormed) { continue }
            $checks = @(@{ Kind = 'technique'; Id = $parent }) + @($subs | ForEach-Object { @{ Kind = 'sub-technique'; Id = $_ } })
            foreach ($check in $checks) {
                $belongs = $null
                if (-not $attack.Techniques.TryGetValue($check.Id, [ref]$belongs)) {
                    $issues.Add("$($check.Kind) '$($check.Id)' is not in MITRE ATT&CK $($attack.AttackVersion)")
                    break
                }
                if ($tacticName -notin $belongs) {
                    $issues.Add("$($check.Kind) '$($check.Id)' belongs to $($belongs -join ', '), not $tacticName, in MITRE ATT&CK $($attack.AttackVersion)")
                    break
                }
            }
        }
    }

    if ($template['entityMappings'] -is [System.Collections.IDictionary]) {
        foreach ($collection in $template['entityMappings'].Keys) {
            if ($collection -notin $contract.EntityMappingCollections) { $issues.Add("unknown entityMappings collection '$collection'") }
        }
    }

    if ($action['automatedActions'] -is [System.Collections.IDictionary]) {
        foreach ($member in $action['automatedActions'].Keys) {
            if (-not $contract.AutomatedActionRequiredColumns.ContainsKey($member)) {
                $issues.Add("unknown automatedActions member '$member'")
                continue
            }
            foreach ($entry in @($action['automatedActions'][$member])) {
                foreach ($required in $contract.AutomatedActionRequiredColumns[$member]) {
                    if (-not ($entry -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace([string]$entry[$required])) {
                        $issues.Add("automatedActions.$member entry missing '$required'")
                    }
                }
            }
        }
    }

    if ($issues.Count -gt 0) { $issues -join '; ' }
}
