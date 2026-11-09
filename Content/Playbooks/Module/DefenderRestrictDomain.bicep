metadata title = 'DefenderRestrictDomain'
metadata description = 'Reusable automation module: DefenderRestrictDomain.'
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
param PlaybookName string = 'Module-DefenderRestrictDomain'

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

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
                playbookName: {
                  type: 'string'
                }
                incidentArmId: {
                  type: 'string'
                }
                indicatorValue: {
                  type: 'string'
                }
                entityProperties: {
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
          runAfter: {}
          type: 'Http'
          inputs: {
            uri: 'https://api.securitycenter.windows.com/api/indicators'
            method: 'POST'
            body: {
              action: 'AlertAndBlock'
              application: 'Microsoft Sentinel'
              description: 'This block command has been made through the @{triggerBody()?[\'playbookName\']}. Ran on URL Entity from Microsoft Sentinel Incident with ARM ID: @{triggerBody()?[\'incidentArmId\']}. Entity properties: @{triggerBody()?[\'entityProperties\']}'
              expirationTime: '@{addDays(utcNow(), 90)}'
              indicatorType: 'DomainName'
              indicatorValue: '@{triggerBody()?[\'indicatorValue\']}'
              title: '@{guid()}'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: 'https://api.securitycenter.windows.com/'
            }
          }
          runtimeConfiguration: {
            contentTransfer: {
              transferMode: 'Chunked'
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
