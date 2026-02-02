---
title: C# Azure Function Service Bus Trigger Research
description: Research findings for implementing Azure Functions v4 isolated worker model with Service Bus triggers in C#
author: copilot
ms.date: 2026-02-02
ms.topic: reference
---

## Overview

This document contains research findings for implementing an Azure Function in C# using the isolated worker model with Azure Service Bus queue triggers. The isolated worker model is recommended for new .NET Azure Functions development, as the in-process model support ends November 10, 2026.

## Project Structure

### Files Required for C# Isolated Worker Azure Function

```text
EmailProcessor/
├── EmailProcessor.csproj          # Project file with NuGet packages
├── Program.cs                     # Host configuration and startup
├── Functions/
│   └── EmailProcessorFunction.cs  # Service Bus trigger function
├── Models/
│   └── EmailMessage.cs            # POCO for email message data
├── host.json                      # Functions host configuration
├── local.settings.json            # Local development settings
└── .gitignore                     # Exclude local.settings.json
```

### Comparison: Python vs C# Structure

| Python Structure | C# Isolated Worker Structure |
|-----------------|------------------------------|
| `function_app.py` | `Program.cs` + `Functions/*.cs` |
| `requirements.txt` | `*.csproj` (NuGet packages) |
| `host.json` | `host.json` (identical format) |
| `local.settings.json` | `local.settings.json` (identical format) |

## NuGet Package References

### Core Packages (Required)

| Package | Version | Purpose |
|---------|---------|---------|
| `Microsoft.Azure.Functions.Worker` | 2.0.0+ | Core isolated worker runtime |
| `Microsoft.Azure.Functions.Worker.Sdk` | 2.0.0+ | SDK for build tooling |
| `Microsoft.Azure.Functions.Worker.Extensions.ServiceBus` | 5.24.0 | Service Bus trigger/output bindings |

### Recommended Packages

| Package | Version | Purpose |
|---------|---------|---------|
| `Microsoft.Azure.Functions.Worker.ApplicationInsights` | 1.0.0+ | Direct Application Insights integration |
| `Microsoft.ApplicationInsights.WorkerService` | 2.22.0+ | Worker telemetry support |
| `Microsoft.Extensions.Azure` | 1.7.0+ | Azure SDK dependency injection |
| `Azure.Messaging.ServiceBus` | 7.17.0+ | SDK types for advanced scenarios |

### Complete .csproj File

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

## C# Code Examples

### Program.cs (Host Configuration)

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

### EmailMessage.cs (Data Model)

```csharp
namespace EmailProcessor.Models;

/// <summary>
/// Represents an email message received from the Service Bus queue.
/// </summary>
public sealed class EmailMessage
{
    public string? MessageId { get; set; }
    public string? From { get; set; }
    public string? To { get; set; }
    public string? Subject { get; set; }
    public string? Body { get; set; }
    public DateTimeOffset ReceivedAt { get; set; }
    public Dictionary<string, string>? Headers { get; set; }
    public List<string>? Attachments { get; set; }
}
```

### EmailProcessorFunction.cs (Service Bus Trigger)

