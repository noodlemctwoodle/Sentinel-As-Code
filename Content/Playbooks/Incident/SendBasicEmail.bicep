metadata title = 'SendBasicEmail'
metadata description = 'Sentinel incident-trigger playbook for SendBasicEmail.'
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

@description('The Logic App\'s name.')
param PlaybookName string = 'SendBasicEmail'

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
        Compose_Incident_link: {
          runAfter: {
            Create_HTML_table_with_Entities: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '<a href="@{triggerBody()?[\'object\']?[\'properties\']?[\'incidentUrl\']}">View Incident</a>'
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
        Select_Entities: {
          runAfter: {}
          type: 'Select'
          inputs: {
            from: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            select: {
              Entity: '@item()?[\'properties\']?[\'friendlyName\']'
              'Entity Type': '@item()?[\'kind\']'
            }
          }
        }
        Send_an_email_with_Incident_details: {
          runAfter: {
            Compose_Incident_link: [
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
              To: 'socengineer@domain.com'
              Subject: 'New Azure Sentinel Incident - @{triggerBody()?[\'object\']?[\'properties\']?[\'title\']}'
              Body: '''
<p><span style="font-size: 16px"><strong>New incident created in Azure Sentinel. Incident details:</strong></span><br>
<br>
<span style="font-size: 14px"><strong>Incident title:<br>
</strong></span>@{triggerBody()?['object']?['properties']?['title']}<br>
<br>
<span style="font-size: 14px"><strong>Incident ID:<br>
</strong></span>@{triggerBody()?['object']?['properties']?['incidentNumber']}<br>
<br>
<span style="font-size: 14px"><strong>Creation time:<br>
</strong></span>@{triggerBody()?['object']?['properties']?['createdTimeUtc']}<br>
<br>
<span style="font-size: 14px"><strong>Severity:<br>
</strong></span>@{triggerBody()?['object']?['properties']?['severity']}<br>
<br>
<span style="font-size: 14px"><strong>Alert providers:<br>
</strong></span>@{join(triggerBody()?['object']?['properties']?['additionalData']?['alertProductNames'], '<br />')}<br>
<br>
<span style="font-size: 14px"><strong>Tactics:<br>
</strong></span>@{join(triggerBody()?['object']?['properties']?['additionalData']?['tactics'], '<br />')}<br>
<br>
<span style="font-size: 14px"><strong>Description:<br>
</strong></span>@{triggerBody()?['object']?['properties']?['description']}<br>
<br>
<span style="font-size: 14px"><strong>Entities:<br>
</strong></span><span style="font-size: 12px"></span><span style="font-size: 12px">@{body('Create_HTML_table_with_Entities')}</span><span style="font-size: 12px"></span><br>
<br>
<span style="font-size: 14px"><strong>Incident link:<br>
</strong></span>@{outputs('Compose_Incident_link')}<br>
</p>'''
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
