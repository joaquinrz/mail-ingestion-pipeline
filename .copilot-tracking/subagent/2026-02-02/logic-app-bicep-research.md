# Logic App Bicep Research: Office 365 Email Triggers

**Research Date:** 2026-02-02  
**Status:** Complete  
**Sources:** Microsoft Learn Documentation, Azure Quickstart Templates

---

## Executive Summary

This document contains research findings for implementing Azure Logic Apps with Office 365 email triggers using Bicep templates. It includes resource types, API versions, connection patterns, and workflow trigger definitions.

---

## 1. Resource Types and API Versions

### Logic App (Consumption Tier)

| Property | Value |
|----------|-------|
| **Resource Type** | `Microsoft.Logic/workflows` |
| **Recommended API Version** | `2019-05-01` |
| **Deployment Scope** | Resource Group |

```bicep
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {}
      actions: {}
    }
    parameters: {}
  }
}
```

### API Connection (Office 365 Outlook)

| Property | Value |
|----------|-------|
| **Resource Type** | `Microsoft.Web/connections` |
| **Recommended API Version** | `2016-06-01` |
| **Alternative API Version** | `2018-07-01-preview` |

```bicep
resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: connectionName
  location: location
  properties: {
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
    displayName: 'office365'
  }
}
```

---

## 2. Connection Authorization Patterns

### Pattern A: Managed API Reference (Recommended)

The Office 365 Outlook connector uses OAuth authentication. Connection requires:

1. **Managed API Reference**: Reference the managed API using `subscriptionResourceId`
2. **Interactive Authorization**: User must authorize the connection post-deployment

```bicep
// Get the managed API reference
var office365ApiId = subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')

resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: office365ConnectionName
  location: location
  properties: {
    api: {
      id: office365ApiId
      name: 'office365'
      displayName: 'Office 365 Outlook'
      iconUri: 'https://connectoricons-prod.azureedge.net/releases/v1.0.1669/1.0.1669.3522/office365/icon.png'
    }
    displayName: office365ConnectionName
  }
}
```

### Pattern B: Connection with Parameter Values

For connectors that support non-interactive authentication (not Office 365):

```bicep
resource connection 'Microsoft.Web/connections@2016-06-01' = {
  name: connectionName
  location: location
  properties: {
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
    }
    displayName: 'azureblob'
    parameterValues: {
      accountName: storageAccountName
      accessKey: storageAccountKey
    }
  }
}
```

### Connection Parameter in Logic App

```bicep
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      // ... triggers and actions
    }
    parameters: {
      '$connections': {
        value: {
          office365: {
            connectionId: office365Connection.id
            connectionName: office365ConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
        }
      }
    }
  }
}
```

---

## 3. Workflow Trigger Definitions for Email

### "When a new email arrives" Trigger (V3 - Current)

**Operation ID:** `OnNewEmailV3`

This is the current recommended trigger version that uses Graph API.

```bicep
triggers: {
  When_a_new_email_arrives_V3: {
    type: 'ApiConnection'
    recurrence: {
      frequency: 'Minute'
      interval: 1
    }
    evaluatedRecurrence: {
      frequency: 'Minute'
      interval: 1
    }
    inputs: {
      host: {
        connection: {
          name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
        }
      }
      method: 'get'
      path: '/v2/Mail/OnNewEmail'
      queries: {
        folderPath: 'Inbox'
        importance: 'Any'
        fetchOnlyWithAttachment: false
        includeAttachments: false
      }
    }
  }
}
```

### Trigger Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `folderPath` | string | Mail folder to monitor (default: 'Inbox') |
| `to` | email | Filter by recipient email addresses (semicolon-separated) |
| `cc` | email | Filter by CC recipients |
| `toOrCc` | email | Filter by To or CC recipients |
| `from` | email | Filter by sender email addresses |
| `importance` | string | Filter by importance (Any, High, Normal, Low) |
| `fetchOnlyWithAttachment` | boolean | Only retrieve emails with attachments |
| `includeAttachments` | boolean | Include attachment content in response |
| `subjectFilter` | string | String to search in subject line |

### Complete Trigger Example with Filters

```bicep
triggers: {
  When_a_new_email_arrives: {
    type: 'ApiConnection'
    recurrence: {
      frequency: 'Minute'
      interval: 3
    }
    inputs: {
      host: {
        connection: {
          name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
        }
      }
      method: 'get'
      path: '/v2/Mail/OnNewEmail'
      queries: {
        folderPath: 'Inbox'
        from: 'important@example.com'
        importance: 'High'
        fetchOnlyWithAttachment: true
        includeAttachments: true
        subjectFilter: 'Invoice'
      }
    }
  }
}
```

---

## 4. Complete Bicep Template Example

