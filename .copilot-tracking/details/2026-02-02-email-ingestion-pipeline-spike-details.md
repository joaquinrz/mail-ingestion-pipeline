<!-- markdownlint-disable-file -->
# Implementation Details: Email Ingestion Pipeline Spike

## Context Reference

Sources: `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md`

## Implementation Phase 1: Project Structure Setup

<!-- parallelizable: true -->

### Step 1.1: Create infrastructure directory structure

Create the Bicep infrastructure directories for modular template organization.

Files:

* `infra/` - Root infrastructure directory
* `infra/modules/` - Bicep module directory for reusable components

Success criteria:

* Directory structure exists at `infra/modules/`
* Structure matches research document project layout

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 85-100) - Project structure definition

Dependencies:

* None

### Step 1.2: Create function app source directory structure

Create the Python Azure Functions source directory structure.

Files:

* `src/functions/` - Function app source code directory

Success criteria:

* Directory structure exists at `src/functions/`
* Ready for function code files

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 85-100) - Project structure definition

Dependencies:

* None

## Implementation Phase 2: Bicep Infrastructure Modules

<!-- parallelizable: true -->

### Step 2.1: Create storage account module

Create the Storage Account Bicep module required for Azure Functions.

Files:

* `infra/modules/storage.bicep` - Storage account resource definition

Implementation:

```bicep
@description('Storage account name')
param name string

@description('Azure region')
param location string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

output name string = storageAccount.name
output key string = storageAccount.listKeys().keys[0].value
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
```

Success criteria:

* Module compiles with `az bicep build`
* Outputs storage name, key, and connection string

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 125-150) - Storage module specification

Dependencies:

* Step 1.1 completion

### Step 2.2: Create Service Bus module

Create the Service Bus namespace and queue Bicep module.

Files:

* `infra/modules/service-bus.bicep` - Service Bus namespace, queue, and authorization rules

Implementation:

```bicep
@description('Service Bus namespace name')
param name string

@description('Azure region')
param location string

@description('Queue name for email messages')
param queueName string

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: name
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
  }
}

resource emailQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: queueName
  properties: {
    lockDuration: 'PT5M'
    maxDeliveryCount: 10
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    enableBatchedOperations: true
    maxSizeInMegabytes: 1024
  }
}

resource sendAuthRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'SendOnly'
  properties: {
    rights: ['Send']
  }
}

resource listenAuthRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'ListenOnly'
  properties: {
    rights: ['Listen']
  }
}

output namespaceName string = serviceBusNamespace.name
output queueName string = emailQueue.name
output connectionString string = listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
output sendConnectionString string = sendAuthRule.listKeys().primaryConnectionString
output listenConnectionString string = listenAuthRule.listKeys().primaryConnectionString
```

Success criteria:

* Module compiles with `az bicep build`
* Creates namespace, queue, and authorization rules
* Outputs connection strings for send and listen operations

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 152-205) - Service Bus module specification

Dependencies:

* Step 1.1 completion

### Step 2.3: Create Logic App module

Create the Logic App workflow with Office 365 and Service Bus connectors.

Files:

* `infra/modules/logic-app.bicep` - Logic App workflow, API connections

Implementation:

```bicep
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
              ContentData: '@{base64(concat(\'{"subject":"\', triggerOutputs()?[\'body/subject\'], \'","from":"\', triggerOutputs()?[\'body/from\'], \'","receivedDateTime":"\', triggerOutputs()?[\'body/receivedDateTime\'], \'","bodyPreview":"\', replace(triggerOutputs()?[\'body/bodyPreview\'], \'"\', \'\\\\\"\'), \'"}\'))}'
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
```

Success criteria:

* Module compiles with `az bicep build`
* Creates Logic App with email trigger and Service Bus action
* Creates API connections for Office 365 and Service Bus

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 207-290) - Logic App module specification

Dependencies:

* Step 1.1 completion

### Step 2.4: Create Function App module

Create the Function App with App Service Plan and Application Insights.

Files:

* `infra/modules/function-app.bicep` - Function App, App Service Plan, Application Insights

Implementation:

```bicep
@description('Function App name')
param name string

@description('Azure region')
param location string

@description('Storage account name')
param storageAccountName string

@description('Storage account key')
@secure()
param storageAccountKey string

@description('Service Bus connection string')
@secure()
param serviceBusConnectionString string

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${name}-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${name}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: name
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      pythonVersion: '3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountKey};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountKey};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(name)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'ServiceBusConnection'
          value: serviceBusConnectionString
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
      ]
    }
  }
}

output name string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
output appInsightsName string = appInsights.name
```

Success criteria:

* Module compiles with `az bicep build`
* Creates consumption-tier Function App on Linux with Python 3.11
* Configures Service Bus connection and Application Insights

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 292-365) - Function App module specification

Dependencies:

* Step 1.1 completion

## Implementation Phase 3: Main Bicep Orchestration

<!-- parallelizable: false -->

### Step 3.1: Create main Bicep template

Create the main orchestration template that deploys all modules.

Files:

* `infra/main.bicep` - Main deployment orchestration

Implementation:

```bicep
targetScope = 'resourceGroup'

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string = 'emailpipeline'

var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${baseName}${environment}'

module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    name: 'st${resourcePrefix}${uniqueSuffix}'
    location: location
  }
}

module serviceBus 'modules/service-bus.bicep' = {
  name: 'servicebus-deployment'
  params: {
    name: 'sb-${resourcePrefix}-${uniqueSuffix}'
    location: location
    queueName: 'email-messages'
  }
}

module logicApp 'modules/logic-app.bicep' = {
  name: 'logicapp-deployment'
  params: {
    name: 'logic-${resourcePrefix}-${uniqueSuffix}'
    location: location
    serviceBusConnectionString: serviceBus.outputs.connectionString
    serviceBusQueueName: 'email-messages'
  }
}

module functionApp 'modules/function-app.bicep' = {
  name: 'functionapp-deployment'
  params: {
    name: 'func-${resourcePrefix}-${uniqueSuffix}'
    location: location
    storageAccountName: storage.outputs.name
    storageAccountKey: storage.outputs.key
    serviceBusConnectionString: serviceBus.outputs.connectionString
  }
}

output resourceGroupName string = resourceGroup().name
output logicAppName string = logicApp.outputs.name
output functionAppName string = functionApp.outputs.name
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output serviceBusQueueName string = 'email-messages'
```

Success criteria:

* Template compiles with `az bicep build`
* References all module files correctly
* Outputs resource names for post-deployment use

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 105-123) - Main Bicep template

Dependencies:

* Phase 2 completion (all modules exist)

### Step 3.2: Create parameters file

Create the Bicep parameters file for deployment configuration.

Files:

* `infra/main.bicepparam` - Parameters for dev environment

Implementation:

```bicep
using './main.bicep'

param environment = 'dev'
param location = 'eastus2'
param baseName = 'emailpipeline'
```

Success criteria:

* Parameters file references main.bicep correctly
* Provides sensible defaults for spike deployment

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 290-300) - Parameters file

Dependencies:

* Step 3.1 completion

### Step 3.3: Validate Bicep templates compile successfully

Run Bicep validation on all template files.

Validation commands:

* `az bicep build --file infra/main.bicep` - Validate main template and modules
* Check for reference errors, missing parameters, and syntax issues

Success criteria:

* All Bicep files compile without errors
* No unresolved module or parameter references

Dependencies:

* Steps 3.1 and 3.2 completion

## Implementation Phase 4: Azure Function Implementation

<!-- parallelizable: true -->

### Step 4.1: Create Python function with Service Bus trigger

Create the main function app code using Python v2 programming model.

Files:

* `src/functions/function_app.py` - Service Bus triggered function

Implementation:

