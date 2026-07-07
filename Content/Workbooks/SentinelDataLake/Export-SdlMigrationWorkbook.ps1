#
# Sentinel-As-Code/Workbooks/SentinelDataLake/Export-SdlMigrationWorkbook.ps1
#
# Created by noodlemctwoodle on 18/05/2026.
#

<#
.SYNOPSIS
    Exports every dataset behind the Sentinel Data Lake Migration workbook to a
    single multi-sheet Excel file (.xlsx).

.DESCRIPTION
    The Sentinel Data Lake Migration workbook (workbook.json) runs many
    independent KQL and ARM queries that the portal cannot bundle into a single
    Excel export - each grid only exports its own sheet. This script mirrors
    every query against the same workspace and writes one .xlsx with one named
    sheet per dataset:

      • Migration Report     - per-table classification, costs, savings, status
      • Exclusions           - tables that cannot move to Lake (UEBA/Sentinel/etc.)
      • Deprecation Warnings - Microsoft-announced table retirements (e.g. TI)
      • Classic V1 Tables    - _CL tables on legacy MMA ingestion path
      • Top 10 Savings       - highest-impact migration candidates
      • Query-Weighted       - LAQueryLogs-based per-table cost model
      • Rules Inventory      - every enabled Sentinel analytic rule
      • Indirection Rules    - rules using ASIM/_GetWatchlist/externaldata/custom fns
      • Workspace Functions  - saved KQL functions in the workspace
      • Function -> Rules    - which rules call which workspace functions
      • XDR Per-Table        - Defender XDR Advanced Hunting cost model (optional)
      • Pricing Assumptions  - every pricing input used by the export

    Read-only: never calls PATCH/PUT, never mutates the workspace. Pricing logic
    mirrors the workbook exactly.

.PARAMETER SubscriptionId
    Azure Subscription ID containing the Log Analytics workspace.

.PARAMETER ResourceGroupName
    Resource group containing the workspace.

.PARAMETER WorkspaceName
    Log Analytics workspace name (Sentinel-enabled).

.PARAMETER OutputPath
    Path for the output .xlsx. Defaults to
    SdlMigrationExport_<workspace>_<yyyyMMdd-HHmm>.xlsx alongside the script
    ($PSScriptRoot), so the file lands in a predictable location regardless
    of the caller's current working directory.

.PARAMETER TimeRangeDays
    Ingestion analysis window. Default: 30. Matches the workbook's TimeRange.

.PARAMETER QueryLookbackDays
    LAQueryLogs lookback for the Query-Weighted sheet. Default: 30.

.PARAMETER AlertActivityDays
    SecurityAlert lookback for alert-activity stats. Default: 30.

.PARAMETER XdrLookbackDays
    Defender XDR lookback for the XDR cost model. Default: 30. Set to 0 to skip XDR.

.PARAMETER PricingModel
    Analytics tier commitment level. One of PAYG, CT50, CT100, CT200, CT300,
    CT400, CT500, CT1000, CT2000, CT5000. Default: PAYG.

.PARAMETER EffectiveAnalyticsRate
    Override Analytics $/GB rate. 0 = use the pricing model rate.

.PARAMETER Currency
    Currency label for column headers (display only). Default: USD.

.PARAMETER LakeIngestPricePerGB
    Sentinel Data Lake ingestion price per GB. Default: 0.05.

.PARAMETER LakeProcessingPricePerGB
    Sentinel Data Lake data-processing price per GB. Default: 0.10.

.PARAMETER LakeStoragePricePerGBMonth
    Lake storage price per GB-month. Default: 0.023.

.PARAMETER LakeQueryPricePerGB
    Lake KQL query scan price per GB. Default: 0.005.

.PARAMETER TargetLakeRetentionDays
    Lake-tier retention used for storage cost. Default: 365.

.PARAMETER CompressionRatio
    Storage compression ratio applied to lake storage cost. Default: 10.

.PARAMETER ThrottleMs
    Milliseconds between ARM calls. Default: 200.

.EXAMPLE
    .\Export-SdlMigrationWorkbook.ps1 `
        -SubscriptionId    "<sub>" `
        -ResourceGroupName "<rg>" `
        -WorkspaceName     "<ws>"

    Export with all defaults: 30-day window, PAYG pricing, USD.

.EXAMPLE
    .\Export-SdlMigrationWorkbook.ps1 `
        -SubscriptionId          "<sub>" `
        -ResourceGroupName       "<rg>" `
        -WorkspaceName           "<ws>" `
        -PricingModel             CT200 `
        -Currency                 GBP `
        -EffectiveAnalyticsRate   2.18 `
        -OutputPath               "./sentinel-lake-prod.xlsx"

    Export with a CT200 commitment tier model, GBP cost labels, and a
    custom output path. Uses a POSIX relative path so the example
    copy-pastes cleanly on Windows, macOS, and Linux; substitute any
    absolute or relative path your environment prefers.

