#Requires -Version 7.6

<#
.SYNOPSIS
    The captures in the order the collector runs them.

.DESCRIPTION
    Defines $script:CollectorCaptures: each capture's label (its name in the run log and the capture summary) and the function that performs it.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Data/CaptureOrder.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a value rather than running.
#>

$script:CollectorCaptures = [ordered]@{
    'workspace'                    = 'Invoke-WorkspaceCapture'
    'workspace-tables'             = 'Invoke-WorkspaceTablesCapture'
    'sentinel-onboarding-state'    = 'Invoke-SentinelOnboardingStateCapture'
    'data-connectors-classic'      = 'Invoke-DataConnectorsClassicCapture'
    'data-connector-definitions'   = 'Invoke-DataConnectorDefinitionsCapture'
    'alert-rules'                  = 'Invoke-AlertRulesCapture'
    'alert-rule-templates'         = 'Invoke-AlertRuleTemplatesCapture'
    'rule-table-references'        = 'Invoke-RuleTableReferencesCapture'
    'automation-rules'             = 'Invoke-AutomationRulesCapture'
    'watchlists'                   = 'Invoke-WatchlistsCapture'
    'bookmarks'                    = 'Invoke-BookmarksCapture'
    'hunts'                        = 'Invoke-HuntsCapture'
    'metadata'                     = 'Invoke-MetadataCapture'
    'content-packages'             = 'Invoke-ContentPackagesCapture'
    'content-product-packages'     = 'Invoke-ContentProductPackagesCapture'
    'summary-rules'                = 'Invoke-SummaryRulesCapture'
    'repositories'                 = 'Invoke-RepositoriesCapture'
    'sentinel-settings'            = 'Invoke-SentinelSettingsCapture'
    'ueba-data-presence'           = 'Invoke-UebaDataPresenceCapture'
    'kql-savedsearches'            = 'Invoke-KqlSavedsearchesCapture'
    'workbooks-saved'              = 'Invoke-WorkbooksSavedCapture'
    'workbook-templates'           = 'Invoke-WorkbookTemplatesCapture'
    'playbooks'                    = 'Invoke-PlaybooksCapture'
    'playbook-runs'                = 'Invoke-PlaybookRunsCapture'
    'dcrs'                         = 'Invoke-DcrsCapture'
    'dces'                         = 'Invoke-DcesCapture'
    'diagnostic-settings'          = 'Invoke-DiagnosticSettingsCapture'
    'dedicated-cluster'            = 'Invoke-DedicatedClusterCapture'
    'sentinel-data-lake'           = 'Invoke-SentinelDataLakeCapture'
    'linked-services'              = 'Invoke-LinkedServicesCapture'
    'linked-storage-accounts'      = 'Invoke-LinkedStorageAccountsCapture'
    'solutions-installed'          = 'Invoke-SolutionsInstalledCapture'
    'subscription'                 = 'Invoke-SubscriptionCapture'
    'resource-providers'           = 'Invoke-ResourceProvidersCapture'
    'subscription-locks'           = 'Invoke-SubscriptionLocksCapture'
    'policy-assignments'           = 'Invoke-PolicyAssignmentsCapture'
    'rbac-workspace'               = 'Invoke-RbacWorkspaceCapture'
    'rbac-resourcegroup'           = 'Invoke-RbacResourcegroupCapture'
    'tables-with-data'             = 'Invoke-TablesWithDataCapture'
    'ingestion-latency'            = 'Invoke-IngestionLatencyCapture'
    'retail-prices'                = 'Invoke-RetailPricesCapture'
    'sentinel-health'              = 'Invoke-SentinelHealthCapture'
    'soc-optimization'             = 'Invoke-SocOptimizationCapture'
    'incidents-summary'            = 'Invoke-IncidentsSummaryCapture'
    'incidents-mttr'               = 'Invoke-IncidentsMttrCapture'
    'sentinel-health-summary'      = 'Invoke-SentinelHealthSummaryCapture'
    'la-query-logs'                = 'Invoke-LaQueryLogsCapture'
    'workspace-locks'              = 'Invoke-WorkspaceLocksCapture'
    'available-service-tiers'      = 'Invoke-AvailableServiceTiersCapture'
    'workspace-usage'              = 'Invoke-WorkspaceUsageCapture'
    'incidents-detail-by-provider' = 'Invoke-IncidentsDetailByProviderCapture'
    'incidents-daily-metrics'      = 'Invoke-IncidentsDailyMetricsCapture'
    'incidents-by-rule'            = 'Invoke-IncidentsByRuleCapture'
    'ama-agents'                   = 'Invoke-AmaAgentsCapture'
    'ama-mma-migration'            = 'Invoke-AmaMmaMigrationCapture'
    'agent-heartbeat-mix'          = 'Invoke-AgentHeartbeatMixCapture'
    'data-exports'                 = 'Invoke-DataExportsCapture'
    'threat-intel-counts'          = 'Invoke-ThreatIntelCountsCapture'
    'threat-intel-metrics'         = 'Invoke-ThreatIntelMetricsCapture'
    'threat-intel-tables'          = 'Invoke-ThreatIntelTablesCapture'
    'threat-intel-health'          = 'Invoke-ThreatIntelHealthCapture'
    'taxii-clients'                = 'Invoke-TaxiiClientsCapture'
    'cef-devices'                  = 'Invoke-CefDevicesCapture'
    'cef-in-syslog'                = 'Invoke-CefInSyslogCapture'
    'security-event-duplicates'    = 'Invoke-SecurityEventDuplicatesCapture'
    'azure-activity-coverage'      = 'Invoke-AzureActivityCoverageCapture'
    'azure-diagnostics-providers'  = 'Invoke-AzureDiagnosticsProvidersCapture'
    'xdr-table-presence'           = 'Invoke-XdrTablePresenceCapture'
    'top-event-ids'                = 'Invoke-TopEventIdsCapture'
    'analytics-rule-volumes'       = 'Invoke-AnalyticsRuleVolumesCapture'
    'rule-effectiveness'           = 'Invoke-RuleEffectivenessCapture'
    'rules-fired'                  = 'Invoke-RulesFiredCapture'
    'workspace-usage-daily'        = 'Invoke-WorkspaceUsageDailyCapture'
    'daily-table-usage'            = 'Invoke-DailyTableUsageCapture'
    'daily-alerts'                 = 'Invoke-DailyAlertsCapture'
    'daily-incidents'              = 'Invoke-DailyIncidentsCapture'
    'daily-rule-incidents'         = 'Invoke-DailyRuleIncidentsCapture'
    'daily-health'                 = 'Invoke-DailyHealthCapture'
    'azure-diagnostics-categories' = 'Invoke-AzureDiagnosticsCategoriesCapture'
    'azure-firewall-categories'    = 'Invoke-AzureFirewallCategoriesCapture'
    'threat-intel-objects'         = 'Invoke-ThreatIntelObjectsCapture'
    'rule-health'                  = 'Invoke-RuleHealthCapture'
    'incident-title-stats'         = 'Invoke-IncidentTitleStatsCapture'
    'threat-intel-by-type'         = 'Invoke-ThreatIntelByTypeCapture'
    'syslog-contributors'          = 'Invoke-SyslogContributorsCapture'
    'securityevent-top-hosts'      = 'Invoke-SecurityeventTopHostsCapture'
    'table-query-usage'            = 'Invoke-TableQueryUsageCapture'
    'defender-custom-detections'   = 'Invoke-DefenderCustomDetectionsCapture'
    'whats-new'                    = 'Invoke-WhatsNewCapture'
    'cost-estimate'                = 'Invoke-CostEstimateCapture'
    'gap-analysis'                 = 'Invoke-GapAnalysisCapture'
    'maturity'                     = 'Invoke-MaturityCapture'
}
