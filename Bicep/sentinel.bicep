// -----------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------

@description('Name of the Log Analytics workspace.')
@minLength(4)
@maxLength(63)
param lawName string

@description('Daily ingestion quota in GB. 0 = unlimited.')
@minValue(0)
@maxValue(5120)
param dailyQuota int = 0

@description('Interactive retention period in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Total retention period in days (includes archive tier). 0 = use platform default.')
@minValue(0)
@maxValue(2555)
param totalRetentionInDays int = 0

@description('Resource tags applied to the workspace.')
param tags object = {}

// -----------------------------------------------------------------------
// Log Analytics Workspace
// -----------------------------------------------------------------------

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: resourceGroup().location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      totalRetentionInDays: (totalRetentionInDays == 0) ? retentionInDays : totalRetentionInDays
    }
    workspaceCapping: {
      dailyQuotaGb: (dailyQuota == 0) ? -1 : dailyQuota
    }
  }
}

// -----------------------------------------------------------------------
// Microsoft Sentinel
// -----------------------------------------------------------------------

resource sentinel 'Microsoft.SecurityInsights/onboardingStates@2024-09-01' = {
  name: 'default'
  scope: logAnalyticsWorkspace
}

// -----------------------------------------------------------------------
// Sentinel Settings
// -----------------------------------------------------------------------

// Entity Analytics — enables entity behaviour from Entra ID
resource entityAnalytics 'Microsoft.SecurityInsights/settings@2023-02-01-preview' = {
  name: 'EntityAnalytics'
  kind: 'EntityAnalytics'
  scope: logAnalyticsWorkspace
  properties: {
    entityProviders: ['AzureActiveDirectory']
  }
  dependsOn: [sentinel]
}

// UEBA — enables user and entity behaviour analytics data sources
resource uebaAnalytics 'Microsoft.SecurityInsights/settings@2023-02-01-preview' = {
  name: 'Ueba'
  kind: 'Ueba'
  scope: logAnalyticsWorkspace
  properties: {
    dataSources: ['AuditLogs', 'AzureActivity', 'SigninLogs', 'SecurityEvent']
  }
  dependsOn: [entityAnalytics]
}

// Anomalies — enables built-in ML-based anomaly detection
resource anomalies 'Microsoft.SecurityInsights/settings@2023-02-01-preview' = {
  name: 'Anomalies'
  kind: 'Anomalies'
  scope: logAnalyticsWorkspace
  properties: {}
  dependsOn: [uebaAnalytics]
}

// EyesOn — enables the SOC incident review flag and overview dashboard
resource eyesOn 'Microsoft.SecurityInsights/settings@2023-02-01-preview' = {
  name: 'EyesOn'
  kind: 'EyesOn'
  scope: logAnalyticsWorkspace
  properties: {}
  dependsOn: [sentinel]
}

// -----------------------------------------------------------------------
// Diagnostic Settings
// -----------------------------------------------------------------------

// Workspace audit logs and metrics — ships management-plane activity to itself
resource lawDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'law-diagnostics'
  scope: logAnalyticsWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
  dependsOn: [sentinel]
}

// Sentinel Health and Audit — populates SentinelHealth and SentinelAudit tables
resource sentinelHealthSettings 'Microsoft.SecurityInsights/settings@2023-02-01-preview' existing = {
  name: 'SentinelHealth'
  scope: logAnalyticsWorkspace
}

resource sentinelHealthDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sentinel-health-diagnostics'
  scope: sentinelHealthSettings
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
  dependsOn: [sentinel]
}

// -----------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------

output sentinelResourceId string = sentinel.id

output logAnalyticsWorkspace object = {
  name: logAnalyticsWorkspace.name
  id: logAnalyticsWorkspace.id
  location: logAnalyticsWorkspace.location
  retentionInDays: logAnalyticsWorkspace.properties.retentionInDays
}