.NOTES
    Authentication : Uses the current Az context (Connect-AzAccount).
    Requires       : PowerShell 7+, Az.Accounts, Az.OperationalInsights, ImportExcel
    Tables API     : 2023-09-01
    AlertRules API : 2025-09-01
    Functions API  : 2020-08-01 (savedSearches)
    Author         : Toby G
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$WorkspaceName,

    [string]$OutputPath,

    [ValidateRange(1, 365)]
    [int]$TimeRangeDays = 30,

    [ValidateRange(1, 365)]
    [int]$QueryLookbackDays = 30,

    [ValidateRange(1, 365)]
    [int]$AlertActivityDays = 30,

    [ValidateRange(0, 365)]
    [int]$XdrLookbackDays = 30,

    [ValidateSet('PAYG', 'CT50', 'CT100', 'CT200', 'CT300', 'CT400', 'CT500', 'CT1000', 'CT2000', 'CT5000')]
    [string]$PricingModel = 'PAYG',

    [ValidateRange(0, 100)]
    [double]$EffectiveAnalyticsRate = 0,

    # $Currency is interpolated into KQL projected column names like
    # AnalyticsCost_$Currency / LakeCost_$Currency. KQL identifiers
    # allow only letters / digits / underscores, so an unconstrained
    # value (e.g. 'US Dollars') would generate invalid KQL. ISO 4217
    # currency codes are exactly three uppercase letters - restrict
    # to that shape to prevent KQL-injection-style breakage.
    [ValidatePattern('^[A-Z]{3}$')]
    [string]$Currency = 'USD',

    [ValidateRange(0, 10)]
    [double]$LakeIngestPricePerGB = 0.05,

    [ValidateRange(0, 10)]
    [double]$LakeProcessingPricePerGB = 0.10,

    [ValidateRange(0, 10)]
    [double]$LakeStoragePricePerGBMonth = 0.023,

    [ValidateRange(0, 10)]
    [double]$LakeQueryPricePerGB = 0.005,

    [ValidateRange(30, 4383)]
    [int]$TargetLakeRetentionDays = 365,

    [ValidateRange(1, 50)]
    [double]$CompressionRatio = 10,

    # Inter-call throttle in milliseconds. 0 disables the sleep.
    # Capped at 60_000 (one minute) because anything beyond that
    # turns the export into a multi-hour run on a busy workspace
    # and almost certainly indicates a typo. ValidateRange ensures
    # Start-Sleep -Milliseconds never receives a negative value at
    # runtime, which throws and aborts the export before any work.
    [ValidateRange(0, 60000)]
    [int]$ThrottleMs = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Now = Get-Date

#region Prerequisites ──────────────────────────────────────────────────────────

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "This script requires PowerShell 7+. Current: $($PSVersionTable.PSVersion). Install from https://aka.ms/powershell"
}

foreach ($mod in @('Az.Accounts', 'Az.OperationalInsights', 'ImportExcel')) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        throw "$mod module is not installed. Run: Install-Module $mod -Scope CurrentUser"
    }
}

$azContext = Get-AzContext -ErrorAction SilentlyContinue
if (-not $azContext) {
    throw "No Azure context found. Run Connect-AzAccount before executing this script."
}
if ($azContext.Subscription.Id -ne $SubscriptionId) {
    Write-Host "  Switching context to subscription $SubscriptionId..." -ForegroundColor DarkGray
    # Re-capture the context returned by Set-AzContext rather than
    # leaving $azContext pointing at the pre-switch state - otherwise
    # the banner below would print the previous context's account /
    # subscription identifiers.
    $azContext = Set-AzContext -SubscriptionId $SubscriptionId
}

Write-Host "Sentinel Data Lake Migration Export" -ForegroundColor Cyan
Write-Host "  Authenticated as : $($azContext.Account.Id)" -ForegroundColor DarkGray
Write-Host "  Subscription     : $SubscriptionId" -ForegroundColor DarkGray
Write-Host "  Workspace        : $ResourceGroupName / $WorkspaceName" -ForegroundColor DarkGray

#endregion

#region Helpers ────────────────────────────────────────────────────────────────

$script:TablesApiVersion       = '2023-09-01'
$script:AlertRulesApiVersion   = '2025-09-01'
$script:SavedSearchesApiVersion = '2020-08-01'
$script:WorkspaceApiVersion    = '2023-09-01'
$script:WorkspaceCustomerId    = $null

# Invariant-culture formatter for numerics interpolated into KQL.
# Default PowerShell string interpolation uses the current thread culture,
# so a double like 1.5 renders as "1,5" on de-DE / fr-FR / it-IT machines.
# KQL toreal() expects US-format ("1.5"), so a culture-localised value
# parses incorrectly (or fails the query). Every numeric that lands in
# a KQL here-string in this script goes through Format-KqlNumber instead
# of being interpolated directly.
function Format-KqlNumber {
    param([double]$Value)
    $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-BaseUri { "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName" }

function Invoke-Arm {
    param ([string]$Path, [string]$Method = 'GET', [object]$Payload, [int]$Retries = 3)

    # Dispatch on whether the caller passed a relative ARM path
    # (e.g. /subscriptions/.../tables?api-version=...) or an
    # absolute URI (e.g. https://management.azure.com/...). ARM
    # nextLink values are always absolute URIs; Get-BaseUri-derived
    # paths are always relative. Invoke-AzRestMethod -Path accepts
    # both in current Az versions but the documentation only
    # commits to PartialUri (relative); using -Uri for absolute
    # input is the explicit, version-stable choice.
    $params = @{ Method = $Method }
    if ($Path -match '^https?://') {
        $params['Uri'] = $Path
    } else {
        $params['Path'] = $Path
    }
    if ($Payload) { $params['Payload'] = ($Payload | ConvertTo-Json -Depth 20) }
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $response = Invoke-AzRestMethod @params -ErrorAction Stop
            if ($response.StatusCode -ge 400) {
                if ($response.StatusCode -in @(429, 503, 504) -and $attempt -lt $Retries) {
                    $wait = [Math]::Pow(2, $attempt)
                    Write-Warning "  ARM HTTP $($response.StatusCode) - retrying in ${wait}s ($attempt/$Retries)"
                    Start-Sleep -Seconds $wait
                    continue
                }
                throw "ARM $Method $Path returned HTTP $($response.StatusCode): $($response.Content)"
            }
            return ($response.Content | ConvertFrom-Json -Depth 50)
        }
        catch {
            if ($attempt -lt $Retries) {
                $wait = [Math]::Pow(2, $attempt)
                Write-Warning "  ARM exception (attempt $attempt/$Retries): $($_.Exception.Message) - retrying in ${wait}s"
                Start-Sleep -Seconds $wait
                continue
            }
            throw
        }
        finally { Start-Sleep -Milliseconds $ThrottleMs }
    }
}

# Follows nextLink pagination on ARM list responses. Without this,
# any list endpoint that exceeds Azure's page size (typically 100
# items) silently truncates and downstream classification misses
# whatever fell off the end. Matches the existing pagination idiom
# in Tools/Invoke-DCRWatchlistSync.ps1.
function Get-ArmList {
    param([string]$Path)
    $items = @()
    $next  = $Path
    while ($next) {
        $page = Invoke-Arm -Path $next
        if ($page -and $page.PSObject.Properties['value']) {
            $items += $page.value
        }
        $next = if ($page -and $page.PSObject.Properties['nextLink']) { $page.nextLink } else { $null }
    }
    return $items
}

