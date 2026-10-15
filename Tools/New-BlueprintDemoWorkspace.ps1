#Requires -Version 7.2

<#
.SYNOPSIS
    Write a synthetic Blueprint inventory for a large demo workspace, built
    from the repository's own content

.DESCRIPTION
    Produces the _raw folder the iSOC Blueprint collector would write for a
    fictitious enterprise workspace (Contoso), so the report, the SharePoint
    dashboard and every page that reads activity can be shown, developed
    and screenshotted without a tenant. Nothing in it comes from a real
    workspace.

    The deployed content is this repository's: the analytics rules under
    Content/AnalyticalRules (the Community folder becomes Content Hub
    templates, some deployed from their template), the hunting queries, the
    Defender XDR custom detections, the playbooks, workbooks, watchlists,
    automation rules, summary rules, parsers and the codeless connector.
    The tables those read, and the rest of a typical large estate (CEF
    firewalls, Defender XDR streaming, Windows and Linux servers, Entra ID,
    Azure Firewall, AWS), ingest about -DailyGb a day over the lookback,
    with weekday and weekend patterns, gentle growth and a runaway source
    for the trend to show. At that volume the workspace sits on the
    commitment tier nearest its Analytics-plan ingest (2,000 GB a day by
    default), and the price list holds the public UK South prices, every
    commitment tier's included, so the estimate prices it as Microsoft
    bills it. Alerts, incidents, verdicts, health events,
    playbook runs and the daily series behind the dashboard's window slider
    are simulated from the rules and products, so they agree with each
    other and with the content.

    The engine's own steps then run over it: the table references, the
    cost estimate, the gap analysis and the maturity assessment. Shapes no
    content drives (subscription, locks, prices, What's new) come from the
    test fixture with the demo's names. A fixed -Seed gives the same data
    every run; -AsOf moves its dates.

    With -Build, the report and the SharePoint bundle are built from it
    and the bundle's folder is returned, ready to open or serve.

.PARAMETER OutputPath
    The workspace folder to write. The inventory goes to its _raw folder
    and -Build writes the report and the bundle beside it. Defaults to
    SecurityDocs/<WorkspaceName> in the repository, which git ignores.

.PARAMETER WorkspaceName
    The demo workspace's name. Defaults to law-contoso-sentinel.

.PARAMETER DailyGb
    The average GB ingested a day over the last 30 days, every table
    included. Defaults to 2048 (2 TB a day).

.PARAMETER LookbackDays
    The days of activity the inventory covers, 7 to 90, as the collector's
    -LookbackDays. The daily series cover the same days, so the dashboard's
    slider runs from 1 to it. Defaults to 90.

.PARAMETER AsOf
    When the demo was "collected". Every date counts back from it.
    Defaults to now (UTC).

.PARAMETER Seed
    The random seed. The same seed and content give the same inventory.
    Defaults to 2048.

.PARAMETER Build
    Render the report and build the SharePoint bundle after writing the
    inventory, and return the bundle's folder.

.PARAMETER RepoPath
    The repository root, for Content/, the engine and the test fixture.
    Defaults to the folder above this script's.

.OUTPUTS
    [pscustomobject] Path (the workspace folder), Raw (its _raw folder),
    Bundle (the SharePoint bundle with -Build, else $null) and a Summary
    of what was written.

.EXAMPLE
    ./Tools/New-BlueprintDemoWorkspace.ps1 -Build

    Writes SecurityDocs/law-contoso-sentinel/_raw for a 2 TB a day
    workspace over 90 days, renders the report and builds the dashboard
    bundle under SecurityDocs/law-contoso-sentinel/sharepoint.

.EXAMPLE
    ./Tools/New-BlueprintDemoWorkspace.ps1 -OutputPath ./artefact/demo -DailyGb 500 -LookbackDays 30

    A 500 GB a day workspace over 30 days, inventory only, under
    ./artefact/demo/_raw.

.NOTES
    File:         Tools/New-BlueprintDemoWorkspace.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-14
    Version:      0.2.2
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+, powershell-yaml (auto-installed if missing)

    Offline: reads the repository and writes files, and calls no Azure
    API. Prices are the public UK South list prices in GBP as published on
    2026-10-14, not a quote.
#>
[CmdletBinding()]
param(
    [string]$OutputPath,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]{2,62}$')]
    [string]$WorkspaceName = 'law-contoso-sentinel',

    [ValidateRange(10, 50000)]
    [double]$DailyGb = 2048,

    [ValidateRange(7, 90)]
    [int]$LookbackDays = 90,

    [datetime]$AsOf = [datetime]::UtcNow,

    [int]$Seed = 2048,

    [switch]$Build,

    [string]$RepoPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
}
Import-Module powershell-yaml -ErrorAction Stop

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
$content = Join-Path $RepoPath 'Content'
$engine = Join-Path $RepoPath 'Modules/iSOCBlueprint/Engine'
$resources = Join-Path $engine 'Private/Resources'
$fixtureRaw = Join-Path $RepoPath 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
if (-not $OutputPath) { $OutputPath = Join-Path $RepoPath "SecurityDocs/$WorkspaceName" }
$raw = Join-Path $OutputPath '_raw'
if (Test-Path -LiteralPath $raw) { Remove-Item -LiteralPath $raw -Recurse -Force }
New-Item -ItemType Directory -Path $raw -Force | Out-Null

. (Join-Path $engine 'Private/Vendor/SentinelCommon.Kql.ps1')
. (Join-Path $engine 'Private/Get-KqlTableReferences.ps1')
. (Join-Path $engine 'Private/Get-DefenderCustomDetections.ps1')

$asOfUtc = if ($AsOf.Kind -eq [System.DateTimeKind]::Unspecified) { [datetime]::SpecifyKind($AsOf, 'Utc') } else { $AsOf.ToUniversalTime() }
$asOfUtc = [datetime]::new($asOfUtc.Year, $asOfUtc.Month, $asOfUtc.Day, $asOfUtc.Hour, $asOfUtc.Minute, 0, [System.DateTimeKind]::Utc)
$L = $LookbackDays
$recentDays = [math]::Min(7, $L)

$script:Rng = [System.Random]::new($Seed)
$subscriptionId = '00000000-0000-0000-0000-00000000c0de'
$tenantId = '00000000-0000-0000-0000-0000000c0de0'
$resourceGroup = 'rg-contoso-sentinel'
$region = 'uksouth'
$wsId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
$siId = "$wsId/providers/Microsoft.SecurityInsights"

