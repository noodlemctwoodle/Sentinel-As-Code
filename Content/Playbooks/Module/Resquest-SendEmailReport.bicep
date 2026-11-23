metadata title = 'Resquest-SendEmailReport'
metadata description = 'Reusable automation module: Resquest-SendEmailReport.'
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

@description('The Logic App\'s name.')
param PlaybookName string = 'Module-Resquest-SendEmailReport'

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var office365ConnectionName = 'Office365-${PlaybookName}'

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
        When_a_HTTP_request_is_received: {
          type: 'Request'
          kind: 'Http'
        }
      }
      actions: {
        Create_HTML_table: {
          runAfter: {
            Condition: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@triggerBody()'
            format: 'HTML'
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
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <link href="https://fonts.googleapis.com/css?family=Roboto&display=swap" rel="stylesheet" />
  <style>
    /* Global Font */
    body,
    table {
      font-family: 'Roboto', sans-serif;
    }

    /* Styling for the nested table */
    table table {
      width: 100%;
      border-collapse: collapse;
      table-layout: auto;
    }

    table table th,
    table table td {
      padding: 10px;
      border: 1px solid #ccc;
      white-space: nowrap; /* Prevent wrapping */
    }

    /* Optionally, set custom widths for each column.
       Adjust the percentages or min-width values as needed. */
    table table th:nth-child(1),
    table table td:nth-child(1) {
      min-width: 150px; /* ApplicationName */
    }
    table table th:nth-child(2),
    table table td:nth-child(2) {
      min-width: 250px; /* ApplicationId */
    }
    table table th:nth-child(3),
    table table td:nth-child(3) {
      min-width: 120px; /* CredentialType */
    }
    table table th:nth-child(4),
    table table td:nth-child(4) {
      min-width: 200px; /* ExpiryDate */
    }
    table table th:nth-child(5),
    table table td:nth-child(5) {
      min-width: 100px; /* DaysUntilExpiry */
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
          <table style="max-width: 1000px; width: 100%; border-collapse: collapse;">
            <tbody>
              <!-- Top Section (Logo + Title) -->
              <tr class="email-header">
                <td align="center">
                  <img class="logo" style="margin: 20px auto; display: block; width: 250px;" src="https://i.postimg.cc/DZ5Kqgb6/sentinel.webp" alt="domain.com Logo" width="150" />
                </td>
              </tr>
              <!-- Microsoft Outlook Email Body -->
              <tr class="email-body">
                <td>
                  <h2 style="font-size: 26px; color: #2f06e6; text-align: center;"> Microsoft EntraID SPN Expiry</h2>
                  <p>Date: @{formatDateTime(utcNow(), 'dd-MM-yyyy HH:mm:ss')}</p>
                  <p>This email is intended to provide a quick, at-a-glance view of all applications at risk due to expiring credentials. Ensure that necessary actions can be taken promptly to renew or replace the affected secrets and certificates, thereby minimising service disruptions and mitigating potential security risks.</p>
                </td>
              </tr>
              <!-- Microsoft Sentinel Playbook Nested HTML Table -->
              <tr style="text-align: left; background-color: #f2f2f2;">
                <td>
                  @{body('Create_HTML_table')}
                </td>
              </tr>
              <!-- Microsoft Outlook Email Footer -->
              <tr>
                <td style="padding: 20px; background-color: #ebe9e2;" align="center">
                  <p style="font-size: 16.0pt;"><strong>Sentinel Security</strong></p>
                  <p>If you have any questions, please reach out to the security team:
                    <a style="color: #2f06e6;" href="mailto:secops@domain.com">Sentinel Security Team</a>
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
            Compose: [
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
              To: 'socengineer@domain.com'
              Subject: 'AD Expiry'
              Body: '<p class="editor-paragraph">@{outputs(\'Compose\')}</p>'
              Importance: 'Normal'
            }
            path: '/v2/Mail'
          }
        }
        Response: {
          runAfter: {
            'Send_an_email_(V2)': [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              status: 'Success'
              timestamp: '@{utcNow(\'dd-MM-yyyy HH:mm:ss\')}'
              message: 'The following applications have credentials that are nearing expiration.'
              expiringCredentials: '@triggerBody()'
            }
          }
        }
        Condition: {
          actions: {}
          runAfter: {}
          else: {
            actions: {
              Terminate: {
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
                not: {
                  equals: [
                    '@triggerBody()'
                    '@null'
                  ]
                }
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
          office365: {
            connectionId: office365Connection.id
            connectionName: office365ConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
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
