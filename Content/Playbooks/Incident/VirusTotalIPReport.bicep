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

param PlaybookName string = 'VirusTotalIPReport'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var Virustotal0ConnectionName = 'Virustotal-${PlaybookName}'
var Azureloganalyticsdatacollector0ConnectionName = 'Azureloganalyticsdatacollector-${PlaybookName}'
var MicrosoftSentinel0ConnectionName = 'MicrosoftSentinel-${PlaybookName}'

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
            connectionId: Virustotal0Connection.id
            connectionName: Virustotal0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/virustotal'
          }
          azureloganalyticsdatacollector_1: {
            connectionId: Azureloganalyticsdatacollector0Connection.id
            connectionName: Azureloganalyticsdatacollector0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azureloganalyticsdatacollector'
          }
          azuresentinel_1: {
            connectionId: MicrosoftSentinel0Connection.id
            connectionName: MicrosoftSentinel0ConnectionName
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
