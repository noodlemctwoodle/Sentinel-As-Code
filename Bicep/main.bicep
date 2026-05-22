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

@description('Whether to (re)deploy the Sentinel module. Set false by the deployment pipeline (GitHub Actions or Azure DevOps) when Sentinel onboarding already exists on the target workspace; the Microsoft.SecurityInsights/onboardingStates resource is not idempotent and re-deploying it returns Conflict. False allows main.bicep to provision only the missing pieces (most commonly the optional playbook RG) without touching an existing Sentinel deployment.')
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

// When the sentinel module is skipped (deploySentinel = false), the
// downstream resourceId / workspace outputs are not meaningful. To
// give consumers a clean way to distinguish "module skipped" from
// "module ran but produced an empty value", a sentinelModuleEnabled
// boolean is emitted alongside. The name reflects what the value
// actually represents: it echoes the deploySentinel input parameter
// (was the module enabled this run?), NOT a post-deploy success
// signal (was Sentinel actually deployed?). Consumers wanting a
// success signal should test sentinelResourceId for non-emptiness
// in combination with this flag.
//
// The resourceId / workspace outputs use the `.?` safe-access plus
// `??` default-coalesce pattern instead of a ternary so Bicep can
// statically prove the access path is safe (a plain
// `deploySentinel ? sentinel.outputs.X : ''` ternary trips BCP318 -
// the analyzer can't tie the guard expression to the module's
// nullability). Consumers should branch on sentinelModuleEnabled
// rather than testing the resourceId for emptiness.
output sentinelModuleEnabled bool = deploySentinel
output sentinelResourceId string = sentinel.?outputs.?sentinelResourceId ?? ''
output logAnalyticsWorkspace object = sentinel.?outputs.?logAnalyticsWorkspace ?? {}