```bicep
@description('Name of the Logic App')
param logicAppName string

@description('Name of the Office 365 connection')
param office365ConnectionName string = 'office365'

@description('Location for all resources')
param location string = resourceGroup().location

// Reference to the Office 365 managed API
var office365ApiId = subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')

// Office 365 API Connection
resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: office365ConnectionName
  location: location
  properties: {
    api: {
      id: office365ApiId
      name: 'office365'
      displayName: 'Office 365 Outlook'
    }
    displayName: office365ConnectionName
  }
}

// Logic App with Email Trigger
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        When_a_new_email_arrives: {
          type: 'ApiConnection'
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v2/Mail/OnNewEmail'
            queries: {
              folderPath: 'Inbox'
              importance: 'Any'
              fetchOnlyWithAttachment: false
              includeAttachments: true
            }
          }
        }
      }
      actions: {
        // Add your actions here
      }
    }
    parameters: {
      '$connections': {
        value: {
          office365: {
            connectionId: office365Connection.id
            connectionName: office365ConnectionName
            id: office365ApiId
          }
        }
      }
    }
  }
}

output logicAppName string = logicApp.name
output logicAppId string = logicApp.id
output connectionId string = office365Connection.id
```

---

## 5. Important Considerations

### Authentication Requirements

1. **OAuth Flow Required**: Office 365 connector requires interactive OAuth authorization
2. **Post-Deployment Step**: After deploying, navigate to the connection in Azure Portal and authorize it
3. **User Permissions**: The authorizing user needs appropriate permissions in Office 365

### Trigger Limitations

| Limitation | Details |
|------------|---------|
| **Message Size** | Skips emails > 50 MB or Exchange Admin limit |
| **Protected Emails** | May skip encrypted/protected emails |
| **Invalid Bodies** | Skips emails with invalid body or attachments |
| **Polling Based** | V3 trigger uses polling (not webhooks) |
| **Delay** | Trigger may delay up to 1 hour in rare cases |

### Throttling Limits

| Limit | Value |
|-------|-------|
| API calls per connection | 300 per 60 seconds |
| Maximum mail content length | 49 MB |
| Maximum total content per 5 min (Send) | 500 MB |
| Maximum total content per 5 min (All actions) | 2000 MB |

### Shared Mailbox Support

For shared mailbox monitoring, use the dedicated trigger:

```bicep
triggers: {
  When_a_new_email_arrives_in_shared_mailbox: {
    type: 'ApiConnection'
    recurrence: {
      frequency: 'Minute'
      interval: 1
    }
    inputs: {
      host: {
        connection: {
          name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
        }
      }
      method: 'get'
      path: '/v2/SharedMailbox/OnNewEmail'
      queries: {
        mailboxAddress: 'shared@example.com'
        folderId: 'Inbox'
        importance: 'Any'
        includeAttachments: true
      }
    }
  }
}
```

---

## 6. Alternative Trigger Patterns

### Blob Storage Trigger Pattern (from quickstart templates)

For scenarios where email content is stored in blob storage:

```bicep
triggers: {
  'When_a_blob_is_added_or_modified_(properties_only)': {
    recurrence: {
      frequency: 'Minute'
      interval: 5
    }
    splitOn: '@triggerBody()'
    type: 'ApiConnection'
    inputs: {
      host: {
        connection: {
          name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
        }
      }
      method: 'get'
      path: '/datasets/default/triggers/batch/onupdatedfile'
      queries: {
        folderId: 'JTJmbXktY29udGFpbmVy'
        maxFileCount: 10
      }
    }
  }
}
```

### Recurrence Trigger (Manual Polling Pattern)

```bicep
triggers: {
  Recurrence: {
    recurrence: {
      frequency: 'Hour'
      interval: 1
    }
    type: 'Recurrence'
  }
}
```

---

## 7. References

### Documentation Links

- [Microsoft.Logic/workflows Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.logic/workflows)
- [Microsoft.Web/connections Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.web/connections)
- [Office 365 Outlook Connector Reference](https://learn.microsoft.com/en-us/connectors/office365/)
- [Azure Quickstart Templates - Logic Apps](https://github.com/Azure/azure-quickstart-templates/tree/main/quickstarts/microsoft.logic)

### Related Quickstart Templates

| Template | Description |
|----------|-------------|
| `logic-app-create` | Basic Logic App with recurrence trigger |
| `logic-app-ftp-to-blob` | Logic App with FTP and Blob connectors |
| `arm-template-retrieve-azure-storage-access-keys` | Logic App with Blob trigger pattern |

---

## Summary of Key Findings

| Component | Resource Type | API Version |
|-----------|--------------|-------------|
| Logic App (Consumption) | `Microsoft.Logic/workflows` | `2019-05-01` |
| API Connection | `Microsoft.Web/connections` | `2016-06-01` |
| Managed API Reference | `Microsoft.Web/locations/managedApis` | N/A (built-in) |

**Email Trigger Operation:** `OnNewEmailV3` (recommended) via path `/v2/Mail/OnNewEmail`

**Key Pattern:** Connection parameters are passed via the `$connections` parameter object, referencing both the `connectionId` and the managed API `id`.
