metadata title = 'SendReport'
metadata description = 'Sentinel incident-trigger playbook for SendReport.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = []
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

param PlaybookName string = 'SendReport'
param AutomationResourceGroup string = ''
param SentinelWorkpaceName string = ''

var MicrosoftSentinel0ConnectionName = 'MicrosoftSentinel0-${PlaybookName}'
var Office3650ConnectionName = 'Office3650-${PlaybookName}'

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
        reportName: {
          defaultValue: 'Microsoft Sentinel Incident Report'
          type: 'String'
        }
        secOpsEmail: {
          defaultValue: 'secops@yourcompany.com'
          type: 'String'
        }
        emailLogoHeader: {
          defaultValue: 'https://domain.com/content/images/size/w2000/2025/03/ernie_banner.png'
          type: 'String'
        }
        dateTimeFormat: {
          defaultValue: 'yyyy-MM-dd HH:mm:ss'
          type: 'String'
        }
        emailRecipient: {
          defaultValue: 'socengineer@domain.com'
          type: 'String'
        }
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
                name: '@parameters(\'$connections\')[\'azuresentinel-1\'][\'connectionId\']'
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
        Select_Entities: {
          runAfter: {}
          type: 'Select'
          inputs: {
            from: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            select: {
              Entity: '@{item()?[\'properties\']?[\'friendlyName\']}'
              'Entity type': '@{item()?[\'kind\']}'
            }
          }
        }
        Create_HTML_table_with_Entities: {
          runAfter: {
            Select_Entities: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@body(\'Select_Entities\')'
            format: 'HTML'
          }
        }
        Select_Alerts: {
          runAfter: {
            Create_HTML_table_with_Entities: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@triggerBody()?[\'object\']?[\'properties\']?[\'Alerts\']'
            select: {
              Alerts: '@{item()?[\'properties\']?[\'alertDisplayName\']}'
            }
          }
        }
        Create_HTML_table_with_Alerts: {
          runAfter: {
            Select_Alerts: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@body(\'Select_Alerts\')'
            format: 'HTML'
          }
        }
        Compose_Email_response: {
          runAfter: {
            Create_HTML_table_with_Alerts: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '''
<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://fonts.googleapis.com/css?family=Roboto&display=swap" rel="stylesheet">
    <style>
        /* Sentinel Global Font */
        body,
        table {
            font-family: 'Roboto', sans-serif;
        }

        /* Add styling for the nested table */
        table table {
            width: 100%;
            border-collapse: collapse;
        }

        table table th,
        table table td {
            padding: 10px;
            border: 1px solid #ccc;
        }

        table table th:nth-child(n+2),
        table table td:nth-child(n+2) {
            text-align: center;
        }

        table table thead tr {
            background-color: #ddd;
        }

        /* Custom styling for top section */
        .email-header {
            background-color: #C9C9C9;
            color: white;
            padding: 20px;
            text-align: center;
        }

        .email-header h1 {
            font-size: 28px;
            margin: 0;
        }

        .email-body {
            background-color: #f2f2f2;
            padding: 20px;
        }

        .email-body p {
            font-size: 16px;
            margin: 10px 0;
        }

        .incident-link {
            font-size: 18px;
            color: #2f06e6;
        }

        .tactics-section {
            font-size: 16px;
            color: #333;
        }

        .tactics-section p {
            margin: 5px 0;
        }
    </style>

</head>

<body>
    <!-- Microsoft Sentinel Monthly Cost Template -->
    <table width="100%" cellspacing="0" cellpadding="0">
        <tbody>
            <tr>
                <td style="padding: 20px 0;" align="center">
                    <table style="max-width: 650px; width: 100%; border-collapse: collapse;">
                        <tbody>
                            <!-- Top Section (Logo + Title) -->
                            <tr class="email-header">
                                <td align="center">
                                    <img class="logo"
                                        style="margin: 20px auto; display: block; width: 250px;"
                                        src="@{parameters('emailLogoHeader')}"
                                        alt="Company Logo" width="150" />
                                </td>
                            </tr>

                            <!-- Microsoft Outlook Email Body -->
                            <tr class="email-body">
                                <td>
                                    <h2 style="font-size: 26px; color: #2f06e6; text-align: center;"> @{parameters('reportName')}</h2>
                                    <p>Date: @{formatDateTime(triggerBody()?['object']?['properties']?['createdTimeUtc'], parameters('dateTimeFormat'))}</p>
                                    <p><a class="incident-link" href="@{triggerBody()?['object']?['properties']?['incidentUrl']}">Microsoft Sentinel Incident</a></p>
                                    <p>Incident Description: @{triggerBody()?['object']?['properties']?['description']}</p>
                                    
                                    <!-- Tactics Section with Line Breaks -->
                                    <div class="tactics-section">
                                        <strong>Tactics:</strong>
                                        <p>@{join(triggerBody()?['object']?['properties']?['additionalData']?['tactics'],'<br>')}</p>
                                    </div>
                                </td>
                            </tr>

                            <!-- Microsoft Sentinel Playbook Nested HTML Table -->
                            <tr style="text-align: left; background-color: #f2f2f2;">
                                <td>
                                    @{body('Create_HTML_table_with_Entities')}
                                </td>
                            </tr>
                            <tr style="text-align: left; background-color: #f2f2f2;">
                                <td>
                                    @{body('Create_HTML_table_with_Alerts')}
                                </td>
                            </tr>

                            <!-- Microsoft Outlook Email Footer -->
                            <tr>
                                <td style="padding: 20px; background-color: #ebe9e2;" align="center">
                                    <p style="font-size: 16.0pt;"><strong>Sentinel Security</strong></p>
                                    <p>If you have any questions, please reach out to the security team:
                                        <a style="color: #2f06e6;" href="mailto:@{parameters('SecOpsEmail')}">Sentinel Security Team</a>
                                    </p>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </td>
            </tr>
        </tbody>
    </table>
</body>

</html>'''
        }
        'Send_an_email_(V2)': {
          runAfter: {
            Compose_Email_response: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              To: '@parameters(\'emailRecipient\')'
              Subject: 'New Microsoft Sentinel incident - @{triggerBody()?[\'object\']?[\'properties\']?[\'title\']}'
              Body: '<p class="editor-paragraph">@{outputs(\'Compose_Email_response\')}</p>'
              Importance: 'High'
            }
            path: '/v2/Mail'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          'azuresentinel-1': {
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