```csharp
using Azure.Messaging.ServiceBus;
using EmailProcessor.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace EmailProcessor.Functions;

/// <summary>
/// Azure Function triggered by Service Bus queue messages for processing incoming emails.
/// </summary>
public sealed class EmailProcessorFunction
{
    private readonly ILogger<EmailProcessorFunction> _logger;

    public EmailProcessorFunction(ILogger<EmailProcessorFunction> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Processes a single email message from the Service Bus queue.
    /// </summary>
    [Function(nameof(ProcessEmailMessage))]
    public async Task ProcessEmailMessage(
        [ServiceBusTrigger("email-queue", Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Processing message ID: {MessageId}", message.MessageId);
        
        try
        {
            // Deserialize message body to EmailMessage POCO
            EmailMessage? email = message.Body.ToObjectFromJson<EmailMessage>();
            
            if (email is null)
            {
                _logger.LogWarning("Failed to deserialize message {MessageId}", message.MessageId);
                await messageActions.DeadLetterMessageAsync(
                    message,
                    deadLetterReason: "InvalidFormat",
                    deadLetterErrorDescription: "Message body could not be deserialized",
                    cancellationToken: cancellationToken);
                return;
            }

            _logger.LogInformation(
                "Processing email from {From} to {To}, Subject: {Subject}",
                email.From,
                email.To,
                email.Subject);

            // Process the email (implement business logic here)
            await ProcessEmailAsync(email, cancellationToken);

            // Complete the message after successful processing
            await messageActions.CompleteMessageAsync(message, cancellationToken);
            
            _logger.LogInformation("Successfully processed message {MessageId}", message.MessageId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing message {MessageId}", message.MessageId);
            
            // Let the message be retried (don't complete or dead-letter)
            throw;
        }
    }

    /// <summary>
    /// Processes a batch of email messages from the Service Bus queue.
    /// </summary>
    [Function(nameof(ProcessEmailMessageBatch))]
    public async Task ProcessEmailMessageBatch(
        [ServiceBusTrigger("email-queue-batch", Connection = "ServiceBusConnection", IsBatched = true)]
        ServiceBusReceivedMessage[] messages,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Processing batch of {Count} messages", messages.Length);

        foreach (ServiceBusReceivedMessage message in messages)
        {
            try
            {
                EmailMessage? email = message.Body.ToObjectFromJson<EmailMessage>();
                
                if (email is not null)
                {
                    await ProcessEmailAsync(email, cancellationToken);
                    await messageActions.CompleteMessageAsync(message, cancellationToken);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in batch for message {MessageId}", message.MessageId);
            }
        }
    }

    private async Task ProcessEmailAsync(EmailMessage email, CancellationToken cancellationToken)
    {
        // Implement email processing logic
        // Examples: save to database, trigger workflow, forward to another service
        await Task.CompletedTask;
    }
}
```

### Alternative: Simple String-Based Trigger

```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace EmailProcessor.Functions;

public sealed class SimpleEmailFunction
{
    private readonly ILogger<SimpleEmailFunction> _logger;

    public SimpleEmailFunction(ILogger<SimpleEmailFunction> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Simple trigger that receives message as a string.
    /// </summary>
    [Function(nameof(ProcessEmailString))]
    public void ProcessEmailString(
        [ServiceBusTrigger("email-queue", Connection = "ServiceBusConnection")]
        string messageBody)
    {
        _logger.LogInformation("Received message: {MessageBody}", messageBody);
    }
}
```

## Configuration Settings

### local.settings.json

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "ServiceBusConnection__fullyQualifiedNamespace": "<namespace>.servicebus.windows.net"
  }
}
```

### local.settings.json (Connection String Alternative)

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "ServiceBusConnection": "Endpoint=sb://<namespace>.servicebus.windows.net/;SharedAccessKeyName=<keyName>;SharedAccessKey=<key>"
  }
}
```

### host.json

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
      "maxConcurrentCalls": 16,
      "maxMessageBatchSize": 1000
    }
  }
}
```

## In-Process vs Isolated Worker Model Comparison

| Aspect | In-Process Model | Isolated Worker Model |
|--------|-----------------|----------------------|
| **Support Status** | Ends November 10, 2026 | Fully supported (recommended) |
| **Process** | Same process as Functions host | Separate worker process |
| **Assembly Conflicts** | Possible conflicts with host | No conflicts |
| **.NET Versions** | Limited to runtime version | .NET 8, 9, 10, .NET Framework 4.8 |
| **Dependency Injection** | Limited | Full .NET DI support |
| **Middleware** | Not supported | Supported (ASP.NET Core style) |
| **NuGet Packages** | `Microsoft.Azure.WebJobs.Extensions.*` | `Microsoft.Azure.Functions.Worker.Extensions.*` |
| **Trigger Attributes** | Same namespace as WebJobs | Worker-specific namespace |
| **Startup** | `FunctionsStartup` class | `Program.cs` with host builder |

### Key Differences in Code

**In-Process (deprecated):**

```csharp
// Uses WebJobs namespace
using Microsoft.Azure.WebJobs;

