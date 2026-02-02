/* ========================================================================== */
/* Key Vault Module                                                           */
/* ========================================================================== */

@description('Key Vault name.')
param name string

@description('Azure region.')
param location string

@description('Tenant ID for Key Vault.')
param tenantId string = tenant().tenantId

/* ========================================================================== */
/* Secrets Parameters                                                         */
/* ========================================================================== */

@description('Service Bus connection string to store.')
@secure()
param serviceBusConnectionString string = ''

@description('Storage connection string to store.')
@secure()
param storageConnectionString string = ''

/* ========================================================================== */
/* Key Vault Resource                                                         */
/* ========================================================================== */

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

/* ========================================================================== */
/* Secret Resources                                                           */
/* ========================================================================== */

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

/* ========================================================================== */
/* Outputs                                                                    */
/* ========================================================================== */

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
