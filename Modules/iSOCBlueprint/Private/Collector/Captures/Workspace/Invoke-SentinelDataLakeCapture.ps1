#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'sentinel-data-lake': writes sentinel-data-lake.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Workspace/Invoke-SentinelDataLakeCapture.ps1
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

function Invoke-SentinelDataLakeCapture {
    <#
    .SYNOPSIS
        Capture 'sentinel-data-lake': writes sentinel-data-lake.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $SubscriptionId = $Context.SubscriptionId

    # Sentinel Data Lake is provisioned as a Microsoft.SentinelPlatformServices/
    # sentinelPlatformServices resource. It's a tenant-wide capability but
    # the resource lives in a specific subscription / resource group / region
    # that the operator chose during Defender-portal onboarding, typically
    # NOT the same RG as the Sentinel workspace. Workspace-scoped GETs against
    # Microsoft.SecurityInsights/dataLake return 400 because no such
    # subresource is registered there. Resource Graph finds the platform-
    # services resource wherever it lives.
    #
    # Strategy: query Resource Graph across every subscription the executing
    # identity can read. A tenant with Lake onboarded returns exactly one
    # `microsoft.sentinelplatformservices/sentinelplatformservices` row;
    # without Lake onboarding the result is empty.
    try {
        $visibleSubs = @(Get-AzSubscription -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
        if ($visibleSubs.Count -eq 0) { $visibleSubs = @($SubscriptionId) }
        $rgBody = @{
            subscriptions = $visibleSubs
            query = 'Resources | where type =~ "microsoft.sentinelplatformservices/sentinelplatformservices" | project id, name, location, resourceGroup, subscriptionId, properties, identity, systemData'
        } | ConvertTo-Json -Compress -Depth 5
        $raw = Invoke-AzRestMethod -Path '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Method POST -Payload $rgBody -ErrorAction Stop
        if ($raw.StatusCode -lt 400 -and $raw.Content) {
            $body = $raw.Content | ConvertFrom-Json
            Save-Json -FileName 'sentinel-data-lake.json' -Data @($body.data)
        } else {
            Save-Json -FileName 'sentinel-data-lake.json' -Data @()
        }
    } catch {
        Skip-Capture -FileName 'sentinel-data-lake.json' -ErrorRecord $_
    }
}
