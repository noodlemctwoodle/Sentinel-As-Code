#Requires -Version 7.6

<#
.SYNOPSIS
    List the differences between two sets of manifest entries.

.DESCRIPTION
    Copied from Compare-Manifest in Tools/Build-DependencyManifest.ps1,
    unchanged in behaviour and in the lines it reports.

.NOTES
    File:         Modules/iSOCDeployments/Private/Manifest/Compare-iSOCDependencyManifest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Compare-iSOCDependencyManifest {
    <#
    .SYNOPSIS
        Compare discovered entries with the entries on disk.

    .DESCRIPTION
        Reports each path added (discovered, not on disk), removed (on disk,
        not discovered) or changed, and for a changed one each bucket whose
        members differ, with both sides. Bucket members are compared as
        sorted lists, so order within a bucket does not count.

    .PARAMETER Discovered
        The entries discovery produced.

    .PARAMETER OnDisk
        The entries in the manifest file.

    .OUTPUTS
        [hashtable] HasDrift and Diff (the report lines).

    .EXAMPLE
        Compare-iSOCDependencyManifest -Discovered $manifest.Entries -OnDisk $onDisk
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Discovered,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $OnDisk
    )

    $diff = [System.Collections.Generic.List[string]]::new()
    $allKeys = ($Discovered.Keys + $OnDisk.Keys) | Sort-Object -Unique

    foreach ($key in $allKeys) {
        $left = $OnDisk[$key]
        $right = $Discovered[$key]

        if (-not $left -and $right) { $diff.Add("ADDED:    $key"); continue }
        if ($left -and -not $right) { $diff.Add("REMOVED:  $key"); continue }

        $changed = $false
        foreach ($depKey in @('tables', 'watchlists', 'functions', 'externalData')) {
            $leftSet = if ($left.Contains($depKey)) { @($left[$depKey]) | Sort-Object } else { @() }
            $rightSet = if ($right.Contains($depKey)) { @($right[$depKey]) | Sort-Object } else { @() }
            $leftStr = $leftSet -join ','
            $rightStr = $rightSet -join ','
            if ($leftStr -ne $rightStr) {
                if (-not $changed) { $diff.Add("CHANGED:  $key"); $changed = $true }
                $diff.Add("    $depKey :  on-disk=[$leftStr]  discovered=[$rightStr]")
            }
        }
    }

    @{
        HasDrift = ($diff.Count -gt 0)
        Diff     = $diff
    }
}
