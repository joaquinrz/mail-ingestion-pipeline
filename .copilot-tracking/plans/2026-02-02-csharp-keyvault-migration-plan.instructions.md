---
applyTo: '.copilot-tracking/changes/2026-02-02-csharp-keyvault-migration-changes.md'
---
<!-- markdownlint-disable-file -->
# Implementation Plan: C# Migration with Key Vault Integration

## Overview

Migrate the email ingestion pipeline from Python to C# isolated worker model, integrate Azure Key Vault for secure secret management, and recover deleted Bicep templates.

## Objectives

* Recover deleted `main.bicep` and `function-app.bicep` templates
* Create C# Azure Function project using .NET 8 isolated worker model
* Add Key Vault Bicep module with RBAC authorization
* Update infrastructure to use Key Vault references for secrets
* Remove Python function code and dependencies

## Context Summary

### Project Files

* [infra/main.bicep](infra/main.bicep) - Empty, requires recovery with Key Vault integration
* [infra/modules/function-app.bicep](infra/modules/function-app.bicep) - Empty, requires recovery with C# runtime
* [infra/modules/storage.bicep](infra/modules/storage.bicep) - Working, outputs secrets (security risk)
* [infra/modules/service-bus.bicep](infra/modules/service-bus.bicep) - Working, outputs connection strings (security risk)
* [infra/modules/logic-app.bicep](infra/modules/logic-app.bicep) - Working, uses Service Bus connection
* [src/functions/function_app.py](src/functions/function_app.py) - Python function to be replaced
* [src/functions/requirements.txt](src/functions/requirements.txt) - Python dependencies to be removed

### References

* [2026-02-02-csharp-keyvault-migration-research.md](.copilot-tracking/research/2026-02-02-csharp-keyvault-migration-research.md) - Full research documentation
* Azure Functions .NET isolated worker model documentation
* Azure Key Vault RBAC authorization patterns

### Standards References

* #file:../../.vscode/extensions/ise-hve-essentials.hve-core-2.0.1/.github/instructions/bicep/bicep.instructions.md - Bicep conventions
* #file:../../.vscode/extensions/ise-hve-essentials.hve-core-2.0.1/.github/instructions/csharp/csharp.instructions.md - C# conventions

## Implementation Checklist

### [x] Implementation Phase 1: Key Vault Bicep Module

<!-- parallelizable: true -->

* [x] Step 1.1: Create Key Vault module with RBAC authorization
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 15-55)
* [x] Step 1.2: Add secrets storage resources for Service Bus and Storage connections
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 56-90)
* [x] Step 1.3: Validate Bicep syntax for Key Vault module
  * Run `az bicep build --file infra/modules/key-vault.bicep`

### [x] Implementation Phase 2: Function App Bicep Recovery

<!-- parallelizable: true -->

* [x] Step 2.1: Recover function-app.bicep with C# isolated worker configuration
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 94-165)
* [x] Step 2.2: Add managed identity and Key Vault reference app settings
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 166-210)
* [x] Step 2.3: Validate Bicep syntax for function-app module
  * Run `az bicep build --file infra/modules/function-app.bicep`

### [x] Implementation Phase 3: Main Bicep Recovery with Key Vault Orchestration

<!-- parallelizable: false -->

* [x] Step 3.1: Recover main.bicep with Key Vault module integration
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 214-290)
* [x] Step 3.2: Add RBAC role assignment for Function App managed identity
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 291-330)
* [x] Step 3.3: Update outputs to remove secret exposure
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 331-355)
* [x] Step 3.4: Validate full Bicep template compilation
  * Run `az bicep build --file infra/main.bicep`

### [x] Implementation Phase 4: C# Function Project

<!-- parallelizable: false -->

* [x] Step 4.1: Create C# project structure with EmailProcessor.csproj
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 359-410)
* [x] Step 4.2: Implement Program.cs with host configuration
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 411-455)
* [x] Step 4.3: Create EmailProcessorFunction.cs with Service Bus trigger
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 456-530)
* [x] Step 4.4: Create EmailMessage.cs model
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 531-560)
* [x] Step 4.5: Update host.json for C# isolated worker
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 561-595)
* [x] Step 4.6: Create local.settings.json for local development
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 596-625)
* [ ] Step 4.7: Validate C# project builds
  * Run `dotnet build src/functions/EmailProcessor/EmailProcessor.csproj`
  * **Blocked**: .NET 8 SDK not installed

### [x] Implementation Phase 5: Python Removal

<!-- parallelizable: false -->

* [x] Step 5.1: Remove Python function files
  * Details: .copilot-tracking/details/2026-02-02-csharp-keyvault-migration-details.md (Lines 629-655)
* [x] Step 5.2: Verify project structure
  * List remaining files to confirm cleanup

### [x] Implementation Phase 6: Validation

<!-- parallelizable: false -->

* [x] Step 6.1: Run full Bicep validation
  * Execute `az bicep build --file infra/main.bicep`
  * Execute `az bicep lint --file infra/main.bicep`
* [ ] Step 6.2: Run C# build and test
  * Execute `dotnet build src/functions/EmailProcessor/EmailProcessor.csproj`
  * Execute `dotnet format --verify-no-changes src/functions/EmailProcessor/`
  * **Blocked**: .NET 8 SDK not installed
* [x] Step 6.3: Fix minor validation issues
  * Iterate on lint errors and build warnings
  * Apply fixes directly when corrections are straightforward
* [x] Step 6.4: Report blocking issues
  * Document issues requiring additional research
  * Provide user with next steps and recommended planning
  * Avoid large-scale fixes within this phase

## Dependencies

* .NET 8 SDK installed
* Azure CLI with Bicep extension
* Azure subscription for deployment validation

## Success Criteria

* All Bicep templates compile without errors
* C# project builds successfully
* No secrets exposed in Bicep outputs
* Managed identity configured for Function App
* Key Vault uses RBAC authorization
* Python code removed from repository
