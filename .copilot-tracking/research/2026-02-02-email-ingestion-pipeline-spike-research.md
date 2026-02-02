<!-- markdownlint-disable-file -->
# Task Research: Email Ingestion Pipeline Spike

A quick spike implementation for an email ingestion pipeline using Azure Logic Apps, Service Bus, and Azure Functions. This document provides step-by-step instructions, Azure CLI commands, and Bicep templates for deploying the infrastructure.

## Task Implementation Requests

* Step-by-step Azure CLI commands to login and set up subscription
* Bicep templates to deploy all infrastructure components
* Basic implementation of Logic App, Service Bus, and Azure Function
* End-to-end working spike for email → queue → function flow

## Scope and Success Criteria

* Scope: Minimum viable spike with all three components deployed and connected
* Assumptions:
  * Office 365 mailbox as email source
  * Python Azure Function for processing
  * Consumption tier for cost-effective spike
  * Single resource group deployment
* Success Criteria:
  * All resources deploy successfully via Bicep
  * Logic App triggers on new emails and sends to Service Bus
  * Azure Function processes messages from Service Bus queue
  * End-to-end flow testable with a real email

## Architecture

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Office 365    │      │   Azure Logic   │      │   Service Bus   │      │ Azure Function  │
│     Mailbox     │ ───▶ │      App        │ ───▶ │     Queue       │ ───▶ │   (Python)      │
│                 │      │  (Consumption)  │      │   (Standard)    │      │                 │
└─────────────────┘      └─────────────────┘      └─────────────────┘      └─────────────────┘
        │                        │                        │                        │
        │                        │                        │                        │
   Email arrives           Polls every            Messages queued          Triggered by
   in Inbox                1 minute               with email data          new messages
```

## Step 1: Azure CLI Setup and Login

### 1.1 Install Azure CLI (macOS)

```bash
# Install via Homebrew (recommended)
brew update && brew install azure-cli

# Verify installation
az version
```

### 1.2 Login to Azure

```bash
# Interactive login (opens browser)
az login

# If you have multiple tenants, specify tenant
az login --tenant <tenant-id>
```

### 1.3 Select Subscription

```bash
# List available subscriptions
az account list --output table

# Set the subscription you want to use
az account set --subscription "<subscription-name-or-id>"

# Verify current subscription
az account show --output table
```

### 1.4 Create Resource Group

```bash
# Set variables
RESOURCE_GROUP="rg-email-pipeline-spike-dev"
LOCATION="eastus2"

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION
```

## Step 2: Bicep Infrastructure

### 2.1 Project Structure

```
mail-ingestion-pipeline/
├── infra/
│   ├── main.bicep                 # Main orchestration
│   ├── main.bicepparam            # Parameters file
│   └── modules/
│       ├── service-bus.bicep      # Service Bus namespace + queue
│       ├── logic-app.bicep        # Logic App + O365 connection
│       ├── function-app.bicep     # Function App + dependencies
│       └── storage.bicep          # Storage account
├── src/
│   └── functions/
│       ├── function_app.py        # Python function code
│       ├── host.json              # Function host config
│       └── requirements.txt       # Python dependencies
└── README.md
```

### 2.2 Main Bicep Template

**File: `infra/main.bicep`**

```bicep
// Main orchestration for Email Ingestion Pipeline Spike
targetScope = 'resourceGroup'

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string = 'emailpipeline'

// Generate unique suffix for globally unique names
var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${baseName}${environment}'

// Storage Account (required for Function App)
module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    name: 'st${resourcePrefix}${uniqueSuffix}'
    location: location
  }
}

// Service Bus Namespace and Queue
module serviceBus 'modules/service-bus.bicep' = {
  name: 'servicebus-deployment'
  params: {
    name: 'sb-${resourcePrefix}-${uniqueSuffix}'
    location: location
    queueName: 'email-messages'
  }
}

