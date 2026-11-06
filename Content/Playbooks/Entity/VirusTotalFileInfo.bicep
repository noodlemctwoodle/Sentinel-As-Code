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

param PlaybookName string = 'VirusTotalFileInfo'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var Virustotal0ConnectionName = 'Virustotal-${PlaybookName}'
var MicrosoftSentinel0ConnectionName = 'MicrosoftSentinel-${PlaybookName}'
var Azureloganalyticsdatacollector0ConnectionName = 'Azureloganalyticsdatacollector-${PlaybookName}'

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
            connectionId: Virustotal0Connection.id
            connectionName: Virustotal0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/virustotal'
          }
          azuresentinel_3: {
            connectionId: MicrosoftSentinel0Connection.id
            connectionName: MicrosoftSentinel0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          azureloganalyticsdatacollector_1: {
            connectionId: Azureloganalyticsdatacollector0Connection.id
            connectionName: Azureloganalyticsdatacollector0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azureloganalyticsdatacollector'
          }
        }
      }
    }
  }
}

resource Virustotal0Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: Virustotal0ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: Virustotal0ConnectionName
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/virustotal'
    }
  }
}

resource MicrosoftSentinel0Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: MicrosoftSentinel0ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: MicrosoftSentinel0ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
    }
  }
}

resource Azureloganalyticsdatacollector0Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: Azureloganalyticsdatacollector0ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: Azureloganalyticsdatacollector0ConnectionName
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azureloganalyticsdatacollector'
    }
  }
}
