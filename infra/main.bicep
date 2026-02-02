// Main orchestration for Email Ingestion Pipeline with Key Vault Integration
targetScope = 'resourceGroup'

@description('Environment name.')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for resources.')
param location string = resourceGroup().location

@description('Base name for resources.')
param baseName string = 'emailpipeline'

/* Variables */

var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${baseName}${environment}'
var keyVaultName = 'kv-${resourcePrefix}-${uniqueSuffix}'
var functionAppName = 'func-${resourcePrefix}-${uniqueSuffix}'

/* Key Vault */

module keyVault 'modules/key-vault.bicep' = {
  name: 'keyvault-deployment'
  params: {
    name: keyVaultName
    location: location
  }
}

/* Storage Account */

module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    name: 'st${resourcePrefix}${uniqueSuffix}'
    location: location
  }
}

/* Service Bus */

module serviceBus 'modules/service-bus.bicep' = {
  name: 'servicebus-deployment'
  params: {
    name: 'sb-${resourcePrefix}-${uniqueSuffix}'
    location: location
    queueName: 'email-messages'
  }
}

/* Key Vault Secrets */

module keyVaultSecrets 'modules/key-vault.bicep' = {
  name: 'keyvault-secrets-deployment'
  params: {
    name: keyVault.outputs.keyVaultName
    location: location
    serviceBusConnectionString: serviceBus.outputs.connectionString
    storageConnectionString: storage.outputs.connectionString
  }
}

/* Logic App */

module logicApp 'modules/logic-app.bicep' = {
  name: 'logicapp-deployment'
  params: {
    name: 'logic-${resourcePrefix}-${uniqueSuffix}'
    location: location
    serviceBusConnectionString: serviceBus.outputs.sendConnectionString
    serviceBusQueueName: 'email-messages'
  }
}

/* Function App */

module functionApp 'modules/function-app.bicep' = {
  name: 'functionapp-deployment'
  dependsOn: [keyVaultSecrets]
  params: {
    name: functionAppName
    location: location
    keyVaultUri: keyVault.outputs.keyVaultUri
  }
}

/* RBAC Role Assignment */

var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource existingKeyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionAppName, keyVaultSecretsUserRoleId)
  scope: existingKeyVault
  properties: {
    principalId: functionApp.outputs.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

/* Outputs */

output resourceGroupName string = resourceGroup().name
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output logicAppName string = logicApp.outputs.name
output functionAppName string = functionApp.outputs.name
output functionAppHostName string = functionApp.outputs.defaultHostName
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output serviceBusQueueName string = 'email-messages'
output storageAccountName string = storage.outputs.name
