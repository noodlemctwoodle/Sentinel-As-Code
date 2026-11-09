metadata title = 'AutoCloseAppleiCloudPrivateRelay'
metadata description = 'Sentinel incident-trigger playbook for AutoCloseAppleiCloudPrivateRelay targeting IP entities.'
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
param PlaybookName string = 'AutoCloseAppleiCloudPrivateRelay'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

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
          inputs: {
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            path: '/incident-creation'
          }
          type: 'ApiConnectionWebhook'
        }
      }
      actions: {
        Initialize_variable: {
          inputs: {
            variables: [
              {
                name: 'CloseIncident'
                type: 'boolean'
                value: '@true'
              }
            ]
          }
          runAfter: {}
          type: 'InitializeVariable'
        }
        Only_proceed_if_incident_name_starts_with_Anonymous_IP_address: {
          actions: {}
          else: {
            actions: {
              Terminate: {
                inputs: {
                  runStatus: 'Cancelled'
                }
                runAfter: {}
                type: 'Terminate'
              }
            }
          }
          expression: {
            and: [
              {
                startsWith: [
                  '@triggerBody()?[\'object\']?[\'properties\']?[\'title\']'
                  'Anonymous IP address '
                ]
              }
            ]
          }
          runAfter: {
            Initialize_variable: [
              'Succeeded'
            ]
          }
          type: 'If'
        }
        'Entities_-_Get_IPs': {
          inputs: {
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/entities/ip'
          }
          runAfter: {
            Only_proceed_if_incident_name_starts_with_Anonymous_IP_address: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
        }
        For_each_IP_address: {
          actions: {
            Create_KQL_query_to_check_for_Apple_IPs: {
              inputs: '''
let AppleiCloudPrivateRelayRanges = externaldata(IPRange: string, Country: string, LanguageCode: string, City: string, AddressFamily: string) [
    @"https://raw.githubusercontent.com/f-bader/AzSentinelQueries/master/ExternalData/iCloudPrivateRelayIPRanges.csv"]
    with(format="csv", ignoreFirstRecord=true)
    | summarize IPRange=make_set(IPRange) by AddressFamily;
let AppleiCloudPrivateRelayRangesIPv4 = toscalar(AppleiCloudPrivateRelayRanges
    | where AddressFamily == "InterNetwork"
    | project IPRange);
let AppleiCloudPrivateRelayRangesIPv6 = toscalar(AppleiCloudPrivateRelayRanges
    | where AddressFamily == "InterNetworkV6"
    | project IPRange);
print "@{items('For_each_IP_address')?['Address']}"
| project-rename IPAddress = print_0
| extend IsInAppleiCloudv4Range = ipv4_is_in_any_range(IPAddress, AppleiCloudPrivateRelayRangesIPv4)
| extend IsInAppleiCloudv6Range = ipv6_is_in_any_range(IPAddress, AppleiCloudPrivateRelayRangesIPv6)
| where  IsInAppleiCloudv4Range or IsInAppleiCloudv6Range
'''
              runAfter: {}
              type: 'Compose'
            }
            HTTP: {
              inputs: {
                authentication: {
                  audience: 'https://api.loganalytics.io'
                  type: 'ManagedServiceIdentity'
                }
                method: 'GET'
                queries: {
                  query: '@{outputs(\'Create_KQL_query_to_check_for_Apple_IPs\')}'
                }
                uri: 'https://api.loganalytics.io/v1/workspaces/@{triggerBody()?[\'workspaceId\']}/query'
              }
              runAfter: {
                Create_KQL_query_to_check_for_Apple_IPs: [
                  'Succeeded'
                ]
              }
              type: 'Http'
            }
            Parse_JSON_from_response: {
              inputs: {
                content: '@body(\'HTTP\')'
                schema: {
                  properties: {
                    tables: {
                      items: {
                        properties: {
                          columns: {
                            items: {
                              properties: {
                                name: {
                                  type: 'string'
                                }
                                type: {
                                  type: 'string'
                                }
                              }
                              required: [
                                'name'
                                'type'
                              ]
                              type: 'object'
                            }
                            type: 'array'
                          }
                          name: {
                            type: 'string'
                          }
                          rows: {
                            items: {
                              type: 'array'
                            }
                            type: 'array'
                          }
                        }
                        type: 'object'
                      }
                      type: 'array'
                    }
                  }
                  type: 'object'
                }
              }
              runAfter: {
                HTTP: [
                  'Succeeded'
                ]
              }
              type: 'ParseJson'
            }
            Compose: {
              inputs: '@length(body(\'Parse_JSON_from_response\')?[\'tables\'][0]?[\'rows\'])'
              runAfter: {
                Parse_JSON_from_response: [
                  'Succeeded'
                ]
              }
              type: 'Compose'
            }
            Check_if_response_is_empty: {
              actions: {
                Set_variable: {
                  inputs: {
                    name: 'CloseIncident'
                    value: '@false'
                  }
                  runAfter: {}
                  type: 'SetVariable'
                }
              }
              expression: {
                and: [
                  {
                    equals: [
                      '@length(body(\'Parse_JSON_from_response\')?[\'tables\'][0]?[\'rows\'])'
                      0
                    ]
                  }
                ]
              }
              runAfter: {
                Compose: [
                  'Succeeded'
                ]
              }
              type: 'If'
            }
          }
          foreach: '@body(\'Entities_-_Get_IPs\')?[\'IPs\']'
          runAfter: {
            'Entities_-_Get_IPs': [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Close_incident_if_all_IP_addresses_where_part_of_Apples_IP_ranges: {
          actions: {
            Update_incident: {
              inputs: {
                body: {
                  classification: {
                    ClassificationAndReason: 'BenignPositive - SuspiciousButExpected'
                    ClassificationReasonText: 'All IP addresses in this incident belong to the Apple iCloud Private Relay network and the detection is expected but benign'
                  }
                  incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
                  status: 'Closed'
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
                  }
                }
                method: 'put'
                path: '/Incidents'
              }
              runAfter: {}
              type: 'ApiConnection'
            }
          }
          else: {
            actions: {
              'Add_comment_to_incident_(V3)': {
                inputs: {
                  body: {
                    incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
                    message: '<p>At least one IP address in this incident was not recognized as beeing part of the Apple iCloud Private Relay network. Please investigate this according to the SOC playbook.</p>'
                  }
                  host: {
                    connection: {
                      name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
                    }
                  }
                  method: 'post'
                  path: '/Incidents/Comment'
                }
                runAfter: {}
                type: 'ApiConnection'
              }
            }
          }
          expression: {
            and: [
              {
                equals: [
                  '@variables(\'CloseIncident\')'
                  '@true'
                ]
              }
            ]
          }
          runAfter: {
            For_each_IP_address: [
              'Succeeded'
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
          azuresentinel: {
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Azuresentinel')
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
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'Azuresentinel')
    }
  }
}
