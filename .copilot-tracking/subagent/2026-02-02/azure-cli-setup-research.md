# Azure CLI Setup and Bicep Deployment Research

> Research Date: 2026-02-02  
> Sources: Microsoft Learn Documentation

## Overview

This document captures the complete Azure CLI workflow for subscription setup and Bicep deployment on macOS.

---

## 1. Installing Azure CLI (macOS)

### Recommended Method: Homebrew

Homebrew is the officially recommended package manager for Azure CLI on macOS.

```bash
# Update Homebrew and install Azure CLI
brew update && brew install azure-cli
```

### Prerequisites

- macOS 13 or higher
- Homebrew package manager ([install homebrew](https://brew.sh/))
- Current Azure CLI version: **2.82.0**

### Verify Installation

```bash
# Check installed version
az version
```

### Update Azure CLI

```bash
# Option 1: Built-in upgrade command (recommended)
az upgrade

# Option 2: Homebrew upgrade
brew update && brew upgrade azure-cli
```

### Enable Shell Completion (Zsh)

Add to `~/.zshrc`:

```bash
autoload bashcompinit && bashcompinit
source $(brew --prefix)/etc/bash_completion.d/az
```

### Troubleshooting Installation

| Issue | Solution |
|-------|----------|
| Python not found | `brew update && brew install python@3.10 && brew upgrade python@3.10 && brew link --overwrite python@3.10` |
| Proxy blocks connection | Set `HTTP_PROXY` and `HTTPS_PROXY` environment variables |
| Old version installed | Run `brew update && brew upgrade azure-cli` |

---

## 2. Logging In to Azure

### Authentication Methods

| Method | Use Case | Command |
|--------|----------|---------|
| Interactive login | Local development, learning | `az login` |
| Managed identity | VM/Container apps | `az login --identity` |
| Service principal | CI/CD, automation scripts | `az login --service-principal` |
| Azure Cloud Shell | Quick access, no local install | Automatic |

### Interactive Login (Default)

```bash
# Opens browser for authentication
az login
```

This command:
1. Opens default browser to Azure sign-in page
2. Authenticates your Microsoft account
3. Returns list of accessible subscriptions
4. Sets a default subscription

### Service Principal Login (Automation)

```bash
# Using client secret
az login --service-principal \
  --username <app-id> \
  --password <client-secret> \
  --tenant <tenant-id>

# Using certificate
az login --service-principal \
  --username <app-id> \
  --password <path-to-cert> \
  --tenant <tenant-id>
```

### Managed Identity Login

```bash
# System-assigned managed identity
az login --identity

# User-assigned managed identity
az login --identity --username <client-id>
```

### Important: Multi-Factor Authentication (MFA)

Starting September 2025, Microsoft requires MFA for Azure CLI with user identities.

- **User identities**: Must use MFA
- **Service principals**: Not affected
- **Managed identities**: Not affected

**Recommendation:** For automation scripts, migrate to service principals or managed identities.

---

## 3. Working with Subscriptions

### List All Subscriptions

```bash
# Show all accessible subscriptions
az account list --output table
```

### View Current Subscription

```bash
# Show currently active subscription
az account show --output table
```

### Set Active Subscription

```bash
# By subscription name
az account set --subscription "My Subscription Name"

# By subscription ID
az account set --subscription "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Common Flags

| Flag | Description |
|------|-------------|
| `--output table` | Human-readable table format |
| `--output json` | JSON format (default) |
| `--output yaml` | YAML format |
| `--output tsv` | Tab-separated values |

---

## 4. Creating Resource Groups

### Naming Conventions

Resource group names have the following requirements:

- **Allowed characters**: Alphanumeric, periods, underscores, hyphens, parentheses
- **Maximum length**: 90 characters
- **Cannot end with**: Period (.)

### Recommended Naming Pattern

```plaintext
rg-<workload>-<environment>-<region>-<instance>
```

**Examples:**
- `rg-mailpipeline-dev-eastus-001`
- `rg-mailpipeline-prod-westus2-001`

### Create Resource Group

```bash
# Basic creation
az group create \
  --name "rg-mailpipeline-dev-eastus-001" \
  --location "eastus"
```

### Common Flags

| Flag | Description | Example |
|------|-------------|---------|
| `--name` / `-n` | Resource group name (required) | `rg-myapp-dev` |
| `--location` / `-l` | Azure region (required) | `eastus`, `westus2` |
| `--tags` | Resource tags | `environment=dev team=platform` |

### Create with Tags

```bash
az group create \
  --name "rg-mailpipeline-dev-eastus-001" \
  --location "eastus" \
  --tags "environment=dev" "project=mail-pipeline" "owner=team-platform"
```

### List Resource Groups

```bash
# List all resource groups
az group list --output table

# Filter by tag
az group list --tag environment=dev --output table
```

### Delete Resource Group

```bash
# With confirmation prompt
az group delete --name "rg-mailpipeline-dev-eastus-001"

# Skip confirmation (use with caution)
az group delete --name "rg-mailpipeline-dev-eastus-001" --yes --no-wait
```

---

## 5. Deploying Bicep Templates

### Prerequisites

- Azure CLI version **2.20.0** or later
- Bicep CLI (automatically installed with Azure CLI 2.20.0+)
- Logged in to Azure (`az login`)
- Target resource group exists (or use subscription-level deployment)

### Deployment Scopes

| Scope | Command | Use Case |
|-------|---------|----------|
| Resource Group | `az deployment group create` | Most common deployments |
| Subscription | `az deployment sub create` | Resource groups, policies |
| Management Group | `az deployment mg create` | Cross-subscription governance |
| Tenant | `az deployment tenant create` | Tenant-wide configuration |

### Deploy to Resource Group

```bash
# Basic deployment
az deployment group create \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --template-file "./infra/main.bicep"
```

### Deploy with Parameters

#### Inline Parameters

```bash
az deployment group create \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --template-file "./infra/main.bicep" \
  --parameters storageAccountName="stmailpipelinedev" location="eastus"
```

#### JSON Parameters File

```bash
az deployment group create \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --template-file "./infra/main.bicep" \
  --parameters '@./infra/parameters/dev.parameters.json'
```

#### Bicep Parameters File (.bicepparam)

```bash
# Note: Requires Azure CLI 2.53.0+ and Bicep CLI 0.22.X+
# No --template-file needed when using .bicepparam with 'using' statement
az deployment group create \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --parameters "./infra/parameters/dev.bicepparam"
```

### Named Deployment

```bash
# Unique deployment name with timestamp
deploymentName="deploy-$(date +%Y%m%d-%H%M%S)"

az deployment group create \
  --name "$deploymentName" \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --template-file "./infra/main.bicep"
```

### Common Deployment Flags

| Flag | Description |
|------|-------------|
| `--name` / `-n` | Deployment name (auto-generated if omitted) |
| `--resource-group` / `-g` | Target resource group |
| `--template-file` / `-f` | Path to Bicep file |
| `--parameters` / `-p` | Parameters (inline, file, or .bicepparam) |
| `--mode` | `Incremental` (default) or `Complete` |
| `--what-if` | Preview changes without deploying |
| `--confirm-with-what-if` | Preview and prompt for confirmation |

### Deployment to Subscription

```bash
az deployment sub create \
  --location "eastus" \
  --template-file "./infra/subscription-resources.bicep"
```

---

## 6. Post-Deployment Verification

### Check Deployment Status

```bash
# List deployments for a resource group
az deployment group list \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --output table

# Show specific deployment details
az deployment group show \
  --name "ExampleDeployment" \
  --resource-group "rg-mailpipeline-dev-eastus-001"
```

### View Deployment Outputs

```bash
# Get deployment outputs as JSON
az deployment group show \
  --name "ExampleDeployment" \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --query "properties.outputs"
```

### List Deployed Resources

```bash
# List all resources in resource group
az resource list \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --output table
```

### What-If Preview (Pre-Deployment)

```bash
# Preview changes before deployment
az deployment group what-if \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --template-file "./infra/main.bicep"
```

### Validate Template (Without Deploying)

```bash
az deployment group validate \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --template-file "./infra/main.bicep"
```

### View Deployment Operations

```bash
# Check individual operations in a deployment
az deployment operation group list \
  --name "ExampleDeployment" \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --output table
```

---

## Error Handling Tips

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `AuthorizationFailed` | Insufficient permissions | Verify RBAC role assignments |
| `ResourceGroupNotFound` | Resource group doesn't exist | Create resource group first |
| `InvalidTemplateDeployment` | Bicep syntax error | Run `az bicep build` to validate |
| `DeploymentFailed` | Resource creation error | Check deployment operations for details |
| `QuotaExceeded` | Subscription limit reached | Request quota increase or choose different SKU |

### Debugging Commands

```bash
# Enable verbose output
az deployment group create ... --verbose

# Enable debug output
az deployment group create ... --debug

# Export deployment template
az deployment group export \
  --name "ExampleDeployment" \
  --resource-group "rg-mailpipeline-dev-eastus-001"
```

### Check Required Permissions

Bicep deployments require:

- **Write access** to resources being deployed
- **`Microsoft.Resources/deployments/*`** operations

Common built-in roles:

- **Contributor**: Full resource management (no RBAC)
- **Owner**: Full access including RBAC

---

## Quick Reference: Complete Workflow

```bash
# 1. Install Azure CLI (one-time)
brew update && brew install azure-cli

# 2. Verify installation
az version

# 3. Log in to Azure
az login

# 4. Set subscription
az account set --subscription "My Subscription"

# 5. Create resource group
az group create \
  --name "rg-mailpipeline-dev-eastus-001" \
  --location "eastus" \
  --tags "environment=dev" "project=mail-pipeline"

# 6. Validate Bicep template
az deployment group validate \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --template-file "./infra/main.bicep"

# 7. Preview deployment (what-if)
az deployment group what-if \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --template-file "./infra/main.bicep"

# 8. Deploy Bicep template
az deployment group create \
  --name "deploy-$(date +%Y%m%d-%H%M%S)" \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --template-file "./infra/main.bicep" \
  --parameters '@./infra/parameters/dev.parameters.json'

# 9. Verify deployment
az deployment group show \
  --name "deploy-20260202-143000" \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --query "properties.provisioningState"

# 10. List deployed resources
az resource list \
  --resource-group "rg-mailpipeline-dev-eastus-001" \
  --output table
```

---

## References

- [Install Azure CLI on macOS](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-macos)
- [Authenticate to Azure using Azure CLI](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli)
- [Deploy Bicep files with the Azure CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-cli)
- [Manage Azure subscriptions with the Azure CLI](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli)
