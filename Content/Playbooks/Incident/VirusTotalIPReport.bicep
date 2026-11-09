metadata title = 'VirusTotalIPReport'
metadata description = 'Sentinel incident-trigger playbook for VirusTotalIPReport targeting IP entities.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = [
  'IP'
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
param PlaybookName string = 'VirusTotalIPReport'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var virustotalConnectionName = 'Virustotal-${PlaybookName}'
var azureloganalyticsdatacollectorConnectionName = 'Azureloganalyticsdatacollector-${PlaybookName}'
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
              message: '<p>@{body(\'Create_HTML_table\')}</p>'
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
              'Failed'
            ]
          }
          type: 'Table'
          inputs: {
            format: 'HTML'
            from: '@variables(\'IPInfo\')'
          }
        }
        'Entities_-_Get_IPs': {
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
            path: '/entities/ip'
          }
        }
        For_each: {
          foreach: '@body(\'Entities_-_Get_IPs\')?[\'IPs\']'
          actions: {
            Condition: {
              actions: {
                Append_to_array_variable: {
                  runAfter: {
                    Send_Data: [
                      'Succeeded'
                    ]
                  }
                  type: 'AppendToArrayVariable'
                  inputs: {
                    name: 'IPInfo'
                    value: {
                      ASOwner: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'as_owner\']}'
                      Country: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'country\']}'
                      IPAddress: '@{items(\'For_each\')?[\'Address\']}'
                      Malicious: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'malicious\']}'
                      Reputation: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'as_owner\']}'
                      Risk: 'Likely harmless'
                      Suspicious: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'suspicious\']}'
                      Undetected: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'undetected\']}'
                    }
                  }
                }
                Send_Data: {
                  runAfter: {}
                  type: 'ApiConnection'
                  inputs: {
                    body: '@{body(\'Get_an_IP_report\')?[\'data\']}'
                    headers: {
                      'Log-Type': 'VTIPReport'
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
                Get_an_IP_report: [
                  'Succeeded'
                ]
              }
              else: {
                actions: {
                  Append_to_array_variable_2: {
                    runAfter: {
                      Send_Data_2: [
                        'Succeeded'
                      ]
                    }
                    type: 'AppendToArrayVariable'
                    inputs: {
                      name: 'IPInfo'
                      value: {
                        ASOwner: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'as_owner\']}'
                        Country: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'country\']}'
                        IPAddress: '@{items(\'For_each\')?[\'Address\']}'
                        Malicious: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'malicious\']}'
                        Reputation: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'as_owner\']}'
                        Risk: 'Likely Malicious'
                        Suspicious: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'suspicious\']}'
                        Undetected: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'undetected\']}'
                      }
                    }
                  }
                  Send_Data_2: {
                    runAfter: {}
                    type: 'ApiConnection'
                    inputs: {
                      body: '@{body(\'Get_an_IP_report\')?[\'data\']}'
                      headers: {
                        'Log-Type': 'VTIPReport'
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
                    greaterOrEquals: [
                      '@body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'reputation\']'
                      0
                    ]
                  }
                ]
              }
              type: 'If'
            }
            Get_an_IP_report: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'virustotal_1\'][\'connectionId\']'
                  }
                }
                method: 'get'
                path: '/api/v3/ip_addresses/@{encodeURIComponent(items(\'For_each\')?[\'Address\'])}'
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
            'Entities_-_Get_IPs': [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'IPInfo'
                type: 'array'
              }
            ]
          }
        }
        Terminate: {
          runAfter: {
            'Add_comment_to_incident_(V3)': [
              'Succeeded'
            ]
          }
          type: 'Terminate'
          inputs: {
            runStatus: 'Succeeded'
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