// Logic App with Office 365 connection
module logicApp 'modules/logic-app.bicep' = {
  name: 'logicapp-deployment'
  params: {
    name: 'logic-${resourcePrefix}-${uniqueSuffix}'
    location: location
    serviceBusConnectionString: serviceBus.outputs.connectionString
    serviceBusQueueName: 'email-messages'
  }
}

// Function App for message processing
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

// Outputs
output resourceGroupName string = resourceGroup().name
output logicAppName string = logicApp.outputs.name
output functionAppName string = functionApp.outputs.name
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output serviceBusQueueName string = 'email-messages'
```

### 2.3 Storage Account Module

**File: `infra/modules/storage.bicep`**

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

### 2.4 Service Bus Module

**File: `infra/modules/service-bus.bicep`**

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
    lockDuration: 'PT5M'                        // 5 minute lock for processing
    maxDeliveryCount: 10                        // Retries before dead-letter
    defaultMessageTimeToLive: 'P14D'            // 14 day retention
    deadLetteringOnMessageExpiration: true      // Dead-letter expired messages
    enableBatchedOperations: true               // Performance optimization
    maxSizeInMegabytes: 1024                    // 1 GB queue size
  }
}

// Authorization rule for the Logic App to send messages
resource sendAuthRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'SendOnly'
  properties: {
    rights: ['Send']
  }
}

// Authorization rule for the Function App to listen
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

### 2.5 Logic App Module

**File: `infra/modules/logic-app.bicep`**

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

// Service Bus API Connection (for sending messages)
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

// Office 365 Outlook API Connection (requires manual authorization after deployment)
resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'office365-connection'
  location: location
  properties: {
    displayName: 'Office 365 Outlook'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
    // Note: OAuth connections require manual authorization in Azure Portal after deployment
  }
}

// Logic App Workflow
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

### 2.6 Function App Module

**File: `infra/modules/function-app.bicep`**

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

// Consumption App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${name}-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true  // Required for Linux
  }
}

// Function App
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

// Application Insights for monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${name}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

output name string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
output appInsightsName string = appInsights.name
```

### 2.7 Parameters File

**File: `infra/main.bicepparam`**

```bicep
using './main.bicep'

param environment = 'dev'
param location = 'eastus2'
param baseName = 'emailpipeline'
```

## Step 3: Function App Code

### 3.1 Python Function Implementation

**File: `src/functions/function_app.py`**

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
    # Get message content
    message_body = msg.get_body().decode('utf-8')
    message_id = msg.message_id
    
    logging.info(f"Processing message ID: {message_id}")
    
    try:
        # Parse the email data from JSON
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
        
        # TODO: Add your email processing logic here
        # Examples:
        # - Store in database
        # - Forward to another service
        # - Extract attachments
        # - Run sentiment analysis
        # - Trigger workflow based on content
        
        logging.info(f"Successfully processed message ID: {message_id}")
        
    except json.JSONDecodeError as e:
        logging.error(f"Failed to parse message JSON: {e}")
        logging.error(f"Raw message: {message_body}")
        raise
    except Exception as e:
        logging.error(f"Error processing message {message_id}: {e}")
        raise
```

### 3.2 Function Host Configuration

**File: `src/functions/host.json`**

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

### 3.3 Python Requirements

**File: `src/functions/requirements.txt`**

```
azure-functions
azure-servicebus
```

## Step 4: Deployment Commands

### 4.1 Deploy Infrastructure

```bash
# Navigate to project root
cd /Users/joaquinrz/joaquin-github/joaquinrz/mail-ingestion-pipeline

# Validate the Bicep template
az deployment group validate \
  --resource-group $RESOURCE_GROUP \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam

# Preview changes (what-if)
az deployment group what-if \
  --resource-group $RESOURCE_GROUP \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam

# Deploy the infrastructure
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam \
  --name "email-pipeline-$(date +%Y%m%d-%H%M%S)"
