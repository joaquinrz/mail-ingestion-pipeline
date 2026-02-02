# Main Bicep Recovery: Email Ingestion Pipeline

**Date:** 2026-02-02
**Source:** [2026-02-02-email-ingestion-pipeline-spike-research.md](../../research/2026-02-02-email-ingestion-pipeline-spike-research.md)
**Status:** Recovery Complete

## Executive Summary

The original `main.bicep` template orchestrates four modular deployments for an email ingestion pipeline: Storage, Service Bus, Logic App, and Function App. This document captures the complete template content and dependency structure recovered from the spike research document.

## Recovered main.bicep Content

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

## Module Dependency Graph

```
                    ┌──────────────────┐
                    │   main.bicep     │
                    │  (Orchestrator)  │
                    └────────┬─────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  (no dependencies)
│ storage.bicep   │  │ service-bus.bicep│
│                 │  │                  │
└────────┬────────┘  └────────┬─────────┘
         │                    │
         │   outputs.name     │   outputs.connectionString
         │   outputs.key      │   outputs.namespaceName
         │                    │
         ▼                    ▼
┌──────────────────────────────────────┐
│         function-app.bicep           │
│  (depends on: storage, serviceBus)   │
└──────────────────────────────────────┘
                    │
                    │   outputs.connectionString
                    │   (from serviceBus)
                    │
                    ▼
         ┌─────────────────┐
         │ logic-app.bicep │
         │ (depends on:    │
         │  serviceBus)    │
         └─────────────────┘
```

## Deployment Order

Azure Resource Manager determines the deployment order based on implicit dependencies. The effective order:

| Order | Module | Deployment Name | Dependencies |
|-------|--------|-----------------|--------------|
| 1 | storage.bicep | `storage-deployment` | None |
| 1 | service-bus.bicep | `servicebus-deployment` | None |
| 2 | function-app.bicep | `functionapp-deployment` | storage, serviceBus |
| 2 | logic-app.bicep | `logicapp-deployment` | serviceBus |

**Note:** Modules at the same order level deploy in parallel.

## Parameters Reference

### Input Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `environment` | string | `'dev'` | Environment name (dev, staging, prod) |
| `location` | string | `resourceGroup().location` | Azure region for resources |
| `baseName` | string | `'emailpipeline'` | Base name for resources |

### Variables

| Variable | Formula | Purpose |
|----------|---------|---------|
| `uniqueSuffix` | `uniqueString(resourceGroup().id)` | Globally unique resource names |
| `resourcePrefix` | `'${baseName}${environment}'` | Consistent naming prefix |

## Module Parameters Mapping

### storage.bicep

| Parameter | Value Passed |
|-----------|--------------|
| `name` | `'st${resourcePrefix}${uniqueSuffix}'` |
| `location` | `location` |

**Outputs Used:**
- `storage.outputs.name` → functionApp
- `storage.outputs.key` → functionApp

### service-bus.bicep

| Parameter | Value Passed |
|-----------|--------------|
| `name` | `'sb-${resourcePrefix}-${uniqueSuffix}'` |
| `location` | `location` |
| `queueName` | `'email-messages'` |

**Outputs Used:**
- `serviceBus.outputs.connectionString` → logicApp, functionApp
- `serviceBus.outputs.namespaceName` → main output

### logic-app.bicep

| Parameter | Value Passed |
|-----------|--------------|
| `name` | `'logic-${resourcePrefix}-${uniqueSuffix}'` |
| `location` | `location` |
| `serviceBusConnectionString` | `serviceBus.outputs.connectionString` |
| `serviceBusQueueName` | `'email-messages'` |

**Outputs Used:**
- `logicApp.outputs.name` → main output

### function-app.bicep

| Parameter | Value Passed |
|-----------|--------------|
| `name` | `'func-${resourcePrefix}-${uniqueSuffix}'` |
| `location` | `location` |
| `storageAccountName` | `storage.outputs.name` |
| `storageAccountKey` | `storage.outputs.key` |
| `serviceBusConnectionString` | `serviceBus.outputs.connectionString` |

**Outputs Used:**
- `functionApp.outputs.name` → main output

## Template Outputs

| Output | Type | Value | Purpose |
|--------|------|-------|---------|
| `resourceGroupName` | string | `resourceGroup().name` | Reference to containing resource group |
| `logicAppName` | string | `logicApp.outputs.name` | Logic App resource name for CLI commands |
| `functionAppName` | string | `functionApp.outputs.name` | Function App name for deployment |
| `serviceBusNamespace` | string | `serviceBus.outputs.namespaceName` | Service Bus namespace for monitoring |
| `serviceBusQueueName` | string | `'email-messages'` | Queue name for configuration reference |

## Resource Naming Convention

| Resource Type | Naming Pattern | Example (dev) |
|---------------|----------------|---------------|
| Storage Account | `st${baseName}${env}${unique}` | `stemailpipelinedevabc123` |
| Service Bus | `sb-${baseName}${env}-${unique}` | `sb-emailpipelinedev-abc123` |
| Logic App | `logic-${baseName}${env}-${unique}` | `logic-emailpipelinedev-abc123` |
| Function App | `func-${baseName}${env}-${unique}` | `func-emailpipelinedev-abc123` |

## Recovery Notes

- Current [main.bicep](../../../infra/main.bicep) file is empty
- Content recovered from research document section 2.2
- Template uses modular architecture with four child modules
- All modules exist in [modules/](../../../infra/modules/) directory
