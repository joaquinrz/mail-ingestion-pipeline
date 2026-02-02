<!-- markdownlint-disable-file -->
# Implementation Details: C# Migration with Key Vault Integration

## Context Reference

Sources: [2026-02-02-csharp-keyvault-migration-research.md](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md)

## Implementation Phase 1: Key Vault Bicep Module

<!-- parallelizable: true -->

### Step 1.1: Create Key Vault module with RBAC authorization

Create a new Key Vault Bicep module at `infra/modules/key-vault.bicep` with RBAC authorization enabled, soft delete protection, and Azure services bypass.

Files:

* `infra/modules/key-vault.bicep` - New file

```bicep
@description('Key Vault name.')
param name string

@description('Azure region.')
param location string

@description('Tenant ID for Key Vault.')
param tenantId string = tenant().tenantId

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
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

Success criteria:

* Key Vault module created with RBAC authorization enabled
* Soft delete and purge protection configured
* Azure services bypass enabled

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 472-495) - Key Vault Bicep template

Dependencies:

* None (first step)

### Step 1.2: Add secrets storage resources for Service Bus and Storage connections

Add secret resources to the Key Vault module for storing Service Bus and Storage connection strings securely.

Files:

* `infra/modules/key-vault.bicep` - Modify to add secret parameters and resources

Add parameters for connection strings:

```bicep
@description('Service Bus connection string to store.')
@secure()
param serviceBusConnectionString string = ''

@description('Storage connection string to store.')
@secure()
param storageConnectionString string = ''
```

Add conditional secret resources:

```bicep
resource serviceBusConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = if (!empty(serviceBusConnectionString)) {
  parent: keyVault
  name: 'ServiceBusConnectionString'
  properties: {
    value: serviceBusConnectionString
  }
}

resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = if (!empty(storageConnectionString)) {
  parent: keyVault
  name: 'StorageConnectionString'
  properties: {
    value: storageConnectionString
  }
}
```

Success criteria:

* Secret resources created conditionally when connection strings provided
* Secrets named consistently for Key Vault reference syntax

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 497-515) - Storing secrets in Key Vault

Dependencies:

* Step 1.1 completion

## Implementation Phase 2: Function App Bicep Recovery

<!-- parallelizable: true -->

### Step 2.1: Recover function-app.bicep with C# isolated worker configuration

Recover the empty `infra/modules/function-app.bicep` with C# isolated worker model configuration, replacing the Python runtime settings.

Files:

* `infra/modules/function-app.bicep` - Recover with C# configuration

```bicep
@description('Function App name.')
param name string

@description('Azure region.')
param location string

@description('Storage account name for Function App.')
param storageAccountName string

@description('Key Vault URI for secret references.')
param keyVaultUri string

// Consumption App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
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

// Function App with managed identity
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|8.0'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/StorageConnectionString/)'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/StorageConnectionString/)'
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
          value: 'dotnet-isolated'
        }
        {
          name: 'WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED'
          value: '1'
        }
        {
          name: 'ServiceBusConnection'
          value: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/ServiceBusConnectionString/)'
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
output principalId string = functionApp.identity.principalId
output appInsightsName string = appInsights.name
```

Success criteria:

* Function App uses `dotnet-isolated` runtime
* `linuxFxVersion` set to `DOTNET-ISOLATED|8.0`
* System-assigned managed identity enabled
* Key Vault references used for secrets

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 260-290) - Bicep changes for C# runtime
* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 545-580) - Function App with Key Vault references

Dependencies:

* None (parallelizable with Phase 1)

### Step 2.2: Add managed identity and Key Vault reference app settings

The managed identity and Key Vault reference configuration is included in Step 2.1. This step validates the configuration is correct.

Files:

* `infra/modules/function-app.bicep` - Verify configuration

Success criteria:

* `identity.type` set to `SystemAssigned`
* `principalId` output exposed for RBAC assignment
* All sensitive app settings use `@Microsoft.KeyVault()` syntax
* Secret URIs omit version for automatic rotation

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 463-470) - Key Vault reference syntax

Dependencies:

* Step 2.1 completion

## Implementation Phase 3: Main Bicep Recovery with Key Vault Orchestration

<!-- parallelizable: false -->

### Step 3.1: Recover main.bicep with Key Vault module integration

Recover the empty `infra/main.bicep` with Key Vault module integration. Deploy Key Vault first, then storage, service bus, and finally the function app.

Files:

* `infra/main.bicep` - Recover with Key Vault orchestration

```bicep
// Main orchestration for Email Ingestion Pipeline with Key Vault Integration
targetScope = 'resourceGroup'

