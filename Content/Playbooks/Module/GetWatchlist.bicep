metadata title = 'GetWatchlist'
metadata description = 'Reusable automation module: GetWatchlist.'
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
param PlaybookName string = 'Module-GetWatchlist'

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
        'Watchlists_-_Get_a_Watchlist_by_alias': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'MicrosoftSentinel\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/Watchlists/subscriptions/@{encodeURIComponent(triggerBody()?[\'subscriptionId\'])}/resourceGroups/@{encodeURIComponent(triggerBody()?[\'resourceGroup\'])}/workspaces/@{encodeURIComponent(triggerBody()?[\'workspaceId\'])}/watchlists/@{encodeURIComponent(triggerBody()?[\'watchlistAlias\'])}'
          }
        }
        Response: {
          runAfter: {
            Parse_JSON: [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              watchlistId: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.watchlistId\']}'
              displayName: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.displayName\']}'
              provider: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.provider\']}'
              source: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.source\']}'
              sourceType: '@body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.sourceType\']'
              created: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.created\']}'
              updated: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.updated\']}'
              description: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.description\']}'
              watchlistType: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.watchlistType\']}'
              watchlistAlias: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.watchlistAlias\']}'
              isDeleted: '@body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.isDeleted\']'
              defaultDuration: '@body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.defaultDuration\']'
              tenantId: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.tenantId\']}'
              numberOfLinesToSkip: '@body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.numberOfLinesToSkip\']'
              rawContent: '@body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.rawContent\']'
              itemsSearchKey: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.itemsSearchKey\']}'
              contentType: '@body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.contentType\']'
              uploadStatus: '@body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.uploadStatus\']'
              watchlistItemsCount: '@body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.watchlistItemsCount\']'
              provisioningState: '@{body(\'Parse_JSON\')?[\'watchlist\']?[\'properties.provisioningState\']}'
            }
          }
        }
        Parse_JSON: {
          runAfter: {
            'Watchlists_-_Get_a_Watchlist_by_alias': [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '@body(\'Watchlists_-_Get_a_Watchlist_by_alias\')?[\'properties\']'
            schema: {
              type: 'object'
              properties: {
                watchlistId: {
                  type: 'string'
                }
                watchlistItemsSearchKey: {
                  type: 'string'
                }
                watchlistAlias: {
                  type: 'string'
                }
                watchlist: {
                  type: 'object'
                  properties: {
                    'properties.watchlistId': {
                      type: 'string'
                    }
                    'properties.displayName': {
                      type: 'string'
                    }
                    'properties.provider': {
                      type: 'string'
                    }
                    'properties.source': {
                      type: 'string'
                    }
                    'properties.sourceType': {}
                    'properties.created': {
                      type: 'string'
                    }
                    'properties.updated': {
                      type: 'string'
                    }
                    'properties.createdBy': {
                      type: 'object'
                      properties: {
                        email: {}
                        name: {
                          type: 'string'
                        }
                        objectId: {
                          type: 'string'
                        }
                      }
                    }
                    'properties.updatedBy': {
                      type: 'object'
                      properties: {
                        email: {}
                        name: {
                          type: 'string'
                        }
                        objectId: {
                          type: 'string'
                        }
                      }
                    }
                    'properties.description': {
                      type: 'string'
                    }
                    'properties.watchlistType': {
                      type: 'string'
                    }
                    'properties.watchlistAlias': {
                      type: 'string'
                    }
                    'properties.isDeleted': {
                      type: 'boolean'
                    }
                    'properties.labels': {
                      type: 'array'
                    }
                    'properties.defaultDuration': {}
                    'properties.tenantId': {
                      type: 'string'
                    }
                    'properties.numberOfLinesToSkip': {
                      type: 'integer'
                    }
                    'properties.rawContent': {}
                    'properties.itemsSearchKey': {
                      type: 'string'
                    }
                    'properties.contentType': {}
                    'properties.uploadStatus': {}
                    'properties.watchlistItemsCount': {}
                    'properties.SasUri': {}
                    'properties.provisioningState': {
                      type: 'string'
                    }
                    etag: {
                      type: 'string'
                    }
                    id: {
                      type: 'string'
                    }
                    name: {
                      type: 'string'
                    }
                    type: {
                      type: 'string'
                    }
                    systemData: {
                      type: 'object'
                      properties: {
                        createdBy: {
                          type: 'string'
                        }
                        createdByType: {
                          type: 'string'
                        }
                        createdAt: {
                          type: 'string'
                        }
                        lastModifiedBy: {
                          type: 'string'
                        }
                        lastModifiedByType: {
                          type: 'string'
                        }
                        lastModifiedAt: {
                          type: 'string'
                        }
                      }
                    }
                  }
                }
              }
            }
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
