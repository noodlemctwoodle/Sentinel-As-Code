#Requires -Version 7.6

<#
.SYNOPSIS
    DEPRECATED. The public command of the SdlMigrationExport module.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Public/Export-SdlMigrationWorkbook.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-18
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, Az.Accounts, Az.OperationalInsights, ImportExcel

    Was a standalone script before 0.2.0; now the module's only exported
    function. To be replaced by the iSOCDeployments module.
#>

# Keeps the file help above from being read as the help of the function below.

function Export-SdlMigrationWorkbook {
    <#
    .SYNOPSIS
        DEPRECATED. Exports every dataset behind the Sentinel Data Lake
        Migration workbook to a single multi-sheet Excel file (.xlsx).

    .DESCRIPTION
        DEPRECATED: frozen, to be replaced by the iSOCDeployments PowerShell
        module; correctness fixes only. Do not compare its output with exports
        taken before version 0.2.0.

        Mirrors every query of the workbook against the workspace and writes
        one .xlsx with fifteen sheets, which the portal cannot do because each
        grid exports only its own sheet. Read-only: it only reads ARM and runs
        KQL. Supports -WhatIf, which runs the queries but writes no file. See
        Docs/Tools/SDL-Migration-Workbook-Export.md.

    .PARAMETER SubscriptionId
        Azure subscription ID containing the Log Analytics workspace.

    .PARAMETER ResourceGroupName
        Resource group containing the workspace.

    .PARAMETER WorkspaceName
        Log Analytics workspace name (Sentinel-enabled).

    .PARAMETER OutputPath
        Path for the .xlsx. Default: SdlMigrationExport_<ws>_<stamp>.xlsx in
        the current directory.

    .PARAMETER TimeRangeDays
        Ingestion analysis window. Default: 30 (the workbook's TimeRange).

    .PARAMETER QueryLookbackDays
        LAQueryLogs lookback for the Query-Weighted sheet. Default: 7.

    .PARAMETER AlertActivityDays
        SecurityAlert lookback for alert-activity stats. Default: 30.

    .PARAMETER XdrLookbackDays
        Lookback for the XDR cost model. Default: 7. 0 skips the XDR sheet.

    .PARAMETER PricingModel
        PAYG or a commitment tier, CT50 to CT50000 (East US rates).

    .PARAMETER EffectiveAnalyticsRate
        Analytics per-GB rate override. 0 = use the pricing model rate.

    .PARAMETER Currency
        Currency label for column headers only; no conversion. Default: USD.

    .PARAMETER LakeIngestPricePerGB
        Data lake ingestion price per GB. Default: 0.05.

    .PARAMETER LakeProcessingPricePerGB
        Data lake processing price per GB. Default: 0.10.

    .PARAMETER LakeStoragePricePerGBMonth
        Data lake storage price per compressed GB-month. Default: 0.026.

    .PARAMETER LakeQueryPricePerGB
        Data lake query price per GB scanned. Default: 0.005.

    .PARAMETER TargetLakeRetentionDays
        Total retention, compared on both sides. Default: 730.

    .PARAMETER AnalyticsRetentionDays
        Analytics retention if a table stays on Analytics. Default: 90 (free).

    .PARAMETER AnalyticsRetentionPricePerGBMonth
        Analytics retention price beyond 90 days per GB-month. Default: 0.10.

    .PARAMETER CompressionRatio
        Lake storage compression ratio. Default: 6 (Microsoft's fixed 6:1).

    .PARAMETER ThrottleMs
        Milliseconds between ARM calls. Default: 200. 0 disables the pause.

    .OUTPUTS
        None. Writes the workbook; progress goes to the information stream.

    .EXAMPLE
        Export-SdlMigrationWorkbook -SubscriptionId '<sub>' -ResourceGroupName '<rg>' -WorkspaceName '<ws>'

        Export with all defaults: 30-day window, PAYG pricing, USD.
    #>
    [CmdletBinding(PositionalBinding = $false, SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SubscriptionId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkspaceName,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [ValidateRange(1, 365)]
        [int]$TimeRangeDays = 30,

        [Parameter()]
        [ValidateRange(1, 365)]
        [int]$QueryLookbackDays = 7,

        [Parameter()]
        [ValidateRange(1, 365)]
        [int]$AlertActivityDays = 30,

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$XdrLookbackDays = 7,

        [Parameter()]
        [ValidateSet('PAYG', 'CT50', 'CT100', 'CT200', 'CT300', 'CT400', 'CT500', 'CT1000', 'CT2000', 'CT5000', 'CT10000', 'CT25000', 'CT50000')]
        [string]$PricingModel = 'PAYG',

        [Parameter()]
        [ValidateRange(0, 100)]
        [double]$EffectiveAnalyticsRate = 0,

        [Parameter()]
        [ValidatePattern('^[A-Z]{3}$')]
        [string]$Currency = 'USD',

        [Parameter()]
        [ValidateRange(0, 10)]
        [double]$LakeIngestPricePerGB = 0.05,

        [Parameter()]
        [ValidateRange(0, 10)]
        [double]$LakeProcessingPricePerGB = 0.10,

        [Parameter()]
        [ValidateRange(0, 10)]
        [double]$LakeStoragePricePerGBMonth = 0.026,

        [Parameter()]
        [ValidateRange(0, 10)]
        [double]$LakeQueryPricePerGB = 0.005,

        [Parameter()]
        [ValidateRange(30, 4383)]
        [int]$TargetLakeRetentionDays = 730,

        [Parameter()]
        [ValidateRange(30, 730)]
        [int]$AnalyticsRetentionDays = 90,

        [Parameter()]
        [ValidateRange(0, 10)]
        [double]$AnalyticsRetentionPricePerGBMonth = 0.10,

        [Parameter()]
        [ValidateRange(1, 50)]
        [double]$CompressionRatio = 6,

        [Parameter()]
        [ValidateRange(0, 60000)]
        [int]$ThrottleMs = 200
    )

    $ErrorActionPreference = 'Stop'
    $moduleVersion = [string]$MyInvocation.MyCommand.Module.Version
    $startedAt = Get-Date

    Write-SdlDeprecationNotice -Version $moduleVersion
    if ($Currency -ne 'USD' -and $EffectiveAnalyticsRate -eq 0) {
        Write-Warning -Message "Currency is '$Currency' but no -EffectiveAnalyticsRate was supplied: the built-in rates are USD list prices, so the figures are USD relabelled as $Currency."
    }

    $connection = [pscustomobject]@{
        SubscriptionId          = $SubscriptionId
        ResourceGroupName       = $ResourceGroupName
        WorkspaceName           = $WorkspaceName
        ThrottleMs              = $ThrottleMs
        WorkspaceCustomerId     = $null
        TablesApiVersion        = '2023-09-01'
        AlertRulesApiVersion    = '2025-09-01'
        SavedSearchesApiVersion = '2020-08-01'
        WorkspaceApiVersion     = '2023-09-01'
    }
    $settings = [pscustomobject]@{
        TimeRangeDays                     = $TimeRangeDays
        QueryLookbackDays                 = $QueryLookbackDays
        AlertActivityDays                 = $AlertActivityDays
        XdrLookbackDays                   = $XdrLookbackDays
        PricingModel                      = $PricingModel
        EffectiveAnalyticsRate            = $EffectiveAnalyticsRate
        Currency                          = $Currency
        LakeIngestPricePerGB              = $LakeIngestPricePerGB
        LakeProcessingPricePerGB          = $LakeProcessingPricePerGB
        LakeStoragePricePerGBMonth        = $LakeStoragePricePerGBMonth
        LakeQueryPricePerGB               = $LakeQueryPricePerGB
        TargetLakeRetentionDays           = $TargetLakeRetentionDays
        AnalyticsRetentionDays            = $AnalyticsRetentionDays
        AnalyticsRetentionPricePerGBMonth = $AnalyticsRetentionPricePerGBMonth
        CompressionRatio                  = $CompressionRatio
    }
    Assert-SdlSetting -Settings $settings

    $azContext = Assert-SdlPrerequisite -SubscriptionId $SubscriptionId
    Write-SdlStatus -Message 'Sentinel Data Lake Migration Export' -Heading
    Write-SdlStatus -Message "Authenticated as : $($azContext.Account.Id)"
    Write-SdlStatus -Message "Workspace        : $SubscriptionId / $ResourceGroupName / $WorkspaceName"

    Write-SdlStatus -Message 'Step 1/6 - Tables ARM API' -Heading
    $inventory = Get-SdlTableInventory -Connection $connection
    Write-SdlStatus -Message "Tables: $($inventory.TableCount) total | Classic V1: $($inventory.ClassicV1.Count) | DCR _CL: $($inventory.DcrCustom.Count) | Basic: $($inventory.BasicPlan.Count) | Auxiliary: $($inventory.AuxiliaryPlan.Count)"

    Write-SdlStatus -Message 'Step 2/6 - Alert Rules ARM API' -Heading
    $rulesInventory = @(Get-SdlRuleInventory -Connection $connection)
    $enabledRules = @($rulesInventory | Where-Object -FilterScript { $_.Enabled -eq $true })
    Write-SdlStatus -Message "Rules: $($rulesInventory.Count) total | enabled: $($enabledRules.Count)"

    Write-SdlStatus -Message 'Step 3/6 - Workspace KQL Functions' -Heading
    $workspaceFunctions = @(Get-SdlFunctionInventory -Connection $connection)
    Write-SdlStatus -Message "Workspace functions: $($workspaceFunctions.Count)"

    Write-SdlStatus -Message 'Step 4/6 - Per-table classification (Migration Report)' -Heading
    $migrationReport = @(Get-SdlMigrationReport -Connection $connection -Settings $settings -Inventory $inventory)
    Write-SdlStatus -Message "Migration Report: $($migrationReport.Count) rows"

    Write-SdlStatus -Message 'Step 5/6 - Per-table rule references + indirection' -Heading
    $tableUniverse = @($migrationReport | ForEach-Object -Process { $_.Table })
    $ruleBodies = @(Get-SdlRuleBody -Rule $enabledRules)
    $functionReach = Get-SdlFunctionReach -Function $workspaceFunctions -TableUniverse $tableUniverse
    $ruleReferences = @(Get-SdlRuleReference -FunctionReach $functionReach -RuleBody $ruleBodies -TableUniverse $tableUniverse)
    $ruleTableSummary = @(Get-SdlRuleTableSummary -Reference $ruleReferences)
    $indirection = @(Get-SdlIndirectionReport -RuleBody $ruleBodies -Function $workspaceFunctions)
    Write-SdlStatus -Message "Per-table rule references: $($ruleTableSummary.Count) tables with >= 1 enabled rule"
    Write-SdlStatus -Message "Indirection patterns: $($indirection.Count) rules with ASIM/Watchlist/externaldata/custom-fn"

    Write-SdlStatus -Message 'Step 6/6 - Secondary datasets and workbook' -Heading
    $pricingAssumption = Get-SdlPricingAssumption -Settings $settings -Workspace $WorkspaceName -Subscription $SubscriptionId -ResourceGroup $ResourceGroupName -ScriptVersion $moduleVersion -GeneratedAt $startedAt
    $sheets = [ordered]@{
        'Migration Report'     = $migrationReport
        'Per-Table Rule Refs'  = $ruleTableSummary
        'Exclusions'           = @(Get-SdlExclusionReport -MigrationReport $migrationReport)
        'Deprecation Warnings' = @(Get-SdlDeprecationReport -Connection $connection -Settings $settings)
        'Classic V1 Tables'    = @(Get-SdlClassicV1Report -Connection $connection -Settings $settings -Inventory $inventory)
        'Top 10 Savings'       = @(Get-SdlTopSavingReport -Currency $Currency -MigrationReport $migrationReport)
        'Rules Inventory'      = $rulesInventory
        'Indirection Rules'    = $indirection
        'Workspace Functions'  = $workspaceFunctions
        'Fns Wrapping Tables'  = @(Get-SdlFunctionTableReport -FunctionReach $functionReach)
        'Function -> Rules'    = @(Get-SdlFunctionRuleMap -RuleBody $ruleBodies -Function $workspaceFunctions)
        'Query-Weighted'       = @(Get-SdlQueryWeightedReport -Connection $connection -Settings $settings -Inventory $inventory)
        'XDR Cost Model'       = @(Get-SdlXdrCostReport -Connection $connection -Settings $settings)
        'Alert Activity'       = @(Get-SdlAlertActivityReport -Connection $connection -Settings $settings)
        'Pricing Assumptions'  = @($pricingAssumption)
    }

    $resolvedPath = Resolve-SdlOutputPath -WorkspaceName $WorkspaceName -Timestamp $startedAt -OutputPath $OutputPath
    Write-SdlStatus -Message "Writing $resolvedPath"
    Write-SdlWorkbook -Path $resolvedPath -Sheet $sheets

    Write-SdlStatus -Message "Done. Output: $resolvedPath" -Heading
    Write-SdlDeprecationNotice -Version $moduleVersion -Short
}
