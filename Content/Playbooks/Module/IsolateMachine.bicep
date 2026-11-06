metadata title = 'IsolateMachine'
metadata description = 'Reusable automation module: IsolateMachine.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = []
metadata tags = [
  'Module'
  'Source: Sentinel-As-Code'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: 'noodlemctwoodle'
}

param PlaybookName string = 'Module-IsolateMachine'

var Wdatp0ConnectionName = 'Wdatp0-${PlaybookName}'
var Wdatp1ConnectionName = 'Wdatp1-${PlaybookName}'

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
        When_a_HTTP_request_is_received: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                MachineId: {
                  type: 'string'
                }
                hostName: {
                  type: 'string'
                }
                Comment: {
                  type: 'string'
                }
              }
              type: 'object'
              oneOf: [
                {
                  required: [
                    'MachineId'
                  ]
                }
                {
                  required: [
                    'hostName'
                  ]
                }
              ]
            }
          }
        }
      }
      actions: {
        'Actions_-_Isolate_machine': {
          runAfter: {
            Condition: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'wdatp\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              Comment: '@triggerBody()?[\'Comment\']'
              IsolationType: 'Full'
            }
            path: '/api/machines/@{encodeURIComponent(variables(\'MDEDeviceId\'))}/isolate'
          }
        }
        Response: {
          runAfter: {
            'Actions_-_Isolate_machine': [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: '@body(\'Actions_-_Isolate_machine\')?[\'status\']'
          }
        }
        Initialize_DeviceId_Var: {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'MDEDeviceId'
                type: 'string'
              }
            ]
          }
        }
        Condition: {
          actions: {
            'Machines_-_Get_single_machine_HostName': {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'wdatp-1\'][\'connectionId\']'
                  }
                }
                method: 'get'
                path: '/api/machines/@{encodeURIComponent(triggerBody()?[\'hostName\'])}'
              }
            }
            Append_to_string_variable_True: {
              runAfter: {
                'Machines_-_Get_single_machine_HostName': [
                  'Succeeded'
                ]
              }
              type: 'AppendToStringVariable'
              inputs: {
                name: 'MDEDeviceId'
                value: '@body(\'Machines_-_Get_single_machine_HostName\')?[\'id\']'
              }
            }
          }
          runAfter: {
            Initialize_DeviceId_Var: [
              'Succeeded'
            ]
          }
          else: {
            actions: {
              'Machines_-_Get_single_MachineId': {
                type: 'ApiConnection'
                inputs: {
                  host: {
                    connection: {
                      name: '@parameters(\'$connections\')[\'wdatp-1\'][\'connectionId\']'
                    }
                  }
                  method: 'get'
                  path: '/api/machines/@{encodeURIComponent(triggerBody()?[\'MachineId\'])}'
                }
              }
              Append_to_string_variable_False: {
                runAfter: {
                  'Machines_-_Get_single_MachineId': [
                    'Succeeded'
                  ]
                }
                type: 'AppendToStringVariable'
                inputs: {
                  name: 'MDEDeviceId'
                  value: '@body(\'Machines_-_Get_single_MachineId\')?[\'id\']'
                }
              }
            }
          }
          expression: {
            and: [
              {
                equals: [
                  '@triggerBody()?[\'hostName\']'
                  '@null'
                ]
              }
            ]
          }
          type: 'If'
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          wdatp: {
            connectionId: Wdatp0Connection.id
            connectionName: Wdatp0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/Wdatp'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          'wdatp-1': {
            connectionId: Wdatp1Connection.id
            connectionName: Wdatp1ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/Wdatp'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
    }
    accessControl: {
      triggers: {
        allowedCallerIpAddresses: []
      }
      actions: {
        allowedCallerIpAddresses: []
      }
    }
  }
}

resource Wdatp0Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: Wdatp0ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: Wdatp0ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/Wdatp'
    }
  }
}

resource Wdatp1Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: Wdatp1ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: Wdatp1ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/Wdatp'
    }
  }
}
