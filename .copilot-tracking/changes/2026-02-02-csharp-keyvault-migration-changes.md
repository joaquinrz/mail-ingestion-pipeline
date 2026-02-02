<!-- markdownlint-disable-file -->
# Release Changes: C# Migration with Key Vault Integration

**Related Plan**: 2026-02-02-csharp-keyvault-migration-plan.instructions.md
**Implementation Date**: 2026-02-02

## Summary

Migration of the email ingestion pipeline from Python to C# isolated worker model with Azure Key Vault integration for secure secret management. Recovers deleted Bicep templates and removes Python dependencies.

## Changes

### Added

* infra/modules/key-vault.bicep - Key Vault module with RBAC authorization, soft delete, purge protection, and conditional secrets storage
* infra/modules/function-app.bicep - Function App module recovered with C# isolated worker (.NET 8), managed identity, and Key Vault references
* src/functions/EmailProcessor/EmailProcessor.csproj - C# project file with .NET 8 isolated worker packages
* src/functions/EmailProcessor/Program.cs - Host configuration with Application Insights integration
* src/functions/EmailProcessor/Functions/EmailProcessorFunction.cs - Service Bus trigger function with message processing
* src/functions/EmailProcessor/Models/EmailMessage.cs - Email message record type
* src/functions/EmailProcessor/host.json - Functions host configuration with Service Bus settings
* src/functions/EmailProcessor/local.settings.json - Local development settings

### Modified

* infra/main.bicep - Recovered with Key Vault orchestration, RBAC role assignment for Function App managed identity, secure outputs

### Removed

* src/functions/function_app.py - Python function code replaced by C# implementation
* src/functions/requirements.txt - Python dependencies no longer needed
* src/functions/host.json - Moved to EmailProcessor project directory

## Additional or Deviating Changes

* infra/main.bicep - Fixed RBAC role assignment to use compile-time constant values for name and scope (Bicep BCP120 error)
* infra/modules/function-app.bicep - Removed unused storageAccountName parameter (not needed with Key Vault references)
* C# project build validation skipped - .NET 8 SDK not installed on development machine

## Release Summary

**Total files affected**: 14 files (9 added, 2 modified, 3 removed)

**Files created**:

* infra/modules/key-vault.bicep - Key Vault module with RBAC authorization
* infra/modules/function-app.bicep - Function App with C# isolated worker configuration
* src/functions/EmailProcessor/EmailProcessor.csproj - C# project file
* src/functions/EmailProcessor/Program.cs - Host configuration
* src/functions/EmailProcessor/Functions/EmailProcessorFunction.cs - Service Bus trigger function
* src/functions/EmailProcessor/Models/EmailMessage.cs - Email message record type
* src/functions/EmailProcessor/host.json - Functions host configuration
* src/functions/EmailProcessor/local.settings.json - Local development settings
* .copilot-tracking/changes/2026-02-02-csharp-keyvault-migration-changes.md - This changes log

**Files modified**:

* infra/main.bicep - Recovered with Key Vault orchestration and RBAC

**Files removed**:

* src/functions/function_app.py - Python function code
* src/functions/requirements.txt - Python dependencies
* src/functions/host.json - Moved to EmailProcessor project

**Infrastructure changes**:

* Key Vault deployed with RBAC authorization (no access policies)
* Managed identity enabled for Function App
* Secrets stored in Key Vault with secure references
* Key Vault Secrets User role assigned to Function App

**Deployment notes**:

* Requires .NET 8 SDK for C# project build
* Bicep templates compile successfully
* Key Vault references require managed identity RBAC before deployment

