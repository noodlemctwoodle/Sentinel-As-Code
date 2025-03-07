// Deploy Log Analytics workspace
param dailyQuota int
param lawName string

// Create Log Analytics workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: resourceGroup().location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    workspaceCapping: {
      dailyQuotaGb: (dailyQuota == 0) ? null : dailyQuota
    }
  }
}

// Enable Microsoft Sentinel
resource Sentinel 'Microsoft.SecurityInsights/onboardingStates@2024-09-01' = {
  name: 'default'
  scope: logAnalyticsWorkspace
}

// Enable the Entity Behavior directory service
resource EntityAnalytics 'Microsoft.SecurityInsights/settings@2023-02-01-preview' = {
  name: 'EntityAnalytics'
  kind: 'EntityAnalytics'
  scope: logAnalyticsWorkspace
  properties: {
    entityProviders: ['AzureActiveDirectory']
  }
  dependsOn: [
    Sentinel
  ]
}

// Enable the additional UEBA data sources
resource uebaAnalytics 'Microsoft.SecurityInsights/settings@2023-02-01-preview' = {
  name: 'Ueba'
  kind: 'Ueba'
  scope: logAnalyticsWorkspace
  properties: {
    dataSources: ['AuditLogs', 'AzureActivity', 'SigninLogs', 'SecurityEvent']
  }
  dependsOn: [
    EntityAnalytics
  ]
}

// Output the Log Analytics workspace object
output logAnalyticsWorkspace object = {
  name: logAnalyticsWorkspace.name
  id: logAnalyticsWorkspace.id
  location: logAnalyticsWorkspace.location
}
