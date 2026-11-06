metadata title = 'RevokeSessions'
metadata description = 'Sentinel entity-trigger playbook for RevokeSessions.'
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

param PlaybookName string = 'RevokeSessions'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var azuresentinel0ConnectionName = 'azuresentinel0-${PlaybookName}'
var azuresentinel1ConnectionName = 'azuresentinel1-${PlaybookName}'

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
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            path: '/entity/@{encodeURIComponent(\'Account\')}'
          }
        }
      }
      actions: {
        'Module-RevokeSessions': {
          runAfter: {
            Revoke_Sessions_Response: [
              'Succeeded'
            ]
          }
          type: 'Workflow'
          inputs: {
            host: {
              workflow: {
                id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-RevokeSessions'
              }
              triggerName: 'Manual'
            }
            body: {
              entraIdUserId: '@triggerBody()?[\'Entity\']?[\'properties\']?[\'AadUserId\']'
            }
          }
        }
        Create_HTML_table: {
          runAfter: {
            Append_to_array_variable: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@variables(\'RevokeSessionsResponse\')'
            format: 'HTML'
          }
        }
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
                name: '@parameters(\'$connections\')[\'azuresentinel-1\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              incidentArmId: '@triggerBody()?[\'IncidentArmID\']'
              message: '<p class="editor-paragraph">@{body(\'Create_HTML_table\')}</p>'
            }
            path: '/Incidents/Comment'
          }
        }
        Revoke_Sessions_Response: {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'RevokeSessionsResponse'
                type: 'array'
              }
            ]
          }
        }
        Append_to_array_variable: {
          runAfter: {
            'Module-RevokeSessions': [
              'Succeeded'
            ]
          }
          type: 'AppendToArrayVariable'
          inputs: {
            name: 'RevokeSessionsResponse'
            value: '@body(\'Module-RevokeSessions\')'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          'azuresentinel-1': {
            connectionId: azuresentinel0Connection.id
            connectionName: azuresentinel0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          azuresentinel: {
            connectionId: azuresentinel1Connection.id
            connectionName: azuresentinel1ConnectionName
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

resource azuresentinel0Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: azuresentinel0ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: azuresentinel0ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
    }
  }
}

resource azuresentinel1Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: azuresentinel1ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: azuresentinel1ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
    }
  }
}
