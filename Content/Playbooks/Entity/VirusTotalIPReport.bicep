metadata title = 'VirusTotalIPReport'
metadata description = 'Sentinel entity-trigger playbook for VirusTotalIPReport.'
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
param PlaybookName string = 'VirusTotalIPReport'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var virustotalConnectionName = 'Virustotal-${PlaybookName}'
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
        Microsoft_Sentinel_entity: {
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
            path: '/entity/@{encodeURIComponent(\'IP\')}'
          }
        }
      }
      actions: {
        Check_if_ARMId_exist: {
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
                    name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
                  }
                }
                method: 'post'
                body: {
                  incidentArmId: '@triggerBody()?[\'IncidentArmID\']'
                  message: '''
<p>@{outputs('Compose')}<br>
<strong></strong><strong>@{body('Create_HTML_table')}</strong><strong></strong></p>'''
                }
                path: '/Incidents/Comment'
              }
            }
            Compose_2: {
              type: 'Compose'
              inputs: [
                {
                  Continent: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'continent\']}'
                  Country: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'country\']}'
                  Harmless: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'harmless\']}'
                  Malicious: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'malicious\']}'
                  Owner: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'as_owner\']}'
                  Reputation: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'reputation\']}'
                  Suspicious: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'suspicious\']}'
                  Timeout: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'timeout\']}'
                  'Total votes harmless': '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'total_votes\']?[\'harmless\']}'
                  'Total votes malicious': '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'total_votes\']?[\'malicious\']}'
                  Undetected: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'last_analysis_stats\']?[\'undetected\']}'
                  ASN: '@{body(\'Get_an_IP_report\')?[\'data\']?[\'attributes\']?[\'asn\']}'
                }
              ]
            }
            Create_HTML_table: {
              runAfter: {
                Compose_2: [
                  'Succeeded'
                ]
              }
              type: 'Table'
              inputs: {
                from: '@outputs(\'Compose_2\')'
                format: 'HTML'
              }
            }
          }
          runAfter: {
            Compose: [
              'Succeeded'
            ]
          }
          else: {
            actions: {}
          }
          expression: {
            and: [
              {
                not: {
                  equals: [
                    '@triggerBody()?[\'IncidentArmID\']'
                    '@null'
                  ]
                }
              }
            ]
          }
          type: 'If'
        }
        Compose: {
          runAfter: {
            Get_an_IP_report: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '<h2>VirusTotal report for IP: @{triggerBody()?[\'Entity\']?[\'properties\']?[\'Address\']}</h2>'
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
            path: '/api/v3/ip_addresses/connectorV2/@{encodeURIComponent(triggerBody()?[\'Entity\']?[\'properties\']?[\'Address\'])}'
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
          azuresentinel: {
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
