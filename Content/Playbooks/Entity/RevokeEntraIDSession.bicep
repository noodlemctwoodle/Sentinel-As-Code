metadata title = 'RevokeEntraIDSession'
metadata description = 'Sentinel entity-trigger playbook for RevokeEntraIDSession.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = []
metadata tags = [
  'Entity'
  'Source: Sentinel-As-Code'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: 'noodlemctwoodle'
}

@description('The Logic App\'s name.')
param PlaybookName string = 'RevokeEntraIDSession'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'

#disable-next-line BCP081
resource workflow 'Microsoft.Logic/workflows@2017-07-01' = {
  name: PlaybookName
  location: location
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
        Microsoft_Sentinel_entity: {
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'microsoftsentinel\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            path: '/entity/@{encodeURIComponent(\'Account\')}'
          }
        }
      }
      actions: {
        Condition: {
          actions: {
            'Module-AddSentinelComment': {
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-AddSentinelComment'
                  }
                  triggerName: 'When_a_HTTP_request_is_received'
                }
                body: {
                  SentinelComment: 'Sign-in session revoked for the user - @{concat(triggerBody()?[\'Entity\']?[\'properties\']?[\'Name\'], \'@\', triggerBody()?[\'Entity\']?[\'properties\']?[\'upnSuffix\'])}'
                  IncidentARMId: '@triggerBody()?[\'IncidentArmID\']'
                }
              }
            }
          }
          runAfter: {
            'Module-RevokeEntraIdSessions': [
              'Succeeded'
            ]
          }
          else: {
            actions: {}
          }
          expression: {
            and: [
              {
                not: {
                  equals: [
                    '@triggerBody()?[\'IncidentArmID\']'
                    '@null'
                  ]
                }
              }
            ]
          }
          type: 'If'
        }
        'Module-RevokeEntraIdSessions': {
          runAfter: {}
          type: 'Workflow'
          inputs: {
            host: {
              workflow: {
                id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-RevokeEntraIdSessions'
              }
              triggerName: 'When_a_HTTP_request_is_received'
            }
            body: {
              userPrincipalName: '@{concat(triggerBody()?[\'Entity\']?[\'properties\']?[\'Name\'], \'@\', triggerBody()?[\'Entity\']?[\'properties\']?[\'upnSuffix\'])}'
            }
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          microsoftsentinel: {
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Azuresentinel')
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
    }
  }
}

resource microsoftSentinelConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: microsoftSentinelConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: microsoftSentinelConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Azuresentinel')
    }
  }
}