@description('Environment name.')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for resources.')
param location string = resourceGroup().location

@description('Base name for resources.')
param baseName string = 'emailpipeline'

// Generate unique suffix for globally unique names
var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${baseName}${environment}'

// Key Vault (deployed first to store secrets)
module keyVault 'modules/key-vault.bicep' = {
  name: 'keyvault-deployment'
  params: {
    name: 'kv-${resourcePrefix}-${uniqueSuffix}'
    location: location
  }
}

// Storage Account
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

// Key Vault Secrets (after storage and service bus are created)
module keyVaultSecrets 'modules/key-vault.bicep' = {
  name: 'keyvault-secrets-deployment'
  params: {
    name: keyVault.outputs.keyVaultName
    location: location
    serviceBusConnectionString: serviceBus.outputs.connectionString
    storageConnectionString: storage.outputs.connectionString
  }
}

// Logic App with Office 365 connection
module logicApp 'modules/logic-app.bicep' = {
  name: 'logicapp-deployment'
  params: {
    name: 'logic-${resourcePrefix}-${uniqueSuffix}'
    location: location
    serviceBusConnectionString: serviceBus.outputs.sendConnectionString
    serviceBusQueueName: 'email-messages'
  }
}

// Function App for message processing (depends on Key Vault secrets)
module functionApp 'modules/function-app.bicep' = {
  name: 'functionapp-deployment'
  dependsOn: [keyVaultSecrets]
  params: {
    name: 'func-${resourcePrefix}-${uniqueSuffix}'
    location: location
    storageAccountName: storage.outputs.name
    keyVaultUri: keyVault.outputs.keyVaultUri
  }
}
```

Success criteria:

* Key Vault deployed before other resources
* Secrets stored in Key Vault after storage and service bus creation
* Function App depends on Key Vault secrets deployment
* No sensitive values passed directly to function app module

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 105-160) - Original main.bicep structure
* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 660-675) - Deployment order with Key Vault

Dependencies:

* Phase 1 completion (Key Vault module exists)
* Phase 2 completion (function-app module updated)

### Step 3.2: Add RBAC role assignment for Function App managed identity

Add RBAC role assignment in main.bicep to grant the Function App managed identity access to Key Vault secrets.

Files:

* `infra/main.bicep` - Add after functionApp module

```bicep
// Key Vault Secrets User role definition ID
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// Grant Function App access to Key Vault secrets
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.outputs.keyVaultId, functionApp.outputs.principalId, keyVaultSecretsUserRoleId)
  scope: resourceGroup()
  properties: {
    principalId: functionApp.outputs.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}
```

Note: The role assignment scope needs to target the Key Vault resource. Update to use existing resource reference:

```bicep
resource existingKeyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVault.outputs.keyVaultName
}

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingKeyVault.id, functionApp.outputs.principalId, keyVaultSecretsUserRoleId)
  scope: existingKeyVault
  properties: {
    principalId: functionApp.outputs.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}
