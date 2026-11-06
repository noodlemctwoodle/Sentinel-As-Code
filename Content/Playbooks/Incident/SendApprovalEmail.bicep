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

param PlaybookName string = 'SendApprovalEmail'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var Office3650ConnectionName = 'Office365-${PlaybookName}'
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
            connectionId: Office3650Connection.id
            connectionName: Office3650ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/office365'
          }
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

resource Office3650Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: Office3650ConnectionName
  location: resourceGroup().location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: Office3650ConnectionName
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/office365'
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
