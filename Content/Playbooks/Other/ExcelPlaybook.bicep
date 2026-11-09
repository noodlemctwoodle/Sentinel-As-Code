metadata title = 'ExcelPlaybook'
metadata description = 'Automation playbook: ExcelPlaybook.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = []
metadata tags = [
  'Other'
  'Source: Sentinel-As-Code'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: 'noodlemctwoodle'
}

@description('The Logic App\'s name.')
param PlaybookName string = 'ExcelPlaybook'

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var azureMonitorLogsConnectionName = 'AzureMonitorLogs-${PlaybookName}'
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
        SubscriptionID: {
          defaultValue: '\', subscription().subscriptionId, \''
          type: 'String'
        }
        ResourceGroup: {
          defaultValue: 'stl-sec-siem-rg'
          type: 'String'
        }
        WorkspaceID: {
          defaultValue: '17180226-9a08-4e89-bdc2-1e04db4114a2'
          type: 'String'
        }
        WatchlistAlias: {
          defaultValue: ' PasswordSharingUsersv1'
          type: 'String'
        }
        companyLogo: {
          defaultValue: 'https://domain.com/content/images/size/w1000/2025/04/36127.png'
          type: 'String'
        }
        socEmail: {
          defaultValue: 'security@company.com'
          type: 'String'
        }
        incidentName: {
          defaultValue: 'Safeguard (SPP) Multiple Passwords Checked-Out in a Short Timeframe'
          type: 'String'
        }
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            interval: 30
            frequency: 'Day'
          }
          evaluatedRecurrence: {
            interval: 30
            frequency: 'Day'
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Run_query_and_list_results: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuremonitorlogs-1\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: '''
SecurityAlert
| where TimeGenerated > ago(90d)
| where DisplayName == "Entra ID Token Theft Detection: Unbound Sessions on Unmanaged Devices (M356CommunityConf)"
| mv-expand Entity = todynamic(Entities)
| extend UserPrincipalName = tostring(Entity.Name)
| extend FormattedTime = format_datetime(TimeGenerated, 'dd/MM/yyyy HH:mm:ss')
| order by UserPrincipalName asc, TimeGenerated desc
| summarize IncidentsGenerated = count(), 
          IncidentDates = make_list(FormattedTime) by UserPrincipalName,DisplayName
| where IncidentsGenerated > 1 
| join kind=inner (IdentityInfo
    | summarize arg_max(TimeGenerated, *) by UserPrincipalName = AccountUPN)
    on UserPrincipalName
| join kind=leftouter (IdentityInfo
    | extend ManagerName = AccountDisplayName
    | extend ManagerEmail = AccountUPN
    | summarize arg_max(TimeGenerated, ManagerEmail) by ManagerName)
    on $left.Manager == $right.ManagerName
| project UserPrincipalName = tostring(UserPrincipalName), AccountDisplayName, IncidentsGenerated, IncidentDates, Manager, ManagerEmail, DisplayName
| sort by IncidentsGenerated desc
| where isnotempty(UserPrincipalName)'''
            path: '/queryData'
            queries: {
              subscriptions: '\', subscription().subscriptionId, \''
              resourcegroups: 'STL-SEC-SIEM-RG'
              resourcetype: 'Log Analytics Workspace'
              resourcename: 'stl-sec-siem-law'
              timerange: '7d'
            }
          }
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
              Subject: 'SafeGaurd Report'
              Body: '<p class="editor-paragraph">@{outputs(\'Compose\')}</p>'
              Importance: 'High'
            }
            path: '/v2/Mail'
          }
        }
        Compose: {
          runAfter: {
            Create_HTML_table_1: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '''
<!DOCTYPE html>
<html>

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Alert</title>
    <style>
        /* Basic page styling */
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            margin: 0; 
            padding: 0; 
            background-color: #f5f5f5;
            color: #252525;
            line-height: 1.5;
        }

        /* Main container */
        .container { 
            max-width: 650px;
            margin: 0 auto;
            background-color: #ffffff;
            border: 1px solid #e0e0e0;
            border-radius: 4px;
            overflow: hidden;
        }

        /* Header styling */
        .header {
            background-color: #0078D4;
            padding: 15px 20px;
            color: white;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .header img { 
            height: 130px;
            width: auto;
        }

        .header h1 {
            margin: 0;
            font-size: 24px;
            font-weight: 600;
        }

        /* Content area */
        .content {
            padding: 20px;
        }

        /* Info layout */
        .info-item {
            margin-bottom: 10px;
            display: flex;
        }

        .info-item {
            margin-bottom: 10px;
            display: flex;
        }

        .info-label {
            font-weight: 600;
            width: 100px;
            color: #444;
        }

        /* Query section */
        .query-section {
            margin: 20px 0;
            border-left: 4px solid #0078D4;
            padding-left: 15px;
            background-color: #f9f9f9;
            position: relative;
        }

        .query-label {
            font-weight: 600;
            margin-bottom: 10px;
            padding-top: 15px;
            padding-left: 15px;
        }

        /* KQL query block */
        .kql-query {
            background-color: #f5f5f5;
            border: 1px solid #e0e0e0;
            border-radius: 4px;
            padding: 15px;
            margin: 10px 15px 15px 15px;
            font-family: Consolas, Monaco, 'Courier New', monospace;
            font-size: 13px;
            line-height: 1.5;
            color: #333;
            position: relative;
        }

        /* Comment styling */
        .comment {
            color: #008000;
            font-style: italic;
        }

        /* Section styling */
        .section {
            margin: 30px 0;
            border-top: 1px solid #eee;
            padding-top: 20px;
        }

        .section-title {
            font-size: 18px;
            margin-bottom: 15px;
            color: #333;
            font-weight: 600;
            display: flex;
            align-items: center;
        }

        .section-title-indicator {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background-color: #0078D4;
            display: inline-block;
            margin-right: 10px;
        }

        /* Table styling */
        .sentinel-tables table {
            width: 100%;
            margin-bottom: 24px;
            border-collapse: collapse;
            border-radius: 4px;
            overflow: hidden;
            table-layout: fixed;
        }

        .sentinel-tables th {
            background-color: #0078D4;
            color: white;
            text-align: left;
            padding: 12px 15px;
            font-weight: 500;
        }

        .sentinel-tables tr:nth-child(even) {
            background-color: #f5f5f5;
        }

        .sentinel-tables td {
            padding: 12px 15px;
            border-bottom: 1px solid #eee;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }

        /* Footer */
        .footer {
            padding: 24px;
            background-color: #f0f0f0;
            text-align: center;
            border-top: 1px solid #ddd;
        }

        .footer h3 {
            margin-top: 0;
            color: #333;
        }

        .link {
            color: #0078D4;
            text-decoration: none;
        }
    </style>
    
</head>

<body>
    <div class="container">
        <!-- Header with alert title and company logo -->
        <div class="header">
            <h1>Safeguard Checked-Out Report</h1>
            <img src="@{parameters('companyLogo')}" alt="Company Logo">
        </div>
        
        <div class="content">
            <!-- Basic alert info -->
            <div class="info-item">
                <span class="info-label">Date:</span>
                <span>@{formatDateTime(utcNow(), 'dd/MM/yyyy HH:mm:ss')}</span>
            </div>

            <div class="info-item">
                <span class="info-label">Since:</span>
                <span>@{formatDateTime(addDays(utcNow(), -30), 'dd/MM/yyyy HH:mm:ss')}</span>
            </div>
            
              <div class="info-item">
                <span class="info-label">Description:</span>
                <span>@{parameters('incidentName')}</span>
            </div>
        
            <!-- Query section -->
            <div class="query-section">
                <div class="query-label">Sentinel Query:</div>
                
                <div class="kql-query">
<span class="comment">// Get security alerts from the past 90 days</span><br>
SecurityAlert<br>
| where TimeGenerated > ago(90d)<br>
| where DisplayName == "Safeguard (SPP) Multiple Passwords Checked-Out in a Short Timeframe"<br>
<span class="comment">// Extract entity information</span><br>
| mv-expand Entity = todynamic(Entities)<br>
| extend UserPrincipalName = tostring(Entity.Name)<br>
| extend FormattedTime = format_datetime(TimeGenerated, 'dd/MM/yyyy HH:mm:ss')<br>
<span class="comment">// Sort results by user and time</span><br>
| order by UserPrincipalName asc, TimeGenerated desc<br>
<span class="comment">// Summarize incidents by user</span><br>
| summarize IncidentsGenerated = count(),<br>
&nbsp;&nbsp;IncidentDates = make_list(FormattedTime)<br>
&nbsp;&nbsp;by UserPrincipalName<br>
| where IncidentsGenerated > 1<br>
<span class="comment">// Join with IdentityInfo to get user details</span><br>
| join kind=inner (<br>
&nbsp;&nbsp;IdentityInfo<br>
&nbsp;&nbsp;| summarize arg_max(TimeGenerated, *) by UserPrincipalName = AccountUPN<br>
) on UserPrincipalName<br>
<span class="comment">// Join with IdentityInfo again to get manager details</span><br>
| join kind=leftouter (<br>
&nbsp;&nbsp;IdentityInfo<br>
&nbsp;&nbsp;| extend ManagerName = AccountDisplayName<br>
&nbsp;&nbsp;| extend ManagerEmail = AccountUPN<br>
&nbsp;&nbsp;| summarize arg_max(TimeGenerated, ManagerEmail) by ManagerName<br>
) on $left.Manager == $right.ManagerName<br>
<span class="comment">// Project relevant fields</span><br>
| project UserPrincipalName, AccountDisplayName, IncidentsGenerated, IncidentDates, Manager, ManagerEmail<br>
| sort by IncidentsGenerated desc
                </div>
            </div>

            <!-- Affected entities details section -->
            <div class="section">
                <div class="section-title">
                    <span class="section-title-indicator"></span>
                    Affected Entities
                </div>
                <!-- Entities table from Sentinel -->
                <div class="sentinel-tables">
                    @{body('Create_HTML_table_1')}
                </div>
            </div>

            <!-- Contact information footer -->
            <div class="footer">
                <h3>Sentinel Security Team</h3>
                <p>If you have any questions, please contact us:</p>
                <p><a class="link" href="mailto:@{parameters('socEmail')}">@{parameters('socEmail')}</a></p>
                <p style="margin-top: 15px; font-size: 12px; color: #999;">This is an automated security alert.</p>
            </div>
        </div>
    </div>
</body>
</html>'''
        }
        Select: {
          runAfter: {
            Run_query_and_list_results: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@body(\'Run_query_and_list_results\')?[\'value\']'
            select: {
              'Account Name': '@{item()?[\'AccountDisplayName\']}'
              'Incidents Generated': '@{item()?[\'IncidentsGenerated\']}'
              Manager: '@{item()?[\'Manager\']}'
              'Manager Email': '@{item()?[\'ManagerEmail\']}'
            }
          }
        }
        Create_HTML_table_1: {
          runAfter: {
            Select: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@body(\'Select\')'
            format: 'HTML'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          'azuremonitorlogs-1': {
            connectionId: azureMonitorLogsConnection.id
            connectionName: azureMonitorLogsConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuremonitorlogs')
          }
          office365: {
            connectionId: office365Connection.id
            connectionName: office365ConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
        }
      }
    }
  }
}

resource azureMonitorLogsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: azureMonitorLogsConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: azureMonitorLogsConnectionName
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuremonitorlogs')
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