function Get-DemoRandom { $script:Rng.NextDouble() }
function Get-DemoBetween([double]$Min, [double]$Max) { $Min + ($Max - $Min) * $script:Rng.NextDouble() }
function Get-DemoNormal([double]$Mean, [double]$Sd) {
    $u1 = 1.0 - $script:Rng.NextDouble(); $u2 = $script:Rng.NextDouble()
    $Mean + $Sd * [math]::Sqrt(-2.0 * [math]::Log($u1)) * [math]::Cos(2 * [math]::PI * $u2)
}
function Get-DemoPoisson([double]$Lambda) {
    if ($Lambda -le 0) { return 0 }
    if ($Lambda -gt 30) { return [int][math]::Max(0, [math]::Round((Get-DemoNormal $Lambda ([math]::Sqrt($Lambda))))) }
    $limit = [math]::Exp(-$Lambda); $k = 0; $p = 1.0
    do { $k++; $p *= $script:Rng.NextDouble() } while ($p -gt $limit)
    return $k - 1
}
function Get-DemoLogNormal([double]$Median, [double]$Sigma) { $Median * [math]::Exp((Get-DemoNormal 0 $Sigma)) }
# One of $Items, chosen with the matching $Weights.
function Get-DemoPick([object[]]$Items, [double[]]$Weights) {
    $total = ($Weights | Measure-Object -Sum).Sum
    $x = $script:Rng.NextDouble() * $total
    for ($i = 0; $i -lt $Items.Count; $i++) { $x -= $Weights[$i]; if ($x -le 0) { return $Items[$i] } }
    return $Items[-1]
}
# The same GUID for the same key and seed, so ids are stable across runs.
function New-DemoGuid([string]$Key) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try { ([guid]::new($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$Seed|$Key")))).ToString() } finally { $md5.Dispose() }
}
function Get-DemoSum($Items, [string]$Property) { $t = 0.0; foreach ($x in @($Items)) { if ($null -ne $x -and $null -ne $x.$Property) { $t += $x.$Property } }; $t }
function Format-DemoTime([datetime]$Time) { $Time.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
# A time inside the day-ago bucket $Day (0 = the last 24 hours).
function Get-DemoTimeIn([int]$Day) { $asOfUtc.AddDays(-$Day - (Get-DemoBetween 0.05 0.95)) }
function Save-DemoJson([string]$Name, $Data) {
    $json = if ($null -eq $Data) { '[]' }
    elseif ($Data -is [System.Collections.IDictionary] -or $Data -is [System.Management.Automation.PSCustomObject]) { ConvertTo-Json -InputObject $Data -Depth 64 }
    else { ConvertTo-Json -InputObject @($Data) -Depth 64 }
    if ([string]::IsNullOrWhiteSpace($json)) { $json = '[]' }
    Set-Content -LiteralPath (Join-Path $raw $Name) -Value $json -Encoding utf8NoBOM
}
function Read-DemoYaml([string]$Path) { ConvertFrom-Yaml (Get-Content -LiteralPath $Path -Raw) }
function Get-DemoValue($Map, [string]$Key, $Default = $null) {
    if ($null -ne $Map -and $Map -is [System.Collections.IDictionary] -and $Map.Contains($Key) -and $null -ne $Map[$Key]) { return $Map[$Key] }
    return $Default
}
# Minutes in an ISO 8601 duration (PT5M, PT1H, P1D).
function ConvertFrom-DemoDuration([string]$Text) {
    if ($Text -notmatch '^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?$') { return 60 }
    $m = 0
    if ($Matches[1]) { $m += 1440 * [int]$Matches[1] }
    if ($Matches[2]) { $m += 60 * [int]$Matches[2] }
    if ($Matches[3]) { $m += [int]$Matches[3] }
    if ($m -le 0) { 60 } else { $m }
}
$people = @('amara.okafor', 'ben.hughes', 'chloe.martin', 'dev.patel', 'ellie.brooks', 'farid.haddad', 'grace.lee', 'hamish.reid')
function Get-DemoPerson { $p = $people[$script:Rng.Next($people.Count)]; "$p@contoso.com" }
function New-DemoActor([string]$Upn) { [ordered]@{ objectId = (New-DemoGuid "user|$Upn"); email = $Upn; name = (($Upn -split '@')[0] -split '\.' | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) -join ' '; userPrincipalName = $Upn } }

# ---------------------------------------------------------------------------
# Tables: what the estate ingests a day, its plan and its retention
# ---------------------------------------------------------------------------
# Gb is the weekday base before scaling to -DailyGb; We the weekend factor;
# Free marks a table Usage records as not billable. Ret and Total are the
# analytics and total retention in days (Total above Ret keeps data in the
# lake). From is how many days ago a table started, Until when it stopped.
$tableSpec = @(
    @{ T = 'CommonSecurityLog'; Gb = 420; We = 0.9; Sol = 'Security'; Total = 180 }
    @{ T = 'DeviceNetworkEvents'; Gb = 205; We = 0.75; Sol = 'Microsoft365Defender' }
    @{ T = 'DeviceProcessEvents'; Gb = 118; We = 0.7; Sol = 'Microsoft365Defender' }
    @{ T = 'DeviceEvents'; Gb = 82; We = 0.7; Sol = 'Microsoft365Defender' }
    @{ T = 'DeviceFileEvents'; Gb = 58; We = 0.7; Sol = 'Microsoft365Defender' }
    @{ T = 'DeviceImageLoadEvents'; Gb = 34; We = 0.7; Sol = 'Microsoft365Defender' }
    @{ T = 'DeviceRegistryEvents'; Gb = 28; We = 0.7; Sol = 'Microsoft365Defender' }
    @{ T = 'DeviceLogonEvents'; Gb = 13; We = 0.7; Sol = 'Microsoft365Defender' }
    @{ T = 'DeviceNetworkInfo'; Gb = 5; We = 0.95; Sol = 'Microsoft365Defender' }
    @{ T = 'DeviceInfo'; Gb = 2.2; We = 0.95; Sol = 'Microsoft365Defender' }
    @{ T = 'DeviceTvmSoftwareVulnerabilities'; Gb = 1.2; We = 1; Sol = 'Microsoft365Defender' }
    @{ T = 'SecurityEvent'; Gb = 185; We = 0.8; Sol = 'Security'; Total = 365 }
    @{ T = 'Syslog'; Gb = 92; We = 0.9; Sol = 'LogManagement' }
    @{ T = 'Event'; Gb = 13; We = 0.85; Sol = 'LogManagement' }
    @{ T = 'AADNonInteractiveUserSignInLogs'; Gb = 84; We = 0.6; Sol = 'LogManagement' }
    @{ T = 'SigninLogs'; Gb = 15; We = 0.55; Sol = 'LogManagement'; Total = 365 }
    @{ T = 'AADServicePrincipalSignInLogs'; Gb = 7; We = 0.95; Sol = 'LogManagement' }
    @{ T = 'AADManagedIdentitySignInLogs'; Gb = 4; We = 0.95; Sol = 'LogManagement' }
    @{ T = 'AuditLogs'; Gb = 7.5; We = 0.6; Sol = 'LogManagement'; Total = 365 }
    @{ T = 'AADRiskyUsers'; Gb = 0.05; We = 0.8; Sol = 'LogManagement' }
    @{ T = 'AADUserRiskEvents'; Gb = 0.08; We = 0.8; Sol = 'LogManagement' }
    @{ T = 'MicrosoftGraphActivityLogs'; Gb = 36; We = 0.7; Sol = 'LogManagement' }
    @{ T = 'AzureDiagnostics'; Gb = 52; We = 0.9; Sol = 'LogManagement' }
    @{ T = 'AZFWNetworkRule'; Gb = 58; We = 0.85; Sol = 'LogManagement' }
    @{ T = 'AZFWApplicationRule'; Gb = 29; We = 0.85; Sol = 'LogManagement' }
    @{ T = 'AZFWDnsQuery'; Gb = 21; We = 0.85; Sol = 'LogManagement' }
    @{ T = 'AZFWThreatIntel'; Gb = 0.9; We = 0.9; Sol = 'LogManagement' }
    @{ T = 'StorageBlobLogs'; Gb = 19; We = 0.9; Sol = 'LogManagement' }
    @{ T = 'CloudAppEvents'; Gb = 27; We = 0.6; Sol = 'Microsoft365Defender' }
    @{ T = 'EmailEvents'; Gb = 10.5; We = 0.55; Sol = 'Microsoft365Defender' }
    @{ T = 'EmailUrlInfo'; Gb = 3.1; We = 0.55; Sol = 'Microsoft365Defender' }
    @{ T = 'EmailAttachmentInfo'; Gb = 2.2; We = 0.55; Sol = 'Microsoft365Defender' }
    @{ T = 'UrlClickEvents'; Gb = 1.6; We = 0.5; Sol = 'Microsoft365Defender' }
    @{ T = 'EmailPostDeliveryEvents'; Gb = 0.4; We = 0.55; Sol = 'Microsoft365Defender' }
    @{ T = 'IdentityLogonEvents'; Gb = 8.5; We = 0.7; Sol = 'Microsoft365Defender' }
    @{ T = 'IdentityDirectoryEvents'; Gb = 2.6; We = 0.7; Sol = 'Microsoft365Defender' }
    @{ T = 'IdentityQueryEvents'; Gb = 5.5; We = 0.7; Sol = 'Microsoft365Defender' }
    @{ T = 'CopilotActivity'; Gb = 1.1; We = 0.4; Sol = 'Microsoft365Defender' }
    @{ T = 'AWSCloudTrail'; Gb = 31; We = 0.85; Sol = 'SecurityInsights' }
    @{ T = 'AWSGuardDuty'; Gb = 0.3; We = 1; Sol = 'SecurityInsights' }
    @{ T = 'GWorkspaceActivityReports'; Gb = 2.4; We = 0.5; Sol = 'SecurityInsights' }
    @{ T = 'W3CIISLog'; Gb = 6.5; We = 0.8; Sol = 'LogManagement' }
    @{ T = 'Heartbeat'; Gb = 2.8; We = 1; Sol = 'LogManagement' }
    @{ T = 'ThreatIntelIndicators'; Gb = 0.32; We = 1; Sol = 'SecurityInsights' }
    @{ T = 'ThreatIntelObjects'; Gb = 0.05; We = 1; Sol = 'SecurityInsights' }
    @{ T = 'BehaviorAnalytics'; Gb = 4.6; We = 0.6; Sol = 'SecurityInsights' }
    @{ T = 'IdentityInfo'; Gb = 0.7; We = 1; Sol = 'SecurityInsights' }
    @{ T = 'UserPeerAnalytics'; Gb = 0.15; We = 1; Sol = 'SecurityInsights' }
    @{ T = 'LAQueryLogs'; Gb = 0.3; We = 0.5; Sol = 'LogManagement' }
    @{ T = 'SentinelHealth'; Gb = 0.4; We = 1; Sol = 'SecurityInsights' }
    @{ T = 'SophosEvents_CL'; Gb = 4.2; We = 0.8; Sol = 'LogManagement'; Custom = 'DataCollectionRuleBased' }
    @{ T = 'pfsense_logstash_CL'; Gb = 9; We = 0.95; Sol = 'LogManagement'; Custom = 'DataCollectionRuleBased' }
    @{ T = 'DockerFlow_CL'; Gb = 3.2; We = 0.9; Sol = 'LogManagement'; Custom = 'DataCollectionRuleBased' }
    @{ T = 'TailscaleAudit_CL'; Gb = 0.2; We = 0.6; Sol = 'LogManagement'; Custom = 'DataCollectionRuleBased' }
    @{ T = 'RegisteredDomains_CL'; Gb = 0.01; We = 1; Sol = 'LogManagement'; Custom = 'DataCollectionRuleBased' }
    @{ T = 'IISAppLegacy_CL'; Gb = 0.6; We = 0.8; Sol = 'LogManagement'; Custom = 'Classic' }
    @{ T = 'LegacyProxy_CL'; Gb = 6; We = 0.8; Sol = 'LogManagement'; Custom = 'DataCollectionRuleBased'; Until = 21 }
    @{ T = 'ContainerLogV2'; Gb = 24; We = 0.95; Sol = 'LogManagement'; Plan = 'Basic' }
    @{ T = 'ZscalerWebLogs_CL'; Gb = 88; We = 0.6; Sol = 'LogManagement'; Plan = 'Auxiliary'; Custom = 'DataCollectionRuleBased'; Total = 365 }
    @{ T = 'NetFlowRaw_CL'; Gb = 110; We = 0.9; Sol = 'LogManagement'; Plan = 'DataLake'; Custom = 'DataCollectionRuleBased'; Total = 365 }
    @{ T = 'AzureActivity'; Gb = 3.6; We = 0.6; Sol = 'LogManagement'; Free = $true; Total = 365 }
    @{ T = 'OfficeActivity'; Gb = 17; We = 0.5; Sol = 'SecurityInsights'; Free = $true }
    @{ T = 'SecurityAlert'; Gb = 1.3; We = 0.8; Sol = 'SecurityInsights'; Free = $true }
    @{ T = 'SecurityIncident'; Gb = 0.25; We = 0.8; Sol = 'SecurityInsights'; Free = $true }
)

# Per-day GB for each table, newest first ([0] = the last 24 hours).
$series = [ordered]@{}
foreach ($s in $tableSpec) {
    $d = [double[]]::new($L)
    for ($i = 0; $i -lt $L; $i++) {
        if ($s.ContainsKey('Until') -and $i -lt $s.Until) { continue }
        $dow = $asOfUtc.AddDays(-$i - 0.5).DayOfWeek
        $weekend = $dow -eq [DayOfWeek]::Saturday -or $dow -eq [DayOfWeek]::Sunday
        $v = $s.Gb * $(if ($weekend) { $s.We } else { 1.0 })
        # Growth of about 6% across 90 days, and a little noise.
        $v *= 1.0 - 0.06 * $i / 90.0
        $v *= [math]::Max(0.6, (Get-DemoNormal 1.0 0.035))
        # A Syslog source left at debug level for five days.
        if ($s.T -eq 'Syslog' -and $i -ge [math]::Min(34, $L - 6) -and $i -le [math]::Min(38, $L - 2)) { $v *= 2.6 }
        # Defender XDR streaming finished onboarding the last server wave.
        if ($s.T -like 'Device*' -and $i -ge 60) { $v *= 0.86 }
        $d[$i] = $v
    }
    $series[$s.T] = $d
}
# Scale every table so the last 30 days average -DailyGb a day.
$window30 = [math]::Min(30, $L)
$sum30 = 0.0
foreach ($k in $series.Keys) { for ($i = 0; $i -lt $window30; $i++) { $sum30 += $series[$k][$i] } }
$scale = $DailyGb * $window30 / $sum30
foreach ($k in $series.Keys) { for ($i = 0; $i -lt $L; $i++) { $series[$k][$i] = [math]::Round($series[$k][$i] * $scale, 4) } }
$specByTable = @{}; foreach ($s in $tableSpec) { $specByTable[$s.T] = $s }
$hasData = @{}; foreach ($s in $tableSpec) { $hasData[$s.T] = $true }
# At this volume the workspace is on a commitment tier: the rung nearest its
# billable Analytics-plan ingest, as published in commitment-tiers.json.
$analyticsDaily = 0.0
foreach ($s in $tableSpec) {
    if ($s.ContainsKey('Free') -or ($s.ContainsKey('Plan') -and $s.Plan -ne 'Analytics')) { continue }
    for ($i = 0; $i -lt $window30; $i++) { $analyticsDaily += $series[$s.T][$i] }
}
$analyticsDaily /= $window30
$rungs = @((Get-Content -LiteralPath (Join-Path $resources 'commitment-tiers.json') -Raw | ConvertFrom-Json).rungsGbPerDay)
$commitmentGb = if ($analyticsDaily -ge 80) { [int]($rungs | Sort-Object { [math]::Abs($_ - $analyticsDaily) } | Select-Object -First 1) } else { 0 }
function Get-SeriesSum([string]$Table, [int]$Days) { $t = 0.0; $d = $series[$Table]; for ($i = 0; $i -lt [math]::Min($Days, $L); $i++) { $t += $d[$i] }; $t }

$tablesWithData = foreach ($s in $tableSpec) {
    $billable = -not $s.ContainsKey('Free')
    $all = Get-SeriesSum $s.T $L; $rec = Get-SeriesSum $s.T $recentDays
    $first = $asOfUtc.AddDays(-$L).AddMinutes(17)
    $last = if ($s.ContainsKey('Until')) { $asOfUtc.AddDays(-$s.Until).AddHours(-3) } else { $asOfUtc.AddMinutes(-(Get-DemoBetween 2 25)) }
    [ordered]@{
        DataType        = $s.T
        Solution        = $s.Sol
        BillableLast90d = $(if ($billable) { [math]::Round($all, 4) } else { 0.0 })
        IngestedLast90d = [math]::Round($all, 4)
        BillableLast30d = $(if ($billable) { [math]::Round($all, 4) } else { 0.0 })
        BillableLast7d  = $(if ($billable) { [math]::Round($rec, 4) } else { 0.0 })
        IngestedLast7d  = [math]::Round($rec, 4)
        BillableLast24h = $(if ($billable) { [math]::Round($series[$s.T][0], 4) } else { 0.0 })
        FirstSeen       = Format-DemoTime $first
        LastIngested    = Format-DemoTime $last
        DayCount        = $(if ($s.ContainsKey('Until')) { $L - $s.Until } else { $L })
    }
}
Save-DemoJson 'tables-with-data.json' $tablesWithData

$dailyUsage = foreach ($s in $tableSpec) {
    if ($s.ContainsKey('Free')) { continue }
    for ($i = 0; $i -lt $L; $i++) { if ($series[$s.T][$i] -gt 0) { [ordered]@{ DataType = $s.T; DaysAgo = $i; GB = [math]::Round($series[$s.T][$i], 4) } } }
}
Save-DemoJson 'daily-table-usage.json' $dailyUsage

$dayTotal = [double[]]::new($L); $dayBillable = [double[]]::new($L)
foreach ($s in $tableSpec) { for ($i = 0; $i -lt $L; $i++) { $dayTotal[$i] += $series[$s.T][$i]; if (-not $s.ContainsKey('Free')) { $dayBillable[$i] += $series[$s.T][$i] } } }
Save-DemoJson 'workspace-usage.json' @([ordered]@{
        TotalGB             = [math]::Round(($dayTotal | Measure-Object -Sum).Sum, 3)
        BillableTotalGB     = [math]::Round(($dayBillable | Measure-Object -Sum).Sum, 3)
        PeakDailyGB         = [math]::Round(($dayTotal | Measure-Object -Maximum).Maximum, 3)
        BillablePeakDailyGB = [math]::Round(($dayBillable | Measure-Object -Maximum).Maximum, 3)
        BillableAvgDailyGB  = [math]::Round(($dayBillable | Measure-Object -Average).Average, 3)
    })
Save-DemoJson 'workspace-usage-daily.json' @(for ($i = $L - 1; $i -ge 0; $i--) {
        [ordered]@{ Day = $asOfUtc.AddDays(-$i - 0.5).Date.ToString('yyyy-MM-ddT00:00:00Z'); BillableGB = [math]::Round($dayBillable[$i], 3); FreeGB = [math]::Round($dayTotal[$i] - $dayBillable[$i], 3) }
    })

# Table plans, retention and schema. An orphan custom table has a schema
# and no data.
$workspaceTables = foreach ($s in ($tableSpec + @(@{ T = 'OldAppAudit_CL'; Custom = 'DataCollectionRuleBased' }))) {
    $plan = if ($s.ContainsKey('Plan')) { $s.Plan } else { 'Analytics' }
    $ret = switch ($plan) { 'Basic' { 30 } 'Auxiliary' { 30 } 'DataLake' { 30 } default { 90 } }
    $total = if ($s.ContainsKey('Total')) { $s.Total } else { $ret }
    $custom = $s.ContainsKey('Custom')
    [ordered]@{
        properties = [ordered]@{
            totalRetentionInDays          = $total
            archiveRetentionInDays        = $total - $ret
            plan                          = $plan
            retentionInDaysAsDefault      = ($ret -eq 90)
            totalRetentionInDaysAsDefault = ($total -eq $ret)
            schema                        = [ordered]@{ tableSubType = $(if ($custom) { $s.Custom } else { 'Any' }); name = $s.T; tableType = $(if ($custom) { 'CustomLog' } else { 'Microsoft' }); displayName = $s.T; solutions = @() }
            provisioningState             = 'Succeeded'
            retentionInDays               = $ret
        }
        id         = "$wsId/tables/$($s.T)"
        name       = $s.T
    }
}
Save-DemoJson 'workspace-tables.json' $workspaceTables

# ---------------------------------------------------------------------------
# The repository's content
# ---------------------------------------------------------------------------
$operatorMap = @{ gt = 'GreaterThan'; greaterthan = 'GreaterThan'; lt = 'LessThan'; lessthan = 'LessThan'; eq = 'Equal'; equal = 'Equal'; ne = 'NotEqual'; notequal = 'NotEqual' }
$ruleFiles = @(Get-ChildItem -LiteralPath (Join-Path $content 'AnalyticalRules') -Recurse -Filter '*.yaml' | Sort-Object FullName)
$customYaml = [System.Collections.Generic.List[object]]::new()
$communityYaml = [System.Collections.Generic.List[object]]::new()
foreach ($f in $ruleFiles) {
    $y = Read-DemoYaml $f.FullName
    if (-not $y -or -not $y['id'] -or -not $y['query']) { continue }
    $entry = [pscustomobject]@{ Yaml = $y; File = $f; Folder = $f.Directory.Name; Tables = @(Resolve-KqlTableNames -Query ([string]$y['query'])) }
    if ($f.FullName -match '[/\\]Community[/\\]') { $communityYaml.Add($entry) } else { $customYaml.Add($entry) }
}
# A rule can fire when it reads a table the estate ingests.
function Test-DemoReadable([string[]]$Tables) { foreach ($t in $Tables) { if ($hasData.ContainsKey($t)) { return $true } }; return $false }

function New-DemoRuleProperties($Y, [bool]$Enabled, [string]$Template, [string]$TemplateVersion) {
    $kind = [string](Get-DemoValue $Y 'kind' 'Scheduled')
    $p = [ordered]@{
        displayName         = [string]$Y['name']
        description         = ([string](Get-DemoValue $Y 'description' '')).Trim().Trim("'")
        severity            = [string](Get-DemoValue $Y 'severity' 'Medium')
        enabled             = $Enabled
        query               = [string]$Y['query']
        suppressionDuration = [string](Get-DemoValue $Y 'suppressionDuration' 'PT5H')
        suppressionEnabled  = [bool](Get-DemoValue $Y 'suppressionEnabled' $false)
    }
    if ($kind -eq 'Scheduled') {
        $p.queryFrequency = [string](Get-DemoValue $Y 'queryFrequency' 'PT1H')
        $p.queryPeriod = [string](Get-DemoValue $Y 'queryPeriod' 'PT1H')
        $op = ([string](Get-DemoValue $Y 'triggerOperator' 'gt')).ToLowerInvariant()
        $p.triggerOperator = if ($operatorMap.ContainsKey($op)) { $operatorMap[$op] } else { 'GreaterThan' }
        $p.triggerThreshold = [int](Get-DemoValue $Y 'triggerThreshold' 0)
    }
    $p.tactics = @(Get-DemoValue $Y 'tactics' @())
    $techs = @(Get-DemoValue $Y 'relevantTechniques' (Get-DemoValue $Y 'techniques' @()))
    $p.techniques = @($techs | ForEach-Object { ($_ -split '\.')[0] } | Select-Object -Unique)
    $p.subTechniques = @($techs | Where-Object { $_ -match '\.' } | Select-Object -Unique)
    foreach ($k in 'entityMappings', 'customDetails', 'alertDetailsOverride', 'eventGroupingSettings') { if ($Y.ContainsKey($k) -and $Y[$k]) { $p[$k] = $Y[$k] } }
    $inc = Get-DemoValue $Y 'incidentConfiguration' $null
    $p.incidentConfiguration = if ($inc) { $inc } else { [ordered]@{ createIncident = $true; groupingConfiguration = [ordered]@{ enabled = $true; reopenClosedIncident = $false; lookbackDuration = 'PT5H'; matchingMethod = 'AllEntities' } } }
    if ($Template) { $p.alertRuleTemplateName = $Template; $p.templateVersion = $TemplateVersion }
    $p.lastModifiedUtc = Format-DemoTime ($asOfUtc.AddDays(-(Get-DemoBetween 3 400)))
    return $p
}

# Deployed rules: every repository rule as the deploy script deploys it, and
# a share of the Community rules deployed from their Content Hub template
# where the estate has their data. The rest stay templates.
$alertRules = [System.Collections.Generic.List[object]]::new()
$ruleModels = [System.Collections.Generic.List[object]]::new()
foreach ($e in $customYaml) {
    $id = ([string]$e.Yaml['id']).ToLowerInvariant()
    $enabled = [bool](Get-DemoValue $e.Yaml 'enabled' $true)
    $kind = [string](Get-DemoValue $e.Yaml 'kind' 'Scheduled')
    $alertRules.Add([ordered]@{ id = "$siId/alertRules/$id"; name = $id; etag = '"' + (New-DemoGuid "etag|$id") + '"'; type = 'Microsoft.SecurityInsights/alertRules'; kind = $kind; properties = (New-DemoRuleProperties $e.Yaml $enabled $null $null) })
    $ruleModels.Add([pscustomobject]@{ Id = $id; Name = [string]$e.Yaml['name']; Kind = $kind; Severity = [string](Get-DemoValue $e.Yaml 'severity' 'Medium'); Enabled = $enabled; Tables = $e.Tables; Frequency = (ConvertFrom-DemoDuration ([string](Get-DemoValue $e.Yaml 'queryFrequency' 'PT1H'))) })
}
$templateDeployed = @{}
foreach ($e in $communityYaml) {
    if (-not (Test-DemoReadable $e.Tables) -or (Get-DemoRandom) -gt 0.5) { continue }
    $tid = ([string]$e.Yaml['id']).ToLowerInvariant()
    $id = New-DemoGuid "from-template|$tid"
    $version = [string](Get-DemoValue $e.Yaml 'version' '1.0.0')
    $alertRules.Add([ordered]@{ id = "$siId/alertRules/$id"; name = $id; etag = '"' + (New-DemoGuid "etag|$id") + '"'; type = 'Microsoft.SecurityInsights/alertRules'; kind = 'Scheduled'; properties = (New-DemoRuleProperties $e.Yaml $true $tid $version) })
    $ruleModels.Add([pscustomobject]@{ Id = $id; Name = [string]$e.Yaml['name']; Kind = 'Scheduled'; Severity = [string](Get-DemoValue $e.Yaml 'severity' 'Medium'); Enabled = $true; Tables = $e.Tables; Frequency = (ConvertFrom-DemoDuration ([string](Get-DemoValue $e.Yaml 'queryFrequency' 'PT1H'))) })
    $templateDeployed[$tid] = $true
}
# Built-in analytics.
foreach ($b in @(@{ Kind = 'Fusion'; Name = 'Advanced Multistage Attack Detection'; Sev = 'High'; Tmpl = 'f71aba3d-28fb-450b-b192-4e76a83015c8' },
        @{ Kind = 'ThreatIntelligence'; Name = 'Microsoft Threat Intelligence Analytics'; Sev = 'Medium'; Tmpl = '40ba9493-4183-4eee-974f-87fe39c8f267' })) {
    $id = New-DemoGuid "builtin|$($b.Kind)"
    $alertRules.Add([ordered]@{ id = "$siId/alertRules/$id"; name = $id; etag = '"' + (New-DemoGuid "etag|$id") + '"'; type = 'Microsoft.SecurityInsights/alertRules'; kind = $b.Kind
            properties = [ordered]@{ displayName = $b.Name; description = ''; alertRuleTemplateName = $b.Tmpl; tactics = @(); severity = $b.Sev; techniques = @(); subTechniques = @(); enabled = $true; lastModifiedUtc = (Format-DemoTime $asOfUtc.AddDays(-210)) } })
}
Save-DemoJson 'alert-rules.json' $alertRules

# The Community rules as Content Hub templates, grouped into solutions by the
# data they read.
function Get-DemoSolutionFor([string[]]$Tables) {
    foreach ($t in $Tables) {
        switch -regex ($t) {
            '^CommonSecurityLog$' { return 'Common Event Format' }
            '^(SigninLogs|AAD|AuditLogs)' { return 'Microsoft Entra ID' }
            '^AzureActivity$' { return 'Azure Activity' }
            '^OfficeActivity$' { return 'Microsoft 365' }
            '^SecurityEvent$' { return 'Windows Security Events' }
            '^ThreatIntel' { return 'Threat Intelligence' }
            '^(SecurityAlert|Device)' { return 'Microsoft Defender XDR' }
            '^IdentityInfo$' { return 'UEBA Essentials' }
            '^StorageBlobLogs$' { return 'Azure Storage' }
        }
    }
    return 'Sentinel SOC Essentials'
}
$templates = [System.Collections.Generic.List[object]]::new()
$solutionTemplates = [ordered]@{}
foreach ($e in $communityYaml) {
    $y = $e.Yaml; $tid = ([string]$y['id']).ToLowerInvariant()
    $techs = @(Get-DemoValue $y 'relevantTechniques' (Get-DemoValue $y 'techniques' @()))
    $created = $asOfUtc.AddDays(-(Get-DemoBetween 200 1400))
    $templates.Add([ordered]@{
            id = "$siId/alertRuleTemplates/$tid"; name = $tid; type = 'Microsoft.SecurityInsights/alertRuleTemplates'; kind = 'Scheduled'
            properties = [ordered]@{
                queryFrequency = [string](Get-DemoValue $y 'queryFrequency' 'PT1H'); queryPeriod = [string](Get-DemoValue $y 'queryPeriod' 'PT1H')
                triggerOperator = 'GreaterThan'; triggerThreshold = [int](Get-DemoValue $y 'triggerThreshold' 0)
                severity = [string](Get-DemoValue $y 'severity' 'Medium'); query = [string]$y['query']
                entityMappings = @(Get-DemoValue $y 'entityMappings' @()); version = [string](Get-DemoValue $y 'version' '1.0.0')
                tactics = @(Get-DemoValue $y 'tactics' @()); techniques = @($techs | ForEach-Object { ($_ -split '\.')[0] } | Select-Object -Unique)
                displayName = [string]$y['name']; description = ([string](Get-DemoValue $y 'description' '')).Trim().Trim("'")
                lastUpdatedDateUTC = (Format-DemoTime $created.AddDays(120)); createdDateUTC = (Format-DemoTime $created); status = 'Available'
                requiredDataConnectors = @(Get-DemoValue $y 'requiredDataConnectors' @())
                alertRulesCreatedByTemplateCount = $(if ($templateDeployed.ContainsKey($tid)) { 1 } else { 0 })
            }
        })
    $sol = Get-DemoSolutionFor $e.Tables
    if (-not $solutionTemplates.Contains($sol)) { $solutionTemplates[$sol] = [System.Collections.Generic.List[object]]::new() }
    $solutionTemplates[$sol].Add([ordered]@{ contentId = $tid; kind = 'AnalyticsRule'; version = [string](Get-DemoValue $y 'version' '1.0.0') })
}
Save-DemoJson 'alert-rule-templates.json' $templates
# Every solution is installed except Azure Storage, so its template reads
# as one whose solution is not installed.
$catalogue = [System.Collections.Generic.List[object]]::new(); $installed = [System.Collections.Generic.List[object]]::new()
foreach ($sol in $solutionTemplates.Keys) {
    $sid = ($sol.ToLowerInvariant() -replace '[^a-z0-9]+', '')
    $pkg = [ordered]@{ contentId = $sid; contentKind = 'Solution'; contentProductId = "$sid-sl"; isNew = $false; isPreview = $false; isFeatured = $false; isDeprecated = $false; version = '3.0.2'; displayName = $sol
        source = [ordered]@{ kind = 'Solution'; name = $sol; sourceId = $sid }; author = [ordered]@{ name = 'Microsoft' }; support = [ordered]@{ tier = 'Microsoft'; name = 'Microsoft Corporation'; link = 'https://support.microsoft.com' }
        dependencies = [ordered]@{ operator = 'AND'; criteria = @($solutionTemplates[$sol]) }; providers = @('Microsoft'); firstPublishDate = '2022-05-16'; lastPublishDate = (Format-DemoTime $asOfUtc.AddDays(-40)); categories = [ordered]@{ domains = @('Security - Threat Protection') } }
    $catalogue.Add([ordered]@{ id = "$siId/contentProductPackages/$sid-sl"; name = "$sid-sl"; type = 'Microsoft.SecurityInsights/contentProductPackages'; properties = $pkg })
    if ($sol -ne 'Azure Storage') {
        $inst = [ordered]@{ contentKind = 'Solution'; contentProductId = "$sid-sl"; contentId = $sid; displayName = $sol; version = $(if ($sol -eq 'Microsoft Entra ID') { '3.0.0' } else { '3.0.2' }); source = $pkg.source; author = $pkg.author; support = $pkg.support; dependencies = $pkg.dependencies; providers = $pkg.providers; firstPublishDate = $pkg.firstPublishDate; categories = $pkg.categories }
        $installed.Add([ordered]@{ id = "$siId/contentPackages/$sid"; name = $sid; type = 'Microsoft.SecurityInsights/contentPackages'; properties = $inst })
    }
}
Save-DemoJson 'content-product-packages.json' $catalogue
Save-DemoJson 'content-packages.json' $installed

# Hunting queries, and the saved searches they sit among.
$hunting = foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $content 'HuntingQueries') -Recurse -Filter '*.yaml' | Sort-Object FullName)) {
    $y = Read-DemoYaml $f.FullName
    if (-not $y -or -not $y['query']) { continue }
    $id = New-DemoGuid "hunt|$($y['id'])"
    [ordered]@{
        properties = [ordered]@{ category = 'Hunting Queries'; displayName = [string]$y['name']; version = 2; query = [string]$y['query']
            tags = @([ordered]@{ name = 'description'; value = ([string](Get-DemoValue $y 'description' '')).Trim() }, [ordered]@{ name = 'tactics'; value = (@(Get-DemoValue $y 'tactics' @()) -join ',') }, [ordered]@{ name = 'techniques'; value = (@(Get-DemoValue $y 'techniques' (Get-DemoValue $y 'relevantTechniques' @())) -join ',') }) }
        id = "$wsId/savedSearches/$id"; name = $id; type = 'Microsoft.OperationalInsights/workspaces/savedSearches'; etag = "W/`"datetime'$(Format-DemoTime $asOfUtc.AddDays(-30))'`""
    }
}
Save-DemoJson 'hunting-queries.json' $hunting
$parsers = foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $content 'Parsers') -Recurse -Filter '*.yaml')) {
    $y = Read-DemoYaml $f.FullName
    $alias = [string](Get-DemoValue $y 'functionAlias' $y['id'])
    [ordered]@{ properties = [ordered]@{ category = [string](Get-DemoValue $y 'category' 'Security'); displayName = [string]$y['name']; version = 2; functionAlias = $alias; query = [string]$y['query'] }
        id = "$wsId/savedSearches/$alias"; name = $alias; type = 'Microsoft.OperationalInsights/workspaces/savedSearches'; etag = "W/`"datetime'$(Format-DemoTime $asOfUtc.AddDays(-60))'`"" }
}
Save-DemoJson 'parsers-functions.json' $parsers
Save-DemoJson 'kql-savedsearches.json' (@($hunting) + @($parsers))

# Watchlists, one a quarter stale.
$watchlists = foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $content 'Watchlists') -Recurse -Filter 'watchlist.json' | Sort-Object FullName)) {
    $w = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
    $alias = [string]$w.watchlistAlias
    $created = $asOfUtc.AddDays(-(Get-DemoBetween 120 700))
    $updated = if ((Get-DemoRandom) -lt 0.25) { $asOfUtc.AddDays(-(Get-DemoBetween 120 300)) } else { $asOfUtc.AddDays(-(Get-DemoBetween 0.2 25)) }
    $actor = New-DemoActor (Get-DemoPerson)
    [ordered]@{ id = "$siId/watchlists/$alias"; name = $alias; etag = '"' + (New-DemoGuid "etag|wl|$alias") + '"'; type = 'Microsoft.SecurityInsights/Watchlists'
        properties = [ordered]@{ watchlistId = (New-DemoGuid "wl|$alias"); displayName = [string]$w.displayName; provider = [string]$w.provider; source = 'data.csv'; itemsSearchKey = [string]$w.itemsSearchKey
            created = (Format-DemoTime $created); updated = (Format-DemoTime $updated); createdBy = $actor; updatedBy = $actor; description = [string]$w.description; watchlistType = 'watchlist'
            watchlistAlias = $alias; isDeleted = $false; labels = @(); tenantId = $tenantId; numberOfLinesToSkip = 0; provisioningState = 'Succeeded'; sasUri = ''; watchlistCategory = ''; watchlistKind = '' } }
}
Save-DemoJson 'watchlists.json' $watchlists

