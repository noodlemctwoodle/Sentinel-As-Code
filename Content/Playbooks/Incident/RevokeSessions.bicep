metadata title = 'RevokeSessions'
metadata description = 'Sentinel incident-trigger playbook for RevokeSessions targeting Account entities.'
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

param PlaybookName string = 'RevokeSessions'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var MicrosoftSentinel0ConnectionName = 'MicrosoftSentinel-${PlaybookName}'
var Office3650ConnectionName = 'Office365-${PlaybookName}'

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
            path: '/entities/account'
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
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
              message: '<p class="editor-paragraph">@{body(\'Create_HTML_table\')}</p>'
            }
            path: '/Incidents/Comment'
          }
        }
        For_each_Account: {
          foreach: '@body(\'Entities_-_Get_Accounts\')?[\'Accounts\']'
          actions: {
            'Module-RevokeSessions': {
              type: 'Workflow'
              inputs: {
                host: {
                  workflow: {
                    id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-RevokeSessions'
                  }
                  triggerName: 'Manual'
                }
                body: {
                  entraIdUserId: '@item()?[\'AadUserId\']'
                }
              }
            }
            'Append_to_Response_Variable_(Array)': {
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
          runAfter: {
            Terminate_1: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Revoke_Sessions_Response: {
          runAfter: {
            'Entities_-_Get_Accounts': [
              'Succeeded'
            ]
          }
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
        Create_HTML_table: {
          runAfter: {
            For_each_Account: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@variables(\'RevokeSessionsResponse\')'
            format: 'HTML'
          }
        }
        For_each: {
          foreach: '@body(\'Entities_-_Get_Accounts\')?[\'Accounts\']'
          actions: {
            'Append_EntraId_Count_(Array)': {
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'EntraIdCounts'
                value: '@item()?[\'AadUserId\']'
              }
            }
            'Append_Affected_Accounts_(Array)': {
              runAfter: {
                'Append_EntraId_Count_(Array)': [
                  'Succeeded'
                ]
              }
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'AffectedAccounts'
                value: {
                  UserPrincipalName: '@{item()?[\'additionalData\']?[\'MailAddress\']}'
                }
              }
            }
          }
          runAfter: {
            'Affected_Accounts_(Array)': [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Accounts_Greater_Than_One: {
          actions: {}
          runAfter: {
            For_each: [
              'Succeeded'
              'Failed'
            ]
          }
          else: {
            actions: {
              Terminate_Failed: {
                type: 'Terminate'
                inputs: {
                  runStatus: 'Failed'
                }
              }
            }
          }
          expression: {
            and: [
              {
                greater: [
                  '@length(variables(\'EntraIdCounts\'))'
                  1
                ]
              }
            ]
          }
          type: 'If'
        }
        'EntraId_Count_(Array)': {
          runAfter: {
            Revoke_Sessions_Response: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'EntraIdCounts'
                type: 'array'
              }
            ]
          }
        }
        Send_approval_email: {
          runAfter: {
            Compose_HTML_Response: [
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
                To: 'socengineer@domain.com'
                Body: '@{outputs(\'Compose_HTML_Response\')}'
                Importance: 'High'
                UseOnlyHTMLMessage: true
                HideHTMLMessage: false
                ShowHTMLConfirmationDialog: false
                Subject: 'Approval Request'
                Options: 'Approve, Reject'
              }
            }
            path: '/approvalmail/$subscriptions'
          }
        }
        Approval_Condtition: {
          actions: {}
          runAfter: {
            Send_approval_email: [
              'Succeeded'
            ]
          }
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
        'Affected_Accounts_(Array)': {
          runAfter: {
            'EntraId_Count_(Array)': [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'AffectedAccounts'
                type: 'array'
              }
            ]
          }
        }
        Create_Accounts_HTML: {
          runAfter: {
            Accounts_Greater_Than_One: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@variables(\'AffectedAccounts\')'
            format: 'HTML'
          }
        }
        Compose_HTML_Response: {
          runAfter: {
            Create_Accounts_HTML: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '''
<!DOCTYPE html>
<html>
<head>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: #f3f2f1;
            margin: 0;
            padding: 20px;
        }
        
        .email-container {
            max-width: 700px;
            margin: 0 auto;
            background-color: #ffffff;
            border-radius: 8px;
            box-shadow: 0 2px 6px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .email-header {
            background: linear-gradient(90deg, #0078d4 0%, #40e0d0 100%);
            color: white;
            padding: 25px;
            text-align: center;
        }
        
        .email-header h1 {
            margin: 0;
            font-size: 24px;
            font-weight: 600;
        }
        
        .email-body {
            padding: 30px;
        }
        
        .alert-box {
            background-color: #fff4e5;
            border-left: 4px solid #ff8c00;
            padding: 15px;
            margin-bottom: 20px;
            border-radius: 4px;
        }
        
        .alert-box p {
            margin: 0;
            color: #323130;
        }
        
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 20px 0;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        
        th {
            background-color: #0078d4;
            color: white;
            padding: 14px;
            text-align: left;
            font-weight: 600;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        td {
            padding: 12px 14px;
            border-bottom: 1px solid #edebe9;
            background-color: #ffffff;
            color: #323130;
            font-size: 14px;
        }
        
        tbody tr:nth-child(even) td {
            background-color: #faf9f8;
        }
        
        tbody tr:hover td {
            background-color: #e1f5fe;
            transition: background-color 0.3s ease;
        }
        
        tbody tr:last-child td {
            border-bottom: none;
        }
        
        .summary-section {
            background-color: #f0f8ff;
            padding: 20px;
            border-radius: 6px;
            margin-top: 25px;
        }
        
        .summary-section h3 {
            margin-top: 0;
            color: #0078d4;
            font-size: 16px;
        }
        
        .count-badge {
            display: inline-block;
            background-color: #0078d4;
            color: white;
            padding: 4px 12px;
            border-radius: 12px;
            font-weight: 600;
            font-size: 14px;
        }
        
        .email-footer {
            background-color: #f3f2f1;
            padding: 20px;
            text-align: center;
            font-size: 12px;
            color: #605e5c;
            border-top: 1px solid #edebe9;
        }
        
        .email-footer a {
            color: #0078d4;
            text-decoration: none;
        }
        
        .timestamp {
            color: #605e5c;
            font-size: 12px;
            margin-top: 20px;
            text-align: right;
        }
    </style>
</head>
<body>
    <div class="email-container">
        <div class="email-header">
            <h1>Microsoft Sentinel Alert</h1>
        </div>
        
        <div class="email-body">
            <div class="alert-box">
                <p><strong>Alert:</strong> User accounts detected requiring attention</p>
            </div>
            
            <h2 style="color: #323130; font-size: 18px; margin-bottom: 15px;">Affected User Accounts</h2>
            
            @{body('Create_Accounts_HTML')}
            
            <div class="summary-section">
                <h3>Summary</h3>
                <p>Total accounts affected: <span class="count-badge">@{length(variables('AffectedAccounts'))}</span></p>
                <p>Detection time: @{formatDateTime(utcNow(), 'dd-MM-yyyy HH:mm:ss')}</p>
                <p>Severity: Medium</p>
            </div>
            
            <div class="timestamp">
                Generated: @{formatDateTime(utcNow(), 'dd-MM-yyyy HH:mm:ss')} UTC
            </div>
        </div>
        
        <div class="email-footer">
            <p>This is an automated alert from Microsoft Sentinel</p>
            <p><a href="@{triggerBody()?['object']?['properties']?['incidentUrl']}>View in Azure Sentinel</a></p>
        </div>
    </div>
</body>
</html>'''
        }
        Terminate_1: {
          runAfter: {
            Approval_Condtition: [
              'Succeeded'
            ]
          }
          type: 'Terminate'
          inputs: {
            runStatus: 'Succeeded'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: MicrosoftSentinel0Connection.id
            connectionName: MicrosoftSentinel0ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuresentinel'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          office365: {
            connectionId: Office3650Connection.id
            connectionName: Office3650ConnectionName
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/office365'
          }
        }
      }
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
