@description('Logic App name')
param name string

@description('Azure region')
param location string

@description('Service Bus connection string')
@secure()
param serviceBusConnectionString string

@description('Service Bus queue name')
param serviceBusQueueName string

resource serviceBusConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'servicebus-connection'
  location: location
  properties: {
    displayName: 'Service Bus Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'servicebus')
    }
    parameterValues: {
      connectionString: serviceBusConnectionString
    }
  }
}

resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'office365-connection'
  location: location
  properties: {
    displayName: 'Office 365 Outlook'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
  }
}

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: name
  location: location
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
        When_a_new_email_arrives_V3: {
          type: 'ApiConnection'
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          evaluatedRecurrence: {
            frequency: 'Minute'
            interval: 1
          }
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v3/Mail/OnNewEmail'
            queries: {
              folderPath: 'Inbox'
              importance: 'Any'
              includeAttachments: false
              fetchOnlyWithAttachment: false
            }
          }
        }
      }
      actions: {
        Send_message_to_Service_Bus: {
          type: 'ApiConnection'
          runAfter: {}
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/@{encodeURIComponent(encodeURIComponent(\'${serviceBusQueueName}\'))}/messages'
            body: {
              ContentData: '@{base64(triggerBody())}'
            }
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
            connectionName: 'office365-connection'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
          servicebus: {
            connectionId: serviceBusConnection.id
            connectionName: 'servicebus-connection'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'servicebus')
          }
        }
      }
    }
  }
}

output name string = logicApp.name
output id string = logicApp.id
output office365ConnectionName string = office365Connection.name
