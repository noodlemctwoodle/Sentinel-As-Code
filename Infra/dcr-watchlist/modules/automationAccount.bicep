/*
  Module: Automation Account
  Deploys the account, a PowerShell 7.6 runtime environment, the runbook
  (draft) linked to it, and the schedule.
  The job schedule linkage is created by the pipeline UpdateRunbook stage
  after the runbook is published.
*/

param location string
param automationAccountName string
param scheduleStartTime string
param scheduleFrequencyHours int

// ── Automation Account ────────────────────────────────────────────────────────

resource automationAccount 'Microsoft.Automation/automationAccounts@2024-10-23' = {
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

// ── Runtime environment: PowerShell 7.6 ───────────────────────────────────────
// The runbook runs on PowerShell 7.6, which Azure Automation offers only
// through a runtime environment. The Az package it carries (15.1.0, the 7.6
// default) brings Az.Accounts, the one module the runbook needs: DCR
// enumeration uses Invoke-AzRestMethod against the ARM REST API directly.

resource runtimeEnvironment 'Microsoft.Automation/automationAccounts/runtimeEnvironments@2024-10-23' = {
  parent: automationAccount
  name:   'PowerShell-76'
  location: location
  properties: {
    description: 'PowerShell 7.6 with the Az package, for Invoke-DCRWatchlistSync.'
    runtime: {
      language: 'PowerShell'
      version:  '7.6'
    }
    defaultPackages: {
      Az: '15.1.0'
    }
  }
}

// ── Runbook ───────────────────────────────────────────────────────────────────

// Runbook shell, linked to the runtime environment. The content is uploaded
// by the pipeline UpdateRunbook stage, which links the runbook again after
// the import and publishes it.
resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = {
  parent: automationAccount
  name:   'Invoke-DCRWatchlistSync'
  location: location
  properties: {
    runbookType:        'PowerShell'
    runtimeEnvironment: runtimeEnvironment.name
    logProgress:        true
    logVerbose:         false
    description:        'Queries DCR associations via ARM REST API and replaces the Sentinel CustomerResources watchlist.'
  }
}

// ── Schedule ──────────────────────────────────────────────────────────────────

resource schedule 'Microsoft.Automation/automationAccounts/schedules@2024-10-23' = {
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