# Workbooks saved in the workspace, and a few Content Hub workbook templates.
$workbooks = foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $content 'Workbooks') -Recurse -Filter 'metadata.json' | Sort-Object FullName)) {
    $m = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
    $wid = if ($m.PSObject.Properties['workbookId'] -and $m.workbookId) { [string]$m.workbookId } else { New-DemoGuid "wb|$($f.Directory.Name)" }
    $who = Get-DemoPerson
    [ordered]@{ identity = [ordered]@{ type = 'None' }; kind = 'shared'; etag = '"' + (New-DemoGuid "etag|wb|$wid") + '"'; id = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/microsoft.insights/workbooks/$wid"; name = $wid; type = 'microsoft.insights/workbooks'; location = $region
        tags = [ordered]@{ 'hidden-title' = [string]$m.displayName; CreatorUPN = $who; 'Created By' = $who; CreatedDate = (Format-DemoTime $asOfUtc.AddDays(-200)) }
        properties = [ordered]@{ displayName = [string]$m.displayName; serializedData = $null; version = '1.0'; category = 'sentinel'; userId = (New-DemoGuid "user|$who"); sourceId = $wsId.ToLowerInvariant(); timeModified = (Format-DemoTime $asOfUtc.AddDays(-(Get-DemoBetween 1 180))); tags = $null; storageUri = $null; revision = (New-DemoGuid "rev|$wid").Replace('-', '') } }
}
Save-DemoJson 'workbooks-saved.json' $workbooks
$workbookTemplates = foreach ($n in @('Microsoft Entra ID Sign-in logs', 'Microsoft Entra ID Audit logs', 'Azure Activity', 'Common Event Format (CEF) overview', 'Windows Security Events', 'Microsoft Defender XDR', 'Threat Intelligence', 'Workspace Usage Report', 'SOC Process Framework', 'Data collection health monitoring')) {
    $cid = ($n.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    [ordered]@{ id = "$siId/contentTemplates/$cid"; name = $cid; type = 'Microsoft.SecurityInsights/contentTemplates'; systemData = [ordered]@{}
        properties = [ordered]@{ packageKind = 'Solution'; packageId = 'sentinelsocessentials'; packageVersion = '3.0.2'; contentSchemaVersion = '3.0.0'; contentProductId = "$cid-wb"; contentId = $cid; displayName = $n; contentKind = 'Workbook'; version = '2.1.0'; source = [ordered]@{ kind = 'Solution'; name = 'Sentinel SOC Essentials'; sourceId = 'sentinelsocessentials' } } }
}
Save-DemoJson 'workbook-templates.json' $workbookTemplates

# Playbooks: each Logic App the repository ships, with its trigger.
$playbooks = [System.Collections.Generic.List[object]]::new(); $playbookModels = [System.Collections.Generic.List[object]]::new()
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $content 'Playbooks') -Recurse -Filter '*.json' | Sort-Object FullName)) {
    $doc = try { Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -Depth 64 } catch { $null }
    if (-not $doc -or -not $doc.PSObject.Properties['resources']) { continue }
    $wf = @($doc.resources | Where-Object { $_ -and $_.PSObject.Properties['type'] -and $_.type -eq 'Microsoft.Logic/workflows' }) | Select-Object -First 1
    if (-not $wf -or -not $wf.properties.definition) { continue }
    $name = $f.BaseName
    if ($name -like '*Template*') { continue }
    # Two folders can ship a playbook of the same name; a resource group cannot hold both.
    if (@($playbookModels | Where-Object Name -eq $name).Count) { $name = "$name-$($f.Directory.Name)" }
    $triggerKey = @($wf.properties.definition.triggers.PSObject.Properties | ForEach-Object { $_.Name }) | Select-Object -First 1
    $trigger = switch -regex ("$triggerKey") { 'Sentinel_incident' { 'Incident' } 'Sentinel_alert' { 'Alert' } 'Sentinel_entity' { 'Entity' } 'Recurrence' { 'Recurrence' } default { 'Other' } }
    $hasIdentity = [bool]($wf.PSObject.Properties['identity'] -and $wf.identity)
    $miId = New-DemoGuid "mi|$name"
    $created = $asOfUtc.AddDays(-(Get-DemoBetween 60 500))
    $state = if ($name -match 'Legacy|Old') { 'Disabled' } else { 'Enabled' }
    $who = Get-DemoPerson
    $playbooks.Add([ordered]@{
            properties = [ordered]@{ provisioningState = 'Succeeded'; createdTime = (Format-DemoTime $created); changedTime = (Format-DemoTime $created.AddDays((Get-DemoBetween 1 50))); state = $state; version = (New-DemoGuid "ver|$name").Replace('-', '').Substring(0, 20).ToUpperInvariant()
                accessEndpoint = "https://prod-12.$region.logic.azure.com:443/workflows/$((New-DemoGuid "wf|$name").Replace('-', ''))"; definition = $wf.properties.definition; parameters = [ordered]@{} }
            id = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$name"; name = $name; type = 'Microsoft.Logic/workflows'; location = $region
            tags = [ordered]@{ 'Created By' = $who; CreatedDate = (Format-DemoTime $created); CreatorUPN = $who }
            identity = $(if ($hasIdentity) { [ordered]@{ type = 'SystemAssigned'; principalId = $miId; tenantId = $tenantId } } else { $null })
        })
    $playbookModels.Add([pscustomobject]@{ Name = $name; Trigger = $trigger; State = $state; Identity = $hasIdentity; PrincipalId = $miId; Id = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$name" })
}
Save-DemoJson 'playbooks.json' $playbooks
$incidentPlaybooks = @($playbookModels | Where-Object { $_.Trigger -eq 'Incident' -and $_.State -eq 'Enabled' })

# Automation rules: the repository's, and the ones that run its incident
# playbooks.
$automation = [System.Collections.Generic.List[object]]::new()
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $content 'AutomationRules') -Filter '*.json' | Sort-Object Name)) {
    $a = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -Depth 32
    $automation.Add([pscustomobject]@{ Id = [string]$a.automationRuleId; DisplayName = [string]$a.displayName; Order = [int]$a.order; Logic = $a.triggeringLogic; Actions = @($a.actions) })
}
# Each runs the first of its playbooks the repository has, else any
# incident playbook.
$runRules = @(
    @{ Name = 'Enrich new incidents with IP reputation'; Order = 5; Sev = @('High', 'Medium'); Want = @('IPEnrichment', 'EnrichIPInfo', 'VTIPEnrichment') }
    @{ Name = 'Notify the SOC channel on high severity'; Order = 6; Sev = @('High'); Want = @('TeamsNotification', 'SendBasicEmail') }
    @{ Name = 'Add vulnerability context to device incidents'; Order = 10; Sev = @('High', 'Medium', 'Low'); Want = @('VulnerabilityEnrichment', 'GetDeviceTags') }
)
foreach ($r in $runRules) {
    if ($incidentPlaybooks.Count -eq 0) { break }
    $pb = $null
    foreach ($w in $r.Want) { $pb = $incidentPlaybooks | Where-Object Name -eq $w | Select-Object -First 1; if ($pb) { break } }
    if (-not $pb) { $pb = $incidentPlaybooks[$r.Order % $incidentPlaybooks.Count] }
    $automation.Add([pscustomobject]@{ Id = (New-DemoGuid "ar|$($r.Name)"); DisplayName = $r.Name; Order = $r.Order
            Logic = [ordered]@{ isEnabled = $true; triggersOn = 'Incidents'; triggersWhen = 'Created'; conditions = @([ordered]@{ conditionType = 'Property'; conditionProperties = [ordered]@{ propertyName = 'IncidentSeverity'; operator = 'Equals'; propertyValues = $r.Sev } }) }
            Actions = @([ordered]@{ order = 1; actionType = 'RunPlaybook'; actionConfiguration = [ordered]@{ logicAppResourceId = $pb.Id; tenantId = $tenantId } }); Playbook = $pb.Name; Severities = $r.Sev })
}
Save-DemoJson 'automation-rules.json' @(foreach ($a in $automation) {
        $who = New-DemoActor (Get-DemoPerson)
        [ordered]@{ id = "$siId/automationRules/$($a.Id)"; name = $a.Id; etag = '"' + (New-DemoGuid "etag|ar|$($a.Id)") + '"'; type = 'Microsoft.SecurityInsights/AutomationRules'
            properties = [ordered]@{ displayName = $a.DisplayName; order = $a.Order; triggeringLogic = $a.Logic; actions = $a.Actions; lastModifiedTimeUtc = (Format-DemoTime $asOfUtc.AddDays(-(Get-DemoBetween 5 120))); createdTimeUtc = (Format-DemoTime $asOfUtc.AddDays(-(Get-DemoBetween 130 400))); lastModifiedBy = $who; createdBy = $who } }
    })

