---
title: Azure Functions with Service Bus Trigger - Research Findings
description: Research documentation for implementing Azure Functions with Service Bus triggers using Bicep templates
ms.date: 2026-02-02
ms.topic: reference
author: copilot-research
---

## Overview

This document contains research findings for implementing Azure Functions with Service Bus trigger capabilities using Infrastructure as Code (Bicep). The research covers Function App deployment, Service Bus connection configuration, and trigger function implementations.

## Sources Referenced

- [Microsoft.Web/sites Bicep Template Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.web/sites)
- [Microsoft.Web/serverfarms Bicep Template Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.web/serverfarms)
- [Azure Service Bus Trigger for Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-service-bus-trigger)
- [Azure/azure-functions-templates GitHub Repository](https://github.com/Azure/azure-functions-templates)

## Function App Bicep Resource Definition

### Basic Function App Structure

```bicep
resource functionApp 'Microsoft.Web/sites@2025-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'  // or 'dotnet-isolated' for C#
        }
        {
          name: 'ServiceBusConnection'
          value: serviceBusConnectionString
        }
      ]
      linuxFxVersion: 'PYTHON|3.11'  // For Python functions
      // OR for .NET Isolated:
      // netFrameworkVersion: 'v8.0'
    }
    reserved: true  // Required for Linux
  }
}
```

### Key Properties Explained

| Property | Description | Required |
|----------|-------------|----------|
| `kind` | Set to `functionapp` for Azure Functions | Yes |
| `serverFarmId` | Reference to the App Service Plan | Yes |
| `httpsOnly` | Enforces HTTPS-only traffic | Recommended |
| `reserved` | Set to `true` for Linux hosting | For Linux |
| `linuxFxVersion` | Runtime stack for Linux (e.g., `PYTHON|3.11`) | For Linux |

## App Service Plan (Consumption) Definition

### Consumption Plan Configuration

The Consumption plan uses `Y1` SKU for dynamic scaling with pay-per-execution billing:

```bicep
resource appServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: appServicePlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    reserved: true  // Required for Linux Consumption
  }
}
```

### SKU Options Reference

| SKU Name | Tier | Use Case |
|----------|------|----------|
| `Y1` | Dynamic | Consumption plan (pay-per-execution) |
| `EP1` | ElasticPremium | Premium plan with VNET support |
| `EP2` | ElasticPremium | Premium plan (more resources) |
| `EP3` | ElasticPremium | Premium plan (maximum resources) |

## Storage Account Requirements

Azure Functions requires a Storage Account for:

- Function code and configuration storage
- Trigger state management (for durable functions)
- Logging and diagnostics

### Storage Account Bicep Definition

```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}
```

### Required Application Settings for Storage

| Setting Name | Description |
|--------------|-------------|
| `AzureWebJobsStorage` | Primary storage connection string |
| `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` | Content storage connection (Consumption/Premium) |
| `WEBSITE_CONTENTSHARE` | File share name for function content |

## Application Settings for Service Bus Connection

### Connection String Approach

```bicep
{
  name: 'ServiceBusConnection'
  value: 'Endpoint=sb://${serviceBusNamespace}.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=${serviceBusKey}'
}
```

### Identity-Based Connection (Recommended)

For managed identity authentication, use the `__fullyQualifiedNamespace` suffix:

```bicep
{
  name: 'ServiceBusConnection__fullyQualifiedNamespace'
  value: '${serviceBusNamespace}.servicebus.windows.net'
}
```

Required RBAC roles for identity-based connections:

| Operation | Required Role |
|-----------|---------------|
| Trigger (receive messages) | Azure Service Bus Data Receiver or Azure Service Bus Data Owner |
| Output binding (send messages) | Azure Service Bus Data Sender |

## Sample Trigger Function Code

### Python V2 Programming Model (Recommended)

```python
import azure.functions as func
import logging

app = func.FunctionApp()

@app.function_name(name="ServiceBusQueueTrigger")
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="myqueue",
    connection="ServiceBusConnection"
)
def servicebus_queue_trigger(msg: func.ServiceBusMessage):
    logging.info('Python ServiceBus Queue trigger processed a message: %s',
                 msg.get_body().decode('utf-8'))

    # Access message properties
    logging.info(f'Message ID: {msg.message_id}')
    logging.info(f'Content Type: {msg.content_type}')
```

### Python with SDK Type Bindings (Advanced)

```python
import azure.functions as func
import azurefunctions.extensions.bindings.servicebus as servicebus
import logging

app = func.FunctionApp()

@app.service_bus_queue_trigger(
    arg_name="receivedmessage",
    queue_name="myqueue",
    connection="ServiceBusConnection"
)
def servicebus_queue_trigger(receivedmessage: servicebus.ServiceBusReceivedMessage):
    logging.info("Python ServiceBus queue trigger processed message.")
    logging.info(f"Message ID: {receivedmessage.message_id}")
    logging.info(f"Body: {receivedmessage.body}")
```

### Python Topic Trigger

```python
import azure.functions as func
import logging

app = func.FunctionApp()

@app.function_name(name="ServiceBusTopicTrigger")
@app.service_bus_topic_trigger(
    arg_name="message",
    topic_name="mytopic",
    subscription_name="mysubscription",
    connection="ServiceBusConnection"
)
def servicebus_topic_trigger(message: func.ServiceBusMessage):
    message_body = message.get_body().decode("utf-8")
    logging.info("Python ServiceBus topic trigger processed message.")
    logging.info(f"Message Body: {message_body}")
```

### C# Isolated Worker Model

```csharp
using System;
using System.Threading.Tasks;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace Company.Function;

public class ServiceBusQueueTrigger
{
    private readonly ILogger<ServiceBusQueueTrigger> _logger;

    public ServiceBusQueueTrigger(ILogger<ServiceBusQueueTrigger> logger)
    {
        _logger = logger;
    }

    [Function(nameof(ServiceBusQueueTrigger))]
    public async Task Run(
        [ServiceBusTrigger("myqueue", Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions)
    {
        _logger.LogInformation("Message ID: {id}", message.MessageId);
        _logger.LogInformation("Message Body: {body}", message.Body);
        _logger.LogInformation("Message Content-Type: {contentType}", message.ContentType);

        // Complete the message
        await messageActions.CompleteMessageAsync(message);
    }
}
```

### C# Topic Trigger

```csharp
using System;
using System.Threading.Tasks;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace Company.Function;

public class ServiceBusTopicTrigger
{
    private readonly ILogger<ServiceBusTopicTrigger> _logger;

    public ServiceBusTopicTrigger(ILogger<ServiceBusTopicTrigger> logger)
    {
        _logger = logger;
    }

    [Function(nameof(ServiceBusTopicTrigger))]
    public async Task Run(
        [ServiceBusTrigger("mytopic", "mysubscription", Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions)
    {
        _logger.LogInformation("Message ID: {id}", message.MessageId);
        _logger.LogInformation("Message Body: {body}", message.Body);

        // Complete the message
        await messageActions.CompleteMessageAsync(message);
    }
}
```

## Complete Bicep Template Example

```bicep
@description('The name of the function app')
param functionAppName string

@description('The location for all resources')
param location string = resourceGroup().location

@description('The Service Bus namespace name')
param serviceBusNamespace string

@description('The Service Bus queue name')
param serviceBusQueueName string

var storageAccountName = 'st${uniqueString(resourceGroup().id)}'
var appServicePlanName = 'asp-${functionAppName}'

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// App Service Plan (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: appServicePlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2025-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    reserved: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
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
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: '${serviceBusNamespace}.servicebus.windows.net'
        }
      ]
    }
  }
}

// Output the Function App managed identity principal ID for RBAC assignment
output functionAppPrincipalId string = functionApp.identity.principalId
output functionAppName string = functionApp.name
```

## Trigger Attribute Properties Reference

| Property | Description | Queue | Topic |
|----------|-------------|-------|-------|
| `QueueName` | Name of the queue to monitor | Yes | No |
| `TopicName` | Name of the topic to monitor | No | Yes |
| `SubscriptionName` | Name of the subscription | No | Yes |
| `Connection` | App setting name for Service Bus connection | Yes | Yes |
| `IsBatched` | Enable batch message processing | Yes | Yes |
| `IsSessionsEnabled` | Enable session-aware processing | Yes | Yes |
| `AutoCompleteMessages` | Auto-complete messages on success | Yes | Yes |

## Requirements Summary

### Python Projects

Add to `requirements.txt`:

```text
azure-functions
azurefunctions-extensions-bindings-servicebus  # For SDK type bindings
```

### C# Projects

Add NuGet packages:

```xml
<PackageReference Include="Microsoft.Azure.Functions.Worker" Version="1.x" />
<PackageReference Include="Microsoft.Azure.Functions.Worker.Extensions.ServiceBus" Version="5.x" />
```

## Key Findings Summary

1. **Consumption Plan**: Use `Y1` SKU with `Dynamic` tier for serverless execution
2. **Storage Account**: Required for function runtime; use `Standard_LRS` minimum
3. **Identity-Based Auth**: Recommended over connection strings; requires `Azure Service Bus Data Receiver` role
4. **Python V2 Model**: Use decorators like `@app.service_bus_queue_trigger()` for cleaner code
5. **C# Isolated Model**: Recommended over in-process; use `ServiceBusReceivedMessage` type for full message access
6. **Message Settlement**: Disable `AutoCompleteMessages` when handling settlement in code
