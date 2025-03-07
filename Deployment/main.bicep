targetScope = 'subscription'

param rgLocation string
param rgName string
param dailyQuota int
param lawName string

// Deploy resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgName
  location: rgLocation
}

// Deploy Sentinel
module sentinel 'sentinel.bicep' = {
  scope: rg
  name: 'sentinelDeployment'
  params: {
    dailyQuota: dailyQuota
    lawName: lawName
  }
}
