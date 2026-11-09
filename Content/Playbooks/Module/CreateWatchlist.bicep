metadata title = 'CreateWatchlist'
metadata description = 'Reusable automation module: CreateWatchlist.'
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
param PlaybookName string = 'Module-CreateWatchlist'

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'

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
                description: {
                  type: 'string'
                }
                displayName: {
                  type: 'string'
                }
                itemsSearchKey: {
                  type: 'string'
                }
                rawContent: {
                  type: 'string'
                }
                source: {
                  type: 'string'
                }
                subscriptionId: {
                  type: 'string'
                }
                resourceGroup: {
                  type: 'string'
                }
                workspaceId: {
                  type: 'string'
                }
                watchlistAlias: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
      }
      actions: {
        Response: {
          runAfter: {
            'Watchlists_-_Create_a_new_Watchlist_with_data_(Raw_Content)': [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
          }
        }
        'Watchlists_-_Create_a_new_Watchlist_with_data_(Raw_Content)': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'MicrosoftSentinel\'][\'connectionId\']'
              }
            }
            method: 'put'
            body: {
              description: '@{triggerBody()?[\'description\']}'
              displayName: '@{triggerBody()?[\'displayName\']}'
              itemsSearchKey: '@{triggerBody()?[\'itemsSearchKey\']}'
              rawContent: '@triggerBody()?[\'rawContent\']'
              source: '@{triggerBody()?[\'source\']}'
            }
            path: '/Watchlists/subscriptions/@{encodeURIComponent(triggerBody()?[\'subscriptionId\'])}/resourceGroups/@{encodeURIComponent(triggerBody()?[\'resourceGroup\'])}/workspaces/@{encodeURIComponent(triggerBody()?[\'workspaceId\'])}/watchlists/@{encodeURIComponent(triggerBody()?[\'watchlistAlias\'])}'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          MicrosoftSentinel: {
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Azuresentinel')
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
