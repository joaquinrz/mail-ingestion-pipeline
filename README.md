# Email Ingestion Pipeline

An Azure-based email processing solution using Logic Apps, Service Bus, and Azure Functions with secure Key Vault integration.

## Architecture

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Office 365    │    │    Logic App    │    │   Service Bus   │    │ Azure Function  │
│     Mailbox     │───▶│    (Trigger)    │───▶│     (Queue)     │───▶│     (C#/.NET)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └────────┬────────┘
                                                                              │
                                                      ┌───────────────────────┘
                                                      │ Managed Identity (RBAC)
                                                      ▼
                                              ┌─────────────────┐
                                              │   Key Vault     │
                                              │   (Secrets)     │
                                              └─────────────────┘
```

## Features

- **C# Isolated Worker** - .NET 8 Azure Function with isolated process model
- **Secure Secret Management** - Key Vault with RBAC authorization and managed identity
- **Event-Driven Processing** - Service Bus queue for reliable message delivery
- **Infrastructure as Code** - Bicep templates for repeatable deployments
- **Application Insights** - Built-in monitoring and telemetry

## Prerequisites

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (2.50+)
- [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local) (v4)
- Azure subscription with Contributor access

## Quick Start

### 1. Clone and Build

```bash
git clone https://github.com/joaquinrz/mail-ingestion-pipeline.git
cd mail-ingestion-pipeline
dotnet build src/functions/EmailProcessor/EmailProcessor.csproj
```

### 2. Deploy Infrastructure

```bash
az login
az group create --name rg-email-pipeline-dev --location eastus2

az deployment group create \
  --resource-group rg-email-pipeline-dev \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

### 3. Deploy Function App

```bash
cd src/functions/EmailProcessor
func azure functionapp publish <function-app-name>
```

## Project Structure

```text
mail-ingestion-pipeline/
├── infra/
│   ├── main.bicep              # Main orchestration template
│   ├── main.bicepparam         # Parameter values
│   └── modules/
│       ├── function-app.bicep  # Function App with managed identity
│       ├── key-vault.bicep     # Key Vault with RBAC
│       ├── logic-app.bicep     # Logic App workflow
│       ├── service-bus.bicep   # Service Bus namespace and queue
│       └── storage.bicep       # Storage account
├── src/functions/EmailProcessor/
│   ├── Functions/
│   │   └── EmailProcessorFunction.cs
│   ├── Models/
│   │   └── EmailMessage.cs
│   ├── Program.cs
│   ├── host.json
│   └── EmailProcessor.csproj
└── README.md
```

## Local Development

1. Copy `local.settings.json.template` to `local.settings.json`
2. Update connection strings for local Service Bus emulator or Azure instance
3. Run the function locally:

```bash
cd src/functions/EmailProcessor
func start
```

## Configuration

The Function App uses Key Vault references for secrets:

| Setting | Key Vault Secret |
|---------|------------------|
| `AzureWebJobsStorage` | `StorageConnectionString` |
| `ServiceBusConnection` | `ServiceBusConnectionString` |

Managed identity automatically authenticates to Key Vault using RBAC (Key Vault Secrets User role).

## Cleanup

```bash
az group delete --name rg-email-pipeline-dev --yes --no-wait
```

## License

MIT
