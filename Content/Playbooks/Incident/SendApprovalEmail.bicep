metadata title = 'SendApprovalEmail'
metadata description = 'Sentinel incident-trigger playbook for SendApprovalEmail targeting Account entities.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = [
  'Account'
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
param PlaybookName string = 'SendApprovalEmail'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var office365ConnectionName = 'Office365-${PlaybookName}'
var microsoftSentinelConnectionName = 'azuresentinel0-${PlaybookName}'
var microsoftSentinel2ConnectionName = 'azuresentinel1-${PlaybookName}'

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
        'Entities_-_Get_Accounts': {
          runAfter: {
            Initialize_variable: [
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
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            path: '/entities/account'
          }
        }
        Send_approval_email: {
          runAfter: {
            For_each: [
              'Succeeded'
            ]
          }
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            body: {
              NotificationUrl: '@listCallbackUrl()'
              Message: {
                To: 'acid.burn@domain.com'
                Body: '''
The User: @{variables('Accounts')} has trigger a potential session theft incident, can we close this or not? 

@{triggerBody()?['object']?['properties']?['title']} - @{triggerBody()?['object']?['properties']?['severity']}

Incident Info:
@{triggerBody()?['object']?['properties']?['incidentUrl']}'''
                Importance: 'High'
                UseOnlyHTMLMessage: false
                HideHTMLMessage: false
                ShowHTMLConfirmationDialog: true
                Subject: 'Approval Request to close Incident'
                Options: 'Approve, Reject'
              }
            }
            path: '/approvalmail/$subscriptions'
          }
        }
        Condition: {
          actions: {
            Update_incident: {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azuresentinel-1\'][\'connectionId\']'
                  }
                }
                method: 'put'
                body: {
                  incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
                  severity: '@triggerBody()?[\'object\']?[\'properties\']?[\'severity\']'
                  status: 'Closed'
                  classification: {
                    ClassificationAndReason: 'BenignPositive - SuspiciousButExpected'
                    ClassificationReasonText: 'Approval to close incident from User'
                  }
                }
                path: '/Incidents'
              }
            }
          }
          runAfter: {
            Send_approval_email: [
              'Succeeded'
            ]
          }
          else: {
            actions: {
              Add_task_to_incident: {
                type: 'ApiConnection'
                inputs: {
                  host: {
                    connection: {
                      name: '@parameters(\'$connections\')[\'azuresentinel-1\'][\'connectionId\']'
                    }
                  }
                  method: 'post'
                  body: {
                    incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
                    taskTitle: 'Contact User'
                    taskDescription: '<p class="editor-paragraph">Contact End User about Incicent</p>'
                  }
                  path: '/Incidents/CreateTask'
                }
              }
              Terminate: {
                runAfter: {
                  Add_task_to_incident: [
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
          expression: {
            and: [
              {
                equals: [
                  '@body(\'Send_approval_email\')?[\'SelectedOption\']'
                  'Approve'
                ]
              }
            ]
          }
          type: 'If'
        }
        For_each: {
          foreach: '@body(\'Entities_-_Get_Accounts\')?[\'Accounts\']'
          actions: {
            Append_to_string_variable: {
              type: 'AppendToStringVariable'
              inputs: {
                name: 'Accounts'
                value: '@items(\'For_each\')?[\'Name\']'
              }
            }
          }
          runAfter: {
            'Entities_-_Get_Accounts': [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Initialize_variable: {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'Accounts'
                type: 'string'
              }
            ]
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          office365: {
            connectionId: office365Connection.id
            connectionName: office365ConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
          'azuresentinel-1': {
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          azuresentinel: {
            connectionId: microsoftSentinel2Connection.id
            connectionName: microsoftSentinel2ConnectionName
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

resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: office365ConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: office365ConnectionName
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
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

resource microsoftSentinel2Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: microsoftSentinel2ConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: microsoftSentinel2ConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
    }
  }
}
