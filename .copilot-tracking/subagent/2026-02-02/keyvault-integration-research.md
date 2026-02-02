---
title: Azure Key Vault Integration Research
description: Research findings for integrating Azure Key Vault with Azure Functions and other resources in Bicep deployments
ms.date: 2026-02-02
ms.topic: reference
---

# Azure Key Vault Integration Research

This document provides research findings for integrating Azure Key Vault with Azure Functions and other resources in Bicep deployments for the mail-ingestion-pipeline project.

## Key Findings Summary

| Area | Recommendation |
|------|----------------|
| Authorization Model | Use Azure RBAC (not access policies) for new deployments |
| Identity Type | System-assigned managed identity for Function App |
| Secret Reference | Use `@Microsoft.KeyVault()` reference syntax in app settings |
| Secret Storage | Store connection strings via Bicep `secrets` child resource |
| Output Security | Never output secrets directly; use Key Vault references |

## Key Vault Bicep Module Template

### Basic Key Vault Resource

```bicep
@description('Key Vault name.')
param keyVaultName string

@description('Azure region.')
param location string

@description('Tenant ID for Key Vault.')
param tenantId string = tenant().tenantId

@description('Enable RBAC authorization (recommended over access policies).')
param enableRbacAuthorization bool = true

@description('Enable soft delete protection.')
param enableSoftDelete bool = true

@description('Soft delete retention in days.')
param softDeleteRetentionInDays int = 90

@description('Enable purge protection (irreversible).')
param enablePurgeProtection bool = true

resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenantId
    enableRbacAuthorization: enableRbacAuthorization
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection
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

### Key Vault Secrets Child Resource

```bicep
@description('Secret name.')
param secretName string

@description('Secret value.')
@secure()
param secretValue string

resource keyVaultSecret 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: secretName
  properties: {
    value: secretValue
    attributes: {
      enabled: true
    }
  }
}
```

## Storing Service Bus Connection Strings Securely

### Pattern: Store Connection String in Key Vault

```bicep
/* Service Bus Secret Storage */

resource serviceBusConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'ServiceBusConnectionString'
  properties: {
    value: listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
  }
}

resource serviceBusSendConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'ServiceBusSendConnectionString'
  properties: {
    value: sendAuthRule.listKeys().primaryConnectionString
  }
}
```

### Important: Avoid Outputting Connection Strings

The current [service-bus.bicep](../../../infra/modules/service-bus.bicep) outputs connection strings directly, which is a security concern:

```bicep
// CURRENT (NOT RECOMMENDED)
output connectionString string = listKeys(...).primaryConnectionString

// RECOMMENDED: Remove sensitive outputs, store in Key Vault instead
output namespaceName string = serviceBusNamespace.name
output queueName string = emailQueue.name
// DO NOT output connection strings
```

## Function App App Settings with Key Vault References

### Key Vault Reference Syntax

Use the `@Microsoft.KeyVault()` reference syntax in app settings:

```bicep
resource functionApp 'Microsoft.Web/sites@2025-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
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

### Reference Format Options

| Format | Example |
|--------|---------|
| Full URI | `@Microsoft.KeyVault(SecretUri=https://myvault.vault.azure.net/secrets/mysecret)` |
| With version | `@Microsoft.KeyVault(SecretUri=https://myvault.vault.azure.net/secrets/mysecret/ec96f02080254f109c51a1f14cdb1931)` |
| Named params | `@Microsoft.KeyVault(VaultName=myvault;SecretName=mysecret)` |

**Recommendation:** Omit the version to allow automatic rotation (secrets refresh every 24 hours).

## Managed Identity Setup in Bicep

### System-Assigned Managed Identity

```bicep
resource functionApp 'Microsoft.Web/sites@2025-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // ...
  }
}

// Access the identity principal ID
output functionAppPrincipalId string = functionApp.identity.principalId
```

### User-Assigned Managed Identity (Alternative)

```bicep
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-${functionAppName}'
  location: location
}

resource functionApp 'Microsoft.Web/sites@2025-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    keyVaultReferenceIdentity: userAssignedIdentity.id
    // ...
  }
}
```

**Recommendation:** Use system-assigned identity for simplicity unless you need to pre-configure access before resource creation.

## Access Policies vs RBAC for Key Vault Permissions

### Comparison

| Aspect | Access Policies (Legacy) | Azure RBAC (Recommended) |
|--------|-------------------------|--------------------------|
| Granularity | Vault-level only | Vault, secret, key, or certificate level |
| Management | Stored in Key Vault properties | Managed via Azure IAM |
| Limit | Max 1024 policies per vault | No practical limit |
| Best Practice | Legacy support only | Recommended for new deployments |
| Bicep Setting | `enableRbacAuthorization: false` | `enableRbacAuthorization: true` |

### Azure RBAC Built-in Roles for Key Vault

