#Requires -Version 7.6

<#
.SYNOPSIS
    Decide how the findings list changes for this run, keeping a history of findings that stop firing.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SyncPlan/Findings/Get-FindingSyncPlan.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint sync planning
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-FindingSyncPlan {
    <#
    .SYNOPSIS
        Decide how the findings list changes for this run, keeping a history
        of findings that stop firing.

    .DESCRIPTION
        A finding that fires is added (new), updated (already open) or
        reopened (previously resolved or retired). An open finding that did
        not fire is only resolved when the gap engine says its check ran and
        passed; a check that errored leaves the finding open, because the
        engine could not tell either way. A finding whose rule is no longer
        in the rule set is retired.

        When the snapshot has no per-check outcomes (artefacts from before
        gap-checks.json existed), an open finding that did not fire is
        resolved. When the snapshot has no gap analysis at all, nothing is
        resolved: an absent analysis is not evidence that anything was
        fixed.

    .PARAMETER Current
        The findings that fired in this run: objects with id, title,
        severity, category, evidence, remediation, learn and, for a rule
        renamed from the SENT-NNN scheme, legacyId.

    .PARAMETER Existing
        Items already in the list: objects with ItemId, FindingId and Status.

    .PARAMETER Checks
        Per-check outcomes from gap-checks.json (objects with Id and
        Outcome: Fired, Passed, Errored, Undefined), or $null when the
        snapshot predates that file.

    .PARAMETER AnalysisAvailable
        $false when the snapshot has no gap-analysis.json.

    .PARAMETER NowUtc
        Timestamp written to FirstSeen / LastSeen / ResolvedOn.

    .OUTPUTS
        [pscustomobject[]] Action (Add, Update, Reopen, Resolve, Retire),
        FindingId, ItemId ($null for Add) and Values (hashtable of list
        field values to write).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Current,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Existing,
        [AllowNull()] [object[]] $Checks,
        [Parameter(Mandatory)] [bool] $AnalysisAvailable,
        [Parameter(Mandatory)] [datetime] $NowUtc
    )

    $sevRank = @{ 'Critical' = 0; 'Error' = 1; 'High' = 1; 'Warning' = 2; 'Medium' = 2; 'Info' = 3; 'Informational' = 3; 'Low' = 3 }
    $now = $NowUtc.ToUniversalTime()

    $existingById = @{}
    foreach ($e in $Existing) { if ($e.FindingId) { $existingById[[string]$e.FindingId] = $e } }

    $checksById = $null
    if ($null -ne $Checks) {
        $checksById = @{}
        foreach ($c in $Checks) { if ($c.Id) { $checksById[[string]$c.Id] = [string]$c.Outcome } }
    }

    $plan = [System.Collections.Generic.List[pscustomobject]]::new()
    $fired = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($f in $Current) {
        $id = [string]$f.id
        if (-not $id) { continue }
        [void]$fired.Add($id)
        # A finding renamed from the SENT-NNN scheme carries its old id as
        # legacyId; an item still filed under that id is the same finding and
        # is updated in place (its FindingId moves to the new id).
        $legacyId = if ($f.PSObject.Properties['legacyId'] -and $f.legacyId) { [string]$f.legacyId } else { $null }
        $match = if ($existingById.ContainsKey($id)) { $existingById[$id] } elseif ($legacyId -and $existingById.ContainsKey($legacyId)) { $existingById[$legacyId] } else { $null }
        if ($match -and $legacyId) { [void]$fired.Add($legacyId) }
        $severity = [string]$f.severity
        $values = @{
            Title        = [string]$f.title
            FindingId    = $id
            Severity     = $severity
            SeverityRank = $(if ($sevRank.ContainsKey($severity)) { $sevRank[$severity] } else { 4 })
            Category     = [string]$f.category
            Evidence     = [string]$f.evidence
            Remediation  = [string]$f.remediation
            Learn        = $(if ($f.learn) { "$($f.learn), Microsoft Learn" } else { $null })
            Status       = 'Open'
            LastSeen     = $now
        }

        if (-not $match) {
            $values.FirstSeen = $now
            $values.ResolvedOn = $null
            $plan.Add([pscustomobject]@{ Action = 'Add'; FindingId = $id; ItemId = $null; Values = $values })
        }
        elseif ([string]$match.Status -ne 'Open') {
            $values.ResolvedOn = $null
            $plan.Add([pscustomobject]@{ Action = 'Reopen'; FindingId = $id; ItemId = $match.ItemId; Values = $values })
        }
        else {
            $plan.Add([pscustomobject]@{ Action = 'Update'; FindingId = $id; ItemId = $match.ItemId; Values = $values })
        }
    }

    if (-not $AnalysisAvailable) { return $plan.ToArray() }

    foreach ($id in ($existingById.Keys | Sort-Object)) {
        if ($fired.Contains($id)) { continue }
        $item = $existingById[$id]
        if ([string]$item.Status -ne 'Open') { continue }

        $action = $null
        if ($null -eq $checksById) {
            $action = 'Resolve'
        }
        elseif (-not $checksById.ContainsKey($id)) {
            $action = 'Retire'
        }
        elseif ($checksById[$id] -eq 'Passed') {
            $action = 'Resolve'
        }
        # Errored / Undefined: the engine could not evaluate the check, so
        # the finding stays open.

        if ($action) {
            $status = if ($action -eq 'Retire') { 'Retired' } else { 'Resolved' }
            $plan.Add([pscustomobject]@{
                    Action    = $action
                    FindingId = $id
                    ItemId    = $item.ItemId
                    Values    = @{ Status = $status; ResolvedOn = $now }
                })
        }
    }

    return $plan.ToArray()
}
