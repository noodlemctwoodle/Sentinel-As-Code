metadata title = 'AnalyticResults-Email'
metadata description = 'Sentinel incident-trigger playbook for AnalyticResults-Email.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = []
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
param PlaybookName string = 'AnalyticResults-Email'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'
var azureMonitorLogsConnectionName = 'AzureMonitorLogs-${PlaybookName}'

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
              callback_url: '@listCallbackUrl()'
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        For_each: {
          foreach: '@triggerBody()?[\'object\']?[\'properties\']?[\'Alerts\']'
          actions: {
            Until: {
              actions: {
                Delay: {
                  type: 'Wait'
                  inputs: {
                    interval: {
                      count: 1
                      unit: 'Minute'
                    }
                  }
                }
                Run_query_and_list_results_1: {
                  runAfter: {
                    Delay: [
                      'Succeeded'
                    ]
                  }
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azuremonitorlogs-1\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: '''
SecurityAlert
| where TimeGenerated > ago(1d)
| where SystemAlertId == "@{item()?['properties']?['systemAlertId']}"
| project Query = parse_json(ExtendedProperties).Query'''
                    path: '/queryData'
                    queries: {
                      subscriptions: '\', subscription().subscriptionId, \''
                      resourcegroups: 'STL-SEC-SIEM-RG'
                      resourcetype: 'Log Analytics Workspace'
                      resourcename: 'stl-sec-siem-law'
                      timerange: '1d'
                    }
                  }
                }
              }
              expression: '@greaterOrEquals(length(items(\'For_each\')),1)'
              limit: {
                count: 60
                timeout: 'PT1H'
              }
              type: 'Until'
            }
            Compose: {
              runAfter: {
                Until: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
              inputs: '@body(\'Run_query_and_list_results_1\')?[\'value\']'
            }
          }
          runAfter: {
            Initialize_variable: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Initialize_variable: {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'result'
                type: 'string'
              }
            ]
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Azuresentinel')
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          'azuremonitorlogs-1': {
            connectionId: azureMonitorLogsConnection.id
            connectionName: azureMonitorLogsConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuremonitorlogs')
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

resource azureMonitorLogsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: azureMonitorLogsConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: azureMonitorLogsConnectionName
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuremonitorlogs')
    }
  }
}
