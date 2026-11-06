metadata title = 'IPEnrichment'
metadata description = 'Sentinel incident-trigger playbook for IPEnrichment targeting IP entities.'
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

param PlaybookName string = 'IPEnrichment'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var MicrosoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'

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
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
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
        'Entities_-_Get_IPs': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            path: '/entities/ip'
          }
        }
        For_each: {
          foreach: '@body(\'Entities_-_Get_IPs\')?[\'IPs\']'
          actions: {
            Condition: {
              actions: {
                HTTP: {
                  type: 'Http'
                  inputs: {
                    uri: 'https://vpnapi.io/api/@{items(\'For_each\')?[\'Address\']}?key=3fb951c6fb3641639df21946a0cbcd4b'
                    method: 'GET'
                  }
                  runtimeConfiguration: {
                    contentTransfer: {
                      transferMode: 'Chunked'
                    }
                  }
                }
                Append_Body_to_Array: {
                  runAfter: {
                    HTTP: [
                      'Succeeded'
                    ]
                  }
                  type: 'AppendToArrayVariable'
                  inputs: {
                    name: 'IPInfo'
                    value: '@body(\'HTTP\')'
                  }
                }
              }
              else: {
                actions: {}
              }
              expression: {
                or: [
                  {
                    not: {
                      startsWith: [
                        '@item()?[\'Address\']'
                        '192.168.'
                      ]
                    }
                  }
                  {
                    not: {
                      startsWith: [
                        '@item()?[\'Address\']'
                        '172.16.'
                      ]
                    }
                  }
                  {
                    not: {
                      startsWith: [
                        '@item()?[\'Address\']'
                        '172.17.'
                      ]
                    }
                  }
                  {
                    startsWith: [
                      '@item()?[\'Address\']'
                      '10.'
                    ]
                  }
                ]
              }
              type: 'If'
            }
          }
          runAfter: {
            Initialise_IPInfo: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Initialise_IPInfo: {
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
        Select: {
          runAfter: {
            For_each: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@variables(\'IPInfo\')'
            select: {
              ip: '@{item()?[\'ip\']}'
              vpn: '@{item()?[\'security\']?[\'vpn\']}'
              proxy: '@{item()?[\'security\']?[\'proxy\']}'
              tor: '@{item()?[\'security\']?[\'tor\']}'
              relay: '@{item()?[\'security\']?[\'relay\']}'
              city: '@{item()?[\'location\']?[\'city\']}'
              region: '@{item()?[\'location\']?[\'region\']}'
              country: '@{item()?[\'location\']?[\'country\']}'
              continent: '@{item()?[\'location\']?[\'continent\']}'
              region_code: '@{item()?[\'location\']?[\'region_code\']}'
              country_code: '@{item()?[\'location\']?[\'country_code\']}'
              continent_code: '@{item()?[\'location\']?[\'continent_code\']}'
              latitude: '@{item()?[\'location\']?[\'latitude\']}'
              longitude: '@{item()?[\'location\']?[\'longitude\']}'
              time_zone: '@{item()?[\'location\']?[\'time_zone\']}'
              locale_code: '@{item()?[\'location\']?[\'locale_code\']}'
              metro_code: '@{item()?[\'location\']?[\'metro_code\']}'
              is_in_european_union: '@{item()?[\'location\']?[\'is_in_european_union\']}'
              network: '@{item()?[\'network\']?[\'network\']}'
              asn: '@{item()?[\'network\']?[\'autonomous_system_number\']}'
              aso: '@{item()?[\'network\']?[\'autonomous_system_organization\']}'
            }
          }
        }
        Create_HTML_table: {
          runAfter: {
            Select: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@body(\'Select\')'
            format: 'HTML'
          }
        }
        'Add_comment_to_incident_(V3)': {
          runAfter: {
            Compose: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
              message: '<p class="editor-paragraph">@{outputs(\'Compose\')}</p>'
            }
            path: '/Incidents/Comment'
          }
        }
        Compose: {
          runAfter: {
            Create_HTML_table: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '''
<div style="width:100%;font-family:Arial,sans-serif"><style>
table { border-collapse: collapse; width: 100%; }
th { background-color: #0078d4; color: white; padding: 12px; }
td { padding: 10px; border-bottom: 1px solid #ddd; }
tr:hover { background-color: #f5f5f5; }
</style>@{body('Create_HTML_table')}</div>'''
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: MicrosoftSentinelConnection.id
            connectionName: MicrosoftSentinelConnectionName
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

resource MicrosoftSentinelConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: MicrosoftSentinelConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: MicrosoftSentinelConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
    }
  }
}
