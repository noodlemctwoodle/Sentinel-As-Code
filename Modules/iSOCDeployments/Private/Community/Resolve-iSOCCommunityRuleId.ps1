#Requires -Version 7.2

<#
.SYNOPSIS
    Give every rule of an import an id no other rule file uses.

.DESCRIPTION
    Copied from Resolve-CommunityRuleId (Tools/Import-CommunityRules.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Resolve-iSOCCommunityRuleId.ps1
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

function Resolve-iSOCCommunityRuleId {
    <#
    .SYNOPSIS
        Settle each pending rule's id, keeping the id a rule already has in
        the repository, and return the ones that are not the upstream's.

    .DESCRIPTION
        The deployer names each rule in the workspace by its id, so two
        files with one id are one rule and every deploy overwrites one with
        the other. In ordinal order of relative path:
        1. a rule whose destination file exists keeps that file's id, so a
           re-import never changes a deployed rule's identity;
        2. any other rule keeps its upstream id unless another rule
           (pending, or reserved) has it; then it gets
           New-iSOCCommunityRuleId of the source repository and its path.
        Ids compare without regard to case. Only the top-level id line of
        each rule's YamlContent changes, in place.

    .PARAMETER PendingRules
        The rules, each with RelativePath and YamlContent.

    .PARAMETER OutputPath
        The folder the rules are written to.

    .PARAMETER SourceRepo
        The source repository; a trailing .git or slash is ignored.

    .PARAMETER ReservedIds
        Ids used outside the import, from Get-iSOCReservedRuleId.

    .OUTPUTS
        [pscustomobject] RelativePath, UpstreamId, Id and Reason for each
        rule whose id is not its upstream id.

    .EXAMPLE
        $changes = @(Resolve-iSOCCommunityRuleId -PendingRules $pending -OutputPath $out -SourceRepo $repo -ReservedIds $reserved)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.IList] $PendingRules,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [Parameter(Mandatory)]
        [string] $SourceRepo,

        [hashtable] $ReservedIds = @{}
    )

    $idLine = '(?m)^id:[ \t]*[''"]?([^''"\r\n]+?)[''"]?[ \t]*$'
    $source = ($SourceRepo.TrimEnd('/') -replace '\.git$', '').TrimEnd('/')
    $used = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $ReservedIds.Keys) { $used[[string]$key] = [string]$ReservedIds[$key] }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in $PendingRules) {
        $relative = ([string]$rule.RelativePath).Replace('\', '/')
        $match = [regex]::Match([string]$rule.YamlContent, $idLine)
        if (-not $match.Success) { throw "Rule '$relative' has no top-level id line." }
        $entries.Add([pscustomobject]@{
                Rule     = $rule
                Relative = $relative
                Upstream = $match.Groups[1].Value.Trim()
                Existing = Get-iSOCRuleFileId -Path (Join-Path $OutputPath $rule.RelativePath)
            })
    }
    $entries.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Relative, $b.Relative) })

    $changes = [System.Collections.Generic.List[object]]::new()
    $assign = {
        param($Entry, [string] $Id, [string] $Reason)
        if ($Id -cne $Entry.Upstream) {
            $Entry.Rule.YamlContent = [regex]::new('(?m)^id:[^\r\n]*').Replace([string]$Entry.Rule.YamlContent, "id: $Id", 1)
            $changes.Add([pscustomobject]@{ RelativePath = $Entry.Relative; UpstreamId = $Entry.Upstream; Id = $Id; Reason = $Reason })
        }
        $used[$Id] = $Entry.Relative
    }

    $fresh = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $entries) {
        if ($entry.Existing -and -not $used.ContainsKey($entry.Existing)) {
            & $assign $entry $entry.Existing 'kept the id the repository file has'
            continue
        }
        $fresh.Add($entry)
    }
    foreach ($entry in $fresh) {
        if (-not $used.ContainsKey($entry.Upstream)) {
            & $assign $entry $entry.Upstream ''
            continue
        }
        $derived = New-iSOCCommunityRuleId -Name "$source#$($entry.Relative)"
        if ($used.ContainsKey($derived)) { throw "Rule '$($entry.Relative)': the derived id $derived is already used by '$($used[$derived])'." }
        & $assign $entry $derived "upstream id $($entry.Upstream) is already used by $($used[$entry.Upstream])"
    }
    $changes.ToArray()
}
