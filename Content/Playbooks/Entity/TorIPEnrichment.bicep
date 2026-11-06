metadata title = 'TorIPEnrichment'
metadata description = 'Sentinel entity-trigger playbook for TorIPEnrichment.'
metadata lastUpdateTime = '24-03-2026'
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

param PlaybookName string = 'TorIPEnrichment'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var AzureMonitorLogs0ConnectionName = 'AzureMonitorLogs-${PlaybookName}'
var MicrosoftSentinel0ConnectionName = 'MicrosoftSentinel-${PlaybookName}'

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
        Microsoft_Sentinel_entity: {
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
            path: '/entity/@{encodeURIComponent(\'IP\')}'
          }
        }
      }
      actions: {
        Condition: {
          actions: {
            'Module-IPHazzardReport': {
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-IPHazzardReport'
                  }
                  triggerName: 'When_a_HTTP_request_is_received'
                }
                body: {
                  IPAddress: '@triggerBody()?[\'Entity\']?[\'properties\']?[\'Address\']'
                }
              }
            }
            Create_HTML_table: {
              runAfter: {
                Compose: [
                  'Succeeded'
                ]
              }
              type: 'Table'
              inputs: {
                from: '@body(\'Module-IPHazzardReport\')'
                format: 'HTML'
              }
            }
            'Module-AddSentinelComment_True': {
              runAfter: {
                Create_HTML_table: [
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
                  SentinelComment: '''
TOR IP Address found in Watchlist.
@{body('Create_HTML_table')}'''
                  IncidentARMId: '@triggerBody()?[\'IncidentArmID\']'
                }
              }
            }
            Compose: {
              runAfter: {
                'Module-IPHazzardReport': [
                  'Succeeded'
                ]
              }
              type: 'Compose'
              inputs: []
            }
          }
          runAfter: {
            'Run_query_and_list_results_V2_(Preview)': [
              'Succeeded'
            ]
          }
          else: {
            actions: {
              Terminate: {
                runAfter: {
                  'Module-AddSentinelComment_False': [
                    'Succeeded'
                  ]
                }
                type: 'Terminate'
                inputs: {
                  runStatus: 'Succeeded'
                }
              }
              'Module-AddSentinelComment_False': {
                type: 'Workflow'
                inputs: {
                  host: {
                    workflow: {
                      id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-AddSentinelComment'
                    }
                    triggerName: 'When_a_HTTP_request_is_received'
                  }
                  body: {
                    SentinelComment: 'TOR IP not found in the watchlist'
                    IncidentARMId: '@triggerBody()?[\'IncidentArmID\']'
                  }
                }
              }
            }
          }
          expression: {
            and: [
              {
                greaterOrEquals: [
                  '@length(body(\'Run_query_and_list_results_V2_(Preview)\')?[\'value\'])'
                  1
                ]
              }
            ]
          }
          type: 'If'
        }
        'Run_query_and_list_results_V2_(Preview)': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuremonitorlogs\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              query: '''
let TorNodes = _GetWatchlist('TorExitNodes');
TorNodes
| where SearchKey == "@{triggerBody()?['Entity']?['properties']?['Address']}"'''
              timerangetype: '2'
              timerange: {
                relativeTimeRange: 'Last 48 hours'
              }
            }
            path: '/queryDataV2'
            queries: {
              subscriptions: '\', subscription().subscriptionId, \''
              resourcegroups: 'STL-SEC-SIEM-RG'
              resourcetype: 'Log Analytics Workspace'
              resourcename: 'stl-sec-siem-law'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuremonitorlogs: {
            connectionId: AzureMonitorLogs0Connection.id
            connectionName: AzureMonitorLogs0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/Azuremonitorlogs'
          }
          azuresentinel: {
            connectionId: MicrosoftSentinel0Connection.id
            connectionName: MicrosoftSentinel0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/Azuresentinel'
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
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/Azuremonitorlogs'
    }
  }
}

resource MicrosoftSentinel0Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: MicrosoftSentinel0ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: MicrosoftSentinel0ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/Azuresentinel'
    }
  }
}
