#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 26-ueba.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Ueba/Write-BlueprintUebaSection.ps1
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
function Write-BlueprintUebaSection {
    <#
    .SYNOPSIS
        Build the figures for and write 26-ueba.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'Every section writer is called with the render context; this one reads nothing from it.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Section 26 — UEBA (TOC 4.16)
    # Two signals are surfaced:
    # 1. Configuration: presence of the /settings/Ueba resource. Absence does NOT
    #    imply UEBA is disabled — the portal toggle writes nothing here.
    # 2. Data presence: row counts in BehaviorAnalytics, IdentityInfo,
    #    UserPeerAnalytics over 12d, from `_raw/ueba-data-presence.json`. Any
    #    non-zero count is the authoritative "UEBA is producing data" signal.
    $settingsRaw = Read-BlueprintRaw 'settings.json'
    $uebaSetting = if ($null -ne $settingsRaw) { $settingsRaw.Ueba } else { $null }
    $uebaSources = if ($uebaSetting -and $uebaSetting.properties) { @($uebaSetting.properties.dataSources) } else { @() }
    $uebaConfigLabel = if ($uebaSetting) {
        'Yes (settings resource present)'
    } else {
        'Settings resource not written. UEBA may still be enabled through the portal toggle, and the configuration API has not been used to set explicit data sources on this workspace'
    }
    $uebaPresence = Read-BlueprintRawArray 'ueba-data-presence.json'
    $uebaPresenceRows = $uebaPresence | ForEach-Object {
        [pscustomobject]@{
            Table   = $_.TableName
            Rows7d  = Get-BlueprintRawProperty $_ 'Count7d' ''
            Rows12d = $_.Count
            Rows14d = Get-BlueprintRawProperty $_ 'Count14d' ''
        }
    }
    # Entity analytics: the identity providers synchronised into IdentityInfo
    # (Microsoft Entra ID, Active Directory), from the settings resource, and the
    # IdentityInfo rows that show the sync is running.
    $entitySetting = if ($null -ne $settingsRaw) { Get-BlueprintRawProperty $settingsRaw 'EntityAnalytics' } else { $null }
    $entityProviders = @(Get-BlueprintRawProperty (Get-BlueprintRawProperty $entitySetting 'properties') 'entityProviders' @())
    $identityRow = @($uebaPresence | Where-Object { $_ -and [string]$_.TableName -eq 'IdentityInfo' }) | Select-Object -First 1
    $identityRows14 = if ($identityRow) {
        ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $identityRow 'Count14d' (Get-BlueprintRawProperty $identityRow 'Count' 0))
    } else { 0 }
    $entityEnabled = $entityProviders.Count -gt 0 -or $identityRows14 -gt 0
    $entityBlock = @"
| | |
|---|---|
| Entity providers (configured) | $(if ($entityProviders.Count -gt 0) { $entityProviders -join ', ' } else { '_(none configured via the settings resource)_' }) |
| IdentityInfo rows ({lookback-d}) | $(Format-BlueprintCount $identityRows14) |
| Entity analytics | $(if ($entityEnabled) { 'Enabled' } elseif ($uebaPresence.Count -eq 0) { 'Unknown (data-presence capture not available)' } else { 'Not enabled ([SAC-COV-08])' }) |
"@
    $uebaTotalRows = ($uebaPresenceRows | Measure-Object -Property Rows12d -Sum).Sum
    $uebaActiveLabel = if ($uebaTotalRows -and $uebaTotalRows -gt 0) {
        "Yes, $(Format-BlueprintPlural $uebaTotalRows 'row') across $(Format-BlueprintPlural @($uebaPresenceRows | Where-Object { $_.Rows12d -gt 0 }).Count 'UEBA table') over the last {lookback}"
    } elseif ($uebaPresence.Count -eq 0) {
        '_(data-presence capture not available, re-run the exporter to refresh)_'
    } else {
        'No, none of BehaviorAnalytics, IdentityInfo, UserPeerAnalytics received rows in the last {lookback}'
    }
    # Pie of rows per UEBA table when there's something to chart.
    $uebaPiePresenceBlock = if ($uebaPresenceRows.Count -gt 0 -and $uebaTotalRows -gt 0) {
        $uebaPieRows = $uebaPresenceRows | Where-Object { $_.Rows12d -gt 0 } | ForEach-Object {
            "    `"$($_.Table)`" : $([long]$_.Rows12d)"
        }
        @"

## UEBA table activity (last {lookback-d})

``````mermaid
pie showData title UEBA rows by table (last {lookback})
$($uebaPieRows -join [Environment]::NewLine)
``````

A workspace producing data in BehaviorAnalytics + IdentityInfo + UserPeerAnalytics has the full UEBA pipeline active. A single-table dominance suggests one anchor source feeding the rest.
"@
    } else { '' }

    $uebaPresenceBlock = if ($uebaPresenceRows.Count -gt 0) {
        @"

## Data-presence inference (last {lookback})

Rows per UEBA table over the last {recent} and the last {lookback}. The {recent-d} column is blank in snapshots taken before it was added.

$(Format-BlueprintTable -Items @($uebaPresenceRows | ForEach-Object { [pscustomobject]@{ Table = $_.Table; Rows7d = (Format-BlueprintCount $_.Rows7d); Rows12d = (Format-BlueprintCount $_.Rows12d) } }) -Columns 'Table','Rows7d','Rows12d')
"@
    } else { '' }
    Write-BlueprintSection '26-ueba.md' (@"
$(Format-Banner -Title 'User and Entity Behaviour Analytics  (TOC 4.16)')

UEBA enriches incidents with anomaly scores and entity-level timelines. It is enabled at the workspace level via the ``Microsoft.SecurityInsights/settings/Ueba`` resource. The configuration row reflects whether the settings resource has been written; the data-presence row reflects whether UEBA is actually producing rows.

| | |
|---|---|
| Configuration | $uebaConfigLabel |
| Data sources (configured) | $(if ($uebaSources.Count -gt 0) { ($uebaSources -join ', ') } else { '_(none configured via the settings resource)_' }) |
| Producing data | $uebaActiveLabel |
$uebaPiePresenceBlock$uebaPresenceBlock

## Entity analytics

Entity analytics synchronises user and group details from the identity providers into ``IdentityInfo``, which enriches every incident with who the account is and what it belongs to. It is configured separately from UEBA.

$entityBlock

[Enable UEBA in Microsoft Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/enable-entity-behavior-analytics)
"@)
}
