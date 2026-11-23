metadata title = 'DefenderRestrictDomain'
metadata description = 'Sentinel entity-trigger playbook for DefenderRestrictDomain.'
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
param PlaybookName string = 'DefenderRestrictDomain'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
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
        'Microsoft_Sentinel_entity_(DNS)': {
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
            path: '/entity/@{encodeURIComponent(\'DNS\')}'
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
                  SentinelComment: '''
An AlertAndBlock request has been sent to the security centre API for the domain: @{triggerBody()?['Entity']?['properties']?['DomainName']}. Note that the expiration time on this request is 90 days.

The response from the API was:

@{body('Create_HTML_table')}
'''
                  IncidentARMId: '@triggerBody()?[\'IncidentArmID\']'
                }
              }
            }
          }
          runAfter: {
            Create_HTML_table: [
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
        'Module-DefenderAddIndicator': {
          runAfter: {
            Get_incident: [
              'Succeeded'
            ]
          }
          type: 'Workflow'
          inputs: {
            host: {
              workflow: {
                id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-DefenderAddIndicator'
              }
              triggerName: 'When_an_indicator_is_received'
            }
            body: {
              playbookName: 'Entity-DefenderRestrictDomain'
              incidentArmId: '@triggerBody()?[\'IncidentArmID\']'
              severity: '@body(\'Get_incident\')?[\'properties\']?[\'severity\']'
              indicatorValue: '@triggerBody()?[\'Entity\']?[\'properties\']?[\'DomainName\']'
              entityProperties: '@triggerBody()?[\'Entity\']?[\'properties\']'
            }
          }
        }
        Create_HTML_table: {
          runAfter: {
            'Module-DefenderAddIndicator': [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@body(\'Module-DefenderAddIndicator\')'
            format: 'HTML'
          }
        }
        Get_incident: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel-1\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              incidentArmId: '@triggerBody()?[\'IncidentArmID\']'
            }
            path: '/Incidents'
          }
          runtimeConfiguration: {
            secureData: {
              properties: [
                'inputs'
                'outputs'
              ]
            }
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          'azuresentinel-1': {
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
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
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
    }
  }
}
