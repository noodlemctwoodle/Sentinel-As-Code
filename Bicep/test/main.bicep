// ---------------------------------------------------------------------------
// PR Validation Test Workspace
// ---------------------------------------------------------------------------
// Minimal Sentinel-enabled workspace deployed once and reused as the target
// for the ARM What-If validation job in .github/workflows/pr-validation.yml.
//
// Deployed manually as part of one-off PR-validation OIDC setup. See:
//   Docs/Deployment/PR-Validation-Setup.md
//
// Cost: a Free-tier Log Analytics workspace + Sentinel onboarding. No data
// is ingested by this workspace; it exists purely so the runner can call
// Test-AzResourceGroupDeployment -WhatIf with a real workspaceResourceId.
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

@description('Azure region for the test workspace.')
param location string = resourceGroup().location

@description('Name of the test Log Analytics workspace.')
@minLength(4)
@maxLength(63)
param workspaceName string = 'law-sentinel-pr-test'

@description('Resource tags applied to all resources.')
param tags object = {
  Purpose: 'PR-Validation-Test'
  ManagedBy: 'Sentinel-As-Code'
}

// -----------------------------------------------------------------------
// Log Analytics workspace (Free tier, no data retention requirements)
// -----------------------------------------------------------------------
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// -----------------------------------------------------------------------
// Modern Sentinel onboarding
// -----------------------------------------------------------------------
resource sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2024-09-01' = {
  scope: law
  name: 'default'
  properties: {}
}

// -----------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------
output workspaceId string = law.id
output workspaceName string = law.name
output workspaceResourceId string = law.id
