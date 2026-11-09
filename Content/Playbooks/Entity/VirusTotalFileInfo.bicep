metadata title = 'VirusTotalFileInfo'
metadata description = 'Sentinel entity-trigger playbook for VirusTotalFileInfo.'
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

@description('The Logic App\'s name.')
param PlaybookName string = 'VirusTotalFileInfo'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var virustotalConnectionName = 'Virustotal-${PlaybookName}'
var microsoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'
var azureloganalyticsdatacollectorConnectionName = 'Azureloganalyticsdatacollector-${PlaybookName}'

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
        Microsoft_Sentinel_entity: {
          type: 'ApiConnectionWebhook'
          inputs: {
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel_3\'][\'connectionId\']'
              }
            }
            path: '/entity/@{encodeURIComponent(\'FileHash\')}'
          }
        }
      }
      actions: {
        Condition_2: {
          actions: {
            'Add_comment_to_incident_(V3)': {
              runAfter: {
                Send_Data: [
                  'Succeeded'
                ]
              }
              type: 'ApiConnection'
              inputs: {
                body: {
                  incidentArmId: '@triggerBody()?[\'IncidentArmID\']'
                  message: '''
<p>Virus Total File Report found for @{triggerBody()?['Entity']?['properties']?['Value']}<br>
Reputation is:@{body('Retrieve_information_about_a_file')?['data']?['attributes']?['reputation']} which indicates likely harmless<br>
Query: VTFileReport_CL | where id_s == "@{triggerBody()?['Entity']?['properties']?['Value']}"</p>'''
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azuresentinel_3\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/Incidents/Comment'
              }
            }
            Send_Data: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: '@{body(\'Retrieve_information_about_a_file\')?[\'data\']}'
                headers: {
                  'Log-Type': 'VTFileReport'
                  'time-generated-field': '@{utcNow()}'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector_1\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/api/logs'
              }
            }
          }
          runAfter: {
            Retrieve_information_about_a_file: [
              'Succeeded'
            ]
          }
          else: {
            actions: {
              'Add_comment_to_incident_(V3)_2': {
                runAfter: {
                  Send_Data_2: [
                    'Succeeded'
                  ]
                }
                type: 'ApiConnection'
                inputs: {
                  body: {
                    incidentArmId: '@triggerBody()?[\'IncidentArmID\']'
                    message: '''
<p>Virus Total File Report found for @{triggerBody()?['Entity']?['properties']?['Value']}<br>
Reputation is:@{body('Retrieve_information_about_a_file')?['data']?['attributes']?['reputation']} which indicates likely malicous<br>
Query: VTFileReport_CL | where id_s == "@{triggerBody()?['Entity']?['properties']?['Value']}"</p>'''
                  }
                  host: {
                    connection: {
                      name: '@parameters(\'$connections\')[\'azuresentinel_3\'][\'connectionId\']'
                    }
                  }
                  method: 'post'
                  path: '/Incidents/Comment'
                }
              }
              Send_Data_2: {
                runAfter: {}
                type: 'ApiConnection'
                inputs: {
                  body: '@{body(\'Retrieve_information_about_a_file\')?[\'data\']}'
                  headers: {
                    'Log-Type': 'VTFileReport'
                    'time-generated-field': '@{utcNow()}'
                  }
                  host: {
                    connection: {
                      name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector_1\'][\'connectionId\']'
                    }
                  }
                  method: 'post'
                  path: '/api/logs'
                }
              }
            }
          }
          expression: {
            and: [
              {
                greater: [
                  '@body(\'Retrieve_information_about_a_file\')?[\'data\']?[\'attributes\']?[\'reputation\']'
                  0
                ]
              }
            ]
          }
          type: 'If'
        }
        Initialize_HashInfo: {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'HashInfo'
                type: 'array'
              }
            ]
          }
        }
        Retrieve_information_about_a_file: {
          runAfter: {
            Initialize_HashInfo: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'virustotal_1\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/api/v3/files/@{encodeURIComponent(triggerBody()?[\'Entity\']?[\'properties\']?[\'Value\'])}'
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          virustotal_1: {
            connectionId: virustotalConnection.id
            connectionName: virustotalConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'virustotal')
          }
          azuresentinel_3: {
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          azureloganalyticsdatacollector_1: {
            connectionId: azureloganalyticsdatacollectorConnection.id
            connectionName: azureloganalyticsdatacollectorConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
          }
        }
      }
    }
  }
}

resource virustotalConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: virustotalConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: virustotalConnectionName
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'virustotal')
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

resource azureloganalyticsdatacollectorConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: azureloganalyticsdatacollectorConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: azureloganalyticsdatacollectorConnectionName
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
    }
  }
}
