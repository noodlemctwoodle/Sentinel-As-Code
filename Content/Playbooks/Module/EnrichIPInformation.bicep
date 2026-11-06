metadata title = 'EnrichIPInformation'
metadata description = 'Reusable automation module: EnrichIPInformation.'
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

param PlaybookName string = 'Module-EnrichIPInformation'

var AzureKeyVaultConnectionName = 'AzureKeyVault-${PlaybookName}'

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
        'Module-EnrichIPInformation': {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                IPAddress: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
      }
      actions: {
        Get_VPN_API_Key: {
          runAfter: {
            Trigger_Security_Condition: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'keyvault\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/secrets/@{encodeURIComponent(\'VPNAPI\')}/value'
          }
          runtimeConfiguration: {
            secureData: {
              properties: [
                'inputs'
                'outputs'
              ]
            }
          }
        }
        'HTTP_IP_Info_(GET)': {
          runAfter: {
            Get_VPN_API_Key: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            uri: 'https://vpnapi.io/api/@{triggerBody()?[\'IPAddress\']}?key=@{body(\'Get_VPN_API_Key\')?[\'value\']}'
            method: 'GET'
          }
          runtimeConfiguration: {
            contentTransfer: {
              transferMode: 'Chunked'
            }
          }
        }
        Parse_HTML_Response: {
          runAfter: {
            'HTTP_IP_Info_(GET)': [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '@body(\'HTTP_IP_Info_(GET)\')'
            schema: {
              type: 'object'
              properties: {
                ip: {
                  type: 'string'
                }
                security: {
                  type: 'object'
                  properties: {
                    vpn: {
                      type: 'boolean'
                    }
                    proxy: {
                      type: 'boolean'
                    }
                    tor: {
                      type: 'boolean'
                    }
                    relay: {
                      type: 'boolean'
                    }
                  }
                }
                location: {
                  type: 'object'
                  properties: {
                    city: {
                      type: 'string'
                    }
                    region: {
                      type: 'string'
                    }
                    country: {
                      type: 'string'
                    }
                    continent: {
                      type: 'string'
                    }
                    region_code: {
                      type: 'string'
                    }
                    country_code: {
                      type: 'string'
                    }
                    continent_code: {
                      type: 'string'
                    }
                    latitude: {
                      type: 'string'
                    }
                    longitude: {
                      type: 'string'
                    }
                    time_zone: {
                      type: 'string'
                    }
                    locale_code: {
                      type: 'string'
                    }
                    metro_code: {
                      type: 'string'
                    }
                    is_in_european_union: {
                      type: 'boolean'
                    }
                  }
                }
                network: {
                  type: 'object'
                  properties: {
                    network: {
                      type: 'string'
                    }
                    autonomous_system_number: {
                      type: 'string'
                    }
                    autonomous_system_organization: {
                      type: 'string'
                    }
                  }
                }
              }
            }
          }
        }
        Compose: {
          runAfter: {
            Parse_HTML_Response: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: {
            IPAddress: '@{body(\'Parse_HTML_Response\')?[\'ip\']}'
            VPN: '@{body(\'Parse_HTML_Response\')?[\'security\']?[\'vpn\']}'
            Proxy: '@{body(\'Parse_HTML_Response\')?[\'security\']?[\'proxy\']}'
            Tor: '@{body(\'Parse_HTML_Response\')?[\'security\']?[\'tor\']}'
            Relay: '@{body(\'Parse_HTML_Response\')?[\'security\']?[\'relay\']}'
            City: '@{body(\'Parse_HTML_Response\')?[\'location\']?[\'city\']}'
          }
        }
        Response: {
          runAfter: {
            Compose: [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: '@outputs(\'Compose\')'
          }
        }
        Trigger_Security_Condition: {
          actions: {}
          runAfter: {}
          else: {
            actions: {
              Terminate: {
                type: 'Terminate'
                inputs: {
                  runStatus: 'Cancelled'
                }
              }
            }
          }
          expression: {
            or: [
              {
                equals: [
                  '@triggerOutputs()?[\'headers\']?[\'x-ms-workflow-name\']'
                  'Entity-EnrichIPInfo'
                ]
              }
              {
                equals: [
                  '@triggerOutputs()?[\'headers\']?[\'x-ms-workflow-name\']'
                  'Incident-EnrichIPInfo'
                ]
              }
            ]
          }
          type: 'If'
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          keyvault: {
            connectionId: AzureKeyVaultConnection.id
            connectionName: AzureKeyVaultConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/keyvault'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
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

resource AzureKeyVaultConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: AzureKeyVaultConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: AzureKeyVaultConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/keyvault'
    }
  }
}