```python
"""
Email Message Processor Function
Triggered by messages from Service Bus queue
"""
import azure.functions as func
import logging
import json

app = func.FunctionApp()


@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="email-messages",
    connection="ServiceBusConnection"
)
def process_email_message(msg: func.ServiceBusMessage) -> None:
    """
    Process incoming email messages from Service Bus queue.

    Args:
        msg: Service Bus message containing email data
    """
    message_body = msg.get_body().decode('utf-8')
    message_id = msg.message_id

    logging.info(f"Processing message ID: {message_id}")

    try:
        email_data = json.loads(message_body)

        subject = email_data.get('subject', 'No Subject')
        sender = email_data.get('from', 'Unknown')
        received_time = email_data.get('receivedDateTime', 'Unknown')
        body_preview = email_data.get('bodyPreview', '')

        logging.info(f"Email received:")
        logging.info(f"  Subject: {subject}")
        logging.info(f"  From: {sender}")
        logging.info(f"  Received: {received_time}")
        logging.info(f"  Preview: {body_preview[:100]}...")

        logging.info(f"Successfully processed message ID: {message_id}")

    except json.JSONDecodeError as e:
        logging.error(f"Failed to parse message JSON: {e}")
        logging.error(f"Raw message: {message_body}")
        raise
    except Exception as e:
        logging.error(f"Error processing message {message_id}: {e}")
        raise
```

Success criteria:

* Python syntax validates successfully
* Uses v2 programming model with decorator-based triggers
* Implements proper error handling and logging

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 370-420) - Function implementation

Dependencies:

* Step 1.2 completion

### Step 4.2: Create host.json configuration

Create the Azure Functions host configuration.

Files:

* `src/functions/host.json` - Function host settings

Implementation:

```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      },
      "enableLiveMetricsFilters": true
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  },
  "extensions": {
    "serviceBus": {
      "prefetchCount": 100,
      "messageHandlerOptions": {
        "autoComplete": true,
        "maxConcurrentCalls": 32,
        "maxAutoRenewDuration": "00:05:00"
      }
    }
  }
}
```

Success criteria:

* Valid JSON syntax
* Configures Application Insights integration
* Sets Service Bus processing options

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 422-450) - Host configuration

Dependencies:

* Step 1.2 completion

### Step 4.3: Create requirements.txt

Create Python dependencies file for the Function App.

Files:

* `src/functions/requirements.txt` - Python package dependencies

Implementation:

```
azure-functions
azure-servicebus
```

Success criteria:

* Lists required Azure Functions SDK
* Includes Service Bus SDK for message handling

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 452-458) - Requirements

Dependencies:

* Step 1.2 completion

## Implementation Phase 5: Documentation

<!-- parallelizable: true -->

### Step 5.1: Create project README with setup instructions

Create comprehensive README documenting the spike and deployment steps.

Files:

* `README.md` - Project documentation

Content sections:

1. Overview and architecture diagram
2. Prerequisites (Azure CLI, subscriptions, tools)
3. Quick start deployment commands
4. Post-deployment configuration (Office 365 authorization)
5. Testing and verification steps
6. Cleanup commands
7. Next steps and limitations

Success criteria:

* Provides clear step-by-step deployment instructions
* Documents manual OAuth authorization requirement
* Includes architecture diagram
* Lists all prerequisites

Context references:

* `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md` (Lines 25-80) - Setup and deployment commands

Dependencies:

* None

## Implementation Phase 6: Validation

<!-- parallelizable: false -->

### Step 6.1: Run Bicep template validation

Execute Bicep build validation on all infrastructure files.

Validation commands:

* `az bicep build --file infra/main.bicep`
* `az bicep build --file infra/modules/storage.bicep`
* `az bicep build --file infra/modules/service-bus.bicep`
* `az bicep build --file infra/modules/logic-app.bicep`
* `az bicep build --file infra/modules/function-app.bicep`

### Step 6.2: Validate Python function syntax

Run Python syntax validation on function code.

Validation commands:

* `python -m py_compile src/functions/function_app.py`
* Verify JSON syntax in `src/functions/host.json`

### Step 6.3: Report blocking issues

When validation failures require changes beyond minor fixes:

* Document the issues and affected files
* Provide the user with next steps
* Recommend additional research and planning rather than inline fixes
* Avoid large-scale refactoring within this phase

## Dependencies

* Azure CLI 2.50+ with Bicep extension
* Python 3.11
* Azure Functions Core Tools v4 (for deployment)
* Azure subscription with Owner or Contributor access
* Office 365 mailbox for email source

## Success Criteria

* All Bicep templates compile without errors
* Python function code passes syntax validation
* Project structure matches architecture specification
* README provides complete deployment instructions
* Single command deployment via `az deployment group create`
