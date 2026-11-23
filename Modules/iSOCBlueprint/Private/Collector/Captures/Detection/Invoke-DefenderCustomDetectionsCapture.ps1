#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'defender-custom-detections': writes defender-custom-detections.json, custom-detection-table-references.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Detection/Invoke-DefenderCustomDetectionsCapture.ps1
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

# Defender XDR custom detections: the other detection logic that reads this
# data. Microsoft Graph, beta security/rules/detectionRules, needs
# CustomDetection.Read.All on the identity; a 403 is recorded as "not
# captured" rather than "none". Table references are resolved with the same
# extractor as the Sentinel rules so coverage counts both.
function Invoke-DefenderCustomDetectionsCapture {
    <#
    .SYNOPSIS
        Capture 'defender-custom-detections': writes defender-custom-detections.json, custom-detection-table-references.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $detections = @(Get-DefenderCustomDetection)
    Save-Json -FileName 'defender-custom-detections.json' -Data $detections
    Save-Json -FileName 'custom-detection-table-references.json' -Data @(Get-CustomDetectionTableReference -Detections $detections)
}
