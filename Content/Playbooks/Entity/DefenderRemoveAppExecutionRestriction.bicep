metadata title = 'Entity-DefenderRemoveAppExecutionRestriction'
metadata description = 'Sentinel entity-trigger playbook for Entity-DefenderRemoveAppExecutionRestriction.'
metadata lastUpdateTime = '31-07-2024'
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

param PlaybookName string = 'Entity-DefenderRemoveAppExecutionRestriction'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var MicrosoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'

#disable-next-line BCP081
resource workflow 'Microsoft.Logic/workflows@2017-07-01' = {
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
                  SentinelComment: '@{triggerBody()?[\'Entity\']?[\'properties\']?[\'HostName\']} was triggered to remove app execution, the status is:  Unrestricted'
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
                    SentinelComment: '@{triggerBody()?[\'Entity\']?[\'properties\']?[\'HostName\']} was triggered to remove app execution, the status is:  Unrestricted'
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
            connectionId: MicrosoftSentinelConnection.id
            connectionName: MicrosoftSentinelConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/Azuresentinel'
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
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/Azuresentinel'
    }
  }
}
