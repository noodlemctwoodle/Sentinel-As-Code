metadata title = 'Schedule-CreateRiskyUsersWatchlist'
metadata description = 'Watchlist management playbook: Schedule-CreateRiskyUsersWatchlist.'
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

@description('The Logic App\'s name.')
param PlaybookName string = 'Schedule-CreateRiskyUsersWatchlist'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'

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
        SubscriptionId: {
          defaultValue: '\', subscription().subscriptionId, \''
          type: 'String'
        }
        ResourceGroup: {
          defaultValue: 'stl-sec-siem-rg'
          type: 'String'
        }
        WorkspaceId: {
          defaultValue: '17180226-9a08-4e89-bdc2-1e04db4114a2'
          type: 'String'
        }
        WatchlistAlias: {
          defaultValue: 'EntraRiskyUsers'
          type: 'String'
        }
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            interval: 1
            frequency: 'Day'
            schedule: {
              hours: [
                0
              ]
              minutes: [
                0
              ]
            }
          }
          evaluatedRecurrence: {
            interval: 1
            frequency: 'Day'
            schedule: {
              hours: [
                0
              ]
              minutes: [
                0
              ]
            }
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Initialize_variable: {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'members'
                type: 'array'
              }
            ]
          }
        }
        HTTP: {
          runAfter: {
            Initialize_variable: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            uri: 'https://graph.microsoft.com/v1.0/groups/a2b598ae-4af9-482b-9aa0-14430f0f800b/members?$select=id,displayName,userPrincipalName'
            method: 'GET'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: 'https://graph.microsoft.com'
            }
          }
          runtimeConfiguration: {
            contentTransfer: {
              transferMode: 'Chunked'
            }
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
              type: 'object'
              properties: {
                '@@odata.context': {
                  type: 'string'
                }
                value: {
                  type: 'array'
                  items: {
                    type: 'object'
                    properties: {
                      '@@odata.type': {
                        type: 'string'
                      }
                      id: {
                        type: 'string'
                      }
                      displayName: {
                        type: 'string'
                      }
                      userPrincipalName: {
                        type: 'string'
                      }
                    }
                    required: [
                      '@@odata.type'
                      'id'
                      'displayName'
                      'userPrincipalName'
                    ]
                  }
                }
              }
            }
          }
        }
        For_each: {
          foreach: '@body(\'Parse_JSON\')?[\'value\']'
          actions: {
            Append_to_array_variable: {
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'members'
                value: {
                  UserPrincipalName: '@{item()?[\'userPrincipalName\']}'
                  FriendlyName: '@{item()?[\'displayName\']}'
                  UserId: '@{item()?[\'id\']}'
                }
              }
            }
          }
          runAfter: {
            Parse_JSON: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Create_CSV_table: {
          runAfter: {
            For_each: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@variables(\'members\')'
            format: 'CSV'
          }
        }
        'Watchlists_-_Get_a_Watchlist_by_alias': {
          runAfter: {
            Create_CSV_table: [
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
            method: 'get'
            path: '/Watchlists/subscriptions/@{encodeURIComponent(parameters(\'SubscriptionId\'))}/resourceGroups/@{encodeURIComponent(parameters(\'ResourceGroup\'))}/workspaces/@{encodeURIComponent(parameters(\'WorkspaceId\'))}/watchlists/@{encodeURIComponent(parameters(\'WatchlistAlias\'))}'
          }
        }
        Condition: {
          actions: {
            'Watchlists_-_Create_a_new_Watchlist_with_data_(Raw_Content)': {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azuresentinel-1\'][\'connectionId\']'
                  }
                }
                method: 'put'
                body: {
                  description: 'A List of all Risky User in a group'
                  displayName: 'EntraIDRiskyUsers'
                  itemsSearchKey: 'UserPrincipalName'
                  rawContent: '@{body(\'Create_CSV_table\')}'
                  source: 'LogicApp'
                }
                path: '/Watchlists/subscriptions/@{encodeURIComponent(parameters(\'SubscriptionId\'))}/resourceGroups/@{encodeURIComponent(parameters(\'ResourceGroup\'))}/workspaces/@{encodeURIComponent(parameters(\'WorkspaceId\'))}/watchlists/@{encodeURIComponent(parameters(\'WatchlistAlias\'))}'
              }
            }
          }
          runAfter: {
            'Watchlists_-_Get_a_Watchlist_by_alias': [
              'Succeeded'
              'Failed'
            ]
          }
          else: {
            actions: {
              'Watchlists_-_Delete_a_Watchlist': {
                type: 'ApiConnection'
                inputs: {
                  host: {
                    connection: {
                      name: '@parameters(\'$connections\')[\'azuresentinel-1\'][\'connectionId\']'
                    }
                  }
                  method: 'delete'
                  path: '/Watchlists/subscriptions/@{encodeURIComponent(parameters(\'SubscriptionId\'))}/resourceGroups/@{encodeURIComponent(parameters(\'ResourceGroup\'))}/workspaces/@{encodeURIComponent(parameters(\'WorkspaceId\'))}/watchlists/@{encodeURIComponent(parameters(\'WatchlistAlias\'))}'
                }
              }
              Delay: {
                runAfter: {
                  'Watchlists_-_Delete_a_Watchlist': [
                    'Succeeded'
                  ]
                }
                type: 'Wait'
                inputs: {
                  interval: {
                    count: 10
                    unit: 'Second'
                  }
                }
              }
              'Watchlists_-_Create_a_new_Watchlist_with_data_(Raw_Content)-copy': {
                runAfter: {
                  Delay: [
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
                    description: 'A List of all Risky User in a group'
                    displayName: 'EntraIDRiskyUsers'
                    itemsSearchKey: 'UserPrincipalName'
                    rawContent: '@{body(\'Create_CSV_table\')}'
                    source: 'LogicApp'
                  }
                  path: '/Watchlists/subscriptions/@{encodeURIComponent(parameters(\'SubscriptionId\'))}/resourceGroups/@{encodeURIComponent(parameters(\'ResourceGroup\'))}/workspaces/@{encodeURIComponent(parameters(\'WorkspaceId\'))}/watchlists/@{encodeURIComponent(parameters(\'WatchlistAlias\'))}'
                }
              }
            }
          }
          expression: {
            and: [
              {
                equals: [
                  '@body(\'Watchlists_-_Get_a_Watchlist_by_alias\')?[\'StatusCode\']'
                  'NotFound'
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
          'azuresentinel-1': {
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
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
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
    }
  }
}
