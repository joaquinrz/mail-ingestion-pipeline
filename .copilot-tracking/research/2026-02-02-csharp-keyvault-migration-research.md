<!-- markdownlint-disable-file -->
# Task Research: C# Migration, Key Vault Integration, and Code Recovery

Research for migrating the email ingestion pipeline from Python to C#, integrating Azure Key Vault for secure secret management, and recovering deleted Bicep templates.

## Task Implementation Requests

* Research what code was deleted and needs recovery (main.bicep, function-app.bicep)
* Research how to migrate Azure Function from Python to C# (isolated worker model)
* Research how to integrate Azure Key Vault for secure secret management
* Research how to remove Python from the solution

## Scope and Success Criteria

* Scope: Research-only investigation with no implementation changes
* Assumptions:
  * C# Azure Functions use the isolated worker model (.NET 8)
  * Key Vault uses RBAC authorization (modern approach)
  * Managed identity for secure Key Vault access
  * All secrets stored in Key Vault instead of direct outputs
* Success Criteria:
  * Complete documentation of deleted code recovery
  * Full C# project structure and code patterns documented
  * Key Vault Bicep module template provided
  * Security best practices identified

## Architecture Changes

### Current Architecture (Broken)

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Office 365    │    │    Logic App    │    │   Service Bus   │    │ Azure Function  │
│     Mailbox     │───▶│    (Working)    │───▶│    (Working)    │───▶│    (BROKEN)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
                                                                            │
                                                                     main.bicep: EMPTY
                                                                     function-app.bicep: EMPTY
```

### Target Architecture (With Key Vault)

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Office 365    │    │    Logic App    │    │   Service Bus   │    │ Azure Function  │
│     Mailbox     │───▶│                 │───▶│                 │───▶│     (C#)        │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └────────┬────────┘
                                                      │                       │
                                                      │    Managed Identity   │
                                                      │         RBAC          │
                                                      ▼                       ▼
                                              ┌─────────────────────────────────┐
                                              │         Azure Key Vault         │
                                              │  • ServiceBusConnectionString   │
                                              │  • StorageConnectionString      │
                                              └─────────────────────────────────┘
```

## Research Executed

### File Analysis: Broken Code Identification

**Empty Files Discovered:**

| File Path | Status | Original Purpose |
|-----------|--------|------------------|
| `infra/main.bicep` | **EMPTY** | Main orchestration template |
| `infra/modules/function-app.bicep` | **EMPTY** | Function App resource definitions |

**Intact Files:**

| File Path | Status | Content |
|-----------|--------|---------|
| `infra/modules/storage.bicep` | Working | Storage Account resource |
| `infra/modules/service-bus.bicep` | Working | Service Bus namespace and queue |
| `infra/modules/logic-app.bicep` | Working | Logic App workflow definition |
| `infra/main.bicepparam` | Working | Parameter values |
| `src/functions/function_app.py` | Working | Python function code |

### Recovery Source

The original content was documented in the spike research:
* Source: `.copilot-tracking/research/2026-02-02-email-ingestion-pipeline-spike-research.md`
* Sections 2.2 and 2.6 contain the complete templates

## Key Discoveries

### 1. Deleted Code Recovery

#### main.bicep Recovery

The original main.bicep contained:

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

#### function-app.bicep Recovery

The original function-app.bicep contained:

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

### 2. C# Migration Research

#### In-Process vs Isolated Worker Model

| Aspect | In-Process Model | Isolated Worker Model |
|--------|-----------------|----------------------|
| **Support Status** | **Ends November 10, 2026** | Fully supported (recommended) |
| **Process** | Same process as Functions host | Separate worker process |
| **Assembly Conflicts** | Possible conflicts with host | No conflicts |
| **.NET Versions** | Limited to runtime version | .NET 8, 9, 10 |
| **Dependency Injection** | Limited | Full .NET DI support |
| **Middleware** | Not supported | Supported (ASP.NET Core style) |
| **NuGet Packages** | `Microsoft.Azure.WebJobs.Extensions.*` | `Microsoft.Azure.Functions.Worker.Extensions.*` |

