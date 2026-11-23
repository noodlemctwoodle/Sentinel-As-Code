#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'xdr-table-presence': writes xdr-table-presence.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Logs/Invoke-XdrTablePresenceCapture.ps1
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

function Invoke-XdrTablePresenceCapture {
    <#
    .SYNOPSIS
        Capture 'xdr-table-presence': writes xdr-table-presence.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # XDR table-presence summary over the known XDR table list. Quick answer
    # to "is Defender XDR connected and producing data?".
    $kql = @'
let tablesOfInterest = dynamic([
    "AlertEvidence","CloudAppEvents","McasShadowItReporting",
    "DeviceEvents","DeviceFileEvents","DeviceImageLoadEvents","DeviceInfo","DeviceLogonEvents",
    "DeviceNetworkEvents","DeviceNetworkInfo","DeviceProcessEvents","DeviceRegistryEvents",
    "DeviceFileCertificateInfo","EmailAttachmentInfo","EmailEvents","EmailPostDeliveryEvents",
    "EmailUrlInfo","UrlClickEvents","IdentityLogonEvents","IdentityQueryEvents","IdentityDirectoryEvents"
]);
union withsource = tt *
| where TimeGenerated > ago(lookback)
| summarize RecordCount = count() by Type
| where Type in (tablesOfInterest)
| order by Type asc
'@
    try {
        $r = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'xdr-table-presence.json' -Data ($r.Results)
    } catch { Skip-Capture -FileName 'xdr-table-presence.json' -ErrorRecord $_ }
}
