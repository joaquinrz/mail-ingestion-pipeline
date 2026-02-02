---
title: Service Bus Bicep Research
description: Research findings for Azure Service Bus Bicep templates including namespace, queues, and authorization rules configuration
author: copilot
ms.date: 2026-02-02
ms.topic: reference
---

## Overview

This document contains research findings for implementing Azure Service Bus infrastructure using Bicep templates for an email message ingestion pipeline.

## Resource Types and API Versions

| Resource Type | Latest API Version | Purpose |
|--------------|-------------------|---------|
| `Microsoft.ServiceBus/namespaces` | `2025-05-01-preview` | Service Bus Namespace |
| `Microsoft.ServiceBus/namespaces/queues` | `2025-05-01-preview` | Queue within namespace |
| `Microsoft.ServiceBus/namespaces/AuthorizationRules` | `2025-05-01-preview` | Namespace-level auth rules |
| `Microsoft.ServiceBus/namespaces/queues/authorizationRules` | `2022-01-01-preview` | Queue-level auth rules |

> **Note:** For production, use the stable API version `2022-01-01-preview` or `2022-10-01-preview` instead of preview versions.

## Service Bus Namespace Configuration

### Standard Tier Template (Recommended for Queues)

```bicep
@description('Name of the Service Bus namespace')
param serviceBusNamespaceName string

@description('Location for all resources.')
param location string = resourceGroup().location

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-01-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}
```

### SKU Options

| SKU | Tier | Features | Use Case |
|-----|------|----------|----------|
| `Basic` | Basic | Basic messaging, no topics | Development/testing |
| `Standard` | Standard | Queues, topics, 256 KB messages | Production workloads |
| `Premium` | Premium | Dedicated resources, larger messages, VNet | Enterprise/high-throughput |

## Queue Configuration for Email Messages

### Recommended Queue Settings

```bicep
@description('Name of the Queue')
param serviceBusQueueName string = 'email-messages'

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-01-01-preview' = {
  parent: serviceBusNamespace
  name: serviceBusQueueName
  properties: {
    // Lock duration for peek-lock (max 5 minutes)
    lockDuration: 'PT5M'
    
    // Queue size (1024 MB = 1 GB for Standard tier)
    maxSizeInMegabytes: 1024
    
    // Message TTL - 14 days for email processing
    defaultMessageTimeToLive: 'P14D'
    
    // Dead-letter on expiration
    deadLetteringOnMessageExpiration: true
    
    // Max delivery attempts before dead-lettering
    maxDeliveryCount: 10
    
    // Duplicate detection (10 minute window)
    requiresDuplicateDetection: false
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    
    // Sessions not required for basic email processing
    requiresSession: false
    
    // Performance optimizations
    enableBatchedOperations: true
    enablePartitioning: false
    enableExpress: false
    
    // Auto-delete disabled (keep queue)
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
  }
}
```

### Queue Properties Reference

| Property | Recommended Value | Description |
|----------|------------------|-------------|
| `lockDuration` | `PT5M` (5 minutes) | Time message is locked for processing. Max is 5 minutes. |
| `maxDeliveryCount` | `10` | Delivery attempts before dead-lettering |
| `defaultMessageTimeToLive` | `P14D` (14 days) | How long messages live in queue |
| `deadLetteringOnMessageExpiration` | `true` | Move expired messages to DLQ |
| `maxSizeInMegabytes` | `1024` | Queue storage size (1-80 GB for Standard) |
| `enableBatchedOperations` | `true` | Improves throughput |
| `requiresDuplicateDetection` | `false` | Enable if duplicate emails are a concern |
| `requiresSession` | `false` | Enable for ordered processing per session |

### ISO 8601 Duration Format Reference

| Format | Duration |
|--------|----------|
| `PT1M` | 1 minute |
| `PT5M` | 5 minutes |
| `PT30S` | 30 seconds |
| `P1D` | 1 day |
| `P7D` | 7 days |
| `P14D` | 14 days |

## Dead-Letter Queue Configuration

Dead-letter queues (DLQ) are automatically created as sub-queues. Access via path: `{queueName}/$deadletterqueue`

### Enable Dead-Letter Queue

```bicep
resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-01-01-preview' = {
  parent: serviceBusNamespace
  name: serviceBusQueueName
  properties: {
    // Enable dead-lettering when messages expire
    deadLetteringOnMessageExpiration: true
    
    // Number of delivery attempts before dead-lettering
    maxDeliveryCount: 10
    
    // Forward dead-lettered messages to another queue (optional)
    forwardDeadLetteredMessagesTo: 'dlq-processor-queue'
  }
}
```

### Dead-Letter Scenarios

Messages are dead-lettered when:

- Message expires (`deadLetteringOnMessageExpiration: true`)
- Max delivery count exceeded
- Message explicitly dead-lettered by receiver
- Message size exceeds queue limit

## Authorization Rules

### Namespace-Level Authorization Rule

