metadata title = 'VirusTotalFileInfo'
metadata description = 'Sentinel incident-trigger playbook for VirusTotalFileInfo targeting FileHash entities.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = [
  'FileHash'
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
param PlaybookName string = 'VirusTotalFileInfo'

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
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel_1\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@{listCallbackUrl()}'
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
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel_1\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
              message: '''
<p>@{body('Create_HTML_table')}<br>
Query: VTFileReport_CL | where id_s == 'File_Hash_Value'",</p>'''
            }
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
            from: '@variables(\'HashInfo\')'
            format: 'HTML'
          }
        }
        'Entities_-_Get_FileHashes': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel_1\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            path: '/entities/filehash'
          }
        }
        Filter_array: {
          runAfter: {
            Initialize_HashInfo: [
              'Succeeded'
            ]
          }
          type: 'Query'
          inputs: {
            from: '@body(\'Entities_-_Get_FileHashes\')?[\'Filehashes\']'
            where: '@equals(item()?[\'Algorithm\'], \'SHA1\')'
          }
        }
        For_each: {
          foreach: '@body(\'Filter_array\')'
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
                    name: 'HashInfo'
                    value: {
                      HashValue: '@{items(\'For_each\')?[\'Value\']}'
                      ProcessName: '@{body(\'Retrieve_information_about_a_file\')?[\'data\']?[\'attributes\']?[\'meaningful_name\']}'
                      Reputation: '@{body(\'Retrieve_information_about_a_file\')?[\'data\']?[\'attributes\']?[\'reputation\']}'
                      Risk: 'Likely harmless'
                      TimesSubmitted: '@{body(\'Retrieve_information_about_a_file\')?[\'data\']?[\'attributes\']?[\'times_submitted\']}'
                    }
                  }
                }
                Send_Data: {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector_1\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: '@{body(\'Retrieve_information_about_a_file\')?[\'data\']}'
                    headers: {
                      'Log-Type': 'VTFileReport'
                      'time-generated-field': '@{utcNow()}'
                    }
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
                  Append_to_array_variable_2: {
                    runAfter: {
                      Send_Data_2: [
                        'Succeeded'
                      ]
                    }
                    type: 'AppendToArrayVariable'
                    inputs: {
                      name: 'HashInfo'
                      value: {
                        HashValue: '@{items(\'For_each\')?[\'Value\']}'
                        ProcessName: '@{body(\'Retrieve_information_about_a_file\')?[\'data\']?[\'attributes\']?[\'meaningful_name\']}'
                        Reputation: '@{body(\'Retrieve_information_about_a_file\')?[\'data\']?[\'attributes\']?[\'reputation\']}'
                        Risk: 'Likely Malicious'
                        TimesSubmitted: '@{body(\'Retrieve_information_about_a_file\')?[\'data\']?[\'attributes\']?[\'times_submitted\']}'
                      }
                    }
                  }
                  Send_Data_2: {
                    type: 'ApiConnection'
                    inputs: {
                      host: {
                        connection: {
                          name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector_1\'][\'connectionId\']'
                        }
                      }
                      method: 'post'
                      body: '@{body(\'Retrieve_information_about_a_file\')?[\'data\']}'
                      headers: {
                        'Log-Type': 'VTFileReport'
                        'time-generated-field': '@{utcNow()}'
                      }
                      path: '/api/logs'
                    }
                  }
                }
              }
              expression: {
                or: [
                  {
                    greaterOrEquals: [
                      '@body(\'Retrieve_information_about_a_file\')?[\'data\']?[\'attributes\']?[\'reputation\']'
                      0
                    ]
                  }
                ]
              }
              type: 'If'
            }
            Retrieve_information_about_a_file: {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'virustotal_1\'][\'connectionId\']'
                  }
                }
                method: 'get'
                path: '/api/v3/files/@{encodeURIComponent(item()?[\'Value\'])}'
              }
            }
          }
          runAfter: {
            Filter_array: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Initialize_HashInfo: {
          runAfter: {
            'Entities_-_Get_FileHashes': [
              'Succeeded'
            ]
          }
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
