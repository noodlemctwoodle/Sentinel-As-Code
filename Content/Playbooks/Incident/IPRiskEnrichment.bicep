metadata title = 'IPRiskEnrichment'
metadata description = 'Sentinel incident-trigger playbook for IPRiskEnrichment targeting IP entities.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = [
  'IP'
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
param PlaybookName string = 'IPRiskEnrichment'

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
        Microsoft_Sentinel_incident: {
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel_2\'][\'connectionId\']'
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
        Create_HTML_table: {
          runAfter: {
            For_each: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@variables(\'IPRiskInfo\')'
            format: 'HTML'
          }
        }
        'Entities_-_Get_IPs': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel_2\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            path: '/entities/ip'
          }
        }
        For_each: {
          foreach: '@body(\'Entities_-_Get_IPs\')?[\'IPs\']'
          actions: {
            Append_to_array_variable: {
              runAfter: {
                'Module-IPQSEnrichment': [
                  'Succeeded'
                ]
              }
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'IPRiskInfo'
                value: '@body(\'Module-IPQSEnrichment\')'
              }
            }
            'Module-IPQSEnrichment': {
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-IPQSEnrichment'
                  }
                  triggerName: 'When_a_HTTP_request_is_received'
                }
                body: {
                  ipAddress: '@item()?[\'Address\']'
                }
              }
            }
          }
          runAfter: {
            Initialize_IPRiskInfo: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Initialize_IPRiskInfo: {
          runAfter: {
            'Entities_-_Get_IPs': [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'IPRiskInfo'
                type: 'array'
              }
            ]
          }
        }
        'Module-AddSentinelComment': {
          runAfter: {
            Create_HTML_table: [
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
              SentinelComment: '@body(\'Create_HTML_table\')'
              IncidentARMId: '@triggerBody()?[\'object\']?[\'id\']'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel_2: {
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