Save-DemoJson 'summary-rules.json' @(foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $content 'SummaryRules') -Filter '*.json' | Sort-Object Name)) {
        $s = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        [ordered]@{ properties = [ordered]@{ ruleType = 'User'; displayName = [string]$s.displayName; description = [string]$s.description
                ruleDefinition = [ordered]@{ query = [string]$s.query; binSize = [int]$s.binSize; binDelay = $(if ($s.PSObject.Properties['binDelay']) { [int]$s.binDelay } else { 10 }); timeSelector = 'TimeGenerated'; destinationTable = [string]$s.destinationTable }
                isActive = $true; statusCode = 'UserAction'; provisioningState = 'Succeeded' }
            systemData = [ordered]@{ createdBy = (Get-DemoPerson); createdAt = (Format-DemoTime $asOfUtc.AddDays(-90)); lastModifiedAt = (Format-DemoTime $asOfUtc.AddDays(-12)) }
            id = "$wsId/summaryLogs/$($s.name)"; name = [string]$s.name }
    })

# Defender XDR custom detections, in the Graph detectionRule shape.
$detections = [System.Collections.Generic.List[object]]::new(); $n = 1000
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $content 'DefenderCustomDetections') -Recurse -Filter '*.yaml' | Sort-Object FullName)) {
    $y = Read-DemoYaml $f.FullName
    if (-not $y -or -not $y['queryCondition']) { continue }
    $n++
    $at = Get-DemoValue $y['detectionAction'] 'alertTemplate' @{}
    $modified = $asOfUtc.AddDays(-(Get-DemoBetween 2 160))
    $detections.Add([ordered]@{ id = "$n"; displayName = [string]$y['displayName']; isEnabled = [bool](Get-DemoValue $y 'isEnabled' $true); createdBy = 'secops@contoso.com'; createdDateTime = (Format-DemoTime $modified.AddDays(-30)); lastModifiedBy = 'secops@contoso.com'; lastModifiedDateTime = (Format-DemoTime $modified)
            schedule = [ordered]@{ period = [string](Get-DemoValue $y['schedule'] 'period' '1H'); nextRunDateTime = (Format-DemoTime $asOfUtc.AddMinutes(37)) }
            queryCondition = [ordered]@{ queryText = [string]$y['queryCondition']['queryText']; lastModifiedDateTime = (Format-DemoTime $modified) }
            detectionAction = [ordered]@{ alertTemplate = [ordered]@{ title = [string](Get-DemoValue $at 'title' $y['displayName']); description = [string](Get-DemoValue $at 'description' ''); severity = [string](Get-DemoValue $at 'severity' 'medium'); category = [string](Get-DemoValue $at 'category' ''); mitreTechniques = @(Get-DemoValue $at 'mitreTechniques' @()); recommendedActions = [string](Get-DemoValue $at 'recommendedActions' ''); impactedAssets = @() }; organizationalScope = $null; responseActions = @() }
            lastRunDetails = [ordered]@{ lastRunDateTime = (Format-DemoTime $asOfUtc.AddMinutes(-23)); status = 'completed'; failureReason = $null; errorCode = $null } })
}
Save-DemoJson 'defender-custom-detections.json' $detections

# ---------------------------------------------------------------------------
# Connectors, collection rules and endpoints
# ---------------------------------------------------------------------------
$classic = @(
    @{ Kind = 'MicrosoftThreatProtection'; Types = [ordered]@{ incidents = [ordered]@{ state = 'enabled' } } }
    @{ Kind = 'Office365'; Types = [ordered]@{ exchange = [ordered]@{ state = 'enabled' }; sharePoint = [ordered]@{ state = 'enabled' }; teams = [ordered]@{ state = 'enabled' } } }
    @{ Kind = 'AzureActiveDirectory'; Types = [ordered]@{ alerts = [ordered]@{ state = 'enabled' } } }
    @{ Kind = 'MicrosoftDefenderAdvancedThreatProtection'; Types = [ordered]@{ alerts = [ordered]@{ state = 'enabled' } } }
    @{ Kind = 'AzureAdvancedThreatProtection'; Types = [ordered]@{ alerts = [ordered]@{ state = 'enabled' } } }
    @{ Kind = 'MicrosoftCloudAppSecurity'; Types = [ordered]@{ alerts = [ordered]@{ state = 'enabled' }; discoveryLogs = [ordered]@{ state = 'disabled' } } }
    @{ Kind = 'OfficeATP'; Types = [ordered]@{ alerts = [ordered]@{ state = 'enabled' } } }
    @{ Kind = 'AzureSecurityCenter'; Types = [ordered]@{ alerts = [ordered]@{ state = 'enabled' } } }
    @{ Kind = 'MicrosoftThreatIntelligence'; Types = [ordered]@{ microsoftEmergingThreatFeed = [ordered]@{ state = 'enabled'; lookbackPeriod = '1970-01-01T00:00:00.000Z' } } }
    @{ Kind = 'AmazonWebServicesS3'; Types = [ordered]@{ logs = [ordered]@{ state = 'enabled' } } }
)
Save-DemoJson 'data-connectors-classic.json' @(foreach ($c in $classic) {
        $id = New-DemoGuid "dc|$($c.Kind)"
        [ordered]@{ id = "$siId/dataConnectors/$id"; name = $id; etag = '"' + (New-DemoGuid "etag|dc|$id") + '"'; type = 'Microsoft.SecurityInsights/dataConnectors'; kind = $c.Kind; properties = [ordered]@{ tenantId = $tenantId; subscriptionId = $subscriptionId; dataTypes = $c.Types } }
    })
$ccf = [System.Collections.Generic.List[object]]::new()
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $content 'CodelessConnectors') -Recurse -Filter '*ConnectorDefinition.json')) {
    $d = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -Depth 64
    $first = @($d)[0]
    $ui = if ($first.PSObject.Properties['properties'] -and $first.properties.PSObject.Properties['connectorUiConfig']) { $first.properties.connectorUiConfig } else { $null }
    $name = if ($ui -and $ui.PSObject.Properties['id']) { [string]$ui.id } else { $f.Directory.Name }
    $ccf.Add([ordered]@{ id = "$siId/dataConnectorDefinitions/$name"; name = $name; etag = '"' + (New-DemoGuid "etag|ccf|$name") + '"'; type = 'Microsoft.SecurityInsights/dataConnectorDefinitions'; kind = 'Customizable'
            properties = [ordered]@{ connectorUiConfig = $ui; createdTimeUtc = (Format-DemoTime $asOfUtc.AddDays(-150)); lastModifiedUtc = (Format-DemoTime $asOfUtc.AddDays(-20)) } })
}
foreach ($c in @(@{ Id = 'GoogleWorkspaceCCPDefinition'; Title = 'Google Workspace Activities (via Codeless Connector Framework)' }, @{ Id = 'TailscaleAuditCCPDefinition'; Title = 'Tailscale audit logs (via Codeless Connector Framework)' })) {
    $ccf.Add([ordered]@{ id = "$siId/dataConnectorDefinitions/$($c.Id)"; name = $c.Id; etag = '"' + (New-DemoGuid "etag|ccf|$($c.Id)") + '"'; type = 'Microsoft.SecurityInsights/dataConnectorDefinitions'; kind = 'Customizable'
            properties = [ordered]@{ connectorUiConfig = [ordered]@{ id = $c.Id; title = $c.Title; publisher = 'Microsoft'; descriptionMarkdown = ('Ingests ' + ($c.Title -replace ' \(.*$', '') + ' into Microsoft Sentinel.') }; createdTimeUtc = (Format-DemoTime $asOfUtc.AddDays(-150)); lastModifiedUtc = (Format-DemoTime $asOfUtc.AddDays(-20)) } })
}
Save-DemoJson 'data-connector-definitions.json' $ccf

