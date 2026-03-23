/*
  DCR Watchlist Sync — Infrastructure
  ====================================
  Deploys:
    - Automation Account (system-assigned managed identity)
    - PowerShell runbook (imported from local script)
    - Recurring schedule + job schedule

  Post-deployment (manual):
    RBAC must be assigned after deployment — the pipeline service principal
    does not have Microsoft.Authorization/roleAssignments/write permission.

    $principalId = (az automation account show `
      --name <automationAccountName> `
      --resource-group <automationResourceGroup> `
      --query identity.principalId -o tsv)

    az role assignment create --assignee $principalId `
      --role "Monitoring Reader" `
      --scope /subscriptions/<subscriptionId>

    az role assignment create --assignee $principalId `
      --role "Microsoft Sentinel Contributor" `
      --scope /subscriptions/<subscriptionId>
*/

targetScope = 'subscription'

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Azure region for all resources.')
param location string = 'uksouth'

@description('Name of the resource group to deploy the Automation Account into.')
param automationResourceGroup string

@description('Name of the Automation Account.')
param automationAccountName string = 'aa-dcr-watchlist-sync'

@description('Schedule start time — must be at least 5 minutes in the future. Set to tomorrow 03:00 UTC or later.')
param scheduleStartTime string

@description('Schedule frequency in hours. 24 = daily, 168 = weekly.')
@allowed([ 24, 168 ])
param scheduleFrequencyHours int = 24

// ── Resource Groups ───────────────────────────────────────────────────────────

resource automationRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name:     automationResourceGroup
  location: location
}

// ── Automation Account ────────────────────────────────────────────────────────

module automationAccount 'modules/automationAccount.bicep' = {
  name:  'automationAccount'
  scope: automationRg
  params: {
    location:               location
    automationAccountName:  automationAccountName
    scheduleStartTime:      scheduleStartTime
    scheduleFrequencyHours: scheduleFrequencyHours
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output automationAccountName string = automationAccountName
output managedIdentityPrincipalId string = automationAccount.outputs.principalId