function Invoke-Kql {
    param ([string]$Query)
    if (-not $script:WorkspaceCustomerId) {
        $ws = Invoke-Arm -Path "$(Get-BaseUri)?api-version=$script:WorkspaceApiVersion"
        $script:WorkspaceCustomerId = $ws.properties.customerId
        if (-not $script:WorkspaceCustomerId) {
            throw "Could not resolve workspace customerId (GUID) for $WorkspaceName."
        }
    }
    $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceCustomerId -Query $Query -ErrorAction Stop
    return $result.Results
}

function ConvertTo-KqlList {
    param ([string[]]$Items)
    if (-not $Items -or $Items.Count -eq 0) { return "''" }
    return ($Items | ForEach-Object { "'$_'" }) -join ','
}

function Get-PricingRate {
    param ([string]$Model)
    switch ($Model) {
        'CT50'   { return 3.23 }
        'CT100'  { return 2.96 }
        'CT200'  { return 2.85 }
        'CT300'  { return 2.77 }
        'CT400'  { return 2.73 }
        'CT500'  { return 2.61 }
        'CT1000' { return 2.41 }
        'CT2000' { return 2.22 }
        'CT5000' { return 2.11 }
        default  { return 4.30 }   # PAYG
    }
}

function Write-Step { param ([string]$Message) Write-Host "  $Message" -ForegroundColor DarkGray }

#endregion

#region Step 1 - Tables ARM API → per-table sub-type and plan ──────────────────

Write-Host ""
Write-Host "Step 1/6 - Tables ARM API" -ForegroundColor Yellow
$allTables = Get-ArmList -Path "$(Get-BaseUri)/tables?api-version=$script:TablesApiVersion"

$classicV1     = @($allTables | Where-Object {
    $_.properties.schema.tableSubType -eq 'Classic' -and $_.name -like '*_CL'
} | ForEach-Object { $_.name })

$dcrCustom     = @($allTables | Where-Object {
    $_.properties.schema.tableSubType -eq 'DataCollectionRuleBased' -and $_.name -like '*_CL'
} | ForEach-Object { $_.name })

$basicPlan     = @($allTables | Where-Object {
    $_.properties.PSObject.Properties['plan'] -and $_.properties.plan -eq 'Basic'
} | ForEach-Object { $_.name })

$auxiliaryPlan = @($allTables | Where-Object {
    $_.properties.PSObject.Properties['plan'] -and $_.properties.plan -eq 'Auxiliary'
} | ForEach-Object { $_.name })

Write-Step "Tables: $($allTables.Count) total | Classic V1: $($classicV1.Count) | DCR _CL: $($dcrCustom.Count) | Basic: $($basicPlan.Count) | Auxiliary: $($auxiliaryPlan.Count)"

$classicV1List     = ConvertTo-KqlList -Items $classicV1
$dcrCustomList     = ConvertTo-KqlList -Items $dcrCustom
$basicPlanList     = ConvertTo-KqlList -Items $basicPlan
$auxiliaryPlanList = ConvertTo-KqlList -Items $auxiliaryPlan

#endregion

#region Step 2 - Alert Rules ARM API → rules dataset ───────────────────────────

Write-Host ""
Write-Host "Step 2/6 - Alert Rules ARM API" -ForegroundColor Yellow
$rulesPath = "$(Get-BaseUri)/providers/Microsoft.SecurityInsights/alertRules?api-version=$script:AlertRulesApiVersion"
$allRules = Get-ArmList -Path $rulesPath

$rulesInventory = $allRules | ForEach-Object {
    $p = $_.properties
    [pscustomobject]@{
        RuleName    = ($p.PSObject.Properties['displayName']) ? $p.displayName : $_.name
        Kind        = $_.kind
        Enabled     = ($p.PSObject.Properties['enabled']) ? $p.enabled : $null
        Severity    = ($p.PSObject.Properties['severity']) ? $p.severity : $null
        Tactics     = ($p.PSObject.Properties['tactics']) ? ($p.tactics -join '; ') : ''
        Techniques  = ($p.PSObject.Properties['techniques']) ? ($p.techniques -join '; ') : ''
        QueryFrequency = ($p.PSObject.Properties['queryFrequency']) ? $p.queryFrequency : ''
        QueryPeriod    = ($p.PSObject.Properties['queryPeriod']) ? $p.queryPeriod : ''
        LastModified   = ($p.PSObject.Properties['lastModifiedUtc']) ? $p.lastModifiedUtc : ''
        QueryText      = ($p.PSObject.Properties['query']) ? $p.query : ''
    }
}

$enabledRules = $rulesInventory | Where-Object { $_.Enabled -eq $true }
Write-Step "Rules: $($rulesInventory.Count) total | enabled: $($enabledRules.Count)"

#endregion

#region Step 3 - Saved Searches (Workspace Functions) ──────────────────────────

Write-Host ""
Write-Host "Step 3/6 - Workspace KQL Functions" -ForegroundColor Yellow
$functionsPath = "$(Get-BaseUri)/savedSearches?api-version=$script:SavedSearchesApiVersion"
$allSavedSearches = Get-ArmList -Path $functionsPath
$workspaceFunctions = @()
foreach ($s in $allSavedSearches) {
    $p = $s.properties
    $hasFn = ($p.PSObject.Properties['functionAlias']) -and $p.functionAlias
    if (-not $hasFn) { continue }
    $workspaceFunctions += [pscustomobject]@{
        FunctionAlias   = $p.functionAlias
        DisplayName     = ($p.PSObject.Properties['displayName']) ? $p.displayName : ''
        Category        = ($p.PSObject.Properties['category']) ? $p.category : ''
        FunctionParameters = ($p.PSObject.Properties['functionParameters']) ? $p.functionParameters : ''
        Version         = ($p.PSObject.Properties['version']) ? $p.version : ''
        QueryBody       = ($p.PSObject.Properties['query']) ? $p.query : ''
    }
}
Write-Step "Workspace functions: $($workspaceFunctions.Count)"

