#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'sentinel-settings': writes settings.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-SentinelSettingsCapture.ps1
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

# Bundle the four settings resources into a single file with one property per setting.
#
# Per-setting null in the produced file does NOT mean the corresponding feature
# is disabled. It means the workspace has no explicit settings resource at
# /providers/Microsoft.SecurityInsights/settings/<name>. UEBA, Entity Analytics,
# Eyes-On, and Anomalies can be toggled on via the portal without writing the
# settings resource, in which case the GET returns 404 and Invoke-SentinelRest
# converts that to an empty array (see Invoke-SentinelRest.ps1 line ~104).
# $val[0] then correctly unwraps the single-element response when the resource
# does exist, and resolves to null when it does not.
#
# To answer the operational question "is UEBA actually producing data?" the
# more robust signal is row counts in BehaviorAnalytics / IdentityInfo /
# UserPeerAnalytics. That data-presence inference is captured separately by
# a future commit; the settings capture here is the configuration-side signal.
function Invoke-SentinelSettingsCapture {
    <#
    .SYNOPSIS
        Capture 'sentinel-settings': writes settings.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    $settings = [ordered]@{}
    foreach ($n in @('Ueba', 'EntityAnalytics', 'EyesOn', 'Anomalies')) {
        try {
            # Invoke-SentinelRest always returns an array (single-resource
            # responses get wrapped in a one-element array, 404s yield @()).
            # When the workspace has the settings resource present, $val has
            # exactly one element; when the toggle lives only in the portal
            # the endpoint 404s and $val is empty -> $null is stored. The
            # renderer treats $null as "settings resource not written" and
            # falls back to the data-presence capture below for the real
            # "is UEBA producing data?" signal.
            $val = Invoke-SentinelRest -Path "$sentinelScope/settings/$n" -ApiVersion $apiVersions.Sentinel
            $settings[$n] = if ($val -and @($val).Count -gt 0) { $val[0] } else { $null }
        } catch {
            $settings[$n] = $null
        }
    }
    Save-Json -FileName 'settings.json' -Data $settings
}
