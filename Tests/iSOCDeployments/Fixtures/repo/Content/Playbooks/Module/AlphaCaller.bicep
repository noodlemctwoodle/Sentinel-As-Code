param PlaybookName string = 'Module-AlphaCaller'

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: PlaybookName
  location: resourceGroup().location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      actions: {
        Call_0: {
          type: 'Workflow'
          inputs: {
            host: {
              workflow: {
                id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Logic/workflows/Module-ZuluBase'
              }
            }
          }
        }
      }
      triggers: {}
    }
  }
}
