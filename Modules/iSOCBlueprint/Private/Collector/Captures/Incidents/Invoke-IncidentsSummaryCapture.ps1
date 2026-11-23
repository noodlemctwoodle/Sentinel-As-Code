#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'incidents-summary': writes incidents-summary.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Incidents/Invoke-IncidentsSummaryCapture.ps1
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

function Invoke-IncidentsSummaryCapture {
    <#
    .SYNOPSIS
        Capture 'incidents-summary': writes incidents-summary.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'The collector calls every capture as & $capture -Context $context, so each takes the same parameter even when it reads its state from script scope.')]
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Aggregate-only, the Blueprint never exports incident bodies (PII).
    # The bags hold counts per key. ByClassification covers closed incidents
    # only; an empty classification is reported as "Unclassified".
    # OpenBySeverity counts the incidents not closed. ClosedBy says who closed
    # each closed incident, from the first record that shows it Closed:
    # an automation rule (ModifiedBy contains "Automation", the test
    # Microsoft's automation rule guide uses), Defender XDR (closed there and
    # synced), an analyst (a user principal name), or Other; only the
    # category leaves the workspace, never the name.
    $kql = @'
let inc = SecurityIncident
| where TimeGenerated > ago(lookback)
| summarize arg_max(TimeGenerated, *) by IncidentNumber;
let byStatus = inc | summarize N = count() by Status   | summarize B = make_bag(bag_pack(Status, N), 100);
let bySev    = inc | summarize N = count() by Severity | summarize B = make_bag(bag_pack(Severity, N), 100);
let byClass  = inc
| where Status == "Closed"
| extend C = iff(isempty(Classification), "Unclassified", Classification)
| summarize N = count() by C
| summarize B = make_bag(bag_pack(C, N), 100);
let byProvider = inc
| extend P = iff(isempty(ProviderName), "Unknown", ProviderName)
| summarize N = count() by P
| summarize B = make_bag(bag_pack(P, N), 100);
let openBySev = inc | where Status != "Closed" | summarize N = count() by Severity | summarize B = make_bag(bag_pack(Severity, N), 100);
let closing = SecurityIncident
| where TimeGenerated > ago(lookback) and Status == "Closed"
| summarize arg_min(TimeGenerated, ModifiedBy) by IncidentNumber;
let closedBy = inc
| where Status == "Closed"
| project IncidentNumber
| join kind=leftouter closing on IncidentNumber
| extend By = case(ModifiedBy contains "Automation", "AutomationRule",
                   ModifiedBy has_any ("Microsoft 365 Defender", "Microsoft Defender XDR", "Microsoft XDR"), "DefenderXdr",
                   ModifiedBy contains "@", "Analyst",
                   "Other")
| summarize N = count() by By
| summarize B = make_bag(bag_pack(By, N), 100);
let isUnified = (p: string, a: string) { p in ("Microsoft 365 Defender", "Microsoft XDR") or a has_any ("Microsoft 365 Defender", "Microsoft XDR") };
inc
| extend Recent = TimeGenerated > ago(recent), IsUnified = isUnified(ProviderName, tostring(AdditionalData))
| summarize Count = count(), Closed = countif(Status == "Closed"),
    Unified = countif(IsUnified),
    Count7d = countif(Recent), Closed7d = countif(Recent and Status == "Closed"),
    FalsePositive7d = countif(Recent and Classification == "FalsePositive"),
    TruePositive7d = countif(Recent and Classification == "TruePositive"),
    Unified7d = countif(Recent and IsUnified)
| extend ByStatus = toscalar(byStatus), BySeverity = toscalar(bySev), ByClassification = toscalar(byClass), ByProvider = toscalar(byProvider),
    OpenBySeverity = toscalar(openBySev), ClosedBy = toscalar(closedBy)
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'incidents-summary.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'incidents-summary.json' -ErrorRecord $_
    }
}
