/*
  sentinel.bicep - Microsoft Sentinel and Log Analytics Workspace Configuration
  
  This template deploys a Log Analytics workspace with Microsoft Sentinel enabled.
  It also configures Entity Behavior Analytics and User Entity Behavior Analytics (UEBA)
  for enhanced security monitoring capabilities.
*/

// Input parameters
param dailyQuota int             // Daily data ingestion quota in GB (0 for unlimited)
param lawName string             // Name of the Log Analytics workspace to create

// Create a Log Analytics workspace to store Sentinel data
// This is the foundation for all Sentinel capabilities
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: resourceGroup().location
  properties: {
    sku: {
      name: 'PerGB2018'          // Pay-as-you-go pricing model
    }
    retentionInDays: 90          // Default data retention period
    workspaceCapping: {
      dailyQuotaGb: (dailyQuota == 0) ? null : dailyQuota  // Set to null if 0 for unlimited ingestion
    }
  }
}

// Enable Microsoft Sentinel on the Log Analytics workspace
// This activates the SIEM & SOAR capabilities
resource Sentinel 'Microsoft.SecurityInsights/onboardingStates@2024-09-01' = {
  name: 'default'
  scope: logAnalyticsWorkspace
}

// Enable Entity Behavior Analytics for Azure Active Directory entities
// This feature tracks behaviors of users, hosts, and other entities to detect anomalies
resource EntityAnalytics 'Microsoft.SecurityInsights/settings@2023-02-01-preview' = {
  name: 'EntityAnalytics'
  kind: 'EntityAnalytics'
  scope: logAnalyticsWorkspace
  properties: {
    entityProviders: ['AzureActiveDirectory']  // Use AAD as the identity provider
  }
  dependsOn: [
    Sentinel  // Entity Analytics depends on Sentinel being enabled
  ]
}

// Configure User and Entity Behavior Analytics (UEBA) data sources
// UEBA uses machine learning to identify suspicious activities
resource uebaAnalytics 'Microsoft.SecurityInsights/settings@2023-02-01-preview' = {
  name: 'Ueba'
  kind: 'Ueba'
  scope: logAnalyticsWorkspace
  properties: {
    dataSources: [
      'AuditLogs',       // Azure AD audit logs
      'AzureActivity',   // Azure activity logs
      'SigninLogs',      // Azure AD sign-in logs
      'SecurityEvent'    // Windows security events
    ]
  }
  dependsOn: [
    EntityAnalytics  // UEBA depends on Entity Analytics being configured
  ]
}

// Output the Log Analytics workspace details for reference in other templates
output logAnalyticsWorkspace object = {
  name: logAnalyticsWorkspace.name
  id: logAnalyticsWorkspace.id
  location: logAnalyticsWorkspace.location
}
