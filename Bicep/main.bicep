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

@description('Optional separate Resource Group for playbooks/Logic Apps. If empty, playbooks deploy to the main RG.')
param playbookRgName string = ''

@description('Whether to (re)deploy the Sentinel module. Set false by the workflow when Sentinel onboarding already exists on the target workspace — the Microsoft.SecurityInsights/onboardingStates resource is not idempotent and re-deploying it returns Conflict. False allows main.bicep to provision only the missing pieces (most commonly the optional playbook RG) without touching an existing Sentinel deployment.')
param deploySentinel bool = true

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
// Playbook Resource Group (optional)
// -----------------------------------------------------------------------

resource playbookRg 'Microsoft.Resources/resourceGroups@2024-07-01' = if (!empty(playbookRgName) && playbookRgName != rgName) {
  name: playbookRgName
  location: rgLocation
  tags: tags
}

// -----------------------------------------------------------------------
// Sentinel Module
// -----------------------------------------------------------------------

module sentinel 'sentinel.bicep' = if (deploySentinel) {
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

// Outputs collapse to empty values when the sentinel module was
// skipped (deploySentinel = false). Downstream pipeline stages read
// workspace identifiers from GitHub repo variables rather than from
// these outputs, so the empty-fallback path is non-breaking. The `.?`
// safe-access + `??` default-coalesce pattern is used instead of a
// ternary so Bicep can statically prove the access path is safe (a
// plain ternary trips BCP318 because the analyzer can't tie the
// guard expression to the module's nullability).
output sentinelResourceId string = sentinel.?outputs.sentinelResourceId ?? ''
output logAnalyticsWorkspace object = sentinel.?outputs.logAnalyticsWorkspace ?? {}
