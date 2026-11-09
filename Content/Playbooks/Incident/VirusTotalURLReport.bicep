metadata title = 'VirusTotalURLReport'
metadata description = 'Sentinel incident-trigger playbook for VirusTotalURLReport targeting URL entities.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = [
  'URL'
]
metadata tags = [
  'Incident'
  'Source: Sentinel-As-Code'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: 'noodlemctwoodle'
}

@description('The Logic App\'s name.')
param PlaybookName string = 'VirusTotalURLReport'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var virustotalConnectionName = 'Virustotal-${PlaybookName}'
var azureloganalyticsdatacollectorConnectionName = 'Azureloganalyticsdatacollector-${PlaybookName}'
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
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        Microsoft_Sentinel_incident: {
          type: 'ApiConnectionWebhook'
          inputs: {
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel_1\'][\'connectionId\']'
              }
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        'Add_comment_to_incident_(V3)': {
          runAfter: {
            Create_HTML_table: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            body: {
              incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
              message: '''
<p>@{body('Create_HTML_table')}<br>
Query: VTURLReport_CL | where id_s == "Id_Value"</p>'''
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel_1\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/Incidents/Comment'
          }
        }
        Create_HTML_table: {
          runAfter: {
            For_each: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            format: 'HTML'
            from: '@variables(\'URLInfo\')'
          }
        }
        'Entities_-_Get_URLs': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel_1\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/entities/url'
          }
        }
        For_each: {
          foreach: '@body(\'Entities_-_Get_URLs\')?[\'URLs\']'
          actions: {
            Analyse_an_URL: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: {
                  '$content-type': 'multipart/form-data'
                  '$multipart': [
                    {
                      body: '@items(\'For_each\')?[\'Url\']'
                      headers: {
                        'Content-Disposition': 'form-data; name="url"'
                      }
                    }
                  ]
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'virustotal_1\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/api/v3/urls'
              }
            }
            Condition: {
              actions: {
                Append_to_array_variable_2: {
                  runAfter: {
                    Send_Data: [
                      'Succeeded'
                    ]
                  }
                  type: 'AppendToArrayVariable'
                  inputs: {
                    name: 'URLInfo'
                    value: {
                      HashValue: '@{items(\'For_each\')?[\'Url\']}'
                      Id: '@{body(\'Analyse_an_URL\')?[\'data\']?[\'id\']}'
                      Malicous: '@{body(\'Retrieve_information_about_a_file_or_URL_analysis\')[\'data\'][\'attributes\'][\'stats\'][\'malicious\']}'
                      Risk: 'Likely harmless'
                      Suspicious: '@{body(\'Retrieve_information_about_a_file_or_URL_analysis\')[\'data\'][\'attributes\'][\'stats\'][\'suspicious\']}'
                    }
                  }
                }
                Send_Data: {
                  runAfter: {}
                  type: 'ApiConnection'
                  inputs: {
                    body: '@{body(\'Retrieve_information_about_a_file_or_URL_analysis\')[\'data\']}'
                    headers: {
                      'Log-Type': 'VTURLReport'
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
                Retrieve_information_about_a_file_or_URL_analysis: [
                  'Succeeded'
                ]
              }
              else: {
                actions: {
                  Append_to_array_variable: {
                    runAfter: {
                      Send_Data_2: [
                        'Succeeded'
                      ]
                    }
                    type: 'AppendToArrayVariable'
                    inputs: {
                      name: 'URLInfo'
                      value: {
                        HashValue: '@{items(\'For_each\')?[\'Url\']}'
                        Id: '@{body(\'Analyse_an_URL\')?[\'data\']?[\'id\']}'
                        Malicous: '@{body(\'Retrieve_information_about_a_file_or_URL_analysis\')[\'data\'][\'attributes\'][\'stats\'][\'malicious\']}'
                        Risk: 'Likely Malicious'
                        Suspicious: '@{body(\'Retrieve_information_about_a_file_or_URL_analysis\')[\'data\'][\'attributes\'][\'stats\'][\'suspicious\']}'
                      }
                    }
                  }
                  Send_Data_2: {
                    runAfter: {}
                    type: 'ApiConnection'
                    inputs: {
                      body: '@{body(\'Retrieve_information_about_a_file_or_URL_analysis\')[\'data\']}'
                      headers: {
                        'Log-Type': 'VTURLReport'
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
                or: [
                  {
                    greater: [
                      '@body(\'Retrieve_information_about_a_file_or_URL_analysis\')[\'data\'][\'attributes\'][\'stats\'][\'malicious\']'
                      0
                    ]
                  }
                  {
                    greater: [
                      '@body(\'Retrieve_information_about_a_file_or_URL_analysis\')[\'data\'][\'attributes\'][\'stats\'][\'suspicious\']'
                      0
                    ]
                  }
                ]
              }
              type: 'If'
            }
            Retrieve_information_about_a_file_or_URL_analysis: {
              runAfter: {
                Analyse_an_URL: [
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
                path: '/api/v3/analyses/@{encodeURIComponent(body(\'Analyse_an_URL\')?[\'data\']?[\'id\'])}'
              }
            }
          }
          runAfter: {
            Initialize_variable: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Initialize_variable: {
          runAfter: {
            'Entities_-_Get_URLs': [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'URLInfo'
                type: 'array'
              }
            ]
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
          azureloganalyticsdatacollector_1: {
            connectionId: azureloganalyticsdatacollectorConnection.id
            connectionName: azureloganalyticsdatacollectorConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
          }
          azuresentinel_1: {
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
