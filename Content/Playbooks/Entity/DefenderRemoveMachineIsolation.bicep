metadata title = 'Entity-DefenderRemoveMachineIsolation'
metadata description = 'Sentinel entity-trigger playbook for Entity-DefenderRemoveMachineIsolation.'
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

@description('The Logic App\'s name.')
param PlaybookName string = 'Entity-DefenderRemoveMachineIsolation'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'Microsoftsentinel-${PlaybookName}'

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
                name: '@parameters(\'$connections\')[\'microsoftsentinel\'][\'connectionId\']'
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
        Get_incident: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'microsoftsentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              incidentArmId: '@triggerBody()?[\'IncidentArmID\']'
            }
            path: '/Incidents'
          }
        }
        Condition_1: {
          actions: {
            'Module-RemoveMachineIsolation_True': {
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-RemoveMachineIsolation'
                  }
                  triggerName: 'When_a_HTTP_request_is_received'
                }
                body: {
                  hostName: '@triggerBody()?[\'Entity\']?[\'properties\']?[\'HostName\']'
                  Comment: 'Removed Machine Isolation from Sentinel Incident #@{body(\'Get_incident\')?[\'properties\']?[\'incidentNumber\']} - @{body(\'Get_incident\')?[\'properties\']?[\'title\']}'
                }
              }
            }
            'Module-AddSentinelComment': {
              runAfter: {
                'Module-RemoveMachineIsolation_True': [
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
                  SentinelComment: '@{triggerBody()?[\'Entity\']?[\'properties\']?[\'HostName\']} was removed from isolation'
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
              'Module-RemoveMachineIsolation_False': {
                type: 'Workflow'
                inputs: {
                  host: {
                    workflow: {
                      id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-RemoveMachineIsolation'
                    }
                    triggerName: 'When_a_HTTP_request_is_received'
                  }
                  body: {
                    MachineId: '@{triggerBody()?[\'entity\']?[\'properties\']?[\'additionalData\']?[\'MdatpDeviceId\']}'
                    Comment: 'Removed Machine Isolation from Sentinel Incident #@{body(\'Get_incident\')?[\'properties\']?[\'incidentNumber\']} - @{body(\'Get_incident\')?[\'properties\']?[\'title\']}'
                  }
                }
              }
              'Module-AddSentinelComment-copy': {
                runAfter: {
                  'Module-RemoveMachineIsolation_False': [
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
                    SentinelComment: '@{triggerBody()?[\'Entity\']?[\'properties\']?[\'HostName\']} was removed from isolation'
                    IncidentARMId: '@body(\'Get_incident\')?[\'id\']'
                  }
                }
              }
            }
          }
          expression: {
            and: [
              {
                equals: [
                  '@triggerBody()?[\'entity\']?[\'properties\']?[\'additionalData\']?[\'MdatpDeviceId\']'
                  '@null'
                ]
              }
            ]
          }
          type: 'If'
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
