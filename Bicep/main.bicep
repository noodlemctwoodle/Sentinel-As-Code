targetScope = 'subscription'

// -----------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------

@description('Name of the Resource Group to create.')
@minLength(1)
@maxLength(90)
param rgName string

@description('Azure region for all resources.')
param rgLocation string

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

@description('Resource tags applied to all resources.')
param tags object = {}

// -----------------------------------------------------------------------
// Resource Group
// -----------------------------------------------------------------------

resource rg 'Microsoft.Resources/resourceGroups@2024-07-01' = {
  name: rgName
  location: rgLocation
  tags: tags
}

// -----------------------------------------------------------------------
// Sentinel Module
// -----------------------------------------------------------------------

module sentinel 'sentinel.bicep' = {
  scope: rg
  name: 'sentinelDeployment'
  params: {
    lawName: lawName
    dailyQuota: dailyQuota
    retentionInDays: retentionInDays
    totalRetentionInDays: totalRetentionInDays
    tags: tags
  }
}

// -----------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------

output sentinelResourceId string = sentinel.outputs.sentinelResourceId
output logAnalyticsWorkspace object = sentinel.outputs.logAnalyticsWorkspace
