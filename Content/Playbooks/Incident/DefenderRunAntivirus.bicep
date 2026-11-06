metadata title = 'Incident-DefenderRunAntivirus'
metadata description = 'Sentinel incident-trigger playbook for Incident-DefenderRunAntivirus targeting Host entities.'
metadata lastUpdateTime = '31-07-2024'
metadata entities = [
  'Host'
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

param PlaybookName string = 'Incident-DefenderRunAntivirus'
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
      actions: {
        'Entities_-_Get_Hosts': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            path: '/entities/host'
          }
        }
        For_each: {
          foreach: '@body(\'Entities_-_Get_Hosts\')?[\'Hosts\']'
          actions: {
            Condition: {
              actions: {
                'Module-RunAntivirus_True': {
                  type: 'Workflow'
                  inputs: {
                    host: {
                      workflow: {
                        id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-RunAntivirus'
                      }
                      triggerName: 'When_a_HTTP_request_is_received'
                    }
                    body: {
                      hostName: '@{items(\'For_each\')?[\'HostName\']}'
                      Comment: '@triggerBody()?[\'object\']?[\'properties\']?[\'title\']'
                    }
                  }
                }
                'Module-AddSentinelComment_True': {
                  runAfter: {
                    'Module-RunAntivirus_True': [
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
                      SentinelComment: '@{items(\'For_each\')?[\'HostName\']} (MDE Device ID: @{body(\'Module-RunAntivirus_True\')?[\'id\']}) had a full AV scan triggered and the status was @{body(\'Module-RunAntivirus_True\')?[\'status\']}'
                      IncidentARMId: '@triggerBody()?[\'object\']?[\'id\']'
                    }
                  }
                }
              }
              else: {
                actions: {
                  'Module-RunAntivirus_False': {
                    type: 'Workflow'
                    inputs: {
                      host: {
                        workflow: {
                          id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-RunAntivirus'
                        }
                        triggerName: 'When_a_HTTP_request_is_received'
                      }
                      body: {
                        MachineId: '@{items(\'For_each\')?[\'MdatpDeviceId\']}'
                        Comment: '@triggerBody()?[\'object\']?[\'properties\']?[\'title\']'
                      }
                    }
                  }
                  'Module-AddSentinelComment_False': {
                    runAfter: {
                      'Module-RunAntivirus_False': [
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
                        SentinelComment: '@{items(\'For_each\')?[\'HostName\']} (MDE Device ID: @{body(\'Module-RunAntivirus_False\')?[\'id\']}) had a full AV scan triggered and the status was @{body(\'Module-RunAntivirus_False\')?[\'status\']}'
                        IncidentARMId: '@triggerBody()?[\'object\']?[\'id\']'
                      }
                    }
                  }
                }
              }
              expression: {
                and: [
                  {
                    equals: [
                      '@items(\'For_each\')?[\'MdatpDeviceId\']'
                      '@null'
                    ]
                  }
                ]
              }
              type: 'If'
            }
          }
          runAfter: {
            'Entities_-_Get_Hosts': [
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
          azuresentinel: {
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