```bicep
resource sendListenRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-01-01-preview' = {
  parent: serviceBusNamespace
  name: 'SendListenPolicy'
  properties: {
    rights: [
      'Send'
      'Listen'
    ]
  }
}

resource sendOnlyRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-01-01-preview' = {
  parent: serviceBusNamespace
  name: 'SendOnlyPolicy'
  properties: {
    rights: [
      'Send'
    ]
  }
}

resource listenOnlyRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-01-01-preview' = {
  parent: serviceBusNamespace
  name: 'ListenOnlyPolicy'
  properties: {
    rights: [
      'Listen'
    ]
  }
}
```

### Available Rights

| Right | Description |
|-------|-------------|
| `Send` | Send messages to queues/topics |
| `Listen` | Receive messages from queues/subscriptions |
| `Manage` | Full control (includes Send and Listen) |

### Queue-Level Authorization Rule

```bicep
resource queueSendRule 'Microsoft.ServiceBus/namespaces/queues/authorizationRules@2022-01-01-preview' = {
  parent: serviceBusQueue
  name: 'QueueSendPolicy'
  properties: {
    rights: [
      'Send'
    ]
  }
}
```

## Connection String Retrieval Pattern

### Using listKeys Function

```bicep
// Output primary connection string
output serviceBusConnectionString string = listKeys(
  '${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey',
  serviceBusNamespace.apiVersion
).primaryConnectionString

// Output for custom authorization rule
output sendListenConnectionString string = listKeys(
  sendListenRule.id,
  sendListenRule.apiVersion
).primaryConnectionString
```

### Secure Output Pattern (Recommended)

```bicep
// Store connection string in Key Vault instead of outputting directly
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

resource serviceBusConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'ServiceBusConnectionString'
  properties: {
    value: listKeys(
      '${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey',
      serviceBusNamespace.apiVersion
    ).primaryConnectionString
  }
}
```

## Complete Template Example

```bicep
@description('Name of the Service Bus namespace')
param serviceBusNamespaceName string

@description('Name of the Queue')
param serviceBusQueueName string = 'email-messages'

@description('Location for all resources.')
param location string = resourceGroup().location

// Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-01-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
  }
}

// Email Messages Queue
resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-01-01-preview' = {
  parent: serviceBusNamespace
  name: serviceBusQueueName
  properties: {
    lockDuration: 'PT5M'
    maxSizeInMegabytes: 1024
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
    enableBatchedOperations: true
  }
}

// Send-only policy for producers
resource sendPolicy 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-01-01-preview' = {
  parent: serviceBusNamespace
  name: 'EmailProducerPolicy'
  properties: {
    rights: ['Send']
  }
}

// Listen-only policy for consumers
resource listenPolicy 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-01-01-preview' = {
  parent: serviceBusNamespace
  name: 'EmailConsumerPolicy'
  properties: {
    rights: ['Listen']
  }
}

// Outputs
output namespaceId string = serviceBusNamespace.id
output queueName string = serviceBusQueue.name
output sendPolicyId string = sendPolicy.id
output listenPolicyId string = listenPolicy.id
```

## Key Findings Summary

### Resource Types

- **Namespace:** `Microsoft.ServiceBus/namespaces@2022-01-01-preview`
- **Queue:** `Microsoft.ServiceBus/namespaces/queues@2022-01-01-preview`
- **Auth Rules:** `Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-01-01-preview`

### Recommended Email Queue Settings

| Setting | Value | Rationale |
|---------|-------|-----------|
| SKU | Standard | Supports queues with good performance |
| Lock Duration | 5 minutes | Allows time for email processing |
| Max Delivery Count | 10 | Sufficient retries before dead-lettering |
| TTL | 14 days | Allows time for processing backlogs |
| Dead-letter on expiration | true | Preserves failed messages for analysis |
| Batched operations | true | Improves throughput |

### Connection String Pattern

Use `listKeys()` function to retrieve connection strings at deployment time. Store in Key Vault for secure access by applications.

### Dead-Letter Queue

Automatically created as sub-queue. Access path: `{queueName}/$deadletterqueue`. Enable `deadLetteringOnMessageExpiration` to capture expired messages.

## References

- [Microsoft.ServiceBus/namespaces](https://learn.microsoft.com/en-us/azure/templates/microsoft.servicebus/namespaces)
- [Microsoft.ServiceBus/namespaces/queues](https://learn.microsoft.com/en-us/azure/templates/microsoft.servicebus/namespaces/queues)
- [Microsoft.ServiceBus/namespaces/AuthorizationRules](https://learn.microsoft.com/en-us/azure/templates/microsoft.servicebus/namespaces/authorizationrules)
- [Azure Quickstart Templates - Service Bus Queue](https://github.com/Azure/azure-quickstart-templates/tree/main/quickstarts/microsoft.servicebus/servicebus-create-queue)
- [Azure Quickstart Templates - Service Bus Auth Rules](https://github.com/Azure/azure-quickstart-templates/tree/main/quickstarts/microsoft.servicebus/servicebus-create-authrule-namespace-and-queue)