#endregion

#region Step 4 - Mirror the workbook's classification KQL ─────────────────────

Write-Host ""
Write-Host "Step 4/6 - Per-table classification (Migration Report)" -ForegroundColor Yellow

$effectiveRate = if ($EffectiveAnalyticsRate -gt 0) { $EffectiveAnalyticsRate } else { Get-PricingRate -Model $PricingModel }

$pricingLet = @"
let userRate = toreal('$(Format-KqlNumber $EffectiveAnalyticsRate)');
let modelRate = toreal('$(Format-KqlNumber (Get-PricingRate -Model $PricingModel))');
let priceAnalytics = iif(userRate > 0, userRate, modelRate);
let priceLakeIngest = toreal('$(Format-KqlNumber $LakeIngestPricePerGB)');
let priceLakeProc = toreal('$(Format-KqlNumber $LakeProcessingPricePerGB)');
let priceLakeStore = toreal('$(Format-KqlNumber $LakeStoragePricePerGBMonth)');
let lakeRetentionDays = toreal('$(Format-KqlNumber $TargetLakeRetentionDays)');
let compressionRatio = toreal('$(Format-KqlNumber $CompressionRatio)');
"@

$classificationLets = @"
let daysInRange = toreal($($TimeRangeDays * 86400)) / 86400.0;
let notSupportedInLake = dynamic(['AzureDiagnostics','AzureMetrics']);
let sentinelFeatureTables = dynamic(['SecurityAlert','SecurityIncident','SecurityRecommendation','ThreatIntelligenceIndicator','ThreatIntelIndicators','ThreatIntelObjects','Watchlist','SentinelHealth','SentinelAudit','HuntingBookmark','SecurityBaseline','SecurityBaselineSummary']);
let uebaTables = dynamic(['BehaviorAnalytics','IdentityInfo','UserPeerAnalytics','BehaviorAnalyticsCloudActivityLogs']);
let systemTables = dynamic(['Heartbeat','Usage','Operation','LAQueryLogs','LASummaryLogs','ProtectionStatus','ComputerGroup']);
let classicV1Tables = dynamic([$classicV1List]);
let dcrCustomTables = dynamic([$dcrCustomList]);
let basicPlanTables = dynamic([$basicPlanList]);
let auxiliaryPlanTables = dynamic([$auxiliaryPlanList]);
"@

$migrationKql = @"
$pricingLet
$classificationLets
Usage
| where TimeGenerated > ago($($TimeRangeDays)d)
| where IsBillable == true
| summarize BillableGB = sum(Quantity) / 1000.0, Solution = take_any(Solution) by DataType
| extend MonthlyGB = (BillableGB / daysInRange) * 30.0
| extend AnalyticsMonthlyCost = MonthlyGB * priceAnalytics
| extend LakeIngestCost = MonthlyGB * priceLakeIngest
       , LakeProcCost   = MonthlyGB * priceLakeProc
       , LakeStorageCost = (MonthlyGB * (lakeRetentionDays / 30.0) / compressionRatio) * priceLakeStore
| extend LakeMonthlyCost = LakeIngestCost + LakeProcCost + LakeStorageCost
| extend MonthlySaving = AnalyticsMonthlyCost - LakeMonthlyCost
       , SavingPct = iif(AnalyticsMonthlyCost > 0, round((AnalyticsMonthlyCost - LakeMonthlyCost) / AnalyticsMonthlyCost * 100.0, 1), real(0))
| extend Plan = case(
    DataType in (basicPlanTables), 'Basic',
    DataType in (auxiliaryPlanTables), 'Auxiliary',
    'Analytics')
| extend IngestionMode = case(
    DataType in (classicV1Tables), 'Classic V1',
    DataType in (dcrCustomTables), 'DCR-based',
    DataType endswith '_CL', 'Custom (unknown)',
    'Standard')
| extend Category = case(
    DataType in (notSupportedInLake), 'Not supported in Lake',
    DataType in (uebaTables), 'UEBA (Analytics-only)',
    DataType in (sentinelFeatureTables), 'Sentinel feature dependency',
    DataType in (systemTables), 'System table',
    DataType in (classicV1Tables), 'Custom log V1 (not supported)',
    Plan == 'Basic', 'Basic plan (convert first)',
    DataType endswith '_CL', 'Custom log DCR-based',
    'Supported')
| extend NotEligibleForLake = Category in ('Not supported in Lake','UEBA (Analytics-only)','Sentinel feature dependency','System table','Custom log V1 (not supported)','Basic plan (convert first)')
| extend Recommendation = case(
    Category == 'Not supported in Lake', 'Not supported - keep in Analytics',
    Category == 'UEBA (Analytics-only)', 'UEBA - keep in Analytics',
    Category == 'Sentinel feature dependency', 'Sentinel feature - keep in Analytics',
    Category == 'System table', 'System table - skip',
    Category == 'Custom log V1 (not supported)', 'Classic V1 - migrate ingestion to DCR before any tier decision',
    Category == 'Basic plan (convert first)', 'Basic plan - convert to Analytics first',
    Category == 'Custom log DCR-based' and MonthlySaving > 0, 'Eligible - DCR-based custom log',
    Category == 'Custom log DCR-based', 'DCR-based custom log - no saving at current model',
    MonthlySaving > 0, 'Eligible - candidate for Lake-only or hybrid tier',
    'No saving at current pricing')
| extend Status = case(
    Category == 'Not supported in Lake', 'Excluded',
    Category == 'UEBA (Analytics-only)', 'Excluded',
    Category == 'Sentinel feature dependency', 'Excluded',
    Category == 'System table', 'Excluded',
    Category == 'Custom log V1 (not supported)', 'Action required',
    Category == 'Basic plan (convert first)', 'Action required',
    Category == 'Custom log DCR-based' and MonthlySaving > 0, 'Eligible',
    MonthlySaving > 0, 'Eligible',
    'No saving')
