metadata title = 'KQLGetIntelligence'
metadata description = 'Reusable automation module: KQLGetIntelligence.'
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

param PlaybookName string = 'Module-KQLGetIntelligence'

var AzureMonitorLogsConnectionName = 'AzureMonitorLogs-${PlaybookName}'

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
        'Module-KQLGetIntelligence': {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                entity: {
                  type: 'string'
                }
                entityType: {
                  type: 'string'
                }
                playboookNmae: {
                  type: 'string'
                }
                IncidentARMId: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
      }
      actions: {
        Condition: {
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
                not: {
                  endsWith: [
                    '@triggerOutputs()?[\'headers\']?[\'x-ms-workflow-name\']'
                    'x'
                  ]
                }
              }
            ]
          }
          type: 'If'
        }
        Switch: {
          runAfter: {
            Initialize_queryResults: [
              'Succeeded'
            ]
          }
          cases: {
            userPrincipalName: {
              case: 'userPrincipalName'
              actions: {
                Run_userPrincipalName_query: {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azuremonitorlogs-1\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: '''
union isfuzzy=true BehaviorAnalytics, AADNonInteractiveUserSignInLogs, ThreatIntelligenceIndicator, SigninLogs
| extend Status = iff(isempty( Status_dynamic ), todynamic(Status_string), Status_dynamic)
| extend DeviceDetail = iff(isempty( DeviceDetail_dynamic ), todynamic(DeviceDetail_string), DeviceDetail_dynamic)
| extend LocationDetails = iff(isempty( LocationDetails_dynamic ), todynamic(LocationDetails_string), LocationDetails_dynamic)
// Remove duplicated columns
| project-away *_dynamic, *_string'''
                    path: '/queryData'
                    queries: {
                      subscriptions: '\', subscription().subscriptionId, \''
                      resourcegroups: 'STL-SEC-SIEM-RG'
                      resourcetype: 'Log Analytics Workspace'
                      resourcename: 'stl-sec-siem-law'
                      timerange: 'Last 24 hours'
                    }
                  }
                }
                Parse_userPrincipalName_query: {
                  runAfter: {
                    Run_userPrincipalName_query: [
                      'Succeeded'
                    ]
                  }
                  type: 'ParseJson'
                  inputs: {
                    content: '@body(\'Run_userPrincipalName_query\')?[\'value\']'
                    schema: [
                      {}
                    ]
                  }
                }
                userPrincipalName_variable: {
                  runAfter: {
                    Parse_userPrincipalName_query: [
                      'Succeeded'
                    ]
                  }
                  type: 'AppendToArrayVariable'
                  inputs: {
                    name: 'queryResults'
                    value: '@body(\'Parse_userPrincipalName_query\')'
                  }
                }
              }
            }
            domainName: {
              case: 'domainName'
              actions: {
                Run_domainName_query: {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azuremonitorlogs-1\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: '''
union isfuzzy=true BehaviorAnalytics, AADNonInteractiveUserSignInLogs, ThreatIntelligenceIndicator, SigninLogs
| extend Status = iff(isempty( Status_dynamic ), todynamic(Status_string), Status_dynamic)
| extend DeviceDetail = iff(isempty( DeviceDetail_dynamic ), todynamic(DeviceDetail_string), DeviceDetail_dynamic)
| extend LocationDetails = iff(isempty( LocationDetails_dynamic ), todynamic(LocationDetails_string), LocationDetails_dynamic)
// Remove duplicated columns
| project-away *_dynamic, *_string'''
                    path: '/queryData'
                    queries: {
                      subscriptions: '\', subscription().subscriptionId, \''
                      resourcegroups: 'STL-SEC-SIEM-RG'
                      resourcetype: 'Log Analytics Workspace'
                      resourcename: 'stl-sec-siem-law'
                      timerange: 'Last 24 hours'
                    }
                  }
                }
                Parse_domainName_query: {
                  runAfter: {
                    Run_domainName_query: [
                      'Succeeded'
                    ]
                  }
                  type: 'ParseJson'
                  inputs: {
                    content: '@body(\'Run_domainName_query\')?[\'value\']'
                    schema: [
                      {}
                    ]
                  }
                }
                domainName_variable: {
                  runAfter: {
                    Parse_domainName_query: [
                      'Succeeded'
                    ]
                  }
                  type: 'AppendToArrayVariable'
                  inputs: {
                    name: 'queryResults'
                    value: '@body(\'Parse_domainName_query\')'
                  }
                }
              }
            }
            ipAddress: {
              case: 'ipAddress'
              actions: {
                Run_ipAddress_query: {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azuremonitorlogs-1\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: '''
union isfuzzy=true BehaviorAnalytics, AADNonInteractiveUserSignInLogs, ThreatIntelligenceIndicator, SigninLogs
| extend Status = iff(isempty( Status_dynamic ), todynamic(Status_string), Status_dynamic)
| extend DeviceDetail = iff(isempty( DeviceDetail_dynamic ), todynamic(DeviceDetail_string), DeviceDetail_dynamic)
| extend LocationDetails = iff(isempty( LocationDetails_dynamic ), todynamic(LocationDetails_string), LocationDetails_dynamic)
// Remove duplicated columns
| project-away *_dynamic, *_string'''
                    path: '/queryData'
                    queries: {
                      subscriptions: '\', subscription().subscriptionId, \''
                      resourcegroups: 'STL-SEC-SIEM-RG'
                      resourcetype: 'Log Analytics Workspace'
                      resourcename: 'stl-sec-siem-law'
                      timerange: 'Last 24 hours'
                    }
                  }
                }
                Parse_ipAddress_query: {
                  runAfter: {
                    Run_ipAddress_query: [
                      'Succeeded'
                    ]
                  }
                  type: 'ParseJson'
                  inputs: {
                    content: '@body(\'Run_ipAddress_query\')?[\'value\']'
                    schema: [
                      {}
                    ]
                  }
                }
                ipAddress_variable: {
                  runAfter: {
                    Parse_ipAddress_query: [
                      'Succeeded'
                    ]
                  }
                  type: 'AppendToArrayVariable'
                  inputs: {
                    name: 'queryResults'
                    value: '@body(\'Parse_ipAddress_query\')'
                  }
                }
              }
            }
          }
          default: {
            actions: {
              Response_Failure: {
                type: 'Response'
                kind: 'Http'
                inputs: {
                  statusCode: 200
                  body: {
                    status: 'error'
                    code: 400
                    message: 'Request failed due to invalid input.'
                    timestamp: '@utcNow()'
                  }
                }
              }
            }
          }
          expression: '@triggerBody()?[\'entityType\']'
          type: 'Switch'
        }
        Initialize_queryResults: {
          runAfter: {
            Condition: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'queryResults'
                type: 'array'
              }
            ]
          }
        }
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
            body: '@variables(\'queryResults\')'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          'azuremonitorlogs-1': {
            connectionId: AzureMonitorLogsConnection.id
            connectionName: AzureMonitorLogsConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuremonitorlogs'
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

resource AzureMonitorLogsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: AzureMonitorLogsConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: AzureMonitorLogsConnectionName
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuremonitorlogs'
    }
  }
}
