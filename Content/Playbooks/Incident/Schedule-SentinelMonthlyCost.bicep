metadata title = 'Schedule-SentinelMonthlyCost'
metadata description = 'Sentinel incident-trigger playbook for Schedule-SentinelMonthlyCost targeting Account, Host, IP entities.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = [
  'Account'
  'Host'
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
param PlaybookName string = 'Schedule-SentinelMonthlyCost'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'
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
        ClientName: {
          defaultValue: 'Client Template'
          type: 'String'
        }
        'Recipients ': {
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
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@listCallbackUrl()'
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        Email_Template: {
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
    </style>

</head>

<body>
    <p>&nbsp;</p>
    <!-- Microsoft Sentinel Monthly Cost Template -->
    <table width="100%" cellspacing="0" cellpadding="0">
        <tbody>
            <tr>
                <td style="padding: 20px 0;" align="center">
                    <table style="max-width: 650px; width: 100%; border-collapse: collapse; background-color: #000000;">
                        <tbody>
                            <tr>
                                <td style="padding: 20px;" align="center"><img class="logo"
                                        style="margin: 20px auto; display: block; width: 450px;"
                                        src="https://i.postimg.cc/DZ5Kqgb6/sentinel.webp"
                                        alt="domain.com Logo" width="150" /></td>
                            </tr>
                            <!-- Microsoft Outlook Email Body -->
                            <tr style="background-color: #f2f2f2;">
                                <td style="padding: 20px;">
                                    <h2 style="font-size: 26px; color: #2f06e6; text-align: center;">@{parameters('ClientName')} Microsoft Sentinel Cost</h2>
                                    <p style="text-align: left;">Date: @{formatDateTime(utcNow(), 'dd-MM-yyyy')}</p>
                                    <p> Below is a comprehensive breakdown of the Microsoft Sentinel costs incurred from @{formatDateTime(startOfMonth(addDays(utcNow(), -1)), 'dd MMMM yyyy')}, through @{formatDateTime(addDays(startOfMonth(utcNow()), -1), 'dd MMMM yyyy')}. </p>
                                    <p>For an in-depth exploration of these costs, please refer to the Microsoft Sentinel Cost Workbook.</p>
                                    <p><a><img src='https://i.ibb.co/42HHMp6/cost-Workbook.png' alt='cost-Workbook.png' border='0'></a></p>
                                    <p>To locate the Microsoft Sentinel Cost Workbook, please follow this path: </p>
                                    <p>In Microsoft Sentinel, select 'Workbooks', and then choose 'Microsoft Sentinel
                                        Cost (GBP)' from the list of deployed Workbooks.</p>
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
            Terminate: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365-1\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              To: '@{parameters(\'Recipients \')}'
              Subject: '@{parameters(\'ClientName\')} Monthly Cost'
              Body: '<p>@{outputs(\'Email_Template\')}</p>'
              Importance: 'Normal'
            }
            path: '/v2/Mail'
          }
        }
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
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            path: '/entities/account'
          }
        }
        'Entities_-_Get_Hosts': {
          runAfter: {
            For_each_3: [
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
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            path: '/entities/host'
          }
        }
        'Entities_-_Get_IPs': {
          runAfter: {
            For_each_4: [
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
            body: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            path: '/entities/ip'
          }
        }
        Initialize_variable: {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'Entities'
                type: 'array'
              }
            ]
          }
        }
        For_each_3: {
          foreach: '@body(\'Entities_-_Get_Accounts\')?[\'Accounts\']'
          actions: {
            Append_to_array_variable: {
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'Entities'
                value: '@items(\'For_each_3\')?[\'Name\']'
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
        For_each_4: {
          foreach: '@body(\'Entities_-_Get_Hosts\')?[\'Hosts\']'
          actions: {
            'Append_to_array_variable-copy': {
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'Entities'
                value: '@items(\'For_each_4\')?[\'HostName\']'
              }
            }
          }
          runAfter: {
            'Entities_-_Get_Hosts': [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        For_each_5: {
          foreach: '@body(\'Entities_-_Get_IPs\')?[\'IPs\']'
          actions: {
            'Append_to_array_variable-copy_1': {
              type: 'AppendToArrayVariable'
              inputs: {
                name: 'Entities'
                value: '@items(\'For_each_5\')?[\'Address\']'
              }
            }
          }
          runAfter: {
            'Entities_-_Get_IPs': [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        Create_HTML_table: {
          runAfter: {
            For_each_5: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@variables(\'Entities\')'
            format: 'HTML'
          }
        }
        Terminate: {
          runAfter: {
            Email_Template: [
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
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          'office365-1': {
            connectionId: office365Connection.id
            connectionName: office365ConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
        }
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
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
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