| extend LakeMonthlyCost = iif(NotEligibleForLake, real(null), LakeMonthlyCost)
       , MonthlySaving   = iif(NotEligibleForLake, real(null), MonthlySaving)
       , SavingPct       = iif(NotEligibleForLake, real(null), SavingPct)
| order by MonthlySaving desc nulls last
| project Table=DataType, Solution, Category, Plan, IngestionMode, Status, Recommendation,
          GBPerMonth=round(MonthlyGB,2),
          AnalyticsCost_$Currency=round(AnalyticsMonthlyCost,2),
          LakeCost_$Currency=round(LakeMonthlyCost,2),
          MonthlySaving_$Currency=round(MonthlySaving,2),
          SavingPct
"@

$migrationReport = Invoke-Kql -Query $migrationKql
Write-Step "Migration Report: $(@($migrationReport).Count) rows"

#endregion

#region Step 5 - Derived datasets (per-table rule references, indirection) ────

Write-Host ""
Write-Host "Step 5/6 - Per-table rule references + indirection" -ForegroundColor Yellow

$tableUniverse = $migrationReport | ForEach-Object { $_.Table }
$enabledKqlRules = $enabledRules | Where-Object { $_.QueryText }

# Per-(rule, table) reference: word-boundary token match in rule body
$ruleTableRefs = @()
$tablesEsc = @{}
foreach ($t in $tableUniverse) { $tablesEsc[$t] = [regex]::Escape($t) }
foreach ($rule in $enabledKqlRules) {
    $body = $rule.QueryText
    foreach ($t in $tableUniverse) {
        $pattern = '\b' + $tablesEsc[$t] + '\b'
        if ($body -cmatch $pattern) {
            $ruleTableRefs += [pscustomobject]@{
                Table    = $t
                RuleName = $rule.RuleName
                Kind     = $rule.Kind
                Severity = $rule.Severity
            }
        }
    }
    # Legacy TI synonym: rules referencing ThreatIntelligenceIndicator implicitly cover the new tables too
    if ($body -cmatch '\bThreatIntelligenceIndicator\b') {
        foreach ($newTi in @('ThreatIntelIndicators','ThreatIntelObjects')) {
            if ($tableUniverse -contains $newTi) {
                $ruleTableRefs += [pscustomobject]@{
                    Table    = $newTi
                    RuleName = $rule.RuleName + ' (via legacy TI alias)'
                    Kind     = $rule.Kind
                    Severity = $rule.Severity
                }
            }
        }
    }
    # _GetWatchlist() implicitly references the Watchlist table
    if ($body -cmatch '_GetWatchlist\s*\(' -and $tableUniverse -contains 'Watchlist') {
        $ruleTableRefs += [pscustomobject]@{
            Table    = 'Watchlist'
            RuleName = $rule.RuleName + ' (via _GetWatchlist)'
            Kind     = $rule.Kind
            Severity = $rule.Severity
        }
    }
}

$perTableRuleSummary = $ruleTableRefs | Group-Object Table | ForEach-Object {
    $rows = @($_.Group)
    $uniqueRuleNames = @($rows.RuleName | Sort-Object -Unique)
    $uniqueKinds     = @($rows.Kind     | Sort-Object -Unique)
    [pscustomobject]@{
        Table             = $_.Name
        EnabledRuleCount  = $uniqueRuleNames.Count
        RuleKinds         = ($uniqueKinds -join ', ')
        TopRuleNames      = (($uniqueRuleNames | Select-Object -First 5) -join '; ')
    }
}

Write-Step "Per-table rule references: $(@($perTableRuleSummary).Count) tables with >= 1 enabled rule"

# Indirection patterns
$indirection = @()
foreach ($rule in $enabledKqlRules) {
    $b = $rule.QueryText
    $asim       = @([regex]::Matches($b, '\b_(Im|Asim|imv)_\w+\s*\(') | ForEach-Object { $_.Value.TrimEnd('(', ' ') } | Sort-Object -Unique)
    $watchlist  = $b -cmatch '_GetWatchlist\s*\('
    $external   = $b -cmatch '\bexternaldata\s*\('
    $customFn   = @()
    foreach ($fn in $workspaceFunctions) {
        $alias = $fn.FunctionAlias
        if ($alias -and ($b -cmatch ('\b' + [regex]::Escape($alias) + '\s*\('))) {
            $customFn += $alias
        }
    }
    if ($asim.Count -gt 0 -or $watchlist -or $external -or $customFn.Count -gt 0) {
        $indirection += [pscustomobject]@{
            RuleName        = $rule.RuleName
            Kind            = $rule.Kind
            Severity        = $rule.Severity
            AsimParsers     = ($asim -join '; ')
            UsesWatchlistFn = $watchlist
            UsesExternalData = $external
            CustomFnCalls   = ($customFn -join '; ')
        }
    }
}
Write-Step "Indirection patterns: $(@($indirection).Count) rules with ASIM/Watchlist/externaldata/custom-fn"

# Function-wraps-table grid: which workspace functions reference each table
$functionsWrappingTables = @()
foreach ($fn in $workspaceFunctions) {
    $body = $fn.QueryBody
    if (-not $body) { continue }
    $wrapped = @()
    foreach ($t in $tableUniverse) {
        $pattern = '\b' + $tablesEsc[$t] + '\b'
        if ($body -cmatch $pattern) { $wrapped += $t }
    }
    if ($wrapped.Count -gt 0) {
        $uniqueWrapped = @($wrapped | Sort-Object -Unique)
        $functionsWrappingTables += [pscustomobject]@{
            FunctionAlias    = $fn.FunctionAlias
            DisplayName      = $fn.DisplayName
            TablesReferenced = ($uniqueWrapped -join '; ')
            TableCount       = $uniqueWrapped.Count
        }
    }
}

