#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'alert-rules': writes alert-rules.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-AlertRulesCapture.ps1
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

function Invoke-AlertRulesCapture {
    <#
    .SYNOPSIS
        Capture 'alert-rules': writes alert-rules.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    # The preview API: each rule's sub-techniques come in their own
    # subTechniques array, which every GA version leaves out (the MITRE page
    # needs it). A tenant that refuses the preview call gets the GA list,
    # without sub-techniques, and a warning in the run log.
    $rules = try {
        Invoke-SentinelRest -Path "$sentinelScope/alertRules" -ApiVersion $apiVersions.SentinelPreview
    } catch {
        Write-CaptureNote -Kind NotAvailable -Text "alertRules $($apiVersions.SentinelPreview) is not served ($(Format-CaptureMessage (Get-CaptureErrorText $_))); used $($apiVersions.Sentinel), which leaves out sub-techniques."
        Invoke-SentinelRest -Path "$sentinelScope/alertRules" -ApiVersion $apiVersions.Sentinel
    }
    $script:AlertRules = @($rules)
    Save-Json -FileName 'alert-rules.json' -Data $rules
}
