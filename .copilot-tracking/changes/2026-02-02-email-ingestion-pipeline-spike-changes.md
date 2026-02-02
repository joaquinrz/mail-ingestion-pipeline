<!-- markdownlint-disable-file -->
# Release Changes: Email Ingestion Pipeline Spike

**Related Plan**: 2026-02-02-email-ingestion-pipeline-spike-plan.instructions.md
**Implementation Date**: 2026-02-02

## Summary

Deploy a minimum viable email ingestion pipeline using Azure Logic Apps, Service Bus, and Azure Functions with Bicep infrastructure-as-code.

## Changes

### Added

* infra/modules/storage.bicep - Storage account module with TLS 1.2, HTTPS-only, and connection string outputs
* infra/modules/service-bus.bicep - Service Bus namespace with queue, dead-lettering, and send/listen authorization rules
* infra/modules/logic-app.bicep - Logic App with Office 365 email trigger and Service Bus message action
* infra/modules/function-app.bicep - Python 3.11 Function App on Linux with App Insights and consumption plan
* infra/main.bicep - Main orchestration template deploying all modules with dependency chaining
* infra/main.bicepparam - Parameters file for dev environment deployment
* src/functions/function_app.py - Service Bus triggered function using Python v2 programming model
* src/functions/host.json - Azure Functions host configuration with Application Insights and Service Bus settings
* src/functions/requirements.txt - Python dependencies (azure-functions, azure-servicebus)
* README.md - Project documentation with deployment instructions, architecture, and post-deployment steps

### Modified

### Removed

## Additional or Deviating Changes

* infra/modules/logic-app.bicep - Simplified ContentData expression from complex string concatenation with escape sequences to `@{base64(triggerBody())}` to resolve Bicep escape sequence validation error (BCP006)
  * Original implementation attempted manual JSON construction with escaped quotes which Bicep does not support
  * The simplified approach sends the entire email body as base64, which the function can parse

## Release Summary

**Total Files Created**: 10

| Category | Files |
|----------|-------|
| Bicep Infrastructure | 6 files (infra/main.bicep, infra/main.bicepparam, infra/modules/*.bicep) |
| Azure Functions | 3 files (src/functions/function_app.py, host.json, requirements.txt) |
| Documentation | 1 file (README.md) |

**Validation Results**:
- Bicep templates: Compiled successfully (5 warnings for expected secret outputs)
- Python syntax: Valid
- JSON syntax (host.json): Valid

**Deployment Command**:
```bash
az deployment group create \
  --resource-group rg-email-pipeline-dev \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

**Post-Deployment**: Manual Office 365 OAuth authorization required via Azure Portal

