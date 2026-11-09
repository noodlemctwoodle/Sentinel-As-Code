metadata title = 'Request-TeamsApproval'
metadata description = 'Reusable automation module: Request-TeamsApproval.'
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
param PlaybookName string = 'Module-Request-TeamsApproval'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'
var microsoftTeamsConnectionName = 'MicrosoftTeams-${PlaybookName}'

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
        UPN1: {
          defaultValue: 'socanalyst@domain.com'
          type: 'String'
        }
        'UPN1 Friendly Name': {
          defaultValue: 'SOC Analyst'
          type: 'String'
        }
        UPN2: {
          defaultValue: 'socengineer@domain.com'
          type: 'String'
        }
        'UPN2 Friendly Name': {
          defaultValue: 'SOC Engineer'
          type: 'String'
        }
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        When_an_approval_is_received: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                algorithm: {
                  type: 'string'
                }
                entityProperties: {
                  type: 'string'
                }
                incidentArmId: {
                  type: 'string'
                }
                indicatorValue: {
                  type: 'string'
                }
                playbookName: {
                  type: 'string'
                }
                severity: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
      }
      actions: {
        Compose_adaptive_care_template: {
          runAfter: {
            Get_incident: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: {
            '$schema': 'http://adaptivecards.io/schemas/adaptive-card.json'
            body: [
              {
                columns: [
                  {
                    id: 'e5756242-0963-37a2-7cb4-4397886d60bb'
                    items: [
                      {
                        id: '20f3833e-0435-5c87-fad1-b528e0046fb6'
                        size: 'Large'
                        text: 'Defender XDR IoC Request'
                        type: 'TextBlock'
                        weight: 'Bolder'
                        wrap: true
                      }
                    ]
                    padding: 'None'
                    type: 'Column'
                    verticalContentAlignment: 'Center'
                    width: 'stretch'
                  }
                  {
                    horizontalAlignment: 'Right'
                    id: '74215a26-fa8b-e549-cced-7f99fd34a661'
                    items: [
                      {
                        id: '795047e2-e63e-6e14-07ba-5a3e13323dff'
                        size: 'Small'
                        type: 'Image'
                        url: 'https://amdesigner.azurewebsites.net/samples/assets/PlaceHolder_Person.png'
                      }
                    ]
                    padding: 'None'
                    type: 'Column'
                    width: 'auto'
                  }
                ]
                id: '1ede2aba-61b9-faa0-9895-9ed0c26b2e6f'
                padding: {
                  bottom: 'Small'
                  left: 'Default'
                  right: 'Small'
                  top: 'Small'
                }
                style: 'emphasis'
                type: 'ColumnSet'
              }
              {
                id: 'fbcee869-2754-287d-bb37-145a4ccd750b'
                items: [
                  {
                    id: '44906797-222f-9fe2-0b7a-e3ee21c6e380'
                    size: 'Large'
                    text: '@{body(\'Get_incident\')?[\'properties\']?[\'title\']}'
                    type: 'TextBlock'
                    weight: 'Bolder'
                    wrap: true
                  }
                  {
                    facts: [
                      {
                        title: 'Created Time'
                        value: '@{formatDateTime(body(\'Get_incident\')?[\'properties\']?[\'createdTimeUtc\'], \'dd-MM-yyyy HH:mm:ss\')}'
                      }
                      {
                        title: 'Severity'
                        value: '@{body(\'Get_incident\')?[\'properties\']?[\'severity\']}'
                      }
                    ]
                    id: '21656664-922b-b4c8-3a65-351e2656fb21'
                    type: 'FactSet'
                  }
                  {
                    id: 'f7abdf1a-3cce-2159-28ef-f2f362ec937e'
                    text: '@{body(\'Get_incident\')?[\'properties\']?[\'description\']}'
                    type: 'TextBlock'
                    wrap: true
                  }
                  {
                    type: 'ActionSet'
                    actions: [
                      {
                        type: 'Action.Submit'
                        title: 'Approve'
                        id: 'action.ioc.approve'
                      }
                    ]
                  }
                  {
                    type: 'ActionSet'
                    actions: [
                      {
                        type: 'Action.Submit'
                        title: 'Deny'
                        id: 'action.ioc.deny'
                      }
                    ]
                  }
                  {
                    actions: [
                      {
                        card: {
                          '$schema': 'http://adaptivecards.io/schemas/adaptive-card.json'
                          body: [
                            {
                              id: 'd2a2f235-2cf2-90c1-dab4-4a28dbea74d8'
                              items: [
                                {
                                  id: 'action.ioc.comments.content'
                                  isMultiline: true
                                  isRequired: true
                                  label: 'Add a Comment to incident'
                                  placeholder: 'Incident Comments*'
                                  type: 'Input.Text'
                                }
                                {
                                  type: 'TextBlock'
                                  text: 'Comment'
                                  wrap: true
                                  isVisible: false
                                }
                                {
                                  actions: [
                                    {
                                      associatedInputs: 'auto'
                                      id: 'action.ioc.comments.submit'
                                      style: 'positive'
                                      title: 'Submit'
                                      type: 'Action.Submit'
                                    }
                                  ]
                                  type: 'ActionSet'
                                }
                              ]
                              padding: 'None'
                              type: 'Container'
                            }
                          ]
                          padding: 'Default'
                          type: 'AdaptiveCard'
                        }
                        id: 'action.ioc.comments.button'
                        title: 'Add Comments'
                        type: 'Action.ShowCard'
                        style: 'positive'
                      }
                    ]
                    id: 'c8a5ba7e-7ec6-53ae-79da-0cfb952a527e'
                    type: 'ActionSet'
                  }
                ]
                padding: 'Default'
                spacing: 'None'
                type: 'Container'
              }
              {
                horizontalAlignment: 'Right'
                id: '77102c5d-fde2-e573-4ea5-66022d646d64'
                items: [
                  {
                    color: 'Accent'
                    horizontalAlignment: 'Right'
                    id: '42654e7e-cece-b419-867a-3e3ef4076870'
                    text: '[View in portal](@{body(\'Get_incident\')?[\'properties\']?[\'incidentUrl\']})'
                    type: 'TextBlock'
                    wrap: true
                  }
                ]
                padding: {
                  bottom: 'Small'
                  left: 'Small'
                  right: 'Default'
                  top: 'Small'
                }
                separator: true
                spacing: 'None'
                type: 'Container'
              }
            ]
            padding: 'None'
            type: 'AdaptiveCard'
            version: '1.4'
          }
        }
        Parse_adaptive_card_response: {
          runAfter: {
            Post_adaptive_card_and_wait_for_a_response: [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '@body(\'Post_adaptive_card_and_wait_for_a_response\')'
            schema: {
              properties: {
                data: {
                  properties: {
                    'action.ioc.approve': {
                      type: 'string'
                    }
                    'action.ioc.deny': {
                      type: 'string'
                    }
                    'action.ioc.comments.content': {
                      type: 'string'
                    }
                    'action.ioc.comments.submit': {
                      type: 'string'
                    }
                  }
                  type: 'object'
                }
                messageId: {
                  type: 'string'
                }
                messageLink: {
                  type: 'string'
                }
                responder: {
                  properties: {
                    displayName: {
                      type: 'string'
                    }
                    email: {
                      type: 'string'
                    }
                    objectId: {
                      type: 'string'
                    }
                    tenantId: {
                      type: 'string'
                    }
                    userPrincipalName: {
                      type: 'string'
                    }
                  }
                  type: 'object'
                }
                responseTime: {
                  type: 'string'
                }
                submitActionId: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
        Post_adaptive_card_and_wait_for_a_response: {
          runAfter: {
            Compose_adaptive_care_template: [
              'Succeeded'
            ]
          }
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'teams-1\'][\'connectionId\']'
              }
            }
            body: {
              notificationUrl: '@{listCallbackUrl()}'
              body: {
                messageBody: '@{outputs(\'Compose_adaptive_care_template\')}'
                updateMessage: 'Thanks for your response!'
                recipient: {
                  groupId: '00000000-0000-0000-0000-000000000000'
                  channelId: '19:00000000000000000000000000000000@thread.tacv2'
                }
              }
            }
            path: '/v1.0/teams/conversation/gatherinput/poster/Flow bot/location/@{encodeURIComponent(\'Channel\')}/$subscriptions'
          }
        }
        Switch: {
          runAfter: {
            Parse_adaptive_card_response: [
              'Succeeded'
            ]
          }
          cases: {
            Approve_IoC: {
              case: 'action.ioc.approve'
              actions: {
                Response_Approved: {
                  type: 'Response'
                  kind: 'Http'
                  inputs: {
                    statusCode: 200
                    body: {
                      success: 'Approved'
                    }
                  }
                }
              }
            }
            Deny_IoC: {
              case: 'action.ioc.deny'
              actions: {
                Response_Denied: {
                  type: 'Response'
                  kind: 'Http'
                  inputs: {
                    statusCode: 200
                    body: {
                      success: 'Blocked'
                    }
                  }
                }
              }
            }
            Add_Comments: {
              case: 'action.ioc.comments.submit'
              actions: {
                'Module-AddSentinelComment': {
                  runAfter: {
                    'Module-SendEmail': [
                      'Succeeded'
                    ]
                  }
                  type: 'Workflow'
                  inputs: {
                    host: {
                      workflow: {
                        id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-AddSentinelComment'
                      }
                      triggerName: 'When_a_HTTP_request_is_received'
                    }
                    body: {
                      SentinelComment: '@body(\'Parse_adaptive_card_response\')?[\'data\']?[\'action.ioc.comments.content\']'
                      IncidentARMId: '@body(\'Get_incident\')?[\'id\']'
                    }
                  }
                }
                Condition: {
                  actions: {
                    Comments_Added_Success: {
                      type: 'Response'
                      kind: 'Http'
                      inputs: {
                        statusCode: 200
                        body: {
                          status: 'success'
                          message: 'Comments added successfully'
                        }
                      }
                    }
                  }
                  runAfter: {
                    'Module-AddSentinelComment': [
                      'Succeeded'
                    ]
                  }
                  else: {
                    actions: {
                      Comments_Added_Failed: {
                        type: 'Response'
                        kind: 'Http'
                        inputs: {
                          statusCode: 400
                          body: {
                            status: 'Failed'
                            message: 'Comments step failed'
                          }
                        }
                      }
                    }
                  }
                  expression: {
                    and: [
                      {
                        equals: [
                          '@outputs(\'Module-AddSentinelComment\')?[\'statusCode\']'
                          200
                        ]
                      }
                    ]
                  }
                  type: 'If'
                }
                'Module-SendEmail': {
                  type: 'Workflow'
                  inputs: {
                    host: {
                      workflow: {
                        id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${AutomationResourceGroup}/providers/Microsoft.Logic/workflows/Module-SendEmail'
                      }
                      triggerName: 'When_a_HTTP_request_is_received'
                    }
                    body: {
                      To: 'socengineer@domain.com'
                      Subject: 'IoC Comments Added'
                      Body: '@body(\'Parse_adaptive_card_response\')?[\'data\']?[\'action.ioc.comments.content\']'
                    }
                  }
                }
              }
            }
          }
          default: {
            actions: {
              Response_404: {
                type: 'Response'
                kind: 'Http'
                inputs: {
                  statusCode: 404
                  body: {
                    status: 'Failed'
                    message: 'No Respoonse'
                  }
                }
              }
            }
          }
          expression: '@body(\'Parse_adaptive_card_response\')?[\'submitActionId\']'
          type: 'Switch'
        }
        Get_incident: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel-1\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              incidentArmId: '@triggerBody()?[\'incidentArmId\']'
            }
            path: '/Incidents'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
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
          'teams-1': {
            connectionId: microsoftTeamsConnection.id
            connectionName: microsoftTeamsConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
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

resource microsoftTeamsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: microsoftTeamsConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: microsoftTeamsConnectionName
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
    }
  }
}
