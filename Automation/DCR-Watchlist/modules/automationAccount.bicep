/*
  Module: Automation Account
  Deploys the account, runbook (draft), schedule, and Az.Accounts module.
  The job schedule linkage is created by the pipeline UpdateRunbook stage
  after the runbook is published.
*/

param location string
param automationAccountName string
param scheduleStartTime string
param scheduleFrequencyHours int

// ── Automation Account ────────────────────────────────────────────────────────

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name:     automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    publicNetworkAccess: true
  }
}

// ── Runbook ───────────────────────────────────────────────────────────────────

// Runbook shell — content is uploaded by the pipeline UpdateRunbook stage
// via Import-AzAutomationRunbook + Publish-AzAutomationRunbook.
resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name:   'Invoke-DCRWatchlistSync'
  location: location
  properties: {
    runbookType:  'PowerShell72'
    logProgress:  true
    logVerbose:   false
    description:  'Queries DCR associations via ARM REST API and replaces the Sentinel CustomerResources watchlist.'
  }
}

// ── Modules: Az.Accounts (PowerShell 7.2 runtime) ───────────────────────────
// PowerShell 7.2 modules use the powershell72Modules resource type.
// Only Az.Accounts is required — DCR enumeration uses Invoke-AzRestMethod
// directly against the ARM REST API, so Az.ResourceGraph is not needed.
// Pinned to 3.0.5 — latest pulls Azure.Identity 1.13+ which has unimplemented
// methods in the Automation sandbox (GetTokenAsync on ManagedIdentityCredential).

resource moduleAzAccounts 'Microsoft.Automation/automationAccounts/powershell72Modules@2023-11-01' = {
  parent: automationAccount
  name:   'Az.Accounts'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Az.Accounts/3.0.5'
    }
  }
}

// ── Schedule ──────────────────────────────────────────────────────────────────

resource schedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name:   'dcr-watchlist-sync-schedule'
  properties: {
    description:   'Triggers DCR watchlist sync runbook'
    startTime:     scheduleStartTime
    frequency:     'Hour'
    interval:      scheduleFrequencyHours
    timeZone:      'UTC'
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output principalId string = automationAccount.identity.principalId
output automationAccountId string = automationAccount.id
