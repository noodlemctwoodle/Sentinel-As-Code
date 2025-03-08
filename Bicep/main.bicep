/*
  main.bicep - Microsoft Sentinel Infrastructure Deployment
  
  This template deploys the required infrastructure for Microsoft Sentinel at subscription scope.
  It creates a new resource group and then deploys the Microsoft Sentinel resources
  including a Log Analytics workspace with the Sentinel solution enabled.
*/

targetScope = 'subscription'

// Parameters
param rgLocation string          // Azure region for the resource group (e.g., 'uksouth', 'eastus')
param rgName string              // Name of the resource group to create or use
param dailyQuota int             // Daily data ingestion quota in GB for the Log Analytics workspace
param lawName string             // Name of the Log Analytics workspace

// Deploy the resource group to contain all Sentinel resources
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgName
  location: rgLocation
}

// Deploy Microsoft Sentinel resources using the sentinel.bicep module
// This creates the Log Analytics workspace and enables the Sentinel solution
module sentinel 'sentinel.bicep' = {
  scope: rg                      // Deploy within the resource group created above
  name: 'sentinelDeployment'     // Deployment name in the Azure deployment history
  params: {
    dailyQuota: dailyQuota       // Pass through the daily ingestion quota
    lawName: lawName             // Pass through the workspace name
  }
}
