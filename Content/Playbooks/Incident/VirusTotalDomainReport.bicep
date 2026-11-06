metadata title = 'VirusTotalDomainReport'
metadata description = 'Sentinel incident-trigger playbook for VirusTotalDomainReport targeting URL entities.'
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

param PlaybookName string = 'VirusTotalDomainReport'
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
            Create_Reputation_HTML: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            body: {
              incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
              message: '''
<p>@{body('Create_Reputation_HTML')}<br>
<br>
Query: VTURLReport_CL | where id_s == "URL_NAME"<br>
<br>
WHOIS:<br>
@{variables('whoisData')}</p>'''
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
        Create_Reputation_HTML: {
          runAfter: {
            For_each: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            format: 'HTML'
            from: '@variables(\'DomainInfo\')'
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
            Append_to_whoisData: {
              runAfter: {
                Get_Domain_report: [
                  'Succeeded'
                ]
              }
              type: 'AppendToStringVariable'
              inputs: {
                name: 'whoisData'
                value: '@body(\'Get_Domain_report\')?[\'data\']?[\'attributes\']?[\'whois\']'
              }
            }
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
                    name: 'DomainInfo'
                    value: {
                      DomainReport: '@{items(\'For_each\')?[\'Url\']}'
                      Registrar: '@{body(\'Get_Domain_report\')?[\'data\']?[\'attributes\']?[\'registrar\']}'
                      Reputation: '@{body(\'Get_Domain_report\')?[\'data\']?[\'attributes\']?[\'reputation\']}'
                      Risk: 'Likely Harmless'
                    }
                  }
                }
                Send_Data: {
                  runAfter: {}
                  type: 'ApiConnection'
                  inputs: {
                    body: '@{body(\'Get_Domain_report\')?[\'data\']}'
                    headers: {
                      'Log-Type': 'VTDomainReport'
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
                Append_to_whoisData: [
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
                      name: 'DomainInfo'
                      value: {
                        DomainReport: '@{items(\'For_each\')?[\'Url\']}'
                        Registrar: '@{body(\'Get_Domain_report\')?[\'data\']?[\'attributes\']?[\'registrar\']}'
                        Reputation: '@{body(\'Get_Domain_report\')?[\'data\']?[\'attributes\']?[\'reputation\']}'
                        Risk: 'Likely Malicious'
                      }
                    }
                  }
                  Send_Data_2: {
                    runAfter: {}
                    type: 'ApiConnection'
                    inputs: {
                      body: '@{body(\'Get_Domain_report\')?[\'data\']}'
                      headers: {
                        'Log-Type': 'VTDomainReport'
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
                    greaterOrEquals: [
                      '@body(\'Get_Domain_report\')?[\'data\']?[\'attributes\']?[\'reputation\']'
                      0
                    ]
                  }
                ]
              }
              type: 'If'
            }
            Get_Domain_report: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'virustotal_1\'][\'connectionId\']'
                  }
                }
                method: 'get'
                path: '/api/v3/domains/@{encodeURIComponent(split(items(\'For_each\')?[\'Url\'], \'/\')[2])}'
              }
            }
          }
          runAfter: {
            Initialize_whoisData: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Initialize_DomainInfo: {
          runAfter: {
            'Entities_-_Get_URLs': [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'DomainInfo'
                type: 'array'
              }
            ]
          }
        }
        Initialize_whoisData: {
          runAfter: {
            Initialize_DomainInfo: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'whoisData'
                type: 'string'
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