```

Success criteria:

* RBAC role assignment created for Function App managed identity
* Role scoped to Key Vault resource
* `Key Vault Secrets User` role assigned

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 517-535) - RBAC role assignment in Bicep

Dependencies:

* Step 3.1 completion

### Step 3.3: Update outputs to remove secret exposure

Update main.bicep outputs to expose only non-sensitive information.

Files:

* `infra/main.bicep` - Add outputs section

```bicep
// Outputs (no secrets exposed)
output resourceGroupName string = resourceGroup().name
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output logicAppName string = logicApp.outputs.name
output functionAppName string = functionApp.outputs.name
output functionAppHostName string = functionApp.outputs.defaultHostName
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output serviceBusQueueName string = 'email-messages'
output storageAccountName string = storage.outputs.name
```

Success criteria:

* No connection strings or keys in outputs
* Key Vault name and URI available for reference
* Resource names output for operational use

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 640-660) - Security considerations

Dependencies:

* Step 3.1 completion

## Implementation Phase 4: C# Function Project

<!-- parallelizable: false -->

### Step 4.1: Create C# project structure with EmailProcessor.csproj

Create the C# project file with required NuGet packages for .NET 8 isolated worker model.

Files:

* `src/functions/EmailProcessor/EmailProcessor.csproj` - New file

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

Success criteria:

* Project targets .NET 8 with isolated worker model
* Required NuGet packages included
* host.json and local.settings.json configured for copy

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 295-330) - C# project file

Dependencies:

* None (starts Phase 4)

### Step 4.2: Implement Program.cs with host configuration

Create the host configuration file with Application Insights integration.

Files:

* `src/functions/EmailProcessor/Program.cs` - New file

```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

var builder = FunctionsApplication.CreateBuilder(args);

// Configure Application Insights telemetry
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

Success criteria:

* Application Insights configured
* Default log filter removed for full logging
* Minimal startup configuration

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 332-360) - Program.cs template

Dependencies:

* Step 4.1 completion

### Step 4.3: Create EmailProcessorFunction.cs with Service Bus trigger

Create the main function class with Service Bus queue trigger.

Files:

* `src/functions/EmailProcessor/Functions/EmailProcessorFunction.cs` - New file

```csharp
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using EmailProcessor.Models;

namespace EmailProcessor.Functions;

/// <summary>
/// Processes email messages from Service Bus queue.
/// </summary>
public sealed class EmailProcessorFunction(ILogger<EmailProcessorFunction> logger)
{
    /// <summary>
    /// Processes incoming email messages from the Service Bus queue.
    /// </summary>
    /// <param name="message">The Service Bus message containing email data.</param>
    /// <param name="messageActions">Actions for completing or dead-lettering the message.</param>
    /// <param name="cancellationToken">Cancellation token for the operation.</param>
    [Function(nameof(ProcessEmailMessage))]
    public async Task ProcessEmailMessage(
        [ServiceBusTrigger("email-messages", Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        logger.LogInformation("Processing message ID: {MessageId}", message.MessageId);

        try
        {
            var emailData = JsonSerializer.Deserialize<EmailMessage>(message.Body);

            if (emailData is null)
            {
                logger.LogWarning("Failed to deserialize message {MessageId}", message.MessageId);
                await messageActions.DeadLetterMessageAsync(
                    message,
                    deadLetterReason: "InvalidFormat",
                    deadLetterErrorDescription: "Message body could not be deserialized",
                    cancellationToken: cancellationToken);
                return;
            }

            logger.LogInformation("Email received:");
            logger.LogInformation("  Subject: {Subject}", emailData.Subject);
            logger.LogInformation("  From: {From}", emailData.From);
            logger.LogInformation("  Received: {ReceivedDateTime}", emailData.ReceivedDateTime);

            var previewLength = Math.Min(100, emailData.BodyPreview?.Length ?? 0);
            if (previewLength > 0)
            {
                logger.LogInformation("  Preview: {Preview}...", emailData.BodyPreview![..previewLength]);
            }

            await messageActions.CompleteMessageAsync(message, cancellationToken);
            logger.LogInformation("Successfully processed message ID: {MessageId}", message.MessageId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error processing message {MessageId}", message.MessageId);
            throw;
        }
    }
}
```

Success criteria:

* Service Bus trigger configured with correct queue name
* Connection parameter references app setting
* Manual message completion using ServiceBusMessageActions
* Structured logging with message ID

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 362-430) - Function implementation

Dependencies:

* Step 4.2 completion

### Step 4.4: Create EmailMessage.cs model

Create the POCO model for deserializing email messages.

