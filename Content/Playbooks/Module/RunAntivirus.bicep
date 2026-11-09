metadata title = 'RunAntivirus'
metadata description = 'Reusable automation module: RunAntivirus.'
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
param PlaybookName string = 'Module-RunAntivirus'

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftDefenderXDRConnectionName = 'Wdatp0-${PlaybookName}'
var microsoftDefenderXDR2ConnectionName = 'Wdatp1-${PlaybookName}'

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
        'Actions_-_Run_antivirus_scan': {
          runAfter: {
            Condition: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'wdatp-1\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              Comment: '@triggerBody()?[\'Comment\']'
              ScanType: 'Full'
            }
            path: '/api/machines/@{encodeURIComponent(variables(\'MDEDeviceId\'))}/runAntiVirusScan'
          }
        }
        Response: {
          runAfter: {
            'Actions_-_Run_antivirus_scan': [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              actions: '@{body(\'Actions_-_Run_antivirus_scan\')}'
              scanId: '@{body(\'Actions_-_Run_antivirus_scan\')?[\'id\']}'
              scanType: '@{body(\'Actions_-_Run_antivirus_scan\')?[\'type\']}'
              scanRequestor: '@{body(\'Actions_-_Run_antivirus_scan\')?[\'requestor\']}'
              scanRequestorComment: '@{body(\'Actions_-_Run_antivirus_scan\')?[\'requestorComment\']}'
              scanStatus: '@{body(\'Actions_-_Run_antivirus_scan\')?[\'status\']}'
              scanMachineId: '@{body(\'Actions_-_Run_antivirus_scan\')?[\'machineId\']}'
              scanCreationDate: '@{body(\'Actions_-_Run_antivirus_scan\')?[\'creationDateTimeUtc\']}'
              scanLastUpdateTime: '@{body(\'Actions_-_Run_antivirus_scan\')?[\'lastUpdateDateTimeUtc\']}'
              liveResponseStartTime: '@{item()?[\'startTime\']}'
              liveResponsenEndTime: '@{item()?[\'endTime\']}'
              liveResponseCommandStatus: '@{item()?[\'commandStatus\']}'
            }
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
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          'wdatp-1': {
            connectionId: microsoftDefenderXDRConnection.id
            connectionName: microsoftDefenderXDRConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Wdatp')
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          wdatp: {
            connectionId: microsoftDefenderXDR2Connection.id
            connectionName: microsoftDefenderXDR2ConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Wdatp')
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
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Wdatp')
    }
  }
}

resource microsoftDefenderXDR2Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: microsoftDefenderXDR2ConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: microsoftDefenderXDR2ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Wdatp')
    }
  }
}
