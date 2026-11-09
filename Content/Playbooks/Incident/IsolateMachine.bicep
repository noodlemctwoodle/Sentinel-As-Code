metadata title = 'IsolateMachine'
metadata description = 'Sentinel incident-trigger playbook for IsolateMachine targeting Host entities.'
metadata lastUpdateTime = '24-03-2026'
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

@description('The Logic App\'s name.')
param PlaybookName string = 'IsolateMachine'

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
          runAfter: {
            Get_incident: [
              'Succeeded'
            ]
          }
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
                'Module-IsolateMachine_True': {
                  type: 'Workflow'
                  inputs: {
                    host: {
                      workflow: {
                        id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-IsolateMachine'
                      }
                      triggerName: 'When_a_HTTP_request_is_received'
                    }
                    body: {
                      hostName: '@item()?[\'HostName\']'
                      Comment: 'Machine Isolated from Sentinel Incident #@{body(\'Get_incident\')?[\'properties\']?[\'incidentNumber\']} - @{body(\'Get_incident\')?[\'properties\']?[\'title\']}'
                    }
                  }
                }
                'Module-AddSentinelComment_True': {
                  runAfter: {
                    'Module-IsolateMachine_True': [
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
                      SentinelComment: '@{item()?[\'HostName\']} was isolated'
                      IncidentARMId: '@body(\'Get_incident\')?[\'id\']'
                    }
                  }
                }
              }
              else: {
                actions: {
                  'Module-IsolateMachine_False': {
                    type: 'Workflow'
                    inputs: {
                      host: {
                        workflow: {
                          id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-IsolateMachine'
                        }
                        triggerName: 'When_a_HTTP_request_is_received'
                      }
                      body: {
                        MachineId: '@{items(\'For_each\')?[\'additionalData\']?[\'MdatpDeviceId\']}'
                        Comment: 'Machine Isolated from Sentinel Incident #@{body(\'Get_incident\')?[\'properties\']?[\'incidentNumber\']} - @{body(\'Get_incident\')?[\'properties\']?[\'title\']}'
                      }
                    }
                  }
                  'Module-AddSentinelComment_False': {
                    runAfter: {
                      'Module-IsolateMachine_False': [
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
                        SentinelComment: '@{item()?[\'HostName\']} was isolated'
                        IncidentARMId: '@body(\'Get_incident\')?[\'id\']'
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
                        '@items(\'For_each\')?[\'additionalData\']?[\'MdatpDeviceId\']'
                        '@null'
                      ]
                    }
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
              incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
            }
            path: '/Incidents'
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
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Azuresentinel')
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          azuresentinel: {
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
