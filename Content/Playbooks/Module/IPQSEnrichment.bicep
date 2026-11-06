metadata title = 'IPQSEnrichment'
metadata description = 'Reusable automation module: IPQSEnrichment.'
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

param PlaybookName string = 'Module-IPQSEnrichment'
param AutomationResourceGroup string = ''

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
        When_a_HTTP_request_is_received: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                ipAddress: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
      }
      actions: {
        HTTP: {
          runAfter: {
            'Module-GetSecret': [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            uri: 'https://ipqualityscore.com/api/json/ip/@{body(\'Module-GetSecret\')}/@{triggerBody()?[\'ipAddress\']}'
            method: 'GET'
          }
          runtimeConfiguration: {
            contentTransfer: {
              transferMode: 'Chunked'
            }
          }
        }
        'Module-GetSecret': {
          runAfter: {}
          type: 'Workflow'
          inputs: {
            host: {
              workflow: {
                id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-GetSecret'
              }
              triggerName: 'When_a_HTTP_request_is_received'
            }
            body: {
              secretName: 'IPQS-API-Key'
            }
          }
        }
        Response: {
          runAfter: {
            HTTP: [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: '@body(\'HTTP\')'
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