| Role | Purpose | Role Definition ID |
|------|---------|-------------------|
| Key Vault Administrator | Full access to all data operations | `00482a5a-887f-4fb3-b363-3b7fe8e74483` |
| Key Vault Secrets User | Read secret contents | `4633458b-17de-408a-b874-0445c86b69e6` |
| Key Vault Secrets Officer | Full secrets management | `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` |
| Key Vault Reader | Read metadata only | `21090545-7ca7-4776-b22c-e363652d74d2` |
| Key Vault Contributor | Manage vaults (control plane only) | N/A |

### RBAC Role Assignment in Bicep

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

### Access Policy Example (Legacy)

```bicep
resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: keyVaultName
  location: location
  properties: {
    enableRbacAuthorization: false
    tenantId: tenantId
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: functionApp.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
}
```

## Security Considerations and Best Practices

### Do's

1. **Enable RBAC Authorization** - Set `enableRbacAuthorization: true` for new vaults
2. **Enable Soft Delete** - Protects against accidental deletion (default: true)
3. **Enable Purge Protection** - Prevents permanent deletion during retention period
4. **Use Managed Identity** - Eliminates need for credentials in code
5. **Omit Secret Versions** - Allows automatic rotation
6. **Set `enabledForTemplateDeployment: true`** - Required for Bicep to read secrets during deployment
7. **Use Network ACLs** - Restrict access to known networks in production

### Don'ts

1. **Never output secrets** - Don't use Bicep outputs for connection strings or keys
2. **Don't hardcode secrets** - Always use Key Vault references or parameters with `@secure()`
3. **Don't use access policies for new deployments** - RBAC is the modern approach
4. **Don't skip dependency ordering** - Ensure Key Vault and secrets exist before Function App

### Deployment Ordering

The deployment must follow this dependency chain:

```text
1. Key Vault
2. Managed Identity (if user-assigned)
3. Role Assignment (RBAC) or Access Policy
4. Secrets (stored in Key Vault)
5. Function App (references secrets)
6. App Settings (depend on Function App and secrets)
```

### Example Deployment Sequence in Bicep

```bicep
// 1. Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: keyVaultName
  // ...
}

// 2. Service Bus (to get connection string)
module serviceBus 'modules/service-bus.bicep' = {
  name: 'serviceBus'
  params: {
    // ...
  }
}

// 3. Store secret
resource sbSecret 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'ServiceBusConnectionString'
  properties: {
    value: serviceBus.outputs.connectionString
  }
}

// 4. Function App with identity
resource functionApp 'Microsoft.Web/sites@2025-03-01' = {
  name: functionAppName
  identity: { type: 'SystemAssigned' }
  // ...
}

// 5. Role assignment (depends on Function App identity)
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

// 6. App settings with Key Vault reference
resource functionAppSettings 'Microsoft.Web/sites/config@2025-03-01' = {
  parent: functionApp
  name: 'appsettings'
  dependsOn: [
    keyVault
    sbSecret
    roleAssignment
  ]
  properties: {
    ServiceBusConnection: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/ServiceBusConnectionString/)'
  }
}
```

## Complete Key Vault Module Example

```bicep
/* ========================================
   Key Vault Module for Mail Ingestion Pipeline
   ======================================== */

@description('Key Vault name.')
param name string

@description('Azure region.')
param location string

@description('Function App principal ID for role assignment.')
param functionAppPrincipalId string

@description('Service Bus connection string to store.')
@secure()
param serviceBusConnectionString string

@description('Storage account connection string to store.')
@secure()
param storageConnectionString string

/* Key Vault Resource */

resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: name
  location: location
  properties: {
    tenantId: tenant().tenantId
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

/* Secrets */

resource serviceBusSecret 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'ServiceBusConnectionString'
  properties: {
    value: serviceBusConnectionString
  }
}

resource storageSecret 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'StorageConnectionString'
  properties: {
    value: storageConnectionString
  }
}

/* Role Assignment */

var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource functionAppKeyVaultAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionAppPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    principalId: functionAppPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

/* Outputs */

@description('Key Vault name.')
output keyVaultName string = keyVault.name

@description('Key Vault URI for secret references.')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Service Bus secret URI for app settings.')
output serviceBusSecretUri string = '${keyVault.properties.vaultUri}secrets/${serviceBusSecret.name}/'

@description('Storage secret URI for app settings.')
output storageSecretUri string = '${keyVault.properties.vaultUri}secrets/${storageSecret.name}/'
```

## References

- [Microsoft.KeyVault/vaults Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults?pivots=deployment-language-bicep)
- [Microsoft.KeyVault/vaults/secrets Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults/secrets?pivots=deployment-language-bicep)
- [Use Key Vault references in App Service/Functions](https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references)
- [Azure RBAC for Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [Manage secrets with Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/scenarios-secrets)
- [Microsoft.Authorization/roleAssignments Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.authorization/roleassignments?pivots=deployment-language-bicep)