# Function-to-rule mapping
$functionRuleMap = @()
foreach ($fn in $workspaceFunctions) {
    $alias = $fn.FunctionAlias
    if (-not $alias) { continue }
    $callers = $enabledKqlRules | Where-Object { $_.QueryText -cmatch ('\b' + [regex]::Escape($alias) + '\s*\(') }
    foreach ($r in $callers) {
        $functionRuleMap += [pscustomobject]@{
            FunctionAlias = $alias
            RuleName      = $r.RuleName
            Kind          = $r.Kind
            Severity      = $r.Severity
        }
    }
}

#endregion

#region Step 6 - Secondary datasets (Exclusions, Deprecation, Query-Weighted, XDR, etc.) ─

Write-Host ""
Write-Host "Step 6/6 - Secondary datasets" -ForegroundColor Yellow

# Exclusions
$exclusionsKql = @"
$classificationLets
Usage
| where TimeGenerated > ago($($TimeRangeDays)d)
| where IsBillable == true
| summarize GBPerMonth = (sum(Quantity) / toreal($($TimeRangeDays * 86400)) * 86400 / 1000.0) * 30.0 by DataType
| extend Category = case(
    DataType in (notSupportedInLake), 'Not supported in Lake',
    DataType in (uebaTables), 'UEBA (Analytics-only)',
    DataType in (sentinelFeatureTables), 'Sentinel feature dependency',
    DataType in (systemTables), 'System table',
    DataType in (classicV1Tables), 'Custom log V1 (not supported)',
    DataType in (basicPlanTables), 'Basic plan (convert first)',
    'Supported')
| where Category != 'Supported'
| extend Reason = case(
    Category == 'Not supported in Lake', 'Sentinel Data Lake does not mirror this table.',
    Category == 'UEBA (Analytics-only)', 'Required by UEBA. Moving breaks behavioural analytics.',
    Category == 'Sentinel feature dependency', 'Required by Sentinel features (alerts, watchlists, TI, Fusion).',
    Category == 'System table', 'Operational/metadata table; not security telemetry.',
    Category == 'Custom log V1 (not supported)', 'Legacy MMA/HTTP Data Collector ingestion; migrate to DCR.',
    Category == 'Basic plan (convert first)', 'Tables on Basic plan cannot move directly to Lake.',
    '')
| project Table=DataType, Category, Reason, GBPerMonth=round(GBPerMonth, 2)
| order by GBPerMonth desc
"@
$exclusionsRows = Invoke-Kql -Query $exclusionsKql
Write-Step "Exclusions: $(@($exclusionsRows).Count) rows"

# Deprecation Warnings - Microsoft-announced retirements + Classic V1 callout
$deprecationKql = @"
let deprecatedTables = datatable(LegacyTable:string, Replacement:string, Urgency:string, Reference:string)
[
    'ThreatIntelligenceIndicator',
        'ThreatIntelIndicators + ThreatIntelObjects',
        'Critical - legacy TI ingestion ends mid-2026',
        'https://learn.microsoft.com/azure/sentinel/threat-intelligence-upgrade'
];
Usage
| where TimeGenerated > ago($($TimeRangeDays)d)
| where IsBillable == true
| summarize GBPerMonth = (sum(Quantity) / toreal($($TimeRangeDays * 86400)) * 86400 / 1000.0) * 30.0 by DataType
| join kind=inner (deprecatedTables) on `$left.DataType == `$right.LegacyTable
| project Table=DataType, DeprecationType='Table replaced', Replacement, Urgency, GBPerMonth=round(GBPerMonth, 2), DocsUrl=Reference
"@
$deprecationRows = Invoke-Kql -Query $deprecationKql
Write-Step "Deprecation warnings: $(@($deprecationRows).Count) rows"

# Classic V1 enrichment with billable GB
$classicV1Rows = @()
if ($classicV1.Count) {
    $classicListLit = ($classicV1 | ForEach-Object { "'$_'" }) -join ','
    $classicV1Kql = @"
let classicV1Tables = dynamic([$classicListLit]);
Usage
| where TimeGenerated > ago($($TimeRangeDays)d)
| where IsBillable == true
| where DataType in (classicV1Tables)
| summarize GBPerMonth = (sum(Quantity) / toreal($($TimeRangeDays * 86400)) * 86400 / 1000.0) * 30.0 by DataType
| project Table=DataType, GBPerMonth=round(GBPerMonth, 2)
"@
    $classicVolumes = Invoke-Kql -Query $classicV1Kql
    $classicVolHash = @{}
    foreach ($cv in $classicVolumes) { $classicVolHash[$cv.Table] = $cv.GBPerMonth }
    foreach ($c in $classicV1) {
        $classicV1Rows += [pscustomobject]@{
            Table        = $c
            DeprecationType = 'Classic V1 _CL'
            Replacement  = 'Migrate to DCR-based ingestion via Logs Ingestion API'
            Urgency      = 'Required for Lake - legacy HTTP Data Collector API and MMA agent deprecated'
            GBPerMonth   = $classicVolHash.ContainsKey($c) ? $classicVolHash[$c] : 0
            DocsUrl      = 'https://learn.microsoft.com/azure/azure-monitor/logs/custom-logs-migrate'
        }
    }
}
Write-Step "Classic V1 _CL tables: $(@($classicV1Rows).Count) rows"

# Top 10 highest-impact moves
$top10Kql = @"
$pricingLet
$classificationLets
Usage
| where TimeGenerated > ago($($TimeRangeDays)d)
| where IsBillable == true
| summarize BillableGB = sum(Quantity) / 1000.0 by DataType
| extend MonthlyGB = (BillableGB / toreal($TimeRangeDays)) * 30.0
| extend AnalyticsMonthlyCost = MonthlyGB * priceAnalytics
| extend LakeMonthlyCost = (MonthlyGB * priceLakeIngest) + (MonthlyGB * priceLakeProc) + ((MonthlyGB * (lakeRetentionDays / 30.0) / compressionRatio) * priceLakeStore)
| extend MonthlySaving = AnalyticsMonthlyCost - LakeMonthlyCost
| extend Category = case(
    DataType in (notSupportedInLake), 'Not supported in Lake',
    DataType in (uebaTables), 'UEBA (Analytics-only)',
    DataType in (sentinelFeatureTables), 'Sentinel feature dependency',
    DataType in (systemTables), 'System table',
    DataType in (classicV1Tables), 'Custom log V1 (not supported)',
    DataType in (basicPlanTables), 'Basic plan (convert first)',
    'Supported')
