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
// Microsoft Sentinel (via OperationsManagement — idempotent, no ETag required)
// -----------------------------------------------------------------------

resource sentinel 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${lawName})'
  location: resourceGroup().location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'SecurityInsights(${lawName})'
    publisher: 'Microsoft'
    product: 'OMSGallery/SecurityInsights'
    promotionCode: ''
  }
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
