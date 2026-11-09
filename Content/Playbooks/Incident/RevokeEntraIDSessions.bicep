metadata title = 'RevokeEntraIDSessions'
metadata description = 'Sentinel incident-trigger playbook for RevokeEntraIDSessions targeting Account entities.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = [
  'Account'
]
metadata tags = [
  'Incident'
  'Source: Sentinel-As-Code'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: 'noodlemctwoodle'
}

@description('The Logic App\'s name.')
param PlaybookName string = 'RevokeEntraIDSessions'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'Azuresentinel0-${PlaybookName}'
var microsoftSentinel2ConnectionName = 'Azuresentinel1-${PlaybookName}'

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
        Microsoft_Sentinel_incident: {
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel-1\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        'Entities_-_Get_Accounts': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel-2\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            path: '/entities/account'
          }
        }
        For_each: {
          foreach: '@body(\'Entities_-_Get_Accounts\')?[\'Accounts\']'
          actions: {
            'Module-RevokeEntraIdSessions': {
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-RevokeEntraIdSessions'
                  }
                  triggerName: 'When_a_HTTP_request_is_received'
                }
                body: {
                  userPrincipalName: '@{concat(items(\'For_each\')?[\'Name\'], \'@\', items(\'for_each\')?[\'UPNSuffix\'])}'
                }
              }
            }
            'Module-GetManager': {
              runAfter: {
                'Module-RevokeEntraIdSessions': [
                  'Succeeded'
                ]
              }
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-GetManager'
                  }
                  triggerName: 'When_a_HTTP_request_is_received'
                }
                body: {
                  userPrincipalName: '@{concat(items(\'For_each\')?[\'Name\'], \'@\', items(\'for_each\')?[\'UPNSuffix\'])}'
                }
              }
            }
            'Module-SendEmail': {
              runAfter: {
                'Module-GetManager': [
                  'Succeeded'
                ]
              }
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-SendEmail'
                  }
                  triggerName: 'When_a_HTTP_request_is_received'
                }
                body: {
                  To: '@{body(\'Module-GetManager\')?[\'manager\']}'
                  Subject: 'User signin sessions were reset due to security incident.'
                  Body: 'User, @{concat(items(\'For_each\')?[\'Name\'], \'@\', items(\'for_each\')?[\'UPNSuffix\'])}, was involved in part of a security incident.  As part of remediation, the user signin sessions have been revoked.  The user will need to reauthenticate in all applications.'
                }
              }
            }
            'Module-AddSentinelComment': {
              runAfter: {
                'Module-SendEmail': [
                  'Succeeded'
                ]
              }
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-AddSentinelComment'
                  }
                  triggerName: 'When_a_HTTP_request_is_received'
                }
                body: {
                  SentinelComment: 'User @{concat(items(\'For_each\')?[\'Name\'], \'@\', items(\'for_each\')?[\'UPNSuffix\'])} singin sessions were revoked in AAD and their manager was contacted using playbook.'
                  IncidentARMId: '@triggerBody()?[\'object\']?[\'id\']'
                }
              }
            }
          }
          runAfter: {
            'Entities_-_Get_Accounts': [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          'azuresentinel-2': {
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Azuresentinel')
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          'azuresentinel-1': {
            connectionId: microsoftSentinel2Connection.id
            connectionName: microsoftSentinel2ConnectionName
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

resource microsoftSentinel2Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: microsoftSentinel2ConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: microsoftSentinel2ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Azuresentinel')
    }
  }
}