**Recommendation:** Use the isolated worker model for new development.

#### C# Project Structure

```text
src/functions/
├── EmailProcessor/
│   ├── EmailProcessor.csproj          # Project file with NuGet packages
│   ├── Program.cs                     # Host configuration and startup
│   ├── Functions/
│   │   └── EmailProcessorFunction.cs  # Service Bus trigger function
│   ├── Models/
│   │   └── EmailMessage.cs            # POCO for email message data
│   ├── host.json                      # Functions host configuration
│   └── local.settings.json            # Local development settings
```

#### Required NuGet Packages

| Package | Version | Purpose |
|---------|---------|---------|
| `Microsoft.Azure.Functions.Worker` | 2.0.0+ | Core isolated worker runtime |
| `Microsoft.Azure.Functions.Worker.Sdk` | 2.0.5+ | SDK for build tooling |
| `Microsoft.Azure.Functions.Worker.Extensions.ServiceBus` | 5.24.0 | Service Bus trigger/output bindings |
| `Microsoft.Azure.Functions.Worker.ApplicationInsights` | 1.0.0+ | Direct Application Insights integration |

#### C# Project File (EmailProcessor.csproj)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <AzureFunctionsVersion>v4</AzureFunctionsVersion>
    <OutputType>Exe</OutputType>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <RootNamespace>EmailProcessor</RootNamespace>
  </PropertyGroup>
  
  <ItemGroup>
    <FrameworkReference Include="Microsoft.AspNetCore.App" />
    <PackageReference Include="Microsoft.Azure.Functions.Worker" Version="2.0.0" />
    <PackageReference Include="Microsoft.Azure.Functions.Worker.Sdk" Version="2.0.5" />
    <PackageReference Include="Microsoft.Azure.Functions.Worker.Extensions.ServiceBus" Version="5.24.0" />
    <PackageReference Include="Microsoft.Azure.Functions.Worker.ApplicationInsights" Version="1.0.0" />
    <PackageReference Include="Microsoft.ApplicationInsights.WorkerService" Version="2.22.0" />
  </ItemGroup>
  
  <ItemGroup>
    <None Update="host.json">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
    <None Update="local.settings.json">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
      <CopyToPublishDirectory>Never</CopyToPublishDirectory>
    </None>
  </ItemGroup>
</Project>
```

#### Program.cs (Host Configuration)

```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var builder = FunctionsApplication.CreateBuilder(args);

// Configure Application Insights
builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

// Remove default Application Insights log filter to capture all levels
builder.Logging.Services.Configure<LoggerFilterOptions>(options =>
{
    LoggerFilterRule? defaultRule = options.Rules.FirstOrDefault(rule =>
        rule.ProviderName == "Microsoft.Extensions.Logging.ApplicationInsights.ApplicationInsightsLoggerProvider");
    
    if (defaultRule is not null)
    {
        options.Rules.Remove(defaultRule);
    }
});

builder.Build().Run();
```

#### EmailProcessorFunction.cs (Service Bus Trigger)

```csharp
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;

namespace EmailProcessor.Functions;

public sealed class EmailProcessorFunction
{
    private readonly ILogger<EmailProcessorFunction> _logger;

    public EmailProcessorFunction(ILogger<EmailProcessorFunction> logger)
    {
        _logger = logger;
    }

