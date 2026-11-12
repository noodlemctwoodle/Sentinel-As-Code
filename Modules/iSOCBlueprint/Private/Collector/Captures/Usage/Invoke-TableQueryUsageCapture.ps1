#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'table-query-usage': writes table-query-usage.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Usage/Invoke-TableQueryUsageCapture.ps1
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

# Audited queries per lake-retained table (LAQueryLogs, 30 days): the
# usage evidence for tables that keep data in the lake beyond analytics
# retention or route to the lake only. Targets come from the
# workspace-tables capture written earlier in this run. Tables go in
# batches of 60 so the query text stays short; a failed batch fails the
# capture, so the pages read "not captured" rather than "no queries".
function Invoke-TableQueryUsageCapture {
    <#
    .SYNOPSIS
        Capture 'table-query-usage': writes table-query-usage.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $rawOut = $Context.rawOut

    $targets = @()
    $tablesPath = Join-Path $rawOut 'workspace-tables.json'
    if (Test-Path -LiteralPath $tablesPath) {
        $wsTables = @(Get-Content -LiteralPath $tablesPath -Raw | ConvertFrom-Json -Depth 32)
        foreach ($t in $wsTables) {
            if (-not $t -or -not $t.PSObject.Properties['properties'] -or -not $t.properties) { continue }
            $pr = $t.properties
            $plan = if ($pr.PSObject.Properties['plan']) { [string]$pr.plan } else { '' }
            $r = if ($pr.PSObject.Properties['retentionInDays'] -and $pr.retentionInDays) { [int]$pr.retentionInDays } else { 0 }
            $tr = if ($pr.PSObject.Properties['totalRetentionInDays'] -and $pr.totalRetentionInDays) { [int]$pr.totalRetentionInDays } else { 0 }
            if ($plan -eq 'DataLake' -or $tr -gt $r) { $targets += [string]$t.name }
        }
    }
    $targets = @($targets | Where-Object { $_ -match '^[A-Za-z0-9_]+$' } | Sort-Object -Unique)
    $usage = [System.Collections.Generic.List[object]]::new()
    for ($b = 0; $b -lt $targets.Count; $b += 60) {
        $batch = @($targets[$b..([math]::Min($b + 59, $targets.Count - 1))])
        $list = ($batch | ForEach-Object { '"' + $_ + '"' }) -join ','
        $kql = @"
LAQueryLogs
| where TimeGenerated > ago(lookback)
| extend Q = tolower(tostring(QueryText))
| mv-apply T = dynamic([$list]) to typeof(string) on (
    where Q contains tolower(T)
    | project T
)
| summarize Queries = count(), Users = dcount(AADEmail), LastQuery = max(TimeGenerated) by Table = T
"@
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        foreach ($row in @($result.Results)) { if ($row) { $usage.Add($row) } }
    }
    Save-Json -FileName 'table-query-usage.json' -Data @($usage | Sort-Object @{ Expression = { [long]$_.Queries }; Descending = $true }, Table)
}