public class Function
{
    [FunctionName("ProcessEmail")]
    public void Run([ServiceBusTrigger("queue")] string message, ILogger log)
    {
        log.LogInformation(message);
    }
}
```

**Isolated Worker (recommended):**

```csharp
// Uses Worker namespace
using Microsoft.Azure.Functions.Worker;

public class Function
{
    [Function("ProcessEmail")]
    public void Run([ServiceBusTrigger("queue", Connection = "ServiceBusConnection")] string message)
    {
        // Use injected ILogger instead
    }
}
```

## Bicep Changes for C# Runtime

### Key App Settings Changes

| Setting | Python Value | C# Isolated Value |
|---------|-------------|-------------------|
| `FUNCTIONS_WORKER_RUNTIME` | `python` | `dotnet-isolated` |
| `netFrameworkVersion` | N/A | `v8.0` |
| `WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED` | N/A | `1` (performance) |

### Bicep Configuration for C# Function App

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
      // C# isolated worker specific settings
      netFrameworkVersion: 'v8.0'
      use32BitWorkerProcess: false
      appSettings: [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED'
          value: '1'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: '${serviceBusNamespace.name}.servicebus.windows.net'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
      ]
    }
  }
}
```

### Linux vs Windows Considerations

| Aspect | Windows | Linux |
|--------|---------|-------|
| `netFrameworkVersion` | Required (`v8.0`) | Use `linuxFxVersion` |
| `linuxFxVersion` | N/A | `DOTNET-ISOLATED|8.0` |
| 32-bit support | Available | 64-bit only |
| .NET Framework 4.8 | Supported | Not supported |

## Service Bus Trigger Attributes

| Attribute Property | Description | Default |
|-------------------|-------------|---------|
| `Connection` | App setting name for connection | `AzureWebJobsServiceBus` |
| `QueueName` | Queue to monitor | Required |
| `TopicName` | Topic to monitor (topics only) | N/A |
| `SubscriptionName` | Subscription (topics only) | N/A |
| `IsBatched` | Receive messages in batches | `false` |
| `IsSessionsEnabled` | Enable session support | `false` |
| `AutoCompleteMessages` | Auto-complete on success | `true` |

## Identity-Based Connection (Recommended)

Instead of connection strings, use managed identity:

### App Settings

```json
{
  "ServiceBusConnection__fullyQualifiedNamespace": "mynamespace.servicebus.windows.net"
}
```

### Required RBAC Role

| Binding Type | Required Role |
|-------------|---------------|
| Trigger | Azure Service Bus Data Receiver |
| Output | Azure Service Bus Data Sender |
| Both | Azure Service Bus Data Owner |

## Key Findings Summary

1. **Use isolated worker model** - In-process support ends November 2026
2. **Target .NET 8.0** - Stable, well-supported, optimal for production
3. **Package versions** - Use `Microsoft.Azure.Functions.Worker` 2.0.0+ and `Microsoft.Azure.Functions.Worker.Extensions.ServiceBus` 5.24.0
4. **Managed identity** - Prefer identity-based connections over connection strings
5. **Bicep changes** - Update `FUNCTIONS_WORKER_RUNTIME` to `dotnet-isolated` and set `netFrameworkVersion`
6. **Application Insights** - Configure directly in `Program.cs` for better control
7. **Auto-complete** - Set to `false` when using `ServiceBusMessageActions` for manual message settlement

## References

- [Azure Functions .NET Isolated Worker Guide](https://learn.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-process-guide)
- [Service Bus Trigger for Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-service-bus-trigger)
- [Service Bus Bindings Overview](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-service-bus)
- [NuGet: Microsoft.Azure.Functions.Worker.Extensions.ServiceBus](https://www.nuget.org/packages/Microsoft.Azure.Functions.Worker.Extensions.ServiceBus)
