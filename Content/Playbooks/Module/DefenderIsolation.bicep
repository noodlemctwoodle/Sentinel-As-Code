metadata title = 'DefenderIsolation'
metadata description = 'Reusable automation module: DefenderIsolation.'
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

param PlaybookName string = 'Module-DefenderIsolation'

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
        When_an_Isolation_Request_is_received: {
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
                PlaybookName: {
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
            Switch: [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
          }
        }
        Switch: {
          runAfter: {
            Initialize_Device_Details: [
              'Succeeded'
            ]
          }
          cases: {
            Isolate_Machine: {
              case: 'Incident-IsolateMachine'
              actions: {
                Condition_1: {
                  actions: {
                    'Isolate_Machines_-_Get_single_machine_Host_Name': {
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
                    'Append_Isolate_Machines_-_Get_Single_Machine_Host_Name': {
                      runAfter: {
                        'Isolate_Machines_-_Get_single_machine_Host_Name': [
                          'Succeeded'
                        ]
                      }
                      type: 'AppendToStringVariable'
                      inputs: {
                        name: 'MDEDeviceId'
                        value: '@body(\'Isolate_Machines_-_Get_single_machine_Host_Name\')?[\'id\']'
                      }
                    }
                  }
                  else: {
                    actions: {
                      'Isolate_Machines_-_Get_single_machine_Id': {
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
                      'Append_Isolate_Machines_-_Get_Single_Machine_Id': {
                        runAfter: {
                          'Isolate_Machines_-_Get_single_machine_Id': [
                            'Succeeded'
                          ]
                        }
                        type: 'AppendToStringVariable'
                        inputs: {
                          name: 'MDEDeviceId'
                          value: '@body(\'Isolate_Machines_-_Get_single_machine_Id\')?[\'id\']'
                        }
                      }
                    }
                  }
                  expression: {
                    and: [
                      {
                        not: {
                          equals: [
                            '@triggerBody()?[\'hostName\']'
                            '@null'
                          ]
                        }
                      }
                    ]
                  }
                  type: 'If'
                }
                'Actions_-_Isolate_machine': {
                  runAfter: {
                    Condition_1: [
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
                      IsolationType: 'Full'
                    }
                    path: '/api/machines/@{encodeURIComponent(variables(\'MDEDeviceId\'))}/isolate'
                  }
                }
              }
            }
            Remove_Machine_Isolation: {
              case: 'Incident-RemoveMachineIsolation'
              actions: {
                Condition: {
                  actions: {
                    'Remove_Isolation_Machines_-_Get_Single_Machine_Host_Name': {
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
                    'Append_Remove_Isolation_Machines_-_Get_Single_Machine_Host_Name': {
                      runAfter: {
                        'Remove_Isolation_Machines_-_Get_Single_Machine_Host_Name': [
                          'Succeeded'
                        ]
                      }
                      type: 'AppendToStringVariable'
                      inputs: {
                        name: 'MDEDeviceId'
                        value: '@body(\'Remove_Isolation_Machines_-_Get_Single_Machine_Host_Name\')?[\'id\']'
                      }
                    }
                  }
                  else: {
                    actions: {
                      'Remove_Isolation_Machines_-_Get_Single_Machine_Id': {
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
                      'Append_Remove_Isolation_Machines_-_Get_Single_Machine_Id': {
                        runAfter: {
                          'Remove_Isolation_Machines_-_Get_Single_Machine_Id': [
                            'Succeeded'
                          ]
                        }
                        type: 'AppendToStringVariable'
                        inputs: {
                          name: 'MDEDeviceId'
                          value: '@body(\'Remove_Isolation_Machines_-_Get_Single_Machine_Id\')?[\'id\']'
                        }
                      }
                    }
                  }
                  expression: {
                    and: [
                      {
                        not: {
                          equals: [
                            '@triggerBody()?[\'hostName\']'
                            '@null'
                          ]
                        }
                      }
                    ]
                  }
                  type: 'If'
                }
                'Actions_-_Unisolate_machine': {
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
                    }
                    path: '/api/machines/@{encodeURIComponent(variables(\'MDEDeviceId\'))}/unisolate'
                  }
                }
              }
            }
          }
          default: {
            actions: {}
          }
          expression: '@triggerBody()?[\'PlaybookName\']'
          type: 'Switch'
        }
        Host_Machine_Device_ID: {
          runAfter: {
            Condition_2: [
              'Succeeded'
            ]
          }
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
        Initialize_Device_Details: {
          runAfter: {
            Host_Machine_Device_ID: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'DeviceDetails'
                type: 'array'
              }
            ]
          }
        }
        Condition_2: {
          actions: {}
          runAfter: {}
          else: {
            actions: {
              Terminate: {
                type: 'Terminate'
                inputs: {
                  runStatus: 'Cancelled'
                }
              }
            }
          }
          expression: {
            and: [
              {
                equals: [
                  '@triggerOutputs()?[\'headers\']?[\'x-ms-workflow-name\']'
                  'Incident-IsolateMachine'
                ]
              }
              {
                equals: [
                  '@triggerOutputs()?[\'headers\']?[\'x-ms-workflow-name\']'
                  'Incident-RemoveMachineIsolation'
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
