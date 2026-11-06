metadata title = 'TorExitNodes'
metadata description = 'Watchlist management playbook: TorExitNodes.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = []
metadata tags = [
  'Watchlist'
  'Source: Sentinel-As-Code'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: 'noodlemctwoodle'
}

param PlaybookName string = 'TorExitNodes'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

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
        SentinelResourceGroup: {
          defaultValue: 'STL-SEC-SIEM-RG'
          type: 'String'
        }
        SubscriptionId: {
          defaultValue: '\', subscription().subscriptionId, \''
          type: 'String'
        }
        WatchlistAlias: {
          defaultValue: 'TorExitNodes'
          type: 'String'
        }
        WorkspaceId: {
          defaultValue: '17180226-9a08-4e89-bdc2-1e04db4114a2'
          type: 'String'
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            frequency: 'Day'
            interval: 1
          }
          evaluatedRecurrence: {
            frequency: 'Day'
            interval: 1
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Condition: {
          actions: {
            'Module-CreateWatchlist-True': {
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-CreateWatchlist'
                  }
                  triggerName: 'When_a_HTTP_request_is_received'
                }
                body: {
                  description: 'A list of TOR exit node IP Addresses'
                  displayName: 'Tor Exit Nodes'
                  itemsSearchKey: 'TorExitNodes'
                  rawContent: '@body(\'Create_CSV_table\')'
                  source: 'Update-TorExitNodesWatchlist'
                  subscriptionId: '@parameters(\'SubscriptionId\')'
                  resourceGroup: '@parameters(\'SentinelResourceGroup\')'
                  workspaceId: '@parameters(\'WorkspaceId\')'
                  watchlistAlias: '@parameters(\'WatchlistAlias\')'
                }
              }
            }
          }
          runAfter: {
            'Module-GetWatchlist': [
              'Succeeded'
              'Failed'
            ]
          }
          else: {
            actions: {
              Delay: {
                runAfter: {
                  'Module-DeleteWatchlist': [
                    'Succeeded'
                  ]
                }
                type: 'Wait'
                inputs: {
                  interval: {
                    count: 30
                    unit: 'Second'
                  }
                }
              }
              'Module-CreateWatchlist-False': {
                runAfter: {
                  Delay: [
                    'Succeeded'
                  ]
                }
                type: 'Workflow'
                inputs: {
                  host: {
                    workflow: {
                      id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-CreateWatchlist'
                    }
                    triggerName: 'When_a_HTTP_request_is_received'
                  }
                  body: {
                    description: 'A list of TOR exit node IP Addresses'
                    displayName: 'Tor Exit Nodes'
                    itemsSearchKey: 'TorExitNodes'
                    rawContent: '@body(\'Create_CSV_table\')'
                    source: 'Update-TorExitNodesWatchlist'
                    subscriptionId: '@parameters(\'SubscriptionId\')'
                    resourceGroup: '@parameters(\'SentinelResourceGroup\')'
                    workspaceId: '@parameters(\'WorkspaceId\')'
                    watchlistAlias: '@parameters(\'WatchlistAlias\')'
                  }
                }
              }
              'Module-DeleteWatchlist': {
                type: 'Workflow'
                inputs: {
                  host: {
                    workflow: {
                      id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-DeleteWatchlist'
                    }
                    triggerName: 'When_a_HTTP_request_is_received'
                  }
                  body: {
                    resourceGroup: '@parameters(\'SentinelResourceGroup\')'
                    subscriptionId: '@parameters(\'SubscriptionId\')'
                    watchlistAlias: '@parameters(\'WatchlistAlias\')'
                    workspaceId: '@parameters(\'WorkspaceId\')'
                  }
                }
              }
            }
          }
          expression: {
            and: [
              {
                equals: [
                  '@body(\'Module-GetWatchlist\')?[\'watchlistAlias\']'
                  '@null'
                ]
              }
            ]
          }
          type: 'If'
        }
        Create_CSV_table: {
          runAfter: {
            Parse_JSON: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@body(\'Parse_JSON\')?[\'TorExitNodes\']'
            format: 'CSV'
            columns: [
              {
                header: 'TorExitNodes'
                value: '@item()'
              }
            ]
          }
        }
        HTTP: {
          runAfter: {}
          type: 'Http'
          inputs: {
            uri: 'https://raw.githubusercontent.com/noodlemctwoodle/SentinelPublic/main/ExternalData/TorExitNodes.json'
            method: 'GET'
          }
        }
        Parse_JSON: {
          runAfter: {
            HTTP: [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '@body(\'HTTP\')'
            schema: {
              properties: {
                TorExitNodes: {
                  items: {
                    type: 'string'
                  }
                  type: 'array'
                }
              }
              type: 'object'
            }
          }
        }
        'Module-GetWatchlist': {
          runAfter: {
            Create_CSV_table: [
              'Succeeded'
            ]
          }
          type: 'Workflow'
          inputs: {
            host: {
              workflow: {
                id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-GetWatchlist'
              }
              triggerName: 'When_a_HTTP_request_is_received'
            }
            body: {
              subscriptionId: '@parameters(\'SubscriptionId\')'
              resourceGroup: '@parameters(\'SentinelResourceGroup\')'
              workspaceId: '@parameters(\'WorkspaceId\')'
              watchlistAlias: '@parameters(\'WatchlistAlias\')'
            }
          }
        }
      }
      outputs: {}
    }
  }
}