    [Function(nameof(ProcessEmailMessage))]
    public async Task ProcessEmailMessage(
        [ServiceBusTrigger("email-messages", Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Processing message ID: {MessageId}", message.MessageId);
        
        try
        {
            var emailData = JsonSerializer.Deserialize<EmailMessage>(message.Body);
            
            if (emailData is null)
            {
                _logger.LogWarning("Failed to deserialize message {MessageId}", message.MessageId);
                await messageActions.DeadLetterMessageAsync(
                    message,
                    deadLetterReason: "InvalidFormat",
                    deadLetterErrorDescription: "Message body could not be deserialized",
                    cancellationToken: cancellationToken);
                return;
            }

            _logger.LogInformation("Email received:");
            _logger.LogInformation("  Subject: {Subject}", emailData.Subject);
            _logger.LogInformation("  From: {From}", emailData.From);
            _logger.LogInformation("  Received: {ReceivedDateTime}", emailData.ReceivedDateTime);
            _logger.LogInformation("  Preview: {Preview}...", emailData.BodyPreview?[..Math.Min(100, emailData.BodyPreview.Length)]);

            await messageActions.CompleteMessageAsync(message, cancellationToken);
            _logger.LogInformation("Successfully processed message ID: {MessageId}", message.MessageId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing message {MessageId}", message.MessageId);
            throw;
        }
    }
}

public sealed record EmailMessage
{
    public string? Subject { get; init; }
    public string? From { get; init; }
    public string? ReceivedDateTime { get; init; }
    public string? BodyPreview { get; init; }
}
```

#### Bicep Changes for C# Runtime

| Setting | Python Value | C# Isolated Value |
|---------|-------------|-------------------|
| `FUNCTIONS_WORKER_RUNTIME` | `python` | `dotnet-isolated` |
| `linuxFxVersion` | `PYTHON\|3.11` | `DOTNET-ISOLATED\|8.0` |
| `WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED` | N/A | `1` (performance optimization) |

### 3. Key Vault Integration Research

#### Authorization Model Comparison

| Aspect | Access Policies (Legacy) | Azure RBAC (Recommended) |
|--------|-------------------------|--------------------------|
| Granularity | Vault-level only | Vault, secret, key, or certificate level |
| Management | Stored in Key Vault properties | Managed via Azure IAM |
| Limit | Max 1024 policies per vault | No practical limit |
| Best Practice | Legacy support only | Recommended for new deployments |
| Bicep Setting | `enableRbacAuthorization: false` | `enableRbacAuthorization: true` |

**Recommendation:** Use Azure RBAC with `enableRbacAuthorization: true`.

#### Key Vault RBAC Roles

| Role | Purpose | Role Definition ID |
|------|---------|-------------------|
| Key Vault Administrator | Full access to all data operations | `00482a5a-887f-4fb3-b363-3b7fe8e74483` |
| Key Vault Secrets User | Read secret contents | `4633458b-17de-408a-b874-0445c86b69e6` |
| Key Vault Secrets Officer | Full secrets management | `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` |
| Key Vault Reader | Read metadata only | `21090545-7ca7-4776-b22c-e363652d74d2` |

**Recommendation:** Assign "Key Vault Secrets User" role to the Function App managed identity.

#### Key Vault Reference Syntax

App settings can reference Key Vault secrets using:

```text
@Microsoft.KeyVault(SecretUri=https://myvault.vault.azure.net/secrets/mysecret/)
```

**Important:** Omit the version to enable automatic rotation (secrets refresh every 24 hours).

Alternative format:
```text
@Microsoft.KeyVault(VaultName=myvault;SecretName=mysecret)
```

#### Key Vault Bicep Module Template

```bicep
@description('Key Vault name.')
param name string

@description('Azure region.')
param location string

@description('Tenant ID for Key Vault.')
param tenantId string = tenant().tenantId

resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: name
  location: location
  properties: {
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enabledForTemplateDeployment: true
    sku: {
      family: 'A'
      name: 'standard'
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
```

#### Storing Secrets in Key Vault

```bicep
resource serviceBusConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'ServiceBusConnectionString'
  properties: {
    value: listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
  }
}

resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'StorageConnectionString'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
  }
}
```

#### RBAC Role Assignment in Bicep

```bicep
@description('Key Vault Secrets User role definition ID.')
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}
```

#### Function App with Key Vault References

```bicep
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      appSettings: [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'ServiceBusConnection'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/ServiceBusConnectionString/)'
        }
        {
          name: 'AzureWebJobsStorage'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/StorageConnectionString/)'
        }
      ]
    }
  }
}
```

### 4. Python Removal Research

#### Files to Remove

| Path | Purpose | Replacement |
|------|---------|-------------|
| `src/functions/function_app.py` | Python function code | C# EmailProcessor project |
| `src/functions/requirements.txt` | Python dependencies | NuGet packages in .csproj |

#### Files to Keep (Format-Agnostic)

| Path | Purpose | Changes Needed |
|------|---------|----------------|
| `src/functions/host.json` | Function host configuration | Minor updates for C# settings |

#### host.json Updates for C#

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
  "extensions": {
    "serviceBus": {
      "prefetchCount": 100,
      "autoCompleteMessages": false,
      "maxAutoLockRenewalDuration": "00:05:00",
      "maxConcurrentCalls": 16
    }
  }
}
```

