// A starting point for a new playbook. Copy it to the folder for its trigger
// (Incident, Entity, Alert, Module, Watchlist or Other), give the file the
// playbook's name, set PlaybookName's default and add the actions.
//
// The deploy (Deploy-iSOCContent) fills SentinelWorkspaceName,
// SentinelResourceGroupName and the other parameters it knows from the
// workspace, by name. After a deploy, Grant-iSOCPlaybookPermission gives the
// Logic App's managed identity the roles its actions need (Microsoft Sentinel
// Responder, for this connection); it finds the playbook by the
// Source: Sentinel-As-Code tag. Files in this folder are not deployed.

metadata title = 'Playbook template'
metadata description = 'A Logic App triggered when a Microsoft Sentinel incident is created, with a Microsoft Sentinel API connection that uses the Logic App\'s managed identity.'

@description('The Logic App\'s name; the deploy updates the workflow of this name.')
param PlaybookName string = 'Incident-REPLACEWITHNAME'

@description('The Sentinel workspace, filled in by the deploy.')
param SentinelWorkspaceName string = ''

@description('The Sentinel workspace\'s resource group, filled in by the deploy.')
param SentinelResourceGroupName string = resourceGroup().name

var MicrosoftSentinelConnectionName = 'azuresentinel-${PlaybookName}'

// The start of an incident's ARM id, for actions that call the incident API.
#disable-next-line no-unused-vars
var ArmIncidentPrefix = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${SentinelResourceGroupName}/providers/Microsoft.OperationalInsights/workspaces/${SentinelWorkspaceName}/providers/Microsoft.SecurityInsights/Incidents/'

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: PlaybookName
  location: resourceGroup().location
  tags: {
    Source: 'Sentinel-As-Code'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        Microsoft_Sentinel_incident: {
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {}
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: MicrosoftSentinelConnection.id
            connectionName: MicrosoftSentinelConnectionName
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', resourceGroup().location, 'azuresentinel')
          }
        }
      }
    }
  }
}

resource MicrosoftSentinelConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: MicrosoftSentinelConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: MicrosoftSentinelConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', resourceGroup().location, 'azuresentinel')
    }
  }
}