| where Category in ('Supported') or (DataType endswith '_CL' and DataType in (dcrCustomTables))
| top 10 by MonthlySaving desc
| project Table=DataType, GBPerMonth=round(MonthlyGB, 2), MonthlySaving_$Currency=round(MonthlySaving, 2)
"@
$top10Rows = Invoke-Kql -Query $top10Kql
Write-Step "Top 10 savings candidates: $(@($top10Rows).Count) rows"

# Query-Weighted
$queryWeightedRows = @()
try {
    $queryWeightedKql = @"
let queryDays = $QueryLookbackDays;
let userRate = toreal('$(Format-KqlNumber $EffectiveAnalyticsRate)');
let modelRate = toreal('$(Format-KqlNumber (Get-PricingRate -Model $PricingModel))');
let priceAnalytics = iif(userRate > 0, userRate, modelRate);
let priceLakeQuery = toreal('$(Format-KqlNumber $LakeQueryPricePerGB)');
let priceLakeIngest = toreal('$(Format-KqlNumber $LakeIngestPricePerGB)');
let priceLakeProc = toreal('$(Format-KqlNumber $LakeProcessingPricePerGB)');
let perTableIngest = Usage
    | where TimeGenerated > ago($($TimeRangeDays)d)
    | where IsBillable == true
    | summarize BillableGB = sum(Quantity) / 1000.0 by DataType
    | extend MonthlyGB = (BillableGB / toreal($TimeRangeDays)) * 30.0;
let perTableQueryActivity = LAQueryLogs
    | where TimeGenerated > ago(queryDays * 1d)
    | where ResponseDurationMs > 0
    | mv-expand TableName = extract_all(@"\b([A-Z][A-Za-z0-9_]+)\b", dynamic([1]), QueryText) to typeof(string)
    | summarize QueryCount = count(), AvgDurationMs = avg(ResponseDurationMs) by TableName
    | extend QueriesPerMonth = (QueryCount / toreal(queryDays)) * 30.0;
perTableIngest
| join kind=leftouter (perTableQueryActivity) on `$left.DataType == `$right.TableName
| extend ScanGBPerMonth = MonthlyGB * coalesce(QueriesPerMonth, 0.0) * 0.1
| extend AnalyticsCost = MonthlyGB * priceAnalytics
| extend LakeIngestCost = MonthlyGB * priceLakeIngest
| extend LakeProcCost   = MonthlyGB * priceLakeProc
| extend LakeQueryCost  = ScanGBPerMonth * priceLakeQuery
| extend LakeTotalCost  = LakeIngestCost + LakeProcCost + LakeQueryCost
| order by AnalyticsCost desc
| project Table=DataType, GBPerMonth=round(MonthlyGB, 2),
          QueriesPerMonth=round(coalesce(QueriesPerMonth, 0.0), 1),
          ScanGBPerMonth=round(ScanGBPerMonth, 2),
          AnalyticsCost_$Currency=round(AnalyticsCost, 2),
          LakeTotalCost_$Currency=round(LakeTotalCost, 2),
          MonthlySaving_$Currency=round(AnalyticsCost - LakeTotalCost, 2)
"@
    $queryWeightedRows = Invoke-Kql -Query $queryWeightedKql
}
catch {
    Write-Warning "  Query-Weighted skipped (likely LAQueryLogs not enabled): $($_.Exception.Message)"
}
Write-Step "Query-Weighted: $(@($queryWeightedRows).Count) rows"

# XDR cost model (optional)
$xdrRows = @()
if ($XdrLookbackDays -gt 0) {
    try {
        $xdrKql = @"
let lookbackDays = $XdrLookbackDays;
let userRate = toreal('$(Format-KqlNumber $EffectiveAnalyticsRate)');
let modelRate = toreal('$(Format-KqlNumber (Get-PricingRate -Model $PricingModel))');
let priceAnalytics = iif(userRate > 0, userRate, modelRate);
let xdrTables = dynamic(['DeviceEvents','DeviceFileEvents','DeviceImageLoadEvents','DeviceLogonEvents','DeviceNetworkEvents','DeviceNetworkInfo','DeviceProcessEvents','DeviceRegistryEvents','DeviceTvmSecureConfigurationAssessment','DeviceTvmSecureConfigurationAssessmentKB','DeviceTvmSoftwareInventory','DeviceTvmSoftwareVulnerabilities','DeviceTvmSoftwareVulnerabilitiesKB','AlertEvidence','AlertInfo','EmailAttachmentInfo','EmailEvents','EmailPostDeliveryEvents','EmailUrlInfo','UrlClickEvents','IdentityLogonEvents']);
Usage
| where TimeGenerated > ago(lookbackDays * 1d)
| where IsBillable == true
| where DataType in (xdrTables)
| summarize BillableGB = sum(Quantity) / 1000.0 by DataType
| extend MonthlyGB = (BillableGB / toreal(lookbackDays)) * 30.0
| extend AnalyticsCost = MonthlyGB * priceAnalytics
| order by AnalyticsCost desc
| project Table=DataType, GBPerMonth=round(MonthlyGB, 2), AnalyticsMonthlyCost_$Currency=round(AnalyticsCost, 2)
"@
        $xdrRows = Invoke-Kql -Query $xdrKql
    }
    catch {
        Write-Warning "  XDR cost model skipped: $($_.Exception.Message)"
    }
}
Write-Step "XDR cost model: $(@($xdrRows).Count) rows"

