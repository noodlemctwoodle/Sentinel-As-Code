metadata title = 'RestrictAppExecution'
metadata description = 'Reusable automation module: RestrictAppExecution.'
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

param PlaybookName string = 'Module-RestrictAppExecution'

var MicrosoftDefenderXDRConnectionName = 'MicrosoftDefenderXDR-${PlaybookName}'

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
        Response: {
          runAfter: {
            'Actions_-_Restrict_app_execution': [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
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
            'Machines_-_Get_single_machine_hostName': {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'wdatp\'][\'connectionId\']'
                  }
                }
                method: 'get'
                path: '/api/machines/@{encodeURIComponent(triggerBody()?[\'hostName\'])}'
              }
            }
            Append_to_DeviceId_Var_True: {
              runAfter: {
                'Machines_-_Get_single_machine_hostName': [
                  'Succeeded'
                ]
              }
              type: 'AppendToStringVariable'
              inputs: {
                name: 'MDEDeviceId'
                value: '@body(\'Machines_-_Get_single_machine_hostName\')?[\'id\']'
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
              'Machines_-_Get_single_machine_Id': {
                type: 'ApiConnection'
                inputs: {
                  host: {
                    connection: {
                      name: '@parameters(\'$connections\')[\'wdatp\'][\'connectionId\']'
                    }
                  }
                  method: 'get'
                  path: '/api/machines/@{encodeURIComponent(triggerBody()?[\'MachineId\'])}'
                }
              }
              Append_to_DeviceId_Var_False: {
                runAfter: {
                  'Machines_-_Get_single_machine_Id': [
                    'Succeeded'
                  ]
                }
                type: 'AppendToStringVariable'
                inputs: {
                  name: 'MDEDeviceId'
                  value: '@body(\'Machines_-_Get_single_machine_Id\')?[\'id\']'
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
        'Actions_-_Restrict_app_execution': {
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
            }
            path: '/api/machines/@{encodeURIComponent(variables(\'MDEDeviceId\'))}/restrictCodeExecution'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          wdatp: {
            connectionId: MicrosoftDefenderXDRConnection.id
            connectionName: MicrosoftDefenderXDRConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/wdatp'
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

resource MicrosoftDefenderXDRConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: MicrosoftDefenderXDRConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: MicrosoftDefenderXDRConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/wdatp'
    }
  }
}
