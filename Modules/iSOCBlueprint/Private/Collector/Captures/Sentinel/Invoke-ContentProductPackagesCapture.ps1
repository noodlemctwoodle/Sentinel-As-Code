#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'content-product-packages': writes content-product-packages.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-ContentProductPackagesCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-ContentProductPackagesCapture {
    <#
    .SYNOPSIS
        Capture 'content-product-packages': writes content-product-packages.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    # Content Hub catalogue. Was gated behind -IncludePreview which meant
    # production runs without the switch produced no catalogue file at all,
    # which then broke the "Update Available" column in section 70.
    # contentProductPackages is GA via the preview api-version; treat
    # missing-file outcomes as endpoint unavailability rather than gate-skip.
    try {
        $catalog = Invoke-SentinelRest -Path "$sentinelScope/contentProductPackages" -ApiVersion $apiVersions.SentinelPreview
        Save-Json -FileName 'content-product-packages.json' -Data $catalog
    } catch {
        Skip-Capture -FileName 'content-product-packages.json' -ErrorRecord $_
    }
}