**Key Change:** Set `autoCompleteMessages: false` when using `ServiceBusMessageActions` for manual message settlement in C#.

## Security Considerations

### Current Security Issues

| Issue | Location | Risk |
|-------|----------|------|
| Connection strings in outputs | `service-bus.bicep` | Secrets exposed in deployment outputs |
| Storage key passed as parameter | `function-app.bicep` | Secret passed between modules |
| No managed identity | `function-app.bicep` | Connection strings stored in app settings |

### Recommended Security Improvements

1. **Remove secret outputs** from service-bus.bicep and storage.bicep
2. **Store all secrets in Key Vault** during deployment
3. **Use managed identity** for Function App
4. **Use Key Vault references** in app settings instead of direct values
5. **Use RBAC** instead of access policies for Key Vault

## Deployment Order with Key Vault

```text
1. Key Vault
2. Storage Account
3. Service Bus Namespace
4. Key Vault Secrets (ServiceBusConnectionString, StorageConnectionString)
5. Function App (with managed identity)
6. RBAC Role Assignment (Key Vault Secrets User → Function App)
```

## Technical Scenarios

### Scenario: C# Function App with Key Vault Integration

**Requirements:**

* .NET 8 isolated worker model
* Service Bus queue trigger
* Secrets stored in Key Vault
* Managed identity for secure access

**Preferred Approach:**

* Use `Microsoft.Azure.Functions.Worker.Extensions.ServiceBus` for triggers
* System-assigned managed identity on Function App
* Key Vault RBAC with "Secrets User" role
* `@Microsoft.KeyVault()` reference syntax in app settings

```text
EmailProcessor/
├── EmailProcessor.csproj
├── Program.cs
├── Functions/
│   └── EmailProcessorFunction.cs
├── Models/
│   └── EmailMessage.cs
├── host.json
└── local.settings.json
```

**Implementation Details:**

| Component | Technology | Notes |
|-----------|------------|-------|
| Runtime | .NET 8 isolated worker | Support through 2026+ |
| Trigger | ServiceBusTrigger attribute | `Connection` parameter references app setting |
| DI | Built-in .NET DI | Constructor injection |
| Logging | ILogger<T> | Application Insights integration |
| Message handling | ServiceBusMessageActions | Manual complete/dead-letter |

#### Considered Alternatives

* **In-process model:** Rejected due to end-of-support in November 2026
* **Access policies:** Rejected in favor of RBAC for better granularity
* **User-assigned identity:** System-assigned is simpler for single-app scenarios

## Potential Next Research

* Deployment pipeline (GitHub Actions or Azure DevOps) for C# Function App
  * Reasoning: Automate build and deployment of new C# project
  * Reference: Azure Functions deployment documentation

* Dead-letter queue handling and monitoring
  * Reasoning: Production readiness requires error handling strategy
  * Reference: Service Bus dead-letter queue patterns

* Application Insights integration and alerting
  * Reasoning: Observability for production deployment
  * Reference: Azure Monitor for Functions documentation

## Subagent Research Files

| Research Area | File |
|---------------|------|
| C# Azure Function patterns | `.copilot-tracking/subagent/2026-02-02/csharp-azure-function-research.md` |
| Key Vault integration | `.copilot-tracking/subagent/2026-02-02/keyvault-integration-research.md` |
| function-app.bicep recovery | `.copilot-tracking/subagent/2026-02-02/function-app-bicep-recovery.md` |
| main.bicep recovery | `.copilot-tracking/subagent/2026-02-02/main-bicep-recovery.md` |
