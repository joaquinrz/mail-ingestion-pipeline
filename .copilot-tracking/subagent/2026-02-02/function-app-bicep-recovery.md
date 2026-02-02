# Function App Bicep Module Recovery

**Date:** 2026-02-02  
**Source:** `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md`  
**Status:** Recovered

## Original function-app.bicep Content

The following content was extracted from section 2.6 of the research document:

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

## Resources Defined

| Resource | Type | API Version | Purpose |
|----------|------|-------------|---------|
| `appServicePlan` | `Microsoft.Web/serverfarms` | 2023-01-01 | Consumption-tier hosting plan for the Function App |
| `functionApp` | `Microsoft.Web/sites` | 2023-01-01 | Linux Python Function App for processing Service Bus messages |
| `appInsights` | `Microsoft.Insights/components` | 2020-02-02 | Application Insights for monitoring and telemetry |

## Parameters

| Parameter | Type | Secure | Description |
|-----------|------|--------|-------------|
| `name` | string | No | Function App name (used as base for related resource names) |
| `location` | string | No | Azure region for deployment |
| `storageAccountName` | string | No | Storage account name for Function App backing storage |
| `storageAccountKey` | string | Yes | Storage account access key |
| `serviceBusConnectionString` | string | Yes | Connection string for Service Bus namespace |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `name` | string | Deployed Function App name |
| `defaultHostName` | string | Default hostname for the Function App (e.g., `func-xxx.azurewebsites.net`) |
| `appInsightsName` | string | Application Insights resource name |

## Dependencies

### Implicit Dependencies

- **appInsights → functionApp**: The Function App references `appInsights.properties.ConnectionString` in its app settings, creating an implicit dependency ensuring Application Insights deploys first.

### External Dependencies (from main.bicep)

The module receives these values from parent deployments:

| Parameter | Source Module | Output Used |
|-----------|---------------|-------------|
| `storageAccountName` | `storage` | `storage.outputs.name` |
| `storageAccountKey` | `storage` | `storage.outputs.key` |
| `serviceBusConnectionString` | `serviceBus` | `serviceBus.outputs.connectionString` |

## App Settings Configured

| Setting | Value | Purpose |
|---------|-------|---------|
| `AzureWebJobsStorage` | Storage connection string | Required for Functions runtime |
| `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` | Storage connection string | File share for function code |
| `WEBSITE_CONTENTSHARE` | `toLower(name)` | File share name |
| `FUNCTIONS_EXTENSION_VERSION` | `~4` | Azure Functions v4 runtime |
| `FUNCTIONS_WORKER_RUNTIME` | `python` | Python worker |
| `ServiceBusConnection` | Service Bus connection string | Used by Service Bus trigger binding |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | App Insights connection string | Telemetry collection |

## Key Configuration Details

### App Service Plan

- **SKU**: Y1 (Consumption/Dynamic tier)
- **Reserved**: `true` (required for Linux hosting)

### Function App

- **Kind**: `functionapp,linux`
- **Runtime**: Python 3.11
- **HTTPS Only**: Enabled
- **Platform**: Linux

### Application Insights

- **Type**: Web application
- **Request Source**: REST

## Usage in main.bicep

```bicep
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
```
