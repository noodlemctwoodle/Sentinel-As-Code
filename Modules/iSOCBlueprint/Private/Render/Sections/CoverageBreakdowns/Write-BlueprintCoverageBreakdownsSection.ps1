#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 14-coverage-breakdowns.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/CoverageBreakdowns/Write-BlueprintCoverageBreakdownsSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintCoverageBreakdownsSection {
    <#
    .SYNOPSIS
        Build the figures for and write 14-coverage-breakdowns.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $cat = $Context.cat
    $m = $Context.m
    $n = $Context.n
    $rawRoot = $Context.rawRoot
    $s = $Context.s
    $tablesWithData = $Context.tablesWithData
    $workspaceTables = $Context.workspaceTables

    # Section 14 — Coverage breakdowns
    $azAct  = Read-BlueprintRawArray 'azure-activity-coverage.json'
    $azDiag = Read-BlueprintRawArray 'azure-diagnostics-providers.json'
    $xdrPres = Read-BlueprintRawArray 'xdr-table-presence.json'

    $azActRows = $azAct | ForEach-Object {
        [pscustomobject]@{ SubscriptionId = $_.SubscriptionId; LogCount = Format-BlueprintCount $_.LogCount }
    }
    $azDiagRows = $azDiag | ForEach-Object {
        [pscustomobject]@{ ResourceProvider = $_.ResourceProvider; LogCount = Format-BlueprintCount $_.LogCount }
    }
    # Entra ID tables: which of the well-known identity tables exist in the
    # catalogue and which received data in the last 7 days.
    $entraTableNames = @(
        'SigninLogs','AuditLogs','AADNonInteractiveUserSignInLogs','AADServicePrincipalSignInLogs','AADManagedIdentitySignInLogs','AADProvisioningLogs',
            'ADFSSignInLogs','AADRiskyUsers','AADUserRiskEvents','AADRiskyServicePrincipals','AADServicePrincipalRiskEvents','MicrosoftGraphActivityLogs',
            'IdentityInfo'
    )
    $entraRows = @(foreach ($name in $entraTableNames) {
        $cat = @($workspaceTables | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'name') -eq $name }) | Select-Object -First 1
        $use = @($tablesWithData | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'DataType') -eq $name }) | Select-Object -First 1
        $gb7 = if ($use) { [math]::Round((ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $use 'BillableLast7d' 0)), 2) } else { 0 }
        $props = Get-BlueprintRawProperty $cat 'properties'
        [pscustomobject]@{
            Table     = $name
            Plan      = if ($props) { [string](Get-BlueprintRawProperty $props 'plan' '') } else { '' }
            Retention = if ($props) { [string](Get-BlueprintRawProperty $props 'retentionInDays' '') } else { '' }
            Gb7d      = $gb7
            Status    = if ($gb7 -gt 0) { 'Receiving data' } elseif ($cat) { 'Catalogue only' } else { 'Not in catalogue' }
        }
    })
    $xdrRows = $xdrPres | ForEach-Object {
        [pscustomobject]@{ Table = $_.Type; RecordCount = $_.RecordCount }
    }
    # XDR-table-presence inputs for the bar chart. Short-label-axis with full
    # names in the table below.
    $xdrChartBlock = if ($xdrPres.Count -gt 0) {
        $xdrAxis = ($xdrRows | ForEach-Object {
            $n = $_.Table
            $s = if ($n.Length -gt 12) { $n.Substring(0,12) } else { $n }
            "`"$s`""
        }) -join ', '
        $xdrBars = ($xdrRows | ForEach-Object { [long]$_.RecordCount }) -join ', '
        $xdrYmax = [long]1
        foreach ($r in $xdrRows) { if ([long]$r.RecordCount -gt $xdrYmax) { $xdrYmax = [long]$r.RecordCount } }
        @"

## XDR table activity (last {lookback-d})

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Defender XDR tables: records ingested in the last {lookback-d}"
    x-axis [$xdrAxis]
$(Format-XyFullLabels @($xdrRows | ForEach-Object { $_.Table }))
    y-axis "Records" 0 --> $($xdrYmax + ([math]::Ceiling($xdrYmax * 0.1)))
    bar [$xdrBars]
``````

A short bar means that XDR surface (email / device / identity / cloud-app) isn't producing data. Bar at 0 = the workspace's XDR connector is silent for that table: investigate it, or accept it (some XDR products gate certain tables behind licensing).
"@
    } else { '' }

    # AzureDiagnostics by category, and Azure Firewall in both its forms: the
    # legacy AzureDiagnostics categories and the resource-specific AZFW* tables.
    $azDiagCategoryRows = @(Read-BlueprintRawArray 'azure-diagnostics-categories.json' | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{ ResourceProvider = $_.ResourceProvider; Category = $_.Category; LogCount = Format-BlueprintCount $_.LogCount }
    })
    $fwCategoryRows = @(Read-BlueprintRawArray 'azure-firewall-categories.json' | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{
            Category = $_.Category
            Form     = $(if ([string]$_.Category -like 'AZFW*') { 'Resource-specific category' } else { 'Legacy category' })
            LogCount = Format-BlueprintCount $_.LogCount
        }
    })
    $fwTableRows = @($tablesWithData | Where-Object { $_ -and [string](Get-BlueprintRawProperty $_ 'DataType' '') -like 'AZFW*' } | ForEach-Object {
        [pscustomobject]@{
            Table = $_.DataType
            Gb7d = [math]::Round((ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'BillableLast7d' 0)), 2)
            LastIngested = Format-DateUtc (Get-BlueprintRawProperty $_ 'LastIngested')
        }
    })
    $fwLegacyRows = @($fwCategoryRows | Where-Object { $_.Form -eq 'Legacy category' })
    $fwVerdict = if (-not (Test-Path (Join-Path $rawRoot 'azure-firewall-categories.json'))) { '_Not captured in this snapshot._' }
        elseif ($fwLegacyRows.Count -gt 0 -and ($fwTableRows.Count -gt 0 -or @($fwCategoryRows | Where-Object { $_.Form -ne 'Legacy category' }).Count -gt 0)) {
            '**Collected twice.** Azure Firewall writes legacy categories into AzureDiagnostics and the resource-specific form as well; remove the legacy diagnostic setting to stop paying for the same events twice ([SAC-LOG-06]).'
        }
        elseif ($fwCategoryRows.Count -eq 0 -and $fwTableRows.Count -eq 0) { '_No Azure Firewall logs in the last {lookback}._' }
        else { 'Azure Firewall logs arrive in one form only.' }

    Write-BlueprintSection '14-coverage-breakdowns.md' (@"
$(Format-Banner -Title "Coverage Breakdowns")

Per-source coverage gaps revealed by direct table queries. A subscription, resource provider, or XDR table missing from these tables is a coverage gap to triage.
$xdrChartBlock

## AzureActivity per subscription (last {lookback-d})

Each row is a subscription shipping Activity Logs into the workspace. Subscriptions absent from this table are either not connected or have no activity in the period.

$(Format-BlueprintTable -Items $azActRows -Columns 'SubscriptionId','LogCount')

## AzureDiagnostics per resource provider (last {lookback-d})

Resource providers emitting diagnostic settings into the workspace. Maps directly to which Azure services have diagnostic settings wired up to this workspace.

$(Format-BlueprintTable -Items $azDiagRows -Columns 'ResourceProvider','LogCount')

## AzureDiagnostics per category (last {lookback-d})

Every diagnostic category writing into AzureDiagnostics, by resource provider, busiest first. A service with a resource-specific table available (Azure Firewall, Key Vault, Application Gateway and others) is cheaper and easier to query in that form ([SAC-LOG-18]).

$(Format-BlueprintTable -Items $azDiagCategoryRows -Columns 'ResourceProvider','Category','LogCount')

## Azure Firewall categories (last {lookback-d})

$fwVerdict

$(Format-BlueprintTable -Items $fwCategoryRows -Columns 'Category','Form','LogCount' -EmptyMessage (Get-BlueprintEmptyMessage 'azure-firewall-categories.json' '_No Azure Firewall categories in AzureDiagnostics._'))

Resource-specific Azure Firewall tables with data:

$(Format-BlueprintTable -Items $fwTableRows -Columns 'Table','Gb7d','LastIngested')

## XDR table presence (last {lookback-d})

Subset of well-known Defender XDR tables that have received data in the last {lookback}. Empty rows would suggest XDR is connected but a particular surface (email, identity, device) is not producing data.

$(Format-BlueprintTable -Items @($xdrRows | ForEach-Object { [pscustomobject]@{ Table = $_.Table; RecordCount = (Format-BlueprintCount $_.RecordCount) } }) -Columns 'Table','RecordCount')

## Entra ID table presence (last {recent-d})

The well-known Microsoft Entra ID tables, with their plan and retention and whether they received billable data in the last {recent}. "Catalogue only" means the schema exists but nothing is writing to it, usually a connector data type that was never enabled.

$(Format-BlueprintTable -Items $entraRows -Columns 'Table','Plan','Retention','Gb7d','Status')

[Microsoft Sentinel data connector reference (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/data-connectors-reference)
"@)

    # Left in the render context for later sections.
    $Context.name = $name
    if (Get-Variable -Name 'props' -Scope 0 -ErrorAction Ignore) { $Context.props = $props }
    $Context.r = $r
    if (Get-Variable -Name 'use' -Scope 0 -ErrorAction Ignore) { $Context.use = $use }
}
