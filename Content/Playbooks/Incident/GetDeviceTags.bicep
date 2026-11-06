metadata title = 'GetDeviceTags'
metadata description = 'Sentinel incident-trigger playbook for GetDeviceTags targeting Host entities.'
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

param PlaybookName string = 'GetDeviceTags'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var AzureMonitorLogs0ConnectionName = 'AzureMonitorLogs0-${PlaybookName}'
var Azuresentinel0ConnectionName = 'Azuresentinel0-${PlaybookName}'
var Azuresentinel1ConnectionName = 'Azuresentinel1-${PlaybookName}'

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
              callback_url: '@listCallbackUrl()'
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
        Condition: {
          actions: {}
          runAfter: {
            'Entities_-_Get_Hosts': [
              'Succeeded'
            ]
          }
          else: {
            actions: {
              Terminate: {
                type: 'Terminate'
                inputs: {
                  runStatus: 'Succeeded'
                }
              }
            }
          }
          expression: {
            and: [
              {
                greater: [
                  '@length(body(\'Entities_-_Get_Hosts\')?[\'Hosts\'])'
                  0
                ]
              }
            ]
          }
          type: 'If'
        }
        For_each: {
          foreach: '@body(\'Entities_-_Get_Hosts\')?[\'Hosts\']'
          actions: {
            Get_Tag_from_Query: {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azuremonitorlogs\'][\'connectionId\']'
                  }
                }
                method: 'post'
                body: '''
DeviceInfo
| where TimeGenerated > ago(1d)
| where isnotempty(DeviceManualTags) or isnotempty(DeviceDynamicTags)
| where DeviceName contains "@{item()?['HostName']}"
| extend ManualTags = todynamic(DeviceManualTags), DynamicTags = todynamic(DeviceDynamicTags)
| extend CombinedTags = array_concat(ManualTags, DynamicTags)
| mv-expand CombinedTags
| summarize Tags = make_set(CombinedTags, 10) by DeviceName
| project DeviceName, Tags'''
                path: '/queryData'
                queries: {
                  subscriptions: '\', subscription().subscriptionId, \''
                  resourcegroups: 'stl-sec-siem-rg'
                  resourcetype: 'Log Analytics Workspace'
                  resourcename: 'stl-sec-siem-law'
                  timerange: 'Last 7 days'
                }
              }
            }
            Condition_1: {
              actions: {
                Parse_Query_Results: {
                  type: 'ParseJson'
                  inputs: {
                    content: '@body(\'Get_Tag_from_Query\')?[\'value\']'
                    schema: {
                      type: 'array'
                      items: {
                        type: 'object'
                        properties: {
                          DeviceName: {
                            type: 'string'
                          }
                          Tags: {
                            type: 'string'
                          }
                        }
                        required: [
                          'DeviceName'
                          'Tags'
                        ]
                      }
                    }
                  }
                }
                Compose: {
                  runAfter: {
                    Parse_Query_Results: [
                      'Succeeded'
                    ]
                  }
                  type: 'Compose'
                  inputs: '@if(\r\n    empty(body(\'Get_Tag_from_Query\')?[\'value\']?[0]?[\'Tags\']), \r\n    null, \r\n    json(body(\'Get_Tag_from_Query\')?[\'value\']?[0]?[\'Tags\'])\r\n)'
                }
                For_each_1: {
                  foreach: '@outputs(\'Compose\')'
                  actions: {
                    Compose_1: {
                      type: 'Compose'
                      inputs: '@if(\r\n    empty(items(\'For_each\')?[\'HostName\']),\r\n    concat(\'UnknownDevice: \', items(\'For_Each_1\')),\r\n    concat(\r\n        first(split(items(\'For_each\')?[\'HostName\'], \'.\')), \r\n        \': \', \r\n        items(\'For_Each_1\')\r\n    )\r\n)'
                    }
                    Update_incident: {
                      runAfter: {
                        Compose_1: [
                          'Succeeded'
                        ]
                      }
                      type: 'ApiConnection'
                      inputs: {
                        host: {
                          connection: {
                            name: '@parameters(\'$connections\')[\'azuresentinel-1\'][\'connectionId\']'
                          }
                        }
                        method: 'put'
                        body: {
                          incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
                          tagsToAdd: {
                            TagsToAdd: [
                              {
                                Tag: '@outputs(\'Compose_1\')'
                              }
                            ]
                          }
                        }
                        path: '/Incidents'
                      }
                    }
                  }
                  runAfter: {
                    Compose: [
                      'Succeeded'
                    ]
                  }
                  type: 'Foreach'
                  runtimeConfiguration: {
                    concurrency: {
                      repetitions: 1
                    }
                  }
                }
              }
              runAfter: {
                Get_Tag_from_Query: [
                  'Succeeded'
                ]
              }
              else: {
                actions: {}
              }
              expression: {
                and: [
                  {
                    greaterOrEquals: [
                      '@length(body(\'Get_Tag_from_Query\')?[\'value\'])'
                      1
                    ]
                  }
                ]
              }
              type: 'If'
            }
          }
          runAfter: {
            Condition: [
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
          azuremonitorlogs: {
            connectionId: AzureMonitorLogs0Connection.id
            connectionName: AzureMonitorLogs0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuremonitorlogs'
          }
          'azuresentinel-1': {
            connectionId: Azuresentinel0Connection.id
            connectionName: Azuresentinel0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          azuresentinel: {
            connectionId: Azuresentinel1Connection.id
            connectionName: Azuresentinel1ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
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

resource AzureMonitorLogs0Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: AzureMonitorLogs0ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: AzureMonitorLogs0ConnectionName
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuremonitorlogs'
    }
  }
}

resource Azuresentinel0Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: Azuresentinel0ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: Azuresentinel0ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
    }
  }
}

resource Azuresentinel1Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: Azuresentinel1ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: Azuresentinel1ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
    }
  }
}