$dce = @('dce-contoso-uks-01', 'dce-contoso-uks-02')
Save-DemoJson 'dces.json' @(foreach ($d in $dce) {
        [ordered]@{ properties = [ordered]@{ immutableId = "dce-$((New-DemoGuid $d).Replace('-',''))"; configurationAccess = [ordered]@{ endpoint = "https://$d-abcd.$region-1.handler.control.monitor.azure.com" }; logsIngestion = [ordered]@{ endpoint = "https://$d-abcd.$region-1.ingest.monitor.azure.com" }; networkAcls = [ordered]@{ publicNetworkAccess = 'Disabled' }; provisioningState = 'Succeeded' }
            location = $region; id = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Insights/dataCollectionEndpoints/$d"; name = $d; type = 'Microsoft.Insights/dataCollectionEndpoints'; etag = '"' + (New-DemoGuid "etag|$d") + '"' }
    })
$dcrSpec = @(
    @{ Name = 'dcr-ama-windows-security'; Kind = 'Windows'; Stream = 'Microsoft-SecurityEvent'; Out = 'Microsoft-SecurityEvent'; Kql = 'source | where EventID !in (5156, 5158)' }
    @{ Name = 'dcr-ama-windows-events'; Kind = 'Windows'; Stream = 'Microsoft-Event'; Out = 'Microsoft-Event'; Kql = 'source' }
    @{ Name = 'dcr-ama-linux-syslog'; Kind = 'Linux'; Stream = 'Microsoft-Syslog'; Out = 'Microsoft-Syslog'; Kql = 'source | where SeverityLevel != "debug"' }
    @{ Name = 'dcr-ama-cef-forwarders'; Kind = 'Linux'; Stream = 'Microsoft-CommonSecurityLog'; Out = 'Microsoft-CommonSecurityLog'; Kql = 'source' }
    @{ Name = 'dcr-ama-iis'; Kind = 'Windows'; Stream = 'Microsoft-W3CIISLog'; Out = 'Microsoft-W3CIISLog'; Kql = 'source' }
    @{ Name = 'dcr-sophos-ccf'; Kind = ''; Stream = 'Custom-SophosEvents'; Out = 'Custom-SophosEvents_CL'; Kql = 'source | extend TimeGenerated = todatetime(created_at)' }
    @{ Name = 'dcr-pfsense-logstash'; Kind = ''; Stream = 'Custom-pfsense'; Out = 'Custom-pfsense_logstash_CL'; Kql = 'source' }
    @{ Name = 'dcr-docker-flow'; Kind = ''; Stream = 'Custom-DockerFlow'; Out = 'Custom-DockerFlow_CL'; Kql = 'source' }
    @{ Name = 'dcr-tailscale-ccf'; Kind = ''; Stream = 'Custom-TailscaleAudit'; Out = 'Custom-TailscaleAudit_CL'; Kql = 'source' }
    @{ Name = 'dcr-registered-domains'; Kind = ''; Stream = 'Custom-RegisteredDomains'; Out = 'Custom-RegisteredDomains_CL'; Kql = 'source' }
    @{ Name = 'dcr-zscaler-aux'; Kind = ''; Stream = 'Custom-ZscalerWeb'; Out = 'Custom-ZscalerWebLogs_CL'; Kql = 'source' }
    @{ Name = 'dcr-netflow-lake'; Kind = ''; Stream = 'Custom-NetFlow'; Out = 'Custom-NetFlowRaw_CL'; Kql = 'source' }
    @{ Name = 'dcr-workspace-transform'; Kind = 'WorkspaceTransforms'; Stream = 'Microsoft-Table-AADNonInteractiveUserSignInLogs'; Out = 'Microsoft-AADNonInteractiveUserSignInLogs'; Kql = 'source | where ResultType != "50126" or Category != ""' }
)
Save-DemoJson 'dcrs.json' @(foreach ($d in $dcrSpec) {
        $who = Get-DemoPerson
        [ordered]@{ properties = [ordered]@{ immutableId = "dcr-$((New-DemoGuid $d.Name).Replace('-',''))"; dataCollectionEndpointId = $(if ($d.Kind -eq '' ) { "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Insights/dataCollectionEndpoints/$($dce[0])" } else { $null })
                streamDeclarations = $(if ($d.Stream -like 'Custom-*') { [ordered]@{ ($d.Stream) = [ordered]@{ columns = @([ordered]@{ name = 'TimeGenerated'; type = 'datetime' }, [ordered]@{ name = 'RawData'; type = 'string' }) } } } else { [ordered]@{} })
                destinations = [ordered]@{ logAnalytics = @([ordered]@{ workspaceResourceId = $wsId; workspaceId = (New-DemoGuid 'workspace'); name = 'la-destination' }) }
                dataFlows = @([ordered]@{ streams = @($d.Stream); destinations = @('la-destination'); transformKql = $d.Kql; outputStream = $d.Out }); provisioningState = 'Succeeded' }
            location = $region; tags = [ordered]@{ 'Created By' = $who; CreatedDate = (Format-DemoTime $asOfUtc.AddDays(-180)); CreatorUPN = $who }; kind = $d.Kind
            id = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Insights/dataCollectionRules/$($d.Name)"; name = $d.Name; type = 'Microsoft.Insights/dataCollectionRules'; etag = '"' + (New-DemoGuid "etag|$($d.Name)") + '"' }
    })

# ---------------------------------------------------------------------------
# Alerts: the enabled rules, the Defender XDR products and custom detections
# ---------------------------------------------------------------------------
# Each source raises a number of alerts a day; weekends are quieter where
# people drive them. A phishing wave lifts the email alerts for four days.
$sources = [System.Collections.Generic.List[object]]::new()
foreach ($r in @($ruleModels | Where-Object { $_.Enabled -and $_.Kind -in @('Scheduled', 'NRT') })) {
    $rate = 0.0
    if (Test-DemoReadable $r.Tables) {
        $u = Get-DemoRandom
        $rate = if ($u -lt 0.3) { 0.0 } elseif ($u -lt 0.82) { Get-DemoBetween 0.03 0.6 } elseif ($u -lt 0.97) { Get-DemoBetween 0.8 5.0 } else { Get-DemoBetween 8 18 }
        # High-severity rules are tuned tighter and fire less.
        if ($r.Severity -eq 'High') { $rate *= 0.45 }
    }
    $noisy = $rate -gt 10
    $sources.Add([pscustomobject]@{ Key = $r.Id; RuleId = $r.Id; Name = $r.Name; Product = 'Azure Sentinel'; Provider = $(if ($r.Kind -eq 'NRT') { 'ASI NRT Alerts' } else { 'ASI Scheduled Alerts' }); Severity = $r.Severity
            Rate = $rate; Weekend = 0.75; Group = (Get-DemoBetween 0.25 0.8); Tp = (Get-DemoBetween 0.02 0.18); Fp = $(if ($noisy) { Get-DemoBetween 0.5 0.8 } else { Get-DemoBetween 0.05 0.4 }); Xdr = $false; Title = $r.Name })
}
$xdrAlerts = @(
    , @('Microsoft Defender for Endpoint', 'MDATP', 'Suspicious PowerShell command line', 'Medium', 22, 0.18)
    , @('Microsoft Defender for Endpoint', 'MDATP', 'Anomaly detected in ASEP registry', 'Low', 18, 0.1)
    , @('Microsoft Defender for Endpoint', 'MDATP', 'Suspicious process injection observed', 'High', 3, 0.5)
    , @('Microsoft Defender for Endpoint', 'MDATP', 'Malicious credential theft tool execution detected', 'High', 0.6, 0.9)
    , @('Microsoft Defender for Endpoint', 'MDATP', 'Suspicious scheduled task', 'Medium', 9, 0.2)
    , @('Microsoft Defender for Endpoint', 'MDATP', 'Suspicious file dropped and launched', 'Medium', 6, 0.3)
    , @('Microsoft Defender for Endpoint', 'MDATP', 'Suspicious LDAP query', 'Low', 14, 0.1)
    , @('Microsoft Defender for Endpoint', 'MDATP', 'Hands-on-keyboard attack via Impacket', 'High', 0.15, 1.0)
    , @('Microsoft Defender for Endpoint', 'MDATP', "An active 'Wacatac' malware was blocked", 'Informational', 35, 0.05)
    , @('Microsoft Defender for Endpoint', 'MDATP', "'PUABundler' unwanted software was detected", 'Informational', 28, 0.04)
    , @('Microsoft Defender for Office 365', 'OATP', 'Email messages containing malicious URL removed after delivery', 'Informational', 40, 0.06)
    , @('Microsoft Defender for Office 365', 'OATP', 'Email messages containing phish URLs removed after delivery', 'Informational', 30, 0.06)
    , @('Microsoft Defender for Office 365', 'OATP', 'A potentially malicious URL click was detected', 'High', 2, 0.8)
    , @('Microsoft Defender for Office 365', 'OATP', 'Email reported by user as malware or phish', 'Informational', 25, 0.15)
    , @('Microsoft Defender for Office 365', 'OATP', 'Suspicious email sending patterns detected', 'Medium', 1, 0.7)
    , @('Microsoft Defender for Identity', 'AATP', 'Suspected brute-force attack (LDAP)', 'Medium', 2.5, 0.6)
    , @('Microsoft Defender for Identity', 'AATP', 'Account enumeration reconnaissance', 'Medium', 1.2, 0.6)
    , @('Microsoft Defender for Identity', 'AATP', 'Suspected DCSync attack (replication of directory services)', 'High', 0.05, 1.0)
    , @('Microsoft Defender for Identity', 'AATP', 'Honeytoken activity', 'Medium', 0.3, 1.0)
    , @('Microsoft Defender for Cloud Apps', 'MCAS', 'Impossible travel activity', 'Medium', 11, 0.3)
    , @('Microsoft Defender for Cloud Apps', 'MCAS', 'Activity from infrequent country', 'Low', 16, 0.2)
    , @('Microsoft Defender for Cloud Apps', 'MCAS', 'Mass download by a single user', 'Medium', 2, 0.5)
    , @('Microsoft Defender for Cloud Apps', 'MCAS', 'Suspicious inbox manipulation rule', 'Medium', 0.8, 0.8)
    , @('Microsoft Entra ID Protection', 'IPC', 'Unfamiliar sign-in properties', 'Medium', 20, 0.25)
    , @('Microsoft Entra ID Protection', 'IPC', 'Anonymous IP address', 'Medium', 9, 0.3)
    , @('Microsoft Entra ID Protection', 'IPC', 'Atypical travel', 'Medium', 6, 0.3)
    , @('Microsoft Entra ID Protection', 'IPC', 'Password spray', 'High', 0.4, 1.0)
    , @('Microsoft Entra ID Protection', 'IPC', 'Leaked credentials', 'High', 0.5, 1.0)
    , @('Microsoft Defender for Cloud', 'Azure Security Center', 'Suspicious process executed', 'High', 0.8, 0.8)
    , @('Microsoft Defender for Cloud', 'Azure Security Center', 'Communication with suspicious domain identified by threat intelligence', 'Medium', 3, 0.5)
    , @('Microsoft Defender for Cloud', 'Azure Security Center', 'Access from a suspicious IP address to a storage account', 'Medium', 1.5, 0.6)
    , @('Microsoft Defender for Cloud', 'Azure Security Center', 'Unusual user accessed a key vault', 'Medium', 0.6, 0.7)
)
foreach ($x in $xdrAlerts) {
    $sources.Add([pscustomobject]@{ Key = $x[2]; RuleId = ''; Name = $x[2]; Product = $x[0]; Provider = $x[1]; Severity = $x[3]; Rate = [double]$x[4]; Weekend = 0.7; Group = [double]$x[5]
            Tp = (Get-DemoBetween 0.04 0.2); Fp = (Get-DemoBetween 0.05 0.3); Xdr = $true; Title = $x[2] })
}
foreach ($d in @($detections | Where-Object { $_.isEnabled })) {
    $sev = (Get-Culture).TextInfo.ToTitleCase(([string]$d.detectionAction.alertTemplate.severity).ToLowerInvariant())
    $sources.Add([pscustomobject]@{ Key = [string]$d.displayName; RuleId = ''; Name = [string]$d.displayName; Product = 'Microsoft Defender XDR'; Provider = 'Microsoft XDR'; Severity = $sev
            Rate = $(if ((Get-DemoRandom) -lt 0.35) { 0.0 } else { Get-DemoBetween 0.05 2.5 }); Weekend = 0.7; Group = (Get-DemoBetween 0.5 1.0); Tp = (Get-DemoBetween 0.05 0.25); Fp = (Get-DemoBetween 0.05 0.35); Xdr = $true; Title = [string]$d.displayName })
}

$alertCount = @{}   # key -> int[] per day
$phish = @{ Start = [math]::Min(19, $L - 1); End = [math]::Max(0, [math]::Min(16, $L - 4)) }
foreach ($s in $sources) {
    $a = [int[]]::new($L)
    for ($i = 0; $i -lt $L; $i++) {
        $dow = $asOfUtc.AddDays(-$i - 0.5).DayOfWeek
        $f = if ($dow -eq [DayOfWeek]::Saturday -or $dow -eq [DayOfWeek]::Sunday) { $s.Weekend } else { 1.0 }
        if ($s.Provider -eq 'OATP' -and $i -le $phish.Start -and $i -ge $phish.End) { $f *= 3.2 }
        $a[$i] = Get-DemoPoisson ($s.Rate * $f)
    }
    $alertCount[$s.Key] = $a
}

# ---------------------------------------------------------------------------
# Incidents, sampled one by one so every aggregate agrees
# ---------------------------------------------------------------------------
$openShare = @(0.55, 0.3, 0.16, 0.08, 0.06, 0.05, 0.04)
$incidents = [System.Collections.Generic.List[object]]::new()
$incNumber = 41000
foreach ($s in $sources) {
    $a = $alertCount[$s.Key]
    for ($i = $L - 1; $i -ge 0; $i--) {
        if ($a[$i] -le 0) { continue }
        $n = [int][math]::Round($a[$i] * $s.Group)
        if ($n -lt 1 -and (Get-DemoRandom) -lt $s.Group * $a[$i]) { $n = 1 }
        for ($k = 0; $k -lt $n; $k++) {
            $incNumber++
            $open = (Get-DemoRandom) -lt $(if ($i -lt $openShare.Count) { $openShare[$i] } else { 0.004 })
            $sev = $s.Severity
            $inc = [pscustomobject]@{ Number = $incNumber; Day = $i; Severity = $sev; Status = 'Closed'; Class = ''; By = ''; Ack = $null; Rsv = $null; Source = $s }
            if ($open) {
                $inc.Status = if ((Get-DemoRandom) -lt 0.6) { 'New' } else { 'Active' }
            } elseif ($sev -eq 'Informational') {
                $inc.By = 'AutomationRule'; $inc.Class = 'BenignPositive'; $inc.Ack = Get-DemoBetween 0 1; $inc.Rsv = Get-DemoBetween 0.5 3
            } else {
                $inc.By = Get-DemoPick @('AutomationRule', 'DefenderXdr', 'Other', 'Analyst') @(0.2, $(if ($s.Xdr) { 0.35 } else { 0.05 }), 0.02, $(if ($s.Xdr) { 0.43 } else { 0.73 }))
                $u = Get-DemoRandom
                $inc.Class = if ($u -lt $s.Tp) { 'TruePositive' } elseif ($u -lt $s.Tp + $s.Fp) { 'FalsePositive' } elseif ($u -lt $s.Tp + $s.Fp + 0.32) { 'BenignPositive' } elseif ($u -lt $s.Tp + $s.Fp + 0.44) { 'Undetermined' } else { '' }
                if ($inc.By -eq 'AutomationRule') { $inc.Class = 'BenignPositive' }
                switch ($inc.By) {
                    'AutomationRule' { $inc.Ack = Get-DemoBetween 0 1; $inc.Rsv = Get-DemoBetween 0.5 4 }
                    'DefenderXdr' { $inc.Ack = Get-DemoLogNormal 15 0.8; $inc.Rsv = $inc.Ack + (Get-DemoLogNormal 150 0.9) }
                    default {
                        $med = switch ($sev) { 'High' { 12 } 'Medium' { 35 } default { 95 } }
                        $inc.Ack = Get-DemoLogNormal $med 0.9
                        $inc.Rsv = $inc.Ack + (Get-DemoLogNormal $(switch ($sev) { 'High' { 220 } 'Medium' { 460 } default { 880 } }) 0.95)
                    }
                }
            }
            $incidents.Add($inc)
        }
    }
}
$closedInc = @($incidents | Where-Object Status -eq 'Closed')
$recentInc = @($incidents | Where-Object Day -lt $recentDays)

# Volumes, rules fired and the daily alert series.
$volumes = foreach ($s in $sources) {
    $a = $alertCount[$s.Key]; $all = ($a | Measure-Object -Sum).Sum
    if ($all -le 0) { continue }
    [ordered]@{ AlertName = $s.Name; ProductName = $s.Product; AlertSeverity = $s.Severity; Alerts = [int]$all; Alerts7d = [int](($a[0..($recentDays - 1)] | Measure-Object -Sum).Sum); ProviderName = $s.Provider }
}
Save-DemoJson 'analytics-rule-volumes.json' @($volumes | Sort-Object { -$_.Alerts })
Save-DemoJson 'rules-fired.json' @($(foreach ($s in @($sources | Where-Object { $_.RuleId })) {
        $a = $alertCount[$s.Key]; $all = ($a | Measure-Object -Sum).Sum
        if ($all -le 0) { continue }
        $lastDay = 0; while ($lastDay -lt $L -and $a[$lastDay] -eq 0) { $lastDay++ }
        [ordered]@{ AlertRuleId = $s.RuleId; AlertName = $s.Name; Alerts = [int]$all; LastAlert = (Format-DemoTime (Get-DemoTimeIn $lastDay)) }
    }) | Sort-Object { -$_.Alerts })
Save-DemoJson 'daily-alerts.json' @(foreach ($s in $sources) {
        $a = $alertCount[$s.Key]
        for ($i = 0; $i -lt $L; $i++) { if ($a[$i] -gt 0) { [ordered]@{ DaysAgo = $i; AlertName = $s.Name; ProductName = $s.Product; AlertSeverity = $s.Severity; ProviderName = $s.Provider; AlertRuleId = $s.RuleId; Alerts = $a[$i] } } }
    })

# Incident captures.
function Get-DemoBag($Items, [scriptblock]$Key) { $b = [ordered]@{}; foreach ($x in $Items) { $k = & $Key $x; if (-not $b.Contains($k)) { $b[$k] = 0 }; $b[$k]++ }; $b }
Save-DemoJson 'incidents-summary.json' @([ordered]@{
        Count = $incidents.Count; Closed = $closedInc.Count; Unified = $incidents.Count
        Count7d = $recentInc.Count; Closed7d = @($recentInc | Where-Object Status -eq 'Closed').Count
        FalsePositive7d = @($recentInc | Where-Object Class -eq 'FalsePositive').Count; TruePositive7d = @($recentInc | Where-Object Class -eq 'TruePositive').Count; Unified7d = $recentInc.Count
        ByStatus = (Get-DemoBag $incidents { param($x) $x.Status }); BySeverity = (Get-DemoBag $incidents { param($x) $x.Severity })
        ByClassification = (Get-DemoBag $closedInc { param($x) if ($x.Class) { $x.Class } else { 'Unclassified' } }); ByProvider = [ordered]@{ 'Microsoft XDR' = $incidents.Count }
        OpenBySeverity = (Get-DemoBag @($incidents | Where-Object Status -ne 'Closed') { param($x) $x.Severity }); ClosedBy = (Get-DemoBag $closedInc { param($x) $x.By })
    })
$avg = { param($xs, $p) $v = @($xs | ForEach-Object { $_.$p } | Where-Object { $null -ne $_ }); if ($v.Count) { [math]::Round(($v | Measure-Object -Average).Average, 1) } else { $null } }
$recentClosed = @($closedInc | Where-Object Day -lt $recentDays)
Save-DemoJson 'incidents-mttr.json' @([ordered]@{ ClosedCount = $closedInc.Count; AcknowledgedCount = $closedInc.Count; MTTAMinutes = (& $avg $closedInc 'Ack'); MTTRMinutes = (& $avg $closedInc 'Rsv')
        ClosedCount7d = $recentClosed.Count; MTTAMinutes7d = (& $avg $recentClosed 'Ack'); MTTRMinutes7d = (& $avg $recentClosed 'Rsv') })
$perDay = @($incidents | Group-Object Day | ForEach-Object { $_.Count })
Save-DemoJson 'incidents-daily-metrics.json' @([ordered]@{ AvgDailyUniqueIncidents = [math]::Round(($perDay | Measure-Object -Average).Average, 1); PeakDailyNewIncidents = [int]($perDay | Measure-Object -Maximum).Maximum })
Save-DemoJson 'daily-incidents.json' @(foreach ($g in ($incidents | Group-Object { "$($_.Day)|$($_.Severity)|$(if ($_.Status -eq 'Closed') { 'Closed' } else { 'Open' })|$($_.Class)|$($_.By)" })) {
        $f = $g.Group[0]; $closed = @($g.Group | Where-Object Status -eq 'Closed')
        [ordered]@{ DaysAgo = $f.Day; Severity = $f.Severity; Status = $(if ($f.Status -eq 'Closed') { 'Closed' } else { 'Open' }); Class = $(if ($f.Status -eq 'Closed') { if ($f.Class) { $f.Class } else { 'Unclassified' } } else { '' }); ClosedBy = $f.By
            Incidents = $g.Count; AckCount = $closed.Count; AckSum = [math]::Round((Get-DemoSum $closed 'Ack'), 1); RsvCount = $closed.Count; RsvSum = [math]::Round((Get-DemoSum $closed 'Rsv'), 1) }
    })
# Per detection: incidents and verdicts, overall and per day.
function Get-DemoVerdicts($Items) {
    $closed = @($Items | Where-Object Status -eq 'Closed')
    [ordered]@{ Incidents = @($Items).Count; Closed = $closed.Count; TruePositive = @($closed | Where-Object Class -eq 'TruePositive').Count; FalsePositive = @($closed | Where-Object Class -eq 'FalsePositive').Count
        BenignPositive = @($closed | Where-Object Class -eq 'BenignPositive').Count; Undetermined = @($closed | Where-Object { $_.Class -in @('Undetermined', '') }).Count }
}
$byDetection = $incidents | Group-Object { $_.Source.Key }
Save-DemoJson 'rule-effectiveness.json' @($(foreach ($g in $byDetection) {
        $s = $g.Group[0].Source; $v = Get-DemoVerdicts $g.Group
        [ordered]@{ AlertRuleId = $s.RuleId; RuleName = $s.Name; Product = $s.Product; Provider = $s.Provider } + $v + [ordered]@{ FPRate = [math]::Round(100.0 * $v.FalsePositive / [math]::Max(1, $v.Closed), 1); Source = $(if ($s.RuleId) { 'Analytics rule' } else { $s.Product }) }
    }) | Sort-Object @{ Expression = { if ($_.AlertRuleId) { 0 } else { 1 } } }, @{ Expression = { -$_.Incidents } })
Save-DemoJson 'daily-rule-incidents.json' @(foreach ($g in ($incidents | Group-Object { "$($_.Source.Key)|$($_.Day)" })) {
        $s = $g.Group[0].Source
        [ordered]@{ RuleKey = $(if ($s.RuleId) { $s.RuleId } else { $s.Name }); DaysAgo = $g.Group[0].Day; AlertRuleId = $s.RuleId; RuleName = $s.Name; Product = $s.Product; Provider = $s.Provider } + (Get-DemoVerdicts $g.Group)
    })
Save-DemoJson 'incidents-by-rule.json' @(foreach ($g in ($incidents | Group-Object { $_.Source.Title } | Sort-Object Count -Descending)) { [ordered]@{ Title = $g.Name; Incidents = "$($g.Count)" } })
Save-DemoJson 'incident-title-stats.json' @(foreach ($g in ($incidents | Group-Object { $_.Source.Title } | Where-Object Count -ge 5 | Sort-Object Count -Descending)) {
        $closed = @($g.Group | Where-Object Status -eq 'Closed')
        [ordered]@{ Title = $g.Name; Severity = $g.Group[0].Severity; Total = $g.Count; Closed = $closed.Count; AvgMinsToClose = (& $avg $closed 'Rsv'); ClosedWithinHour = @($closed | Where-Object { $_.Rsv -le 60 }).Count
            FP = @($closed | Where-Object Class -eq 'FalsePositive').Count; TP = @($closed | Where-Object Class -eq 'TruePositive').Count; BP = @($closed | Where-Object Class -eq 'BenignPositive').Count }
    })
Save-DemoJson 'incidents-detail-by-provider.json' @(foreach ($g in ($incidents | Group-Object { "$($_.Source.Provider)|$($_.Source.Product)|$($_.Source.RuleId)" } | Sort-Object Count -Descending)) {
        $s = $g.Group[0].Source
        [ordered]@{ ProviderName = $s.Provider; ProductName = $s.Product; FirstRule = $s.RuleId; AlertCount = [int](($alertCount[$s.Key] | Measure-Object -Sum).Sum) }
    })

# ---------------------------------------------------------------------------
# Playbook runs, health events and failing rules
# ---------------------------------------------------------------------------
$runsByPlaybook = @{}
foreach ($p in $playbookModels) { $runsByPlaybook[$p.Name] = [pscustomobject]@{ Runs = [int[]]::new($L); Failed = [int[]]::new($L) } }
foreach ($a in @($automation | Where-Object { $_.PSObject.Properties['Playbook'] })) {
    foreach ($inc in $incidents) { if ($inc.Severity -in $a.Severities) { $runsByPlaybook[$a.Playbook].Runs[$inc.Day]++ } }
}
foreach ($p in $playbookModels) {
    if ($p.State -ne 'Enabled') { continue }
    $rb = $runsByPlaybook[$p.Name]
    for ($i = 0; $i -lt $L; $i++) {
        switch ($p.Trigger) {
            'Recurrence' { $rb.Runs[$i] += 24 }
            'Entity' { $rb.Runs[$i] += Get-DemoPoisson 0.6 }
            'Alert' { $rb.Runs[$i] += Get-DemoPoisson 0.4 }
            'Incident' { $rb.Runs[$i] += Get-DemoPoisson 0.3 }
            default { $rb.Runs[$i] += Get-DemoPoisson 0.15 }
        }
    }
}
# The notification playbook's Teams connection expired five days ago, and
# the VirusTotal IP lookup hits the API's rate limit now and then.
$failingPlaybook = @($automation | Where-Object { $_.PSObject.Properties['Playbook'] -and $_.DisplayName -like 'Notify*' } | ForEach-Object { $_.Playbook }) | Select-Object -First 1
foreach ($p in $playbookModels) {
    $rb = $runsByPlaybook[$p.Name]
    for ($i = 0; $i -lt $L; $i++) {
        $rate = if ($p.Name -eq $failingPlaybook -and $i -lt 5) { 0.85 } elseif ($p.Name -eq 'VirusTotalIPReport') { 0.05 } else { 0.0 }
        $f = 0; for ($k = 0; $k -lt $rb.Runs[$i]; $k++) { if ($script:Rng.NextDouble() -lt $rate) { $f++ } }
        $rb.Failed[$i] = $f
    }
}
Save-DemoJson 'playbook-runs.json' @(foreach ($p in $playbookModels) {
        $rb = $runsByPlaybook[$p.Name]; $runs = ($rb.Runs | Measure-Object -Sum).Sum; $failed = ($rb.Failed | Measure-Object -Sum).Sum
        $lastFail = $null; for ($i = 0; $i -lt $L; $i++) { if ($rb.Failed[$i] -gt 0) { $lastFail = Format-DemoTime (Get-DemoTimeIn $i); break } }
        [ordered]@{ Playbook = $p.Name; Id = $p.Id; Runs7d = [int]$runs; Failed7d = [int]$failed; LastFailureUtc = $lastFail
            LastRunStatus = $(if ($p.State -ne 'Enabled' -or $runs -eq 0) { 'Skipped' } elseif ($rb.Failed[0] -gt 0) { 'Failed' } else { 'Succeeded' }); Note = $null
            Daily = @(for ($i = 0; $i -lt $L; $i++) { if ($rb.Runs[$i] -gt 0) { [ordered]@{ DaysAgo = $i; Runs = $rb.Runs[$i]; Failed = $rb.Failed[$i] } } }) }
    })
Save-DemoJson 'rbac-playbook-mi.json' @(foreach ($p in @($playbookModels | Where-Object Identity)) {
        $roles = if ($p.Trigger -in @('Incident', 'Alert', 'Entity')) { @('Microsoft Sentinel Responder') } else { @('Microsoft Sentinel Reader') }
        [ordered]@{ Playbook = $p.Name; PrincipalId = $p.PrincipalId; AllAssignments = @(foreach ($r in $roles) { [ordered]@{ RoleAssignmentName = (New-DemoGuid "ra|$($p.Name)|$r"); Scope = $wsId; DisplayName = $p.Name; RoleDefinitionName = $r; ObjectId = $p.PrincipalId; ObjectType = 'ServicePrincipal'; CanDelegate = $false } }); WorkspaceRoles = $roles }
    })

# Health: rule runs, NRT runs, automation, playbooks and connector fetches.
$enabledRules = @($ruleModels | Where-Object { $_.Enabled -and $_.Kind -in @('Scheduled', 'NRT') })
$failingRules = @($enabledRules | Where-Object { $_.Kind -eq 'Scheduled' -and $_.Frequency -le 60 } | Select-Object -First 2)
$failingName = @{}; foreach ($r in $failingRules) { $failingName[$r.Name] = $true }
$failReasons = @('Query execution exceeded the 10 minute timeout.', "The query referenced a column that does not exist: 'ActorDisplayName'.")
$health = @{}
function Add-DemoHealth([int]$Day, [string]$Op, [string]$Status, [long]$N) { if ($N -le 0) { return }; $k = "$Day|$Op|$Status"; if (-not $health.ContainsKey($k)) { $health[$k] = 0 }; $health[$k] += $N }
$resourceHealth = [System.Collections.Generic.List[object]]::new()
foreach ($r in $enabledRules) {
    $perDay = if ($r.Kind -eq 'NRT') { 1440 } else { [int][math]::Max(1, [math]::Round(1440 / $r.Frequency)) }
    $op = if ($r.Kind -eq 'NRT') { 'NRT analytics rule run' } else { 'Scheduled analytics rule run' }
    $fails = 0; $lastFail = $null
    for ($i = 0; $i -lt $L; $i++) {
        $f = if ($failingName.ContainsKey($r.Name) -and $i -lt 12) { [int][math]::Round($perDay * (Get-DemoBetween 0.2 0.5)) } elseif ((Get-DemoRandom) -lt 0.01) { 1 } else { 0 }
        Add-DemoHealth $i $op 'Success' ($perDay - $f); Add-DemoHealth $i $op 'Failure' $f
        $fails += $f; if ($f -gt 0 -and -not $lastFail) { $lastFail = Format-DemoTime (Get-DemoTimeIn $i) }
    }
    $resourceHealth.Add([ordered]@{ SentinelResourceName = $r.Name; SentinelResourceKind = $r.Kind; SentinelResourceType = 'Analytics Rule'; Events = [long]($perDay * $L); LastEvent = (Format-DemoTime $asOfUtc.AddMinutes(-(Get-DemoBetween 1 50))); Statuses = @($(if ($fails) { 'Success', 'Failure' } else { 'Success' })); Failures = $fails; LastFailure = $lastFail })
}
foreach ($c in @('Sophos Endpoint Protection (CCF)', 'Google Workspace Activities (CCF)', 'Tailscale audit logs (CCF)')) {
    $fails = 0
    for ($i = 0; $i -lt $L; $i++) { $f = if ($c -like 'Google*' -and $i -ge 40 -and $i -lt 43) { 96 } elseif ((Get-DemoRandom) -lt 0.05) { 2 } else { 0 }; Add-DemoHealth $i 'Data fetcher run' 'Success' (288 - $f); Add-DemoHealth $i 'Data fetcher run' 'Failure' $f; $fails += $f }
    $resourceHealth.Add([ordered]@{ SentinelResourceName = $c; SentinelResourceKind = 'RestApiPoller'; SentinelResourceType = 'Data connector'; Events = [long](288 * $L); LastEvent = (Format-DemoTime $asOfUtc.AddMinutes(-4)); Statuses = @($(if ($fails) { 'Success', 'Failure' } else { 'Success' })); Failures = $fails; LastFailure = $(if ($fails) { Format-DemoTime (Get-DemoTimeIn 41) } else { $null }) })
}
$incPerDay = [int[]]::new($L); foreach ($inc in $incidents) { $incPerDay[$inc.Day]++ }
foreach ($i in 0..($L - 1)) {
    $n = $incPerDay[$i]
    Add-DemoHealth $i 'Automation rule run' 'Success' ([long]($n * $automation.Count * 0.98)); Add-DemoHealth $i 'Automation rule run' 'Partial success' ([long]($n * 0.02))
    foreach ($p in $playbookModels) { $rb = $runsByPlaybook[$p.Name]; Add-DemoHealth $i 'Playbook was triggered' 'Success' ($rb.Runs[$i] - $rb.Failed[$i]); Add-DemoHealth $i 'Playbook was triggered' 'Failure' $rb.Failed[$i] }
}
foreach ($a in $automation) { $resourceHealth.Add([ordered]@{ SentinelResourceName = $a.DisplayName; SentinelResourceKind = 'Automation rule'; SentinelResourceType = 'Automation rule'; Events = [long]$incidents.Count; LastEvent = (Format-DemoTime $asOfUtc.AddMinutes(-9)); Statuses = @('Success'); Failures = 0; LastFailure = $null }) }
Save-DemoJson 'sentinel-health.json' $resourceHealth
Save-DemoJson 'daily-health.json' @(foreach ($k in $health.Keys) { $p = $k -split '\|', 3; [ordered]@{ DaysAgo = [int]$p[0]; OperationName = $p[1]; Status = $p[2]; LogCount = $health[$k] } })
$healthSum = @{}; foreach ($k in $health.Keys) { $p = $k -split '\|', 3; $hk = "$($p[1])|$($p[2])"; if (-not $healthSum.ContainsKey($hk)) { $healthSum[$hk] = 0 }; $healthSum[$hk] += $health[$k] }
Save-DemoJson 'sentinel-health-summary.json' @(foreach ($k in ($healthSum.Keys | Sort-Object { -$healthSum[$_] })) { $p = $k -split '\|', 2; [ordered]@{ OperationName = $p[0]; Status = $p[1]; LogCount = $healthSum[$k] } })
Save-DemoJson 'rule-health.json' @(for ($i = 0; $i -lt $failingRules.Count; $i++) { [ordered]@{ RuleName = $failingRules[$i].Name; Status = 'Failure'; Failures = [int](@($resourceHealth | Where-Object { $_.SentinelResourceName -eq $failingRules[$i].Name })[0].Failures); LastFailure = (Format-DemoTime $asOfUtc.AddHours(-2 - $i)); Reason = $failReasons[$i] } })

# ---------------------------------------------------------------------------
# Telemetry captures
# ---------------------------------------------------------------------------
$gbToRows = { param([double]$Gb, [double]$BytesPerRow) [long]($Gb * 1GB / $BytesPerRow) }
$tiRows = & $gbToRows (Get-SeriesSum 'ThreatIntelIndicators' $L) 2400
$tiRecent = & $gbToRows (Get-SeriesSum 'ThreatIntelIndicators' $recentDays) 2400
Save-DemoJson 'threat-intel-counts.json' @(
    [ordered]@{ SourceSystem = 'Microsoft Defender Threat Intelligence'; Count = [long]($tiRows * 0.58); Indicators = [long]($tiRows * 0.58 / 6.5); Last = (Format-DemoTime $asOfUtc.AddMinutes(-11)) }
    [ordered]@{ SourceSystem = 'MISP (TAXII)'; Count = [long]($tiRows * 0.22); Indicators = [long]($tiRows * 0.22 / 9); Last = (Format-DemoTime $asOfUtc.AddMinutes(-48)) }
    [ordered]@{ SourceSystem = 'Abuse.ch URLhaus (upload API)'; Count = [long]($tiRows * 0.14); Indicators = [long]($tiRows * 0.14 / 4); Last = (Format-DemoTime $asOfUtc.AddHours(-3)) }
    [ordered]@{ SourceSystem = 'SOC analyst submissions'; Count = [long]($tiRows * 0.06); Indicators = [long]($tiRows * 0.06 / 2); Last = (Format-DemoTime $asOfUtc.AddDays(-2)) }
)
Save-DemoJson 'threat-intel-by-type.json' @(foreach ($t in @(@('IP', 0.46), @('Domain', 0.22), @('URL', 0.19), @('FileHash', 0.11), @('Email', 0.02))) { [ordered]@{ Type = $t[0]; Count = [long]($tiRows * $t[1]); Indicators = [long]($tiRows * $t[1] / 6) } })
Save-DemoJson 'threat-intel-objects.json' @(foreach ($t in @(@('indicator', 0.0), @('attack-pattern', 1840), @('threat-actor', 412), @('identity', 205), @('relationship', 5120), @('malware', 630))) { if ($t[1] -gt 0) { [ordered]@{ StixType = $t[0]; Count = [long]$t[1] } } })
Save-DemoJson 'threat-intel-tables.json' @(
    [ordered]@{ Table = 'ThreatIntelIndicators'; Records30d = $tiRows; Records7d = $tiRecent; FirstSeen = (Format-DemoTime $asOfUtc.AddDays(-$L).AddMinutes(9)); LastSeen = (Format-DemoTime $asOfUtc.AddMinutes(-11)) }
    [ordered]@{ Table = 'ThreatIntelObjects'; Records30d = 8207; Records7d = 911; FirstSeen = (Format-DemoTime $asOfUtc.AddDays(-$L).AddHours(2)); LastSeen = (Format-DemoTime $asOfUtc.AddHours(-1)) }
)
$tiUnique = [long]($tiRows / 6.4)
Save-DemoJson 'threat-intel-health.json' @([ordered]@{ Total = $tiUnique; Active = [long]($tiUnique * 0.81); Deleted = [long]($tiUnique * 0.07); Revoked = [long]($tiUnique * 0.02); StillValid = [long]($tiUnique * 0.78) })
$uebaRows = & $gbToRows (Get-SeriesSum 'BehaviorAnalytics' $L) 3800
Save-DemoJson 'ueba-data-presence.json' @(
    [ordered]@{ TableName = 'BehaviorAnalytics'; Count = $uebaRows; Count7d = (& $gbToRows (Get-SeriesSum 'BehaviorAnalytics' $recentDays) 3800); Count14d = $uebaRows }
    [ordered]@{ TableName = 'IdentityInfo'; Count = (& $gbToRows (Get-SeriesSum 'IdentityInfo' $L) 5200); Count7d = (& $gbToRows (Get-SeriesSum 'IdentityInfo' $recentDays) 5200); Count14d = (& $gbToRows (Get-SeriesSum 'IdentityInfo' $L) 5200) }
    [ordered]@{ TableName = 'UserPeerAnalytics'; Count = (& $gbToRows (Get-SeriesSum 'UserPeerAnalytics' $L) 900); Count7d = (& $gbToRows (Get-SeriesSum 'UserPeerAnalytics' $recentDays) 900); Count14d = (& $gbToRows (Get-SeriesSum 'UserPeerAnalytics' $L) 900) }
)
$settingsDoc = [ordered]@{
    Ueba            = [ordered]@{ name = 'Ueba'; kind = 'Ueba'; properties = [ordered]@{ dataSources = @('AuditLogs', 'AzureActivity', 'SecurityEvent', 'SigninLogs') } }
    EntityAnalytics = [ordered]@{ name = 'EntityAnalytics'; kind = 'EntityAnalytics'; properties = [ordered]@{ entityProviders = @('AzureActiveDirectory', 'ActiveDirectory') } }
    EyesOn          = [ordered]@{ name = 'EyesOn'; kind = 'EyesOn'; properties = [ordered]@{ isEnabled = $true } }
    Anomalies       = [ordered]@{ name = 'Anomalies'; kind = 'Anomalies'; properties = [ordered]@{ isEnabled = $true } }
}
Save-DemoJson 'settings.json' $settingsDoc

# Agents: Windows and Linux servers on the Azure Monitor Agent, and a tail
# still on the legacy agent.
$agentMix = @(
    @{ OS = 'Windows'; Cat = 'Azure Monitor Agent'; Ver = '1.33.0.0'; OSV = 'Windows Server 2022 Datacenter 10.0'; N = 612 }
    @{ OS = 'Windows'; Cat = 'Azure Monitor Agent'; Ver = '1.32.0.0'; OSV = 'Windows Server 2019 Datacenter 10.0'; N = 344 }
    @{ OS = 'Linux'; Cat = 'Azure Monitor Agent'; Ver = '1.34.2'; OSV = 'Ubuntu 22.04'; N = 286 }
    @{ OS = 'Linux'; Cat = 'Azure Monitor Agent'; Ver = '1.33.5'; OSV = 'Red Hat Enterprise Linux 9.4'; N = 131 }
    @{ OS = 'Windows'; Cat = 'Direct Agent'; Ver = '10.20.18069.0'; OSV = 'Windows Server 2016 Datacenter 10.0'; N = 58 }
    @{ OS = 'Linux'; Cat = 'Direct Agent'; Ver = '1.19.0'; OSV = 'CentOS 7.9'; N = 17 }
)
Save-DemoJson 'agent-heartbeat-mix.json' @(foreach ($m in $agentMix) { [ordered]@{ OSType = $m.OS; Category = $m.Cat; Version = $m.Ver; OSVersion = $m.OSV; Computers = $m.N; LastSeen = (Format-DemoTime $asOfUtc.AddMinutes(-1)) } })
$hostNo = 100
$amaMachines = foreach ($m in @($agentMix | Where-Object Cat -eq 'Azure Monitor Agent')) {
    for ($i = 1; $i -le $m.N; $i++) {
        $hostNo++
        $role = if ($m.OS -eq 'Windows') { Get-DemoPick @('app', 'sql', 'web', 'dc', 'file', 'rds') @(5, 2, 3, 0.5, 1, 1) } else { Get-DemoPick @('app', 'web', 'k8s', 'db', 'fwd') @(5, 3, 3, 1, 0.3) }
        $name = "$(if ($m.OS -eq 'Windows') { 'WIN' } else { 'lnx' })-$role-$('{0:d4}' -f $hostNo)"
        $late = (Get-DemoRandom) -lt 0.012
        [ordered]@{ SourceComputerId = (New-DemoGuid "host|$name"); LastHeartbeat = (Format-DemoTime $(if ($late) { $asOfUtc.AddDays(-(Get-DemoBetween 2 20)) } else { $asOfUtc.AddMinutes(-(Get-DemoBetween 0.2 3)) })); OS = $m.OS; Version = $m.Ver; Solutions = '"security", "changeTracking"'; Computer = $name.ToLowerInvariant() + '.corp.contoso.com'
            Resource = "/subscriptions/$subscriptionId/resourcegroups/rg-servers-$role/providers/microsoft.compute/virtualmachines/$($name.ToLowerInvariant())" }
    }
}
Save-DemoJson 'ama-agents.json' $amaMachines
Save-DemoJson 'ama-mma-migration.json' @(
    [ordered]@{ MachineType = 'Windows'; MachineCount = 1014; MMACount = 58; AMACount = 956; MigrationStatus = 'In progress' }
    [ordered]@{ MachineType = 'Linux'; MachineCount = 434; MMACount = 17; AMACount = 417; MigrationStatus = 'In progress' }
)

$cefRows = & $gbToRows (Get-SeriesSum 'CommonSecurityLog' $L) 1350
Save-DemoJson 'cef-devices.json' @(foreach ($c in @(@('Palo Alto Networks', 'PAN-OS', 0.44), @('Fortinet', 'Fortigate', 0.27), @('Zscaler', 'NSSWeblog', 0.15), @('Check Point', 'VPN-1 & FireWall-1', 0.09), @('Cisco', 'ASA', 0.05))) { [ordered]@{ DeviceVendor = $c[0]; DeviceProduct = $c[1]; LogCount = [long]($cefRows * $c[2]) } })
Save-DemoJson 'cef-in-syslog.json' @([ordered]@{ Computer = 'lnx-fwd-0007.corp.contoso.com'; ProductVendor = 'Cisco-ASA'; LogCount = 184220 })
$sysRows = & $gbToRows (Get-SeriesSum 'Syslog' $L) 420
Save-DemoJson 'syslog-contributors.json' @(foreach ($h in @(@('lnx-k8s-0412.corp.contoso.com', 'daemon', 0.24), @('lnx-app-0233.corp.contoso.com', 'local4', 0.16), @('lnx-web-0117.corp.contoso.com', 'authpriv', 0.09), @('lnx-db-0031.corp.contoso.com', 'daemon', 0.07), @('lnx-app-0298.corp.contoso.com', 'user', 0.05))) { [ordered]@{ Computer = $h[0]; Facility = $h[1]; LogCount = [long]($sysRows * $h[2]); SizeMB = [math]::Round($sysRows * $h[2] * 420 / 1MB, 1) } })
$secRows = & $gbToRows (Get-SeriesSum 'SecurityEvent' $L) 1100
Save-DemoJson 'securityevent-top-hosts.json' @(foreach ($h in @(@('WIN-dc-0101.corp.contoso.com', 0.11), @('WIN-dc-0102.corp.contoso.com', 0.1), @('WIN-dc-0103.corp.contoso.com', 0.08), @('WIN-file-0204.corp.contoso.com', 0.05), @('WIN-rds-0311.corp.contoso.com', 0.04))) { [ordered]@{ Computer = $h[0]; LogCount = [long]($secRows * $h[1]); SizeMB = [math]::Round($secRows * $h[1] * 1100 / 1MB, 1) } })
$secGb = Get-SeriesSum 'SecurityEvent' $L
Save-DemoJson 'top-event-ids.json' @(foreach ($e in @(@(4624, 'An account was successfully logged on', 0.24), @(4688, 'A new process has been created', 0.19), @(4663, 'An attempt was made to access an object', 0.12), @(4634, 'An account was logged off', 0.09), @(5145, 'A network share object was checked to see whether client can be granted desired access', 0.08), @(4672, 'Special privileges assigned to new logon', 0.06), @(4625, 'An account failed to log on', 0.04), @(4769, 'A Kerberos service ticket was requested', 0.04), @(4776, 'The computer attempted to validate the credentials for an account', 0.03), @(4662, 'An operation was performed on an object', 0.03))) {
        [ordered]@{ TableName = 'SecurityEvent'; EventID = $e[0]; EventDescription = $e[1]; BilledSizeGB = [math]::Round($secGb * $e[2] * 1.07374, 3); LogCount = [long]($secRows * $e[2]) }
    })
Save-DemoJson 'security-event-duplicates.json' @([ordered]@{ Computer = 'WIN-file-0204.corp.contoso.com'; DuplicateRecords = 412; LogCount = 9120; DuplicateEventIds = @(4663, 5145) })
Save-DemoJson 'azure-activity-coverage.json' @(foreach ($i in 1..14) { $sid = '00000000-0000-0000-0000-{0:x12}' -f (0xc0de00 + $i); [ordered]@{ SubscriptionId = $sid; LogCount = [long](Get-DemoBetween 20000 900000) } })
Save-DemoJson 'azure-diagnostics-providers.json' @(foreach ($p in @(@('MICROSOFT.KEYVAULT', 0.31), @('MICROSOFT.NETWORK', 0.27), @('MICROSOFT.SQL', 0.22), @('MICROSOFT.WEB', 0.12), @('MICROSOFT.CONTAINERSERVICE', 0.08))) { [ordered]@{ ResourceProvider = $p[0]; LogCount = [long]((& $gbToRows (Get-SeriesSum 'AzureDiagnostics' $L) 1500) * $p[1]) } })
Save-DemoJson 'azure-diagnostics-categories.json' @(foreach ($p in @(@('MICROSOFT.KEYVAULT', 'AuditEvent', 0.31), @('MICROSOFT.NETWORK', 'ApplicationGatewayFirewallLog', 0.18), @('MICROSOFT.NETWORK', 'ApplicationGatewayAccessLog', 0.09), @('MICROSOFT.SQL', 'SQLSecurityAuditEvents', 0.22), @('MICROSOFT.WEB', 'AppServiceHTTPLogs', 0.12), @('MICROSOFT.CONTAINERSERVICE', 'kube-audit-admin', 0.08))) { [ordered]@{ ResourceProvider = $p[0]; Category = $p[1]; LogCount = [long]((& $gbToRows (Get-SeriesSum 'AzureDiagnostics' $L) 1500) * $p[2]) } })
Save-DemoJson 'azure-firewall-categories.json' @(foreach ($c in @(@('AZFWNetworkRule', 'AZFWNetworkRule'), @('AZFWApplicationRule', 'AZFWApplicationRule'), @('AZFWDnsQuery', 'AZFWDnsQuery'), @('AZFWThreatIntel', 'AZFWThreatIntel'))) { [ordered]@{ Category = $c[0]; LogCount = (& $gbToRows (Get-SeriesSum $c[1] $L) 600) } })
Save-DemoJson 'xdr-table-presence.json' @(foreach ($t in @($tableSpec | Where-Object { $_.T -match '^(Device|Email|Identity|UrlClick|CloudApp)' })) { [ordered]@{ Type = $t.T; RecordCount = (& $gbToRows (Get-SeriesSum $t.T $recentDays) 900) } })
Save-DemoJson 'la-query-logs.json' @([ordered]@{ QueryCount = [long](Get-DemoBetween 380000 460000) })
Save-DemoJson 'ingestion-latency.json' @([ordered]@{ OperationKey = "Data collection rule 'dcr-pfsense-logstash' transformation failed for 3 records: column 'src_port' type mismatch."; Resource = 'Ingestion'; Failures = 214; Last = (Format-DemoTime $asOfUtc.AddDays(-3)) })
Save-DemoJson 'table-query-usage.json' @(foreach ($t in @(@('SigninLogs', 1820, 31), @('AuditLogs', 640, 14), @('SecurityEvent', 2210, 22), @('CommonSecurityLog', 1180, 17), @('AzureActivity', 210, 9), @('ZscalerWebLogs_CL', 46, 5), @('NetFlowRaw_CL', 12, 3))) { [ordered]@{ Table = $t[0]; Queries = "$($t[1])"; Users = "$($t[2])"; LastQuery = (Format-DemoTime $asOfUtc.AddHours(-(Get-DemoBetween 1 70))) } })

# Hunting activity: hunts and bookmarks drawn from the hunting queries.
$huntNames = @(@($hunting) | Select-Object -First 6 | ForEach-Object { $_.properties.displayName })
Save-DemoJson 'hunts.json' @(for ($i = 0; $i -lt $huntNames.Count; $i++) {
        $hid = New-DemoGuid "hunt-mission|$i"; $who = Get-DemoPerson; $created = $asOfUtc.AddDays(-(Get-DemoBetween 3 80))
        [ordered]@{ id = "$siId/hunts/$hid"; name = $hid; etag = '"' + (New-DemoGuid "etag|$hid") + '"'; type = 'Microsoft.SecurityInsights/hunts'
            systemData = [ordered]@{ createdAt = (Format-DemoTime $created); createdBy = $who; createdByType = 'User'; lastModifiedAt = (Format-DemoTime $created.AddDays(2)); lastModifiedBy = $who; lastModifiedByType = 'User' }
            properties = [ordered]@{ displayName = "Hunt: $($huntNames[$i])"; description = "Hypothesis-led hunt built on the '$($huntNames[$i])' query."; owner = [ordered]@{ objectId = (New-DemoGuid "user|$who"); email = $who; assignedTo = $who; userPrincipalName = $who; ownerType = 'User' }
                status = @('New', 'Active', 'Closed', 'Active', 'Closed', 'Backlog')[$i]; hypothesisStatus = @('Unknown', 'Unknown', 'Validated', 'Unknown', 'Invalidated', 'Unknown')[$i] } }
    })
Save-DemoJson 'bookmarks.json' @(for ($i = 0; $i -lt 9; $i++) {
        $bid = New-DemoGuid "bookmark|$i"; $who = New-DemoActor (Get-DemoPerson)
        [ordered]@{ id = "$siId/bookmarks/$bid"; name = $bid; etag = '"' + (New-DemoGuid "etag|$bid") + '"'; type = 'Microsoft.SecurityInsights/Bookmarks'
            properties = [ordered]@{ displayName = "Suspicious result $($i + 1) from $($huntNames[$i % [math]::Max(1, $huntNames.Count)])"; created = (Format-DemoTime $asOfUtc.AddDays(-(Get-DemoBetween 1 60))); createdBy = $who; updated = (Format-DemoTime $asOfUtc.AddDays(-(Get-DemoBetween 0.1 1))); updatedBy = $who; query = 'SigninLogs | take 10'; labels = @('hunt'); notes = '' } }
    })

# ---------------------------------------------------------------------------
# Workspace, identity and the shapes no content drives
# ---------------------------------------------------------------------------
$created = $asOfUtc.AddYears(-3).AddDays(-41)
Save-DemoJson 'workspace.json' ([ordered]@{
        properties = [ordered]@{
            customerId = (New-DemoGuid 'workspace'); provisioningState = 'Succeeded'; sku = $(if ($commitmentGb) { [ordered]@{ name = 'CapacityReservation'; capacityReservationLevel = $commitmentGb; lastSkuUpdate = (Format-DemoTime $asOfUtc.AddDays(-200)) } } else { [ordered]@{ name = 'PerGB2018'; lastSkuUpdate = (Format-DemoTime $created) } }); retentionInDays = 90
            features = [ordered]@{ legacy = 0; searchVersion = 1; enableLogAccessUsingOnlyResourcePermissions = $true; unifiedSentinelBillingOnly = $true; disableLocalAuth = $true; enableDataExport = $true; immediatePurgeDataOn30Days = $false; clusterResourceId = $null }
            workspaceCapping = [ordered]@{ dailyQuotaGb = -1.0; quotaNextResetTime = (Format-DemoTime $asOfUtc.Date.AddDays(1).AddHours(9)); dataIngestionStatus = 'RespectQuota' }
            publicNetworkAccessForIngestion = 'Enabled'; publicNetworkAccessForQuery = 'Enabled'; createdDate = (Format-DemoTime $created); modifiedDate = (Format-DemoTime $asOfUtc.AddDays(-12))
            defaultDataCollectionRuleResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Insights/dataCollectionRules/dcr-workspace-transform"
            replication = [ordered]@{ enabled = $true; location = 'ukwest' }
        }
        location = $region; tags = [ordered]@{ Environment = 'Production'; Owner = 'secops@contoso.com'; CostCentre = 'SEC-001' }; id = $wsId; name = $WorkspaceName; type = 'Microsoft.OperationalInsights/workspaces'; etag = '"' + (New-DemoGuid 'etag|workspace') + '"'
    })
Save-DemoJson 'subscription.json' ([ordered]@{ Id = $subscriptionId; Name = 'Contoso Security Production'; TenantId = $tenantId; State = 'Enabled'; HomeTenantId = $tenantId })
Save-DemoJson 'resource-providers.json' @(foreach ($p in 'Microsoft.OperationalInsights', 'Microsoft.SecurityInsights', 'Microsoft.OperationsManagement', 'Microsoft.Insights', 'Microsoft.Logic', 'Microsoft.SentinelPlatformServices') { [ordered]@{ ProviderNamespace = $p; RegistrationState = 'Registered' } })
$roleSpec = @(
    @('SOC Analysts Tier 1', 'Group', 'Microsoft Sentinel Responder'), @('SOC Analysts Tier 2', 'Group', 'Microsoft Sentinel Responder'), @('SOC Engineering', 'Group', 'Microsoft Sentinel Contributor'),
    @('SOC Engineering', 'Group', 'Logic App Contributor'), @('Security Leadership', 'Group', 'Microsoft Sentinel Reader'), @('Threat Hunters', 'Group', 'Microsoft Sentinel Contributor'),
    @('Platform Operations', 'Group', 'Log Analytics Reader'), @('sp-sentinel-as-code-deploy', 'ServicePrincipal', 'Microsoft Sentinel Contributor'), @('sp-sentinel-as-code-deploy', 'ServicePrincipal', 'Log Analytics Contributor'),
    @('sp-blueprint-reader', 'ServicePrincipal', 'Microsoft Sentinel Reader'), @('sp-legacy-siem-export', 'ServicePrincipal', 'Contributor'), @('Break Glass Admins', 'Group', 'Owner'))
$asRole = { param($scope, $r) [ordered]@{ RoleAssignmentName = (New-DemoGuid "ra|$scope|$($r[0])|$($r[2])"); RoleAssignmentId = "$scope/providers/Microsoft.Authorization/roleAssignments/$(New-DemoGuid "ra|$scope|$($r[0])|$($r[2])")"; Scope = $scope; DisplayName = $r[0]; SignInName = $null; RoleDefinitionName = $r[2]; RoleDefinitionId = "/providers/Microsoft.Authorization/roleDefinitions/$(New-DemoGuid "rd|$($r[2])")"; ObjectId = (New-DemoGuid "obj|$($r[0])"); ObjectType = $r[1]; CanDelegate = $false; Description = $null; ConditionVersion = $null; Condition = $null } }
Save-DemoJson 'rbac-workspace.json' @(foreach ($r in $roleSpec) { & $asRole $wsId $r })
Save-DemoJson 'rbac-resourcegroup.json' @(foreach ($r in @($roleSpec | Where-Object { $_[2] -in @('Owner', 'Contributor', 'Logic App Contributor') })) { & $asRole "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup" $r })
Save-DemoJson 'sentinel-data-lake.json' @([ordered]@{ id = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.SentinelPlatformServices/sentinelPlatformServices/default"; name = 'default'; location = $region; resourceGroup = $resourceGroup; subscriptionId = $subscriptionId
        properties = [ordered]@{ provisioningState = 'Succeeded' }; identity = [ordered]@{ principalId = (New-DemoGuid 'lake-mi'); tenantId = $tenantId; type = 'SystemAssigned' }
        systemData = [ordered]@{ lastModifiedByType = 'User'; lastModifiedAt = (Format-DemoTime $asOfUtc.AddDays(-160)); lastModifiedBy = 'secops@contoso.com'; createdByType = 'User'; createdAt = (Format-DemoTime $asOfUtc.AddDays(-160)); createdBy = 'secops@contoso.com' } })
Save-DemoJson 'available-service-tiers.json' @(
    [ordered]@{ serviceTier = 'PerGB2018'; enabled = (-not $commitmentGb) }
    [ordered]@{ serviceTier = 'CapacityReservation'; capacityReservationLevel = $(if ($commitmentGb) { $commitmentGb } else { 100 }); enabled = [bool]$commitmentGb }
    [ordered]@{ serviceTier = 'Free'; enabled = $false }
)
# UK South public list prices in GBP, as the Retail Prices API published
# them on 2026-10-14: the simplified Microsoft Sentinel meters (service
# 'Sentinel'), every commitment tier's price a day, and the classic Log
# Analytics meters.
$listPrices = @(
    @('Sentinel', 'Pay-as-you-go Analysis', '1 GB', 4.0605), @('Sentinel', 'Basic Logs Analysis', '1 GB', 0.8529)
    @('Sentinel', 'Classic Auxiliary Logs Analysis', '1 GB', 0.0472), @('Sentinel', 'Data lake ingestion Data Processed', '1 GB', 0.0472)
    @('Sentinel', 'Data processing Data Processed', '1 GB', 0.0943), @('Sentinel', 'Data lake storage Data Stored', '1 GB/Month', 0.0181)
    ,@('Sentinel', 'Data lake query Data Analyzed', '1 GB', 0.0047)
    @('Log Analytics', 'Analytics Logs Data Ingestion', '1 GB', 2.1737), @('Log Analytics', 'Analytics Logs Data Analyzed', '1 GB', 1.7359)
    ,@('Log Analytics', 'Analytics Logs Data Retention', '1 GB/Month', 0.0981)
)
$tierList = [ordered]@{ 50 = 152.1284; 100 = 279.2558; 200 = 517.0006; 300 = 754.7455; 400 = 978.6483; 500 = 1193.4413; 1000 = 2339.7109; 2000 = 4528.4728; 5000 = 10896.6376; 10000 = 20981.9238; 25000 = 50426.4312; 50000 = 96796.1055 }
$priceRow = { param($Service, $Meter, $Unit, $Price) [ordered]@{ currencyCode = 'GBP'; tierMinimumUnits = 0.0; retailPrice = $Price; unitPrice = $Price; armRegionName = $region; location = 'UK South'; meterName = $Meter; productName = $Service; serviceName = $Service; unitOfMeasure = $Unit; type = 'Consumption' } }
Save-DemoJson 'retail-prices.json' ([ordered]@{ FetchedAtUtc = (Format-DemoTime $asOfUtc.AddMinutes(-1)); Region = $region; Currency = 'GBP'; CurrencySource = 'Region'; Services = @('Sentinel', 'Log Analytics')
        Prices = @(@(foreach ($p in $listPrices) { & $priceRow $p[0] $p[1] $p[2] $p[3] }) + @(foreach ($kv in $tierList.GetEnumerator()) { & $priceRow 'Sentinel' "$($kv.Key) GB Commitment Tier Capacity Reservation" '1/Day' $kv.Value })) })

# What's new: the demo's own items, dated in the months before the demo's
# day (the fixture's are marked as fixture items and dated for its own run).
$monthAgo = { param([int] $m) $asOfUtc.AddMonths(-$m).ToString('yyyy-MM') }
$sentinelNews = 'https://learn.microsoft.com/en-us/azure/sentinel/whats-new'
$xdrNews = 'https://learn.microsoft.com/en-us/defender-xdr/whats-new'
$newsItem = { param($Product, $Month, $Title, $Status, $Summary, $Link, $Deadline) [ordered]@{ Product = $Product; Month = $Month; Title = $Title; Status = $Status; Summary = $Summary; Details = @(); Link = $Link; LearnMore = $null; Deadline = $Deadline } }
$newsItems = @(
    (& $newsItem 'Microsoft Sentinel' (& $monthAgo 1) 'Call to action: move playbooks to the new incident trigger before 31 Mar 2027' 'Action needed' 'Playbooks on the old incident trigger stop running after the date. Move them to the new trigger and test each one.' "$sentinelNews#call-to-action" '2027-03')
    (& $newsItem 'Microsoft Sentinel' (& $monthAgo 1) 'UEBA behaviour layer is now generally available' 'Generally available' 'UEBA behaviours summarise raw logs into entity activity that hunting and detections can query.' "$sentinelNews#ueba" $null)
    (& $newsItem 'Microsoft Sentinel' (& $monthAgo 2) 'Query the data lake tier from advanced hunting (Preview)' 'Preview' 'Interactive queries over the data lake tier, beside the analytics tier, from the same hunting page.' "$sentinelNews#data-lake" $null)
    (& $newsItem 'Microsoft Sentinel' (& $monthAgo 4) 'Microsoft Sentinel in the Azure portal to be retired' 'Retiring' 'Microsoft Sentinel moves to the Defender portal. Plan the move of workbooks, automation and access before the date.' "$sentinelNews#portal" '2027-03')
    (& $newsItem 'Microsoft Defender XDR' (& $monthAgo 1) 'Custom detection rules support near real-time frequency' 'Preview' 'Custom detections can run continuously instead of on a schedule.' "$xdrNews#custom-detections" $null)
    (& $newsItem 'Microsoft Defender XDR' (& $monthAgo 3) 'Incident queue filters for sensitivity labels' 'Update' 'Filter the incident queue by the sensitivity labels of the data involved.' "$xdrNews#incident-queue" $null)
)
Save-DemoJson 'whats-new.json' ([ordered]@{ FetchedUtc = (Format-DemoTime $asOfUtc.AddMinutes(-2)); Months = 12
        Sources = @([ordered]@{ Product = 'Microsoft Sentinel'; Url = $sentinelNews; Ok = $true; Error = $null; Items = 4 }, [ordered]@{ Product = 'Microsoft Defender XDR'; Url = $xdrNews; Ok = $true; Error = $null; Items = 2 })
        Items = $newsItems })

# The rest from the fixture, under the demo's names.
$rename = [ordered]@{ 'law-sentinel-test' = $WorkspaceName; 'rg-sentinel-test' = $resourceGroup; '/resourceGroups/rg-test/' = "/resourceGroups/$resourceGroup/"; '00000000-0000-0000-0000-000000000001' = $subscriptionId; '00000000-0000-0000-0000-000000000000' = $subscriptionId; 'example.test' = 'contoso.com'; 'Sentinel Test' = 'Contoso Security Production' }
foreach ($f in @(Get-ChildItem -LiteralPath $fixtureRaw -Filter '*.json')) {
    $dest = Join-Path $raw $f.Name
    if (Test-Path -LiteralPath $dest) { continue }
    if ($f.Name -in @('gap-analysis.json', 'gap-checks.json', 'maturity.json', 'cost-estimate.json', 'run-context.json', 'rule-table-references.json', 'template-table-references.json', 'custom-detection-table-references.json')) { continue }
    $text = Get-Content -LiteralPath $f.FullName -Raw
    foreach ($k in $rename.Keys) { $text = $text.Replace($k, $rename[$k]) }
    Set-Content -LiteralPath $dest -Value $text -Encoding utf8NoBOM
}
# The Microsoft Sentinel solution's SKU, which the pages read the pricing
# model from: simplified (Unified), as on any workspace since July 2023.
$solPath = Join-Path $raw 'solutions-installed.json'
if (Test-Path -LiteralPath $solPath) {
    $sols = @(Get-Content -LiteralPath $solPath -Raw | ConvertFrom-Json -Depth 32)
    foreach ($sol in $sols) {
        if ($sol -and $sol.PSObject.Properties['plan'] -and [string]$sol.plan.product -eq 'OMSGallery/SecurityInsights' -and $sol.PSObject.Properties['properties']) {
            $sol.properties | Add-Member -NotePropertyName sku -NotePropertyValue ([pscustomobject]@{ name = 'Unified' }) -Force
        }
    }
    ConvertTo-Json -InputObject @($sols) -Depth 32 | Set-Content -LiteralPath $solPath -Encoding utf8NoBOM
}

# The run's context.
$started = $asOfUtc
Save-DemoJson 'run-context.json' ([ordered]@{ SubscriptionId = $subscriptionId; TenantId = $tenantId; Account = 'sp-blueprint-reader'; AccountType = 'ServicePrincipal'; ResourceGroup = $resourceGroup; WorkspaceName = $WorkspaceName; WorkspaceResourceId = $wsId
        StartedAtUtc = (Format-DemoTime $started); CompletedAtUtc = (Format-DemoTime $started.AddMinutes(14)); BlueprintVersion = [string](Import-PowerShellDataFile -LiteralPath (Join-Path $RepoPath 'Modules/iSOCBlueprint/iSOCBlueprint.psd1')).ModuleVersion
        AzPSVersion = '5.1.0'; IncludePreview = $true; LookbackDays = $L; RecentDays = $recentDays; DailyDays = $L; Demo = $true })

# ---------------------------------------------------------------------------
# The engine's own steps over the demo inventory
# ---------------------------------------------------------------------------
$rulesForRefs = @(Get-Content -LiteralPath (Join-Path $raw 'alert-rules.json') -Raw | ConvertFrom-Json -Depth 64)
$templatesForRefs = @(Get-Content -LiteralPath (Join-Path $raw 'alert-rule-templates.json') -Raw | ConvertFrom-Json -Depth 64)
$detectionsForRefs = @(Get-Content -LiteralPath (Join-Path $raw 'defender-custom-detections.json') -Raw | ConvertFrom-Json -Depth 64)
Save-DemoJson 'rule-table-references.json' @(Get-RuleTableReferences -AlertRules $rulesForRefs)
Save-DemoJson 'template-table-references.json' @(Get-TemplateTableReferences -Templates $templatesForRefs -AlertRules $rulesForRefs)
Save-DemoJson 'custom-detection-table-references.json' @(Get-CustomDetectionTableReferences -Detections $detectionsForRefs)

. (Join-Path $engine 'Private/Get-SentinelCostEstimate.ps1')
Save-DemoJson 'cost-estimate.json' (Get-SentinelCostEstimate -InputRoot $raw -ResourcesRoot $resources)
. (Join-Path $engine 'Private/Get-SentinelGap.ps1')
$outcomes = [System.Collections.Generic.List[object]]::new()
$findings = Get-SentinelGap -InputRoot $raw -ResourcesRoot $resources -RulesPath (Join-Path $resources 'best-practices.json') -GapChecksPath (Join-Path $engine 'Private/GapChecks.ps1') -OutcomeCollector $outcomes
Save-DemoJson 'gap-analysis.json' @($findings)
Save-DemoJson 'gap-checks.json' $outcomes.ToArray()
. (Join-Path $engine 'Private/Get-SentinelMaturity.ps1')
Save-DemoJson 'maturity.json' (Get-SentinelMaturity -InputRoot $raw -ResourcesRoot $resources -CriteriaPath (Join-Path $resources 'maturity-criteria.json') -GapOutcomes $outcomes.ToArray() -TargetLevel 3)

# ---------------------------------------------------------------------------
# Optionally the report and the dashboard
# ---------------------------------------------------------------------------
$bundle = $null
if ($Build) {
    # The renderer and the build are not written for strict mode, which a
    # child script inherits from this one.
    Set-StrictMode -Off
    & (Join-Path $engine 'Convert-SentinelInventoryToMarkdown.ps1') -WorkspaceName $WorkspaceName -InputRoot $OutputPath -OutputRoot $OutputPath -ResourcesRoot $resources -InformationAction SilentlyContinue *> $null
    $bundle = & (Join-Path $engine 'SharePoint/Build-SentinelDocsSite.ps1') -Source $OutputPath -SkipWhatsNew 6> $null
    # The maturity trend reads the history the publisher keeps on the site,
    # which a local bundle lacks; the demo carries a quarter's climb to
    # today's score so the panel shows: twelve runs about a week apart, the
    # first 90 days back, so each of the Progress tab's baselines (previous
    # run, 7, 30 and 90 days) has a run. Areas climb at their own pace
    # (weights, in area order): some faster, some held at their score, one
    # slipping, so the Progress tab's area bars show each kind of change.
    $maturity = Get-Content -LiteralPath (Join-Path $raw 'maturity.json') -Raw | ConvertFrom-Json -Depth 32
    if ($bundle -and $maturity -and $null -ne $maturity.overall.score) {
        $now = [double]$maturity.overall.score
        $areaPace = @(1.6, 1.2, 0, 1.0, 0.8, 0, 1.4, 0.6, 0, -0.4, 0.9)
        $runAgo = { param([int] $w) [int][math]::Round(7.5 * $w, [System.MidpointRounding]::AwayFromZero) }
        $entries = for ($w = 12; $w -ge 0; $w--) {
            $lift = 0.55 * $w / 12.0
            $when = Format-DemoTime $asOfUtc.AddDays(-(& $runAgo $w))
            [ordered]@{ publishedUtc = $when; bundleBuiltUtc = $when; targetLevel = [int]$maturity.targetLevel
                overall = [ordered]@{ score = [math]::Round([math]::Max(1.0, $now - $lift + $(if ($w -gt 0) { Get-DemoBetween -0.04 0.04 } else { 0 })), 2); level = [int]$maturity.overall.level }
                areas = @($i = 0; foreach ($a in @($maturity.areas)) {
                        $pace = $areaPace[$i++ % $areaPace.Count]
                        [ordered]@{ id = [string]$a.id; score = $(if ($null -ne $a.score) { [math]::Round([math]::Min(5.0, [math]::Max(1.0, [double]$a.score - $lift * $pace)), 2) } else { $null }) }
                    }) }
        }
        Set-Content -LiteralPath (Join-Path $bundle 'maturity-history.json') -Value (ConvertTo-Json -InputObject ([ordered]@{ entries = @($entries) }) -Depth 16) -Encoding utf8NoBOM
    }
    # The Progress tab compares runs; the demo carries the same quarter of
    # runs, each a step behind today's on the same climb: findings
    # that have since been fixed still firing, fewer rules enabled, fewer
    # criteria met, less ATT&CK coverage, tables no detection read yet. Not
    # all of it is better: one warning is new this week and one criterion
    # met until last week is a gap now.
    $progressPath = if ($bundle) { Join-Path $bundle 'progress.json' } else { $null }
    if ($progressPath -and (Test-Path -LiteralPath $progressPath)) {
        . (Join-Path $engine 'SharePoint/Private/Get-SacProgress.ps1')
        $now = Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json -Depth 32
        $firing = @($now.sets.findings | ForEach-Object { [string]$_.id })
        $fixed = @((Get-Content -LiteralPath (Join-Path $resources 'best-practices.json') -Raw | ConvertFrom-Json -Depth 16).rules |
            Where-Object { $firing -notcontains [string]$_.id -and $_.severity -in 'Critical', 'Warning' } | Select-Object -First 8 |
            ForEach-Object { [ordered]@{ id = [string]$_.id; severity = [string]$_.severity; title = [string]$_.title } })
        $nowRules = @($now.sets.rules); $nowTech = @($now.sets.techniques); $nowTables = @($now.sets.tables); $nowUncovered = @($now.sets.uncovered)
        $coveredNow = @($nowTables | Where-Object { $nowUncovered -notcontains $_ })
        $metNow = @($now.sets.criteria | Where-Object { $_.status -eq 'M' } | ForEach-Object { [string]$_.id })
        $newId = [string](@($now.sets.findings | Where-Object { $_.severity -eq 'Warning' }) | Select-Object -Last 1).id
        $slipped = [string](@($now.sets.criteria | Where-Object { $_.status -eq 'G' }) | Select-Object -First 1).id
        $records = for ($w = 12; $w -ge 1; $w--) {
            $f = $w / 12.0
            $rules = @($nowRules | Select-Object -First ($nowRules.Count - [int][math]::Round($nowRules.Count * 0.3 * $f)))
            $tech = @($nowTech | Select-Object -First ($nowTech.Count - [int][math]::Round($nowTech.Count * 0.25 * $f)))
            $findings = @($now.sets.findings | Where-Object { [string]$_.id -ne $newId }) + @($fixed | Select-Object -First ([int][math]::Round($fixed.Count * $f)))
            $wasGap = @($metNow | Select-Object -First ([int][math]::Round($metNow.Count * 0.3 * $f)))
            $criteria = @($now.sets.criteria | ForEach-Object { [ordered]@{ id = [string]$_.id; name = [string]$_.name; status = $(if ([string]$_.id -eq $slipped) { 'M' } elseif ($wasGap -contains [string]$_.id) { 'G' } else { [string]$_.status }) } })
            $uncovered = @($nowUncovered) + @($coveredNow | Select-Object -Last ([int][math]::Round($coveredNow.Count * 0.2 * $f)))
            $bySev = { param($s) @($findings | Where-Object { $_.severity -eq $s }).Count }
            $m = $now.metrics
            $areas = [ordered]@{}
            foreach ($a in @($entries[12 - $w].areas)) { $areas[[string]$a.id] = $a.score }
            [ordered]@{
                schemaVersion = 1
                date          = $asOfUtc.AddDays(-(& $runAgo $w)).ToString('yyyy-MM-dd')
                generatedUtc  = $asOfUtc.AddDays(-(& $runAgo $w)).ToString('yyyy-MM-dd HH:mm') + ' UTC'
                windowDays    = $now.windowDays
                currency      = $now.currency
                metrics       = [ordered]@{
                    maturityScore     = [double]$entries[12 - $w].overall.score
                    maturityLevel     = $m.maturityLevel
                    criteriaMet       = @($criteria | Where-Object { $_.status -eq 'M' }).Count
                    criteriaGap       = @($criteria | Where-Object { $_.status -eq 'G' }).Count
                    findings          = $findings.Count
                    findingsCritical  = & $bySev 'Critical'
                    findingsWarning   = & $bySev 'Warning'
                    findingsInfo      = & $bySev 'Info'
                    rulesEnabled      = [int]$m.rulesEnabled - ($nowRules.Count - $rules.Count)
                    rulesTotal        = $m.rulesTotal
                    customDetections  = $m.customDetections
                    techniquesCovered = $tech.Count
                    tacticsCovered    = $m.tacticsCovered
                    tacticsTotal      = $m.tacticsTotal
                    connectors        = $m.connectors
                    tablesIngesting   = $nowTables.Count
                    uncoveredTables   = $uncovered.Count
                    uncoveredGb       = [math]::Round([double]$m.uncoveredGb * (1 + 0.6 * $f), 2)
                    totalGb           = $m.totalGb
                    monthlyCost       = [math]::Round([double]$m.monthlyCost * (1 - 0.05 * $f), 2)
                    dailyGb           = [math]::Round([double]$m.dailyGb * (1 - 0.05 * $f), 2)
                    openIncidents     = [int]$m.openIncidents + [int][math]::Round(12 * $f)
                    mttrMinutes       = [math]::Round([double]$m.mttrMinutes * (1 + 0.4 * $f), 1)
                }
                areas         = $areas
                sets          = [ordered]@{ findings = $findings; criteria = $criteria; rules = $rules; techniques = $tech; tables = $nowTables; uncovered = $uncovered }
            }
        }
        $history = Merge-SacProgressHistory -History $null -Records (@($records) + , $now) -Days 90
        Set-Content -LiteralPath (Join-Path $bundle 'progress-history.json') -Value (ConvertTo-Json -InputObject $history -Depth 32 -Compress) -Encoding utf8NoBOM
    }
}

$avgDay = [math]::Round((($dayTotal[0..($window30 - 1)]) | Measure-Object -Average).Average, 1)
[pscustomobject]@{
    Path    = $OutputPath
    Raw     = $raw
    Bundle  = $bundle
    Summary = [pscustomobject]@{
        AverageGbPerDay = $avgDay
        CommitmentTierGb = $commitmentGb
        Tables          = $tableSpec.Count
        Rules           = $alertRules.Count
        EnabledRules    = @($alertRules | Where-Object { $_.properties.enabled }).Count
        Templates       = $templates.Count
        HuntingQueries  = @($hunting).Count
        CustomDetections = $detections.Count
        Playbooks       = $playbooks.Count
        Workbooks       = @($workbooks).Count
        Watchlists      = @($watchlists).Count
        AutomationRules = $automation.Count
        Alerts          = [long](@($volumes | ForEach-Object { $_.Alerts }) | Measure-Object -Sum).Sum
        Incidents       = $incidents.Count
        Findings        = @($findings).Count
    }
}
