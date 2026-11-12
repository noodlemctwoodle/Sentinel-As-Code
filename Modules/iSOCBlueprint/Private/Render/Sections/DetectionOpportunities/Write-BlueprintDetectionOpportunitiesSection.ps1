#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 28-detection-opportunities.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DetectionOpportunities/Write-BlueprintDetectionOpportunitiesSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintDetectionOpportunitiesSection {
    <#
    .SYNOPSIS
        Build the figures for and write 28-detection-opportunities.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $connectorCatalogue = $Context.connectorCatalogue
    $customDetectionTableSet = $Context.customDetectionTableSet
    $enabledRules = $Context.enabledRules
    $m = $Context.m
    $n = $Context.n
    $name = $Context.name
    $ruleTableRefs = $Context.ruleTableRefs
    $sol = $Context.sol
    $tablesWithData = $Context.tablesWithData
    $templateSolutionMap = $Context.templateSolutionMap
    $templateTableRefs = $Context.templateTableRefs

    # Section 28 — Detection opportunities: tables with data that no enabled
    # rule reads, and the undeployed templates that would cover them. The
    # detection-headroom view from the health-check script contributed to the
    # project, computed from the collector's table references.
    $applicableTemplates = @($templateTableRefs | Where-Object { $_.Deprecated -ne $true -and -not (Test-TemplateRetired -Map $templateSolutionMap -TemplateId ([string]$_.TemplateId)) })
    $undeployedTemplates = @($applicableTemplates | Where-Object { $_.AlreadyDeployed -ne $true })
    $enabledTableSet = @{}
    foreach ($ref in $ruleTableRefs) {
        if ($ref.Enabled -ne $true) { continue }
        foreach ($t in @($ref.Tables)) { if ($t) { $enabledTableSet[[string]$t] = $true } }
    }
    foreach ($t in $customDetectionTableSet.Keys) { $enabledTableSet[$t] = $true }
    $dataTableSet = @{}
    foreach ($t in $tablesWithData) { if ($t.DataType -and (ConvertTo-BlueprintNumber $t.BillableLast30d) -gt 0) { $dataTableSet[[string]$t.DataType] = $true } }
    $sevRank = @{ High = 0; Medium = 1; Low = 2; Informational = 3 }
    # Sentinel's own operational tables are outputs, not detection sources.
    $operationalOnlyTables = @('SecurityIncident', 'SecurityAlert', 'Usage', 'Operation', 'LAQueryLogs', 'SentinelHealth', 'SentinelAudit', 'AzureMetrics')
    $uncoveredTables = @($tablesWithData | Where-Object {
        $_.DataType -and (ConvertTo-BlueprintNumber $_.BillableLast30d) -gt 0 -and
        -not $enabledTableSet.ContainsKey([string]$_.DataType) -and
        ([string]$_.DataType) -notin $operationalOnlyTables
    } | Sort-Object { ConvertTo-BlueprintNumber $_.BillableLast30d } -Descending)
    # The Content Hub solution each template comes from, and whether it is
    # installed, from the packages' own content lists (Get-TemplateSolution).
    # Templates that read a table with data but only a deprecated solution ships:
    # left out above, listed on their own with the solution replacing it.
    $retiredReady = @($templateTableRefs | Where-Object {
        $_.Deprecated -ne $true -and $_.AlreadyDeployed -ne $true -and
        (Test-TemplateRetired -Map $templateSolutionMap -TemplateId ([string]$_.TemplateId)) -and
        @(@($_.Tables) | Where-Object { $dataTableSet.ContainsKey([string]$_) }).Count -gt 0
    } | Sort-Object DisplayName | ForEach-Object {
        $sol = Get-TemplateSolution -Map $templateSolutionMap -TemplateId ([string]$_.TemplateId)
        [pscustomobject]@{
            Template              = $_.DisplayName
            'Deprecated solution' = $sol.Solution
            'Replaced by'         = $(if ($sol.ReplacedBy) { $sol.ReplacedBy } else { '' })
            Tables                = (@($_.Tables) -join ', ')
        }
    })
    $retiredBlock = if ($retiredReady.Count -gt 0) {
        $replaced = @($retiredReady | Where-Object { $_.'Replaced by' }).Count
        @"
## Templates from deprecated solutions

**$(Format-BlueprintPlural $retiredReady.Count 'template')** $(if ($retiredReady.Count -eq 1) { 'reads a table with data but is' } else { 'read a table with data but are' }) left out of the lists above: the only Content Hub solution that ships $(if ($retiredReady.Count -eq 1) { 'it' } else { 'them' }) is deprecated, so Microsoft no longer maintains $(if ($retiredReady.Count -eq 1) { 'it' } else { 'them' })$(if ($replaced) { ", and $(Format-BlueprintCount $replaced) $(if ($replaced -eq 1) { 'names' } else { 'name' }) the solution that replaces it: install that and enable its templates instead" }). An installed deprecated solution is flagged by [SAC-DET-13].

$(Format-BlueprintTable -Items $retiredReady -Columns 'Template','Deprecated solution','Replaced by','Tables')
"@
    } else { '' }
    $opportunityRows = @($uncoveredTables | ForEach-Object {
        $name = [string]$_.DataType
        $cands = @($undeployedTemplates | Where-Object { @($_.Tables) -contains $name } | Sort-Object { $sv = [string]$_.Severity; if ($sevRank.ContainsKey($sv)) { $sevRank[$sv] } else { 9 } }, DisplayName)
        [pscustomobject]@{
            Table                       = $name
            'GB ({lookback-d})'                  = [math]::Round((ConvertTo-BlueprintNumber $_.BillableLast30d), 2)
            Templates                   = $cands.Count
            'From solutions'            = (Format-TemplateSolutionSummary -Templates $cands -Map $templateSolutionMap)
            TemplateCount               = $cands.Count
            Gb30d                       = [math]::Round((ConvertTo-BlueprintNumber $_.BillableLast30d), 2)
        }
    })
    $installedSolutionNames = @(Read-BlueprintRawArray 'content-packages.json' | Where-Object { $_ } | ForEach-Object { [string](Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'displayName' '') } | Where-Object { $_ })
    $noTemplateRows = @($opportunityRows | Where-Object { $_.TemplateCount -eq 0 } | ForEach-Object {
        [pscustomobject]@{
            Table      = $_.Table
            'GB ({lookback-d})' = $_.Gb30d
            Solutions  = $(if ($connectorCatalogue) { Get-TableSolutionLabel -Catalogue $connectorCatalogue -Table ([string]$_.Table) -InstalledSolutions $installedSolutionNames } else { '' })
        }
    })
    $readyTemplates = @($undeployedTemplates | Where-Object {
        $tbls = @($_.Tables)
        @($tbls | Where-Object { $dataTableSet.ContainsKey([string]$_) }).Count -gt 0
    } | Sort-Object { $sv = [string]$_.Severity; if ($sevRank.ContainsKey($sv)) { $sevRank[$sv] } else { 9 } }, DisplayName | ForEach-Object {
        $sol = Get-TemplateSolution -Map $templateSolutionMap -TemplateId ([string]$_.TemplateId)
        [pscustomobject]@{
            Template             = $_.DisplayName
            Solution             = $sol.Solution
            'Solution installed' = $(if ($sol.Installed -eq $true) { 'Yes' } elseif ($sol.Installed -eq $false) { 'No' } else { '' })
            Severity             = $_.Severity
            Kind                 = $_.Kind
            Tactics              = (Format-TacticList $_.Tactics)
            Tables               = (@($_.Tables) -join ', ')
        }
    })
    $readyInstalled = @($readyTemplates | Where-Object { $_.'Solution installed' -eq 'Yes' }).Count
    $readyNotInstalled = @($readyTemplates | Where-Object { $_.'Solution installed' -eq 'No' }).Count
    $readyBuiltIn = @($readyTemplates | Where-Object { $_.'Solution installed' -eq '' }).Count
    # The headroom as proportions for the SharePoint graphic: how much of the
    # template catalogue is deployed, and of what is ready to enable, how much
    # comes from a solution already installed.
    $headroomVisualLine = Format-VisualLine -Kind 'meters' -Data ([ordered]@{ meters = @(
        [ordered]@{ title = 'Applicable templates'; caption = 'Rule templates in the catalogue, deprecated ones left out'; total = $applicableTemplates.Count; parts = @(
            [ordered]@{ label = 'Deployed'; value = ($applicableTemplates.Count - $undeployedTemplates.Count); tone = 'ok' }
            [ordered]@{ label = 'Not yet deployed'; value = $undeployedTemplates.Count; tone = 'violet' }
        ) }
        [ordered]@{ title = 'Ready to enable'; caption = 'Not yet deployed, and their tables have data'; total = $readyTemplates.Count; parts = @(
            [ordered]@{ label = 'Solution installed'; value = $readyInstalled; tone = 'ok' }
            [ordered]@{ label = 'Solution not installed'; value = $readyNotInstalled; tone = 'warn' }
            [ordered]@{ label = 'Built-in'; value = $readyBuiltIn; tone = 'info' }
        ) }
    ); figures = @(
        [ordered]@{ label = 'Enabled analytics rules'; value = $enabledRules.Count; caption = 'Of every kind, on this workspace' }
        [ordered]@{ label = 'Tables with data and no detection'; value = $opportunityRows.Count; caption = 'Read by no enabled rule or custom detection, last {lookback}' }
    ) })
    $headroomChart = if ($applicableTemplates.Count -gt 0 -or $enabledRules.Count -gt 0) {
    @"

``````mermaid
---
config:
  xyChart:
    width: 900
    height: 380
---
xychart-beta
$headroomVisualLine
    title "Detection headroom"
    x-axis ["Applicable templates", "Enabled rules", "Not yet deployed"]
    y-axis "Count" 0 --> $([math]::Max($applicableTemplates.Count, $enabledRules.Count) + 2)
    bar [$($applicableTemplates.Count), $($enabledRules.Count), $($undeployedTemplates.Count)]
``````
"@
    } else { '' }
    $opportunityBody = if ($ruleTableRefs.Count -eq 0 -and $templateTableRefs.Count -eq 0) {
    @"
$(Format-Banner -Title "Detection Opportunities")

_Table-to-rule mapping was not computed in this run (``rule-table-references.json`` and ``template-table-references.json`` are absent), so there is nothing to compare. The collector writes both; they are missing from an inventory taken by an older collector or when that capture failed._
"@
    } else {
    @"
$(Format-Banner -Title "Detection Opportunities")

Which ingested tables no enabled analytics rule reads, and which rule templates would cover them. The template list is the workspace's own alert-rule template catalogue, so a suggestion here can be enabled from Content Hub without a new data source. Deprecated templates and templates already deployed are never suggested.
$headroomChart

<!-- bp:shown-in-graphic -->

**$(Format-BlueprintPlural $applicableTemplates.Count 'applicable template')**  ·  **$(Format-BlueprintPlural $enabledRules.Count 'enabled rule')**  ·  **$(Format-BlueprintPlural $undeployedTemplates.Count 'template')** not yet deployed  ·  **$(Format-BlueprintPlural $opportunityRows.Count 'table')** with data and no detection

## Tables with data but no detection (last {lookback-d})

"Detection" here means an enabled Sentinel analytics rule, or an enabled Defender XDR custom detection, whose query reads the table. Alerts raised inside Defender XDR, Entra ID Protection, Defender for Identity or Defender for Cloud do not read workspace tables, so a table can be covered by a first-party product and still appear below; see the alerts by detection source in [16-alerts.md](16-alerts.md) before treating a row as unprotected.

``Templates`` counts the undeployed templates that read the table, and ``From solutions`` the Content Hub solutions they come from, marking those installed; Built-in templates ship with Sentinel rather than in a solution. Every template is listed, with its solution, under **Undeployed templates ready to enable** below: filter that list by a table's name to see its templates.

$(Format-BlueprintTable -Items $opportunityRows -Columns 'Table','GB ({lookback-d})','Templates','From solutions')

## Tables with no template available

Tables above with no undeployed, non-deprecated template that reads them. Covering one of these means writing a custom rule, or a Defender XDR custom detection, rather than enabling a template. ``Solutions`` names the Content Hub solutions that ship the table, from the connector catalogue, marking the ones installed: installing one usually brings rule templates for it. A blank means no Content Hub solution ships the table, as for most custom tables.

$(Format-BlueprintTable -Items $noTemplateRows -Columns 'Table','GB ({lookback-d})','Solutions' -EmptyMessage '_Every table above has at least one template available._')

[SAC-MON-05] lists the same tables above 5 GB per 30 days. A table kept for investigation only belongs on a cheaper tier; see [81-table-plans-retention.md](81-table-plans-retention.md).

## Undeployed templates ready to enable

Templates that are not deployed, not deprecated (nor shipped only by a deprecated solution), and read at least one table that has data, highest severity first, with the Content Hub solution each comes from. **$(Format-BlueprintCount $readyInstalled)** come from solutions already installed and can be enabled as they are; **$(Format-BlueprintCount $readyNotInstalled)** are in solutions not installed, which Sentinel still offers as gallery templates (installing the solution keeps them current); **$(Format-BlueprintCount $readyBuiltIn)** are built-in templates no solution ships.

$(Format-BlueprintTable -Items $readyTemplates -Columns 'Template','Solution','Solution installed','Severity','Kind','Tactics','Tables')

$retiredBlock

[SOC optimization (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/soc-optimization/soc-optimization-access) · [Detect threats from template](https://learn.microsoft.com/azure/sentinel/detect-threats-from-template)
"@
    }
    Write-BlueprintSection '28-detection-opportunities.md' $opportunityBody

    # Left in the render context for later sections.
    $Context.t = $t
}
