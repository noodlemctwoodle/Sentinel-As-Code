metadata title = 'RevokeSessions'
metadata description = 'Reusable automation module: RevokeSessions.'
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
param PlaybookName string = 'Module-RevokeSessions'

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

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
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        Manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            method: 'POST'
            schema: {
              properties: {
                entraIdUserId: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
      }
      actions: {
        HTTP_POST_Graph_RevokeSessions: {
          runAfter: {
            Authenticate_Workflow: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            uri: 'https://graph.microsoft.com/v1.0/users/@{triggerBody()?[\'entraIdUserId\']}/revokeSignInSessions'
            method: 'POST'
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
        Graph_Response: {
          runAfter: {
            Parse_JSON: [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: '@outputs(\'HTTP_POST_Graph_RevokeSessions\')?[\'statusCode\']'
            body: {
              EntraIdUserId: '@{triggerBody()?[\'entraIdUserId\']}'
              SessionsRevoke: '@{body(\'Parse_JSON\')?[\'value\']}'
            }
          }
        }
        Authenticate_Workflow: {
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
            or: [
              {
                equals: [
                  '@triggerOutputs()?[\'headers\']?[\'x-ms-workflow-name\']'
                  'Incident-RevokeSessions'
                ]
              }
              {
                equals: [
                  '@triggerOutputs()?[\'headers\']?[\'x-ms-workflow-name\']'
                  'Entity-RevokeSessions'
                ]
              }
            ]
          }
          type: 'If'
        }
        Parse_JSON: {
          runAfter: {
            HTTP_POST_Graph_RevokeSessions: [
              'Succeeded'
              'Failed'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '@body(\'HTTP_POST_Graph_RevokeSessions\')'
            schema: {
              type: 'object'
              properties: {
                '@@odata.context': {
                  type: 'string'
                }
                value: {
                  type: 'boolean'
                }
              }
            }
          }
        }
      }
      outputs: {}
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
