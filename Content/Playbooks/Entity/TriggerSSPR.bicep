metadata title = 'TriggerSSPR'
metadata description = 'Sentinel entity-trigger playbook for TriggerSSPR.'
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

param PlaybookName string = 'TriggerSSPR'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var MicrosoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'

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
            path: '/entity/@{encodeURIComponent(\'Account\')}'
          }
        }
      }
      actions: {
        HTTP: {
          runAfter: {}
          type: 'Http'
          inputs: {
            uri: 'https://graph.microsoft.com/beta/users/@{triggerBody()?[\'Entity\']?[\'properties\']?[\'AadUserId\']}/authentication/passwordMethods'
            method: 'GET'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: ' https://graph.microsoft.com'
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
                      id: {
                        type: 'string'
                      }
                      password: {}
                      createdDateTime: {
                        type: 'string'
                      }
                    }
                    required: [
                      'id'
                    ]
                  }
                }
              }
            }
          }
        }
        HTTP_1: {
          runAfter: {
            Compose: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            uri: 'https://graph.microsoft.com/beta/users/@{triggerBody()?[\'Entity\']?[\'properties\']?[\'AadUserId\']}/authentication/passwordMethods/@{outputs(\'Compose\')}/resetPassword'
            method: 'POST'
            headers: {
              'content-type': 'application/json'
            }
            body: {
              newPassword: '''
@{concat(
  substring(guid(), 0, 8),
  substring(base64(utcNow()), 0, 4),
  '!@#$',
  substring(guid(), 0, 4),
  '%^&*',
  substring(base64(utcNow('u')), 2, 2),
  substring(guid(), 0, 6)
)}'''
            }
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
        Compose: {
          runAfter: {
            Parse_JSON: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@body(\'Parse_JSON\')?[\'value\'][0][\'id\']'
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: MicrosoftSentinelConnection.id
            connectionName: MicrosoftSentinelConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
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

resource MicrosoftSentinelConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: MicrosoftSentinelConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: MicrosoftSentinelConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
    }
  }
}
