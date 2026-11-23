metadata title = 'RemoveAppExecutionRestriction'
metadata description = 'Sentinel entity-trigger playbook for RemoveAppExecutionRestriction.'
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
param PlaybookName string = 'RemoveAppExecutionRestriction'

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
        Microsoft_Sentinel_entity: {
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
            path: '/entity/@{encodeURIComponent(\'Host\')}'
          }
        }
      }
      actions: {
        Condition_2: {
          actions: {
            'Module-RemoveAppExecutionRestriction_True': {
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-RemoveAppExecutionRestriction'
                  }
                  triggerName: 'When_a_HTTP_request_is_received'
                }
                body: {
                  hostName: '@triggerBody()?[\'Entity\']?[\'properties\']?[\'HostName\']'
                  Comment: 'Unrestricted App Execution from Sentinel Incident #@{body(\'Get_incident\')?[\'properties\']?[\'incidentNumber\']} - @{body(\'Get_incident\')?[\'properties\']?[\'title\']}'
                }
              }
            }
            'Module-AddSentinelComment_True': {
              runAfter: {
                'Module-RemoveAppExecutionRestriction_True': [
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
                  SentinelComment: '@{triggerBody()?[\'Entity\']?[\'properties\']?[\'HostName\']} was triggered to remove app execution, the status is:  Unrestricted'
                  IncidentARMId: '@body(\'Get_incident\')?[\'id\']'
                }
              }
            }
          }
          runAfter: {
            Get_incident: [
              'Succeeded'
            ]
          }
          else: {
            actions: {
              'Module-AddSentinelComment_False': {
                runAfter: {
                  'Module-RemoveAppExecutionRestriction_False': [
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
                    SentinelComment: '@{triggerBody()?[\'Entity\']?[\'properties\']?[\'HostName\']} was triggered to remove app execution, the status is:  Unrestricted'
                    IncidentARMId: '@body(\'Get_incident\')?[\'id\']'
                  }
                }
              }
              'Module-RemoveAppExecutionRestriction_False': {
                type: 'Workflow'
                inputs: {
                  host: {
                    workflow: {
                      id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-RemoveAppExecutionRestriction'
                    }
                    triggerName: 'When_a_HTTP_request_is_received'
                  }
                  body: {
                    MachineId: '@{triggerBody()?[\'Entity\']?[\'properties\']?[\'additionalData\']?[\'MdatpDeviceId\']}'
                    Comment: 'Unrestricted App Execution from Sentinel Incident #@{body(\'Get_incident\')?[\'properties\']?[\'incidentNumber\']} - @{body(\'Get_incident\')?[\'properties\']?[\'title\']}'
                  }
                }
              }
            }
          }
          expression: {
            and: [
              {
                not: {
                  equals: [
                    '@triggerBody()?[\'Entity\']?[\'properties\']?[\'additionalData\']?[\'MdatpDeviceId\']'
                    '@null'
                  ]
                }
              }
            ]
          }
          type: 'If'
        }
        Get_incident: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel_2\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              incidentArmId: '@triggerBody()?[\'IncidentArmID\']'
            }
            path: '/Incidents'
          }
        }
      }
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