```

### 4.2 Authorize Office 365 Connection (Manual Step)

After deployment, the Office 365 connection requires manual OAuth authorization:

```bash
# Get the Logic App name from deployment output
LOGIC_APP_NAME=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name "email-pipeline-*" \
  --query "properties.outputs.logicAppName.value" \
  --output tsv)

# Open Azure Portal to authorize the connection
echo "Open this URL to authorize the Office 365 connection:"
echo "https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/connections/office365-connection/edit"
```

**In Azure Portal:**
1. Navigate to the `office365-connection` API Connection resource
2. Click "Edit API connection"
3. Click "Authorize" and sign in with your Office 365 account
4. Click "Save"

### 4.3 Deploy Function App Code

```bash
# Get the Function App name
FUNCTION_APP_NAME=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name "email-pipeline-*" \
  --query "properties.outputs.functionAppName.value" \
  --output tsv)

# Navigate to function source
cd src/functions

# Deploy using Azure Functions Core Tools
func azure functionapp publish $FUNCTION_APP_NAME --python
```

**Alternative: Deploy via ZIP**

```bash
# Create deployment package
cd src/functions
zip -r ../function-app.zip .

# Deploy
az functionapp deployment source config-zip \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --src ../function-app.zip
```

## Step 5: Testing and Verification

### 5.1 Verify Resources Deployed

```bash
# List all resources in the resource group
az resource list \
  --resource-group $RESOURCE_GROUP \
  --output table
```

### 5.2 Test the Pipeline

1. **Send a test email** to the mailbox monitored by the Logic App
2. **Check Logic App run history**:
   ```bash
   az logic workflow run list \
     --resource-group $RESOURCE_GROUP \
     --name $LOGIC_APP_NAME \
     --output table
   ```

3. **Check Service Bus queue metrics**:
   ```bash
   az servicebus queue show \
     --resource-group $RESOURCE_GROUP \
     --namespace-name <sb-namespace> \
     --name email-messages \
     --query "{ActiveMessages:countDetails.activeMessageCount, DeadLetter:countDetails.deadLetterMessageCount}"
   ```

4. **Check Function App logs**:
   ```bash
   az webapp log tail \
     --resource-group $RESOURCE_GROUP \
     --name $FUNCTION_APP_NAME
   ```

### 5.3 View Application Insights

```bash
# Open Application Insights in browser
az monitor app-insights component show \
  --resource-group $RESOURCE_GROUP \
  --app "${FUNCTION_APP_NAME}-insights" \
  --query "instrumentationKey" \
  --output tsv
```

## Cleanup

```bash
# Delete all resources when done with spike
az group delete \
  --name $RESOURCE_GROUP \
  --yes \
  --no-wait
```

## Key Discoveries

### Project Structure

This spike uses a modular Bicep structure with separate modules for each component, enabling:
- Independent resource updates
- Clear separation of concerns
- Reusable modules for future projects

### Implementation Patterns

| Pattern | Implementation |
|---------|----------------|
| **Message Format** | JSON with email metadata (subject, from, timestamp, preview) |
| **Error Handling** | Dead-letter queue after 10 retries |
| **Processing Lock** | 5-minute lock duration for message processing |
| **Monitoring** | Application Insights integrated with Function App |

### Important Considerations

1. **OAuth Authorization**: The Office 365 connector requires manual authorization after deployment
2. **Message Size**: Service Bus Standard tier supports up to 256 KB messages; large emails may need Blob Storage
3. **Attachments**: Currently disabled in trigger; enable with `includeAttachments: true` and handle separately
4. **Rate Limits**: Office 365 connector has 300 calls/60 seconds throttling

## Next Steps (Post-Spike)

* Add Blob Storage for email attachments
* Implement structured logging with correlation IDs
* Add Azure Key Vault for secrets management
* Create CI/CD pipeline for automated deployments
* Add unit tests for the Function App
* Implement retry policies and circuit breakers
