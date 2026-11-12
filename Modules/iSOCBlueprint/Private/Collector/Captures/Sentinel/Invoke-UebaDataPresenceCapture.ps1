#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'ueba-data-presence': writes ueba-data-presence.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-UebaDataPresenceCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# UEBA data-presence inference.
# The /settings/Ueba endpoint only reflects the configuration-side state and
# returns 404 when UEBA is toggled on via the portal without an explicit
# settings resource being written. The operational question users ask
# ("is UEBA producing data?") is better answered by counting rows in the
# tables UEBA writes to: BehaviorAnalytics, IdentityInfo, UserPeerAnalytics.
# Capture the per-table row counts over the last 12 days so the renderer can
# surface "data flowing -> Yes" even when the settings GET reported absence.
function Invoke-UebaDataPresenceCapture {
    <#
    .SYNOPSIS
        Capture 'ueba-data-presence': writes ueba-data-presence.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Stamp the table name onto every row BEFORE union, `union withsource`
    # only labels rows present at the moment of the union, and the inner
    # `summarize count()` collapsed each arm to a single row, so withsource
    # fell back to synthetic positional names (union_arg0/1/2) instead of
    # the real table name. The fix: extend Table at the source, summarize
    # by Table after the union. `isfuzzy=true` also handles a workspace
    # that hasn't enabled UEBA yet (UserPeerAnalytics may be missing), 
    # KQL skips the missing arm rather than throwing.
    $kql = @'
union isfuzzy=true
    (BehaviorAnalytics  | where TimeGenerated > ago(lookback) | extend TableName = "BehaviorAnalytics"),
    (IdentityInfo       | where TimeGenerated > ago(lookback) | extend TableName = "IdentityInfo"),
    (UserPeerAnalytics  | where TimeGenerated > ago(lookback) | extend TableName = "UserPeerAnalytics")
| summarize Count = countif(TimeGenerated > ago(lookback)), Count7d = countif(TimeGenerated > ago(recent)), Count14d = count() by TableName
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'ueba-data-presence.json' -Data ($r.Results)
    } catch { Skip-Capture -FileName 'ueba-data-presence.json' -ErrorRecord $_ }
}
