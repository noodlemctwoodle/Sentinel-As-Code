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

@description('The Logic App\'s name.')
param PlaybookName string = 'Module-RestrictAppExecution'

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftDefenderXDRConnectionName = 'MicrosoftDefenderXDR-${PlaybookName}'

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
            connectionId: microsoftDefenderXDRConnection.id
            connectionName: microsoftDefenderXDRConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'wdatp')
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

resource microsoftDefenderXDRConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: microsoftDefenderXDRConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: microsoftDefenderXDRConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'wdatp')
    }
  }
}
