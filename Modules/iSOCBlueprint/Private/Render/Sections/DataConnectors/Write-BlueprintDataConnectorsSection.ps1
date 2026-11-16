#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 10-data-connectors.md (part 1 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataConnectors/Write-BlueprintDataConnectorsSection.ps1
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
function Write-BlueprintDataConnectorsSection {
    <#
    .SYNOPSIS
        Build the figures for and write 10-data-connectors.md (part 1 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $connectors = $Context.connectors
    $dcrs = $Context.dcrs
    $incSummary = $Context.incSummary
    $ResourcesRoot = $Context.ResourcesRoot
    $rules = $Context.rules
    $tablesWithData = $Context.tablesWithData
    $workspace = $Context.workspace

    # ---------------------------------------------------------------------------

    $ccfDefs = Read-BlueprintRawArray 'data-connector-definitions.json'

    # Index CCF definitions by name so RestApiPoller / Push connectors can look up
    # their human-readable title via the `connectorDefinitionName` field.
    $ccfTitleByName = @{}
    foreach ($d in $ccfDefs) {
        if ($d.name -and $d.properties.connectorUiConfig.title) {
            $ccfTitleByName[$d.name] = $d.properties.connectorUiConfig.title
        }
    }

    # Pre-index tables-with-data by name so the connector rows can join on it
    # without rebuilding the lookup once per row.
    $tablesByNameForConnectors = @{}
    foreach ($t in $tablesWithData) {
        if ($t.DataType) { $tablesByNameForConnectors[$t.DataType] = $t }
    }

    $connectorRows = $connectors | ForEach-Object {
        [pscustomobject]@{
            Title     = Get-ConnectorFriendlyTitle -Kind $_.kind -Connector $_ -CcfTitleByName $ccfTitleByName
            Kind      = $_.kind
            DataTypes = Get-ConnectorDataTypes -Connector $_
            State     = Get-ConnectorAggregateState -Connector $_
            Data7d    = Get-ConnectorData7d -Connector $_
        }
    }

    $ccfRows = $ccfDefs | ForEach-Object {
        [pscustomobject]@{
            Name      = $_.name
            Title     = $_.properties.connectorUiConfig.title
            Publisher = $_.properties.connectorUiConfig.publisher
        }
    }

    # Build a per-connector / per-data-type activity table by joining each
    # connector's data types to the corresponding workspace table via
    # Get-ConnectorTargetTable, then looking up the table's last-ingested
    # timestamp and 24h billable volume from tables-with-data.json. Rows where
    # we can't map a data type to a known table are still listed (operators
    # can recognise the mapping gap) with blank activity columns.
    $tablesByName = @{}
    foreach ($t in $tablesWithData) {
        if ($t.DataType) { $tablesByName[$t.DataType] = $t }
    }

    $healthRows = foreach ($c in $connectors) {
        $kind = $c.kind
        $title = Get-ConnectorFriendlyTitle -Kind $kind -Connector $c
        $dataTypes = $c.properties.dataTypes
        if ($null -eq $dataTypes) { continue }
        foreach ($dtName in @($dataTypes.PSObject.Properties.Name)) {
            $table = Get-ConnectorTargetTable -Kind $kind -DataType $dtName
            $lastIngested = ''
            $last24h = ''
            if ($table -and $tablesByName.ContainsKey($table)) {
                $row = $tablesByName[$table]
                if ($row.LastIngested) { $lastIngested = Format-DateUtc $row.LastIngested }
                if ($null -ne $row.BillableLast24h) { $last24h = Format-Gb $row.BillableLast24h }
            }
            [pscustomobject]@{
                Connector    = $title
                DataType     = $dtName
                Table        = if ($table) { $table } else { '_(no mapping)_' }
                LastIngested = $lastIngested
                BillableLast24hGB = $last24h
            }
        }
    }

    # Build the synthesised effective-connectors view. Covers DCR-driven and
    # diagnostic-settings-driven ingestion which the Sentinel data-connectors
    # endpoint doesn't enumerate. See Get-EffectiveConnectors for the precedence
    # rules.
    $diagSettings = Read-BlueprintRawArray 'diagnostic-settings.json'
    $workspaceResourceId = if ($workspace.id) { [string]$workspace.id } else { '' }
    $effective = Get-EffectiveConnectors `
        -ClassicConnectors   $connectors `
        -CcfDefinitions      $ccfDefs `
        -Dcrs                $dcrs `
        -DiagnosticSettings  $diagSettings `
        -TablesWithData      $tablesWithData `
        -WorkspaceResourceId $workspaceResourceId

    # The connector catalogue: every Sentinel data connector and the tables it
    # writes. Each connector in the workspace is matched against it, and each
    # table in the effective view is credited to the connector the catalogue
    # names for it.
    $connectorCatalogue = Import-ConnectorCatalogue -Path (Join-Path $ResourcesRoot 'connector-catalogue.json')
    $tableActivity7d = Get-TableActivity -TablesWithData @($tablesWithData)
    $connectedConnectorIds = @($connectors | Where-Object { $_ } | ForEach-Object { Get-WorkspaceConnectorId -Connector $_ } | Where-Object { $_ })
    $catalogueStatus = if ($connectorCatalogue) { @(Get-ConnectorCatalogueStatus -Catalogue $connectorCatalogue -Connectors @($connectors) -Activity $tableActivity7d) } else { @() }
    $catalogueStatusOrder = @{ 'Silent' = 0; 'Receiving data' = 1; 'No tables in the catalogue' = 2; 'Not in the catalogue' = 3 }
    $catalogueRows = @($catalogueStatus | Sort-Object @{ Expression = { $catalogueStatusOrder[$_.Status] } }, Connector | ForEach-Object {
        [pscustomobject]@{
            Connector      = $_.Connector
            Solution       = $_.Solution
            Status         = $(if ($_.Deprecated) { "$($_.Status), deprecated connector" } else { $_.Status })
            TablesWithData = ($_.WithData -join ', ')
            QuietTables    = ($_.Quiet -join ', ')
        }
    })
    $effectiveRows = @($effective | Where-Object { $_ } | ForEach-Object {
        # A classic connector's row names its connector in the identifier.
        $ownId = if ([string]$_.Source -eq 'Classic') { ([string]$_.Identifier -split '/')[0] } else { '' }
        $label = if ($connectorCatalogue -and $_.Table) { Get-TableConnectorLabel -Catalogue $connectorCatalogue -Table ([string]$_.Table) -ConnectedIds $connectedConnectorIds -ConnectorId $ownId } else { '' }
        $_ | Select-Object *, @{ Name = 'CatalogueConnector'; Expression = { $label } }
    })
    $catalogueBlock = if (-not $connectorCatalogue) {
        '_The connector catalogue (``Resources/Data/connector-catalogue.json``) is missing from this Blueprint build._'
    } else {
        Format-BlueprintTable -Items $catalogueRows -Columns 'Connector','Solution','Status','TablesWithData','QuietTables' -EmptyMessage (Get-BlueprintEmptyMessage 'data-connectors-classic.json' '_No data connectors in the workspace._')
    }

    # Connector-kind distribution for the headline pie. Excludes CCF defs
    # (counted separately) since they're not deployed instances per se.
    $kindCounts = @{}
    foreach ($c in $connectors) {
        $k = if ($c.kind) { [string]$c.kind } else { 'unknown' }
        if (-not $kindCounts.ContainsKey($k)) { $kindCounts[$k] = 0 }
        $kindCounts[$k]++
    }
    $kindPieRows = $kindCounts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
        "    `"$($_.Key)`" : $($_.Value)"
    }

    # Defender XDR unification and Defender for Cloud: read from the classic
    # connector list, the XDR table presence capture, the rules and the
    # workspace. Defender-portal onboarding itself is not observable from the
    # workspace API, so the table says so rather than guessing.
    $mtpConnector = @($connectors | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'kind') -eq 'MicrosoftThreatProtection' }) | Select-Object -First 1
    $mtpTypes = Get-BlueprintRawProperty (Get-BlueprintRawProperty $mtpConnector 'properties') 'dataTypes'
    $mtpState = { param($name) $dt = Get-BlueprintRawProperty $mtpTypes $name; if ($dt) { [string](Get-BlueprintRawProperty $dt 'state' 'unknown') } else { 'not configured' } }
    $xdrPresenceRows = @(Read-BlueprintRawArray 'xdr-table-presence.json' | Where-Object { $_ })
    $xdrActive = @($xdrPresenceRows | Where-Object { (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'RecordCount' 0)) -gt 0 }).Count
    $legacyIncidentRulesEnabled = @($rules | Where-Object { $_ -and $_.kind -eq 'MicrosoftSecurityIncidentCreation' -and (Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'enabled' $false) }).Count
    $mdcSubscription = @($connectors | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'kind') -eq 'AzureSecurityCenter' }).Count
    $mdcTenant = @($connectors | Where-Object { $_ -and (Get-BlueprintRawProperty $_ 'kind') -eq 'MicrosoftDefenderForCloudTenantBased' }).Count
    $unifiedBillingFlag = [bool](Get-BlueprintRawProperty (Get-BlueprintRawProperty (Get-BlueprintRawProperty $workspace 'properties') 'features') 'unifiedSentinelBillingOnly' $false)
    $onboardingRow = @(Read-BlueprintRawArray 'onboarding-state.json' | Where-Object { $_ }) | Select-Object -First 1
    # What actually flows: incidents created through the unified queue, Defender
    # XDR alerts in SecurityAlert, and alerts still labelled with the retired
    # Azure Security Center product name.
    $unifiedIncidents = if ($incSummary -and $incSummary.PSObject.Properties['Unified7d']) {
        "$(Format-BlueprintCount (ConvertTo-BlueprintNumber $incSummary.Unified7d)) of $(Format-BlueprintCount (ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $incSummary 'Count7d' 0)))"
    } else { 'Not captured' }
    $alertVolumes10 = @(Read-BlueprintRawArray 'analytics-rule-volumes.json' | Where-Object { $_ })
    $xdrAlerts30d = [long](@($alertVolumes10 | Where-Object { [string]$_.ProductName -match 'Microsoft 365 Defender|Microsoft Defender XDR' } | ForEach-Object { ConvertTo-BlueprintNumber $_.Alerts }) | Measure-Object -Sum).Sum
    $ascAlerts30d = [long](@($alertVolumes10 | Where-Object { [string]$_.ProductName -eq 'Azure Security Center' } | ForEach-Object { ConvertTo-BlueprintNumber $_.Alerts }) | Measure-Object -Sum).Sum
    $unificationRows = @(
        [pscustomobject]@{ Check = 'Defender XDR connector (MicrosoftThreatProtection)'; Value = $(if ($mtpConnector) { 'Present' } else { 'Not configured' }); Meaning = 'Brings XDR incidents and alerts into the workspace; without it Sentinel and Defender run separate queues' }
        [pscustomobject]@{ Check = 'XDR incidents data type'; Value = (& $mtpState 'incidents'); Meaning = 'Enabled means Defender incidents (and their alerts) are synchronised, the unified-queue path' }
        [pscustomobject]@{ Check = 'XDR alerts data type'; Value = (& $mtpState 'alerts'); Meaning = 'Enabled means raw XDR alerts also land in SecurityAlert' }
        [pscustomobject]@{ Check = 'XDR advanced-hunting tables with data ({lookback-d})'; Value = "$xdrActive of $($xdrPresenceRows.Count) checked"; Meaning = 'Device, Email, Identity and CloudApp tables streaming into the workspace; see 14-coverage-breakdowns.md' }
        [pscustomobject]@{ Check = 'Incidents raised through Defender XDR ({recent-d})'; Value = $unifiedIncidents; Meaning = 'Incidents whose provider is Microsoft XDR (or Microsoft 365 Defender), against all incidents updated in the window; see 15-incidents.md' }
        [pscustomobject]@{ Check = 'Defender XDR alerts in SecurityAlert ({lookback-d})'; Value = $xdrAlerts30d; Meaning = 'Alerts whose product is Microsoft 365 Defender or Microsoft Defender XDR; zero with the connector present means the alerts data type is off' }
        [pscustomobject]@{ Check = 'Alerts under the retired Azure Security Center name ({lookback-d})'; Value = $ascAlerts30d; Meaning = 'Non-zero means the legacy Azure Security Center connector path is still feeding alerts; Defender for Cloud replaces it' }
        [pscustomobject]@{ Check = 'Legacy Microsoft incident-creation rules enabled'; Value = $legacyIncidentRulesEnabled; Meaning = 'The pre-unification way of promoting Defender alerts; with the incidents data type enabled they duplicate work ([SAC-DET-08])' }
        [pscustomobject]@{ Check = 'Unified Sentinel and Defender billing'; Value = $(if ($unifiedBillingFlag) { 'true' } else { 'false / absent' }); Meaning = 'features.unifiedSentinelBillingOnly on the workspace, set once the workspace is on the unified billing model' }
        [pscustomobject]@{ Check = 'Sentinel onboarding state resource'; Value = $(if ($onboardingRow) { 'Present' } else { 'Not captured' }); Meaning = 'Microsoft.SecurityInsights/onboardingStates/default exists on every Sentinel-enabled workspace; it does not prove Defender-portal onboarding' }
        [pscustomobject]@{ Check = 'Defender portal onboarding'; Value = 'Not observable'; Meaning = 'No workspace-scope API reports it; confirm under Defender portal, System, Settings, Microsoft Sentinel' }
        [pscustomobject]@{ Check = 'Defender for Cloud connector (subscription level)'; Value = $(if ($mdcSubscription -gt 0) { "Configured ($mdcSubscription)" } else { 'Not configured' }); Meaning = 'AzureSecurityCenter connector per subscription' }
        [pscustomobject]@{ Check = 'Defender for Cloud connector (tenant level)'; Value = $(if ($mdcTenant -gt 0) { 'Configured' } else { 'Not configured' }); Meaning = 'MicrosoftDefenderForCloudTenantBased connector, the newer tenant-wide path' }
    )

    # Left in the render context for later sections.
    $Context.c = $c
    $Context.catalogueBlock = $catalogueBlock
    $Context.catalogueStatus = $catalogueStatus
    $Context.ccfRows = $ccfRows
    $Context.ccfTitleByName = $ccfTitleByName
    $Context.connectedConnectorIds = $connectedConnectorIds
    $Context.connectorCatalogue = $connectorCatalogue
    $Context.connectorRows = $connectorRows
    $Context.d = $d
    $Context.effective = $effective
    $Context.effectiveRows = $effectiveRows
    $Context.healthRows = $healthRows
    if (Get-Variable -Name 'k' -Scope 0 -ErrorAction Ignore) { $Context.k = $k }
    if (Get-Variable -Name 'kind' -Scope 0 -ErrorAction Ignore) { $Context.kind = $kind }
    $Context.kindCounts = $kindCounts
    $Context.kindPieRows = $kindPieRows
    if (Get-Variable -Name 'row' -Scope 0 -ErrorAction Ignore) { $Context.row = $row }
    $Context.t = $t
    if (Get-Variable -Name 'Table' -Scope 0 -ErrorAction Ignore) { $Context.Table = $Table }
    if (Get-Variable -Name 'title' -Scope 0 -ErrorAction Ignore) { $Context.title = $title }
    $Context.unificationRows = $unificationRows
    $Context.workspaceResourceId = $workspaceResourceId
}
