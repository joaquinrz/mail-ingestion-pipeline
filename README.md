---
title: Email Ingestion Pipeline
description: Azure-based spike solution for ingesting Office 365 emails through Logic Apps, Service Bus, and Azure Functions
ms.date: 2026-02-02
ms.topic: overview
---

## Overview

This repository contains a spike implementation for an email ingestion pipeline on Azure. The solution monitors an Office 365 mailbox, captures incoming emails through a Logic App, queues them via Azure Service Bus, and processes them with an Azure Function.

The architecture demonstrates a decoupled, event-driven approach to email processing that can scale independently at each stage.

## Architecture

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Office 365    │    │    Logic App    │    │   Service Bus   │    │ Azure Function  │
│     Mailbox     │───▶│    (Trigger)    │───▶│     (Queue)     │───▶│   (Processor)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
        │                      │                      │                      │
        │                      │                      │                      │
   Incoming Email         Polls every          Stores messages       Processes and
   arrives in inbox       minute for new       for reliable          logs email
                          emails               delivery              metadata
```

### Components

| Component | Purpose |
|-----------|---------|
| Office 365 Mailbox | Source of incoming emails monitored by the pipeline |
| Logic App | Polls the mailbox on a schedule and forwards email data to Service Bus |
| Service Bus Queue | Provides reliable message queuing between ingestion and processing |
| Azure Function | Consumes messages from the queue and processes email content |

## Prerequisites

Before deploying this solution, ensure you have:

- Azure CLI 2.50 or later installed
- An Azure subscription with Owner or Contributor access
- An Office 365 mailbox to monitor
- Python 3.11 (for local development only)

Verify your Azure CLI version:

```bash
az --version
```

## Quick Start

### 1. Authenticate with Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Create a Resource Group

```bash
az group create --name rg-email-pipeline-dev --location eastus2
```

### 3. Deploy the Infrastructure

```bash
az deployment group create \
  --resource-group rg-email-pipeline-dev \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

The deployment creates:

- Storage Account for Azure Function
- Service Bus Namespace with `email-messages` queue
- Logic App with Office 365 connector
- Azure Function App with Service Bus trigger

### 4. Deploy the Function Code

```bash
cd src/functions
func azure functionapp publish func-emailpipelinedev-<unique-suffix>
```

Replace `<unique-suffix>` with the actual suffix from your deployment outputs.

## Post-Deployment Configuration

### Authorize the Office 365 Connection

The Logic App requires manual authorization to access the Office 365 mailbox:

1. Open the Azure Portal and navigate to your resource group
2. Select the Logic App resource (name starts with `logic-`)
3. In the left menu, select **API connections**
4. Select **office365-connection**
5. Select **Edit API connection** from the toolbar
6. Select **Authorize** and sign in with your Office 365 credentials
7. Select **Save** to confirm the connection

### Configure the Monitored Folder

By default, the Logic App monitors the Inbox folder. To change the monitored folder:

1. Open the Logic App in the Azure Portal
2. Select **Logic app designer**
3. Expand the **When a new email arrives** trigger
4. Modify the **Folder** parameter to your desired folder path

## Testing

Verify the pipeline functions correctly with these steps:

1. Send a test email to the configured Office 365 mailbox
2. Wait up to one minute for the Logic App trigger to fire
3. In the Azure Portal, open the Logic App and select **Run history** to confirm execution
4. Navigate to the Service Bus namespace and verify messages are being processed
5. Open the Function App and select **Monitor** to view processing logs

### View Function Logs

```bash
az functionapp logs tail \
  --name func-emailpipelinedev-<unique-suffix> \
  --resource-group rg-email-pipeline-dev
```

### Check Service Bus Queue Metrics

```bash
az servicebus queue show \
  --name email-messages \
  --namespace-name sb-emailpipelinedev-<unique-suffix> \
  --resource-group rg-email-pipeline-dev \
  --query "{activeMessages:countDetails.activeMessageCount, deadLetter:countDetails.deadLetterMessageCount}"
```

## Project Structure

```text
mail-ingestion-pipeline/
├── infra/                      # Infrastructure as Code
│   ├── main.bicep              # Main Bicep template
│   ├── main.bicepparam         # Parameter file
│   └── modules/                # Reusable Bicep modules
│       ├── function-app.bicep  # Azure Function resources
│       ├── logic-app.bicep     # Logic App workflow
│       ├── service-bus.bicep   # Service Bus namespace and queue
│       └── storage.bicep       # Storage account
├── src/
│   └── functions/              # Azure Function source code
│       ├── function_app.py     # Email processor function
│       ├── host.json           # Function host configuration
│       └── requirements.txt    # Python dependencies
└── README.md                   # This file
```

## Cleanup

Remove all deployed resources by deleting the resource group:

```bash
az group delete --name rg-email-pipeline-dev --yes --no-wait
```

The `--no-wait` flag returns immediately while deletion continues in the background.

## Limitations

This spike implementation has several limitations to consider:

| Limitation | Description |
|------------|-------------|
| Manual OAuth Authorization | The Office 365 connection requires manual authorization through the Azure Portal after deployment |
| Polling Interval | The Logic App polls every minute rather than providing real-time notification |
| No Attachment Handling | Email attachments are not captured or processed in this implementation |
| Basic Error Handling | Errors are logged but not routed to dead-letter queues with retry policies |
| Single Environment | The parameter file targets development; production deployments need additional configuration |
| No Authentication | The Function App does not implement authentication for any HTTP endpoints |

## Next Steps

To evolve this spike into a production solution, consider:

- Implementing attachment extraction and storage in Blob Storage
- Adding Application Insights for comprehensive monitoring
- Configuring dead-letter queue handling with alerts
- Setting up CI/CD pipelines for automated deployment
- Adding managed identity for secure credential management
- Implementing message filtering and routing based on email properties