# Alert activity per-table
$alertActivityRows = @()
try {
    $alertActivityKql = @"
SecurityAlert
| where TimeGenerated > ago($($AlertActivityDays)d)
| summarize Alerts = count(), HighSeverity = countif(AlertSeverity == 'High'), Last = max(TimeGenerated) by AlertName
| order by Alerts desc
| project RuleOrAlertName=AlertName, Alerts, HighSeverity, LastSeen=Last
"@
    $alertActivityRows = Invoke-Kql -Query $alertActivityKql
}
catch {
    Write-Warning "  Alert activity skipped: $($_.Exception.Message)"
}
Write-Step "Alert activity: $(@($alertActivityRows).Count) rows"

# Pricing assumptions sheet
$pricingAssumptions = [pscustomobject]@{
    GeneratedAt                    = $script:Now.ToString('u')
    Workspace                      = $WorkspaceName
    Subscription                   = $SubscriptionId
    ResourceGroup                  = $ResourceGroupName
    TimeRangeDays                  = $TimeRangeDays
    QueryLookbackDays              = $QueryLookbackDays
    AlertActivityDays              = $AlertActivityDays
    XdrLookbackDays                = $XdrLookbackDays
    PricingModel                   = $PricingModel
    EffectiveAnalyticsRate_PerGB   = $effectiveRate
    Currency                       = $Currency
    LakeIngestPricePerGB           = $LakeIngestPricePerGB
    LakeProcessingPricePerGB       = $LakeProcessingPricePerGB
    LakeStoragePricePerGBMonth     = $LakeStoragePricePerGBMonth
    LakeQueryPricePerGB            = $LakeQueryPricePerGB
    TargetLakeRetentionDays        = $TargetLakeRetentionDays
    CompressionRatio               = $CompressionRatio
}

#endregion

#region Write xlsx ─────────────────────────────────────────────────────────────

if (-not $OutputPath) {
    $stamp = $script:Now.ToString('yyyyMMdd-HHmm')
    # Anchor the default output beside the script itself ($PSScriptRoot)
    # rather than Get-Location. Get-Location depends on the caller's
    # current working directory, which makes "where did the export go?"
    # confusing when the script is launched from a parent folder or via
    # an absolute path. $PSScriptRoot is always the script's own folder.
    $OutputPath = Join-Path $PSScriptRoot "SdlMigrationExport_${WorkspaceName}_${stamp}.xlsx"
}
# Defensive guard for explicit -OutputPath callers. The default-path
# branch above is already safe because $PSScriptRoot resolves to a
# POSIX path on non-Windows, but a user who copied a Windows-style
# example like -OutputPath "C:\Reports\foo.xlsx" (or "C:/Reports/...")
# and ran the script on macOS/Linux would otherwise hit Split-Path /
# Test-Path / New-Item further down with the unhelpful message:
#
#     Cannot find drive. A drive with the name 'C' does not exist.
#
# Catch it upfront with a clearer, platform-aware error. The regex
# matches both backslash (C:\) and forward-slash (C:/) drive-rooted
# forms because PowerShell on Windows accepts both, so either could
# plausibly appear in a copied example. The guard only fires on
# non-Windows; Windows drive paths are perfectly valid on Windows.
if (-not $IsWindows -and $OutputPath -match '^[A-Za-z]:[\\/]') {
    throw "OutputPath '$OutputPath' uses a Windows drive path, which is not valid on macOS/Linux. Use a forward-slash path instead, e.g. '/tmp/report.xlsx' or './report.xlsx'."
}
# Path-manipulation primitives here drop to .NET because the
# obvious PowerShell idioms have parameter-set traps:
#   - Split-Path -LiteralPath ... -Parent is invalid because
#     -LiteralPath and -Parent live in different parameter sets
#     (LiteralPathSet vs ParentSet) and PowerShell cannot resolve
#     the call. [System.IO.Path]::GetDirectoryName() is the literal-
#     string equivalent.
#   - New-Item has no -LiteralPath parameter at all (only -Path /
#     -Name), so it would either need [WildcardPattern]::Escape on
#     the input or a drop to .NET. [System.IO.Directory]::
#     CreateDirectory() is idempotent (no-op if the directory
#     already exists), takes a literal path by definition, and
#     behaves identically on Windows, macOS, and Linux.
# The surrounding Test-Path / Remove-Item calls keep -LiteralPath
# because those cmdlets do support it; this block is therefore
# consistent on "literal path, no wildcard interpretation" without
# pretending every cmdlet supports the same parameter name.
$outputDir = [System.IO.Path]::GetDirectoryName($OutputPath)
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) { [void][System.IO.Directory]::CreateDirectory($outputDir) }
if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }

Write-Host ""
Write-Host "Writing $OutputPath" -ForegroundColor Cyan

$sheets = [ordered]@{
    'Migration Report'      = $migrationReport
    'Per-Table Rule Refs'   = $perTableRuleSummary
    'Exclusions'            = $exclusionsRows
    'Deprecation Warnings'  = $deprecationRows
    'Classic V1 Tables'     = $classicV1Rows
    'Top 10 Savings'        = $top10Rows
    'Rules Inventory'       = $rulesInventory
    'Indirection Rules'     = $indirection
    'Workspace Functions'   = $workspaceFunctions
    'Fns Wrapping Tables'   = $functionsWrappingTables
    'Function -> Rules'     = $functionRuleMap
    'Query-Weighted'        = $queryWeightedRows
    'XDR Cost Model'        = $xdrRows
    'Alert Activity'        = $alertActivityRows
    'Pricing Assumptions'   = @($pricingAssumptions)
}

foreach ($sheetName in $sheets.Keys) {
    $rows = $sheets[$sheetName]
    if (-not $rows -or @($rows).Count -eq 0) {
        # Write a one-row placeholder so the sheet still exists
        [pscustomobject]@{ Note = "No rows produced for this dataset." } |
            Export-Excel -Path $OutputPath -WorksheetName $sheetName -AutoSize -BoldTopRow -FreezeTopRow
        Write-Step "$sheetName : 0 rows (placeholder written)"
        continue
    }
    $rows | Export-Excel -Path $OutputPath -WorksheetName $sheetName -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow -TableStyle Medium2
    Write-Step "$sheetName : $(@($rows).Count) rows"
}

#endregion

Write-Host ""
Write-Host "Done. Output: $OutputPath" -ForegroundColor Green
