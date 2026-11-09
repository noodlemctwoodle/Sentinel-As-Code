metadata title = 'DefenderRestrictFileHash'
metadata description = 'Reusable automation module: DefenderRestrictFileHash.'
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
param PlaybookName string = 'Module-DefenderRestrictFileHash'

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
                algorithm: {
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
            Switch: [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
          }
        }
        Switch: {
          runAfter: {}
          cases: {
            Case: {
              case: 'SHA1'
              actions: {
                POST_SHA1: {
                  type: 'Http'
                  inputs: {
                    uri: 'https://api.securitycenter.windows.com/api/indicators'
                    method: 'POST'
                    body: {
                      action: 'AlertAndBlock'
                      application: 'Microsoft Sentinel'
                      description: 'This block command has been made through the @{triggerBody()?[\'playbookName\']}. Ran on URL Entity from Microsoft Sentinel Incident with ARM ID: @{triggerBody()?[\'incidentArmId\']}. Entity properties: @{triggerBody()?[\'entityProperties\']}'
                      expirationTime: '@{addDays(utcNow(), 90)}'
                      indicatorType: 'FileSha1'
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
              }
            }
            'Case 2': {
              case: 'SHA256'
              actions: {
                POST_SHA265: {
                  type: 'Http'
                  inputs: {
                    uri: 'https://api.securitycenter.windows.com/api/indicators'
                    method: 'POST'
                    body: {
                      action: 'AlertAndBlock'
                      application: 'Microsoft Sentinel'
                      description: 'This block command has been made through the @{triggerBody()?[\'playbookName\']}. Ran on URL Entity from Microsoft Sentinel Incident with ARM ID: @{triggerBody()?[\'incidentArmId\']}. Entity properties: @{triggerBody()?[\'entityProperties\']}'
                      expirationTime: '@{addDays(utcNow(), 90)}'
                      indicatorType: 'SHA256'
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
              }
            }
          }
          default: {
            actions: {}
          }
          expression: '@triggerBody()?[\'algorithm\']'
          type: 'Switch'
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