Files:

* `src/functions/EmailProcessor/Models/EmailMessage.cs` - New file

```csharp
namespace EmailProcessor.Models;

/// <summary>
/// Represents an email message received from the Service Bus queue.
/// </summary>
public sealed record EmailMessage
{
    /// <summary>
    /// Gets the email subject line.
    /// </summary>
    public string? Subject { get; init; }

    /// <summary>
    /// Gets the sender email address.
    /// </summary>
    public string? From { get; init; }

    /// <summary>
    /// Gets the date and time the email was received.
    /// </summary>
    public string? ReceivedDateTime { get; init; }

    /// <summary>
    /// Gets a preview of the email body content.
    /// </summary>
    public string? BodyPreview { get; init; }
}
```

Success criteria:

* Record type with nullable properties
* XML documentation on all members
* Matches JSON structure from Logic App

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 422-430) - EmailMessage record

Dependencies:

* Step 4.3 (function references this model)

### Step 4.5: Update host.json for C# isolated worker

Update the existing host.json with C# isolated worker configuration and Service Bus settings.

Files:

* `src/functions/host.json` - Move to `src/functions/EmailProcessor/host.json` and update

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

Success criteria:

* `autoCompleteMessages` set to `false` for manual completion
* Application Insights sampling configured
* Service Bus prefetch and concurrency optimized

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 614-635) - host.json for C#

Dependencies:

* Step 4.1 completion

### Step 4.6: Create local.settings.json for local development

Create the local settings file for development environment.

Files:

* `src/functions/EmailProcessor/local.settings.json` - New file

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "ServiceBusConnection": "<your-servicebus-connection-string>"
  }
}
```

Success criteria:

* Development storage configured
* Runtime set to dotnet-isolated
* Placeholder for Service Bus connection

Context references:

* Azure Functions local development documentation

Dependencies:

* Step 4.1 completion

## Implementation Phase 5: Python Removal

<!-- parallelizable: false -->

### Step 5.1: Remove Python function files

Remove the Python function code and dependencies.

Files to delete:

* `src/functions/function_app.py` - Python function code
* `src/functions/requirements.txt` - Python dependencies
* `src/functions/host.json` - Moved to EmailProcessor project

Success criteria:

* Python function code removed
* Python dependencies file removed
* No Python artifacts remain in src/functions root

Context references:

* [Research file](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) (Lines 593-610) - Files to remove

Dependencies:

* Phase 4 completion (C# project created)

## Implementation Phase 6: Validation

<!-- parallelizable: false -->

### Step 6.1: Run full Bicep validation

Execute all Bicep validation commands for the infrastructure templates.

Validation commands:

* `az bicep build --file infra/main.bicep` - Compile to ARM template
* `az bicep lint --file infra/main.bicep` - Check best practices
* `az bicep build --file infra/modules/key-vault.bicep` - Validate Key Vault module
* `az bicep build --file infra/modules/function-app.bicep` - Validate Function App module

### Step 6.2: Run C# build and test

Execute build commands for the C# project.

Validation commands:

* `dotnet restore src/functions/EmailProcessor/EmailProcessor.csproj` - Restore packages
* `dotnet build src/functions/EmailProcessor/EmailProcessor.csproj` - Build project
* `dotnet format --verify-no-changes src/functions/EmailProcessor/` - Check formatting

### Step 6.3: Fix minor validation issues

Iterate on lint errors, build warnings, and test failures. Apply fixes directly when corrections are straightforward and isolated.

### Step 6.4: Report blocking issues

When validation failures require changes beyond minor fixes:

* Document the issues and affected files
* Provide the user with next steps
* Recommend additional research and planning rather than inline fixes
* Avoid large-scale refactoring within this phase

## Dependencies

* .NET 8 SDK
* Azure CLI with Bicep extension
* Azure subscription (for deployment validation)

## Success Criteria

* All Bicep templates compile without errors
* C# project builds successfully
* No secrets exposed in Bicep outputs
* Managed identity configured for Function App
* Key Vault uses RBAC authorization
* Python code removed from repository
