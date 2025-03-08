# Microsoft Sentinel Deployment Automation

## Overview

This PowerShell script automates the deployment of Microsoft Sentinel resources within an Azure environment. It handles the deployment of solutions from the Content Hub, analytics rules, and workbooks, streamlining the configuration of a complete Sentinel environment with minimal manual intervention.

## Key Features

### Comprehensive Resource Deployment
- **Solutions**: Deploy Microsoft Sentinel solutions from the Content Hub
- **Analytics Rules**: Deploy rules filtered by severity with proper configuration and metadata
- **Workbooks**: Deploy workbooks for each solution

### Intelligent Resource Management
- **Unified Status Testing**: Consolidated resource status checking with `Test-SentinelResource`
- **Smart Update Handling**: Skip or force updates based on your requirements
- **Metadata Association**: Proper linking of resources with their metadata

### Deployment Controls
- **Granular Solution Management**: Control which solutions to deploy, update, or skip
- **Rule Severity Filtering**: Deploy only rules matching specified severities
- **Workbook Deployment Options**: Control whether to update or redeploy existing workbooks

### Error Resilience
- **Graceful Error Handling**: Skip problematic resources rather than failing the entire deployment
- **Status Reporting**: Clear, color-coded status summaries for all resource types
- **Detailed Logging**: Informative messages for tracking deployment progress

### Azure Government Support
- **Cloud Environment Detection**: Support for both Azure Commercial and Azure Government clouds

## Parameter Reference

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ResourceGroup` | string | Yes | - | Azure Resource Group containing the Sentinel workspace |
| `Workspace` | string | Yes | - | Microsoft Sentinel workspace name |
| `Region` | string | Yes | - | Azure region for deployments |
| `Solutions` | string[] | Yes | - | Array of solution names to deploy |
| `SeveritiesToInclude` | string[] | No | `@("High", "Medium", "Low")` | Analytics rule severities to include |
| `IsGov` | string | No | `"false"` | Set to 'true' for Azure Government cloud |
| `ForceSolutionUpdate` | switch | No | `$false` | Force update of already installed solutions |
| `ForceRuleDeployment` | switch | No | `$false` | Force deployment of rules for already installed solutions |
| `SkipSolutionUpdates` | switch | No | `$false` | Skip updating solutions that need updates |
| `SkipRuleUpdates` | switch | No | `$false` | Skip updating analytics rules that need updates |
| `SkipRuleDeployment` | switch | No | `$false` | Skip deploying analytics rules entirely |
| `SkipWorkbookDeployment` | switch | No | `$false` | Skip deploying workbooks entirely |
| `ForceWorkbookDeployment` | switch | No | `$false` | Force redeployment of existing workbooks |

## Usage Examples

### Basic Usage
```powershell
.\Set-SentinelContent.ps1 `
    -ResourceGroup "Security-RG" `
    -Workspace "MySentinelWorkspace" `
    -Region "EastUS" `
    -Solutions "Microsoft 365","Threat Intelligence" `
    -SeveritiesToInclude "High","Medium"
```

### Advanced Usage (Controlling Updates)
```powershell
.\Set-SentinelContent.ps1 `
    -ResourceGroup "Security-RG" `
    -Workspace "MySentinelWorkspace" `
    -Region "EastUS" `
    -Solutions "Microsoft 365","Threat Intelligence","Windows Security Events" `
    -SeveritiesToInclude "High","Medium","Low" `
    -ForceSolutionUpdate `
    -SkipRuleUpdates `
    -ForceWorkbookDeployment
```

### Deployment in Azure Government
```powershell
.\Set-SentinelContent.ps1 `
    -ResourceGroup "Security-RG" `
    -Workspace "GovSentinelWorkspace" `
    -Region "USGovVirginia" `
    -Solutions "Microsoft 365","Azure Activity" `
    -IsGov "true"
```

### CI/CD Pipeline Example (Azure DevOps)
```yaml
variables:
  azureSubscription: 'SentinelDeployment'
  resourceGroup: 'Sentinel-RG'
  workspaceName: 'SentinelWorkspace'
  region: 'eastus'
  solutions: '"Microsoft 365","Azure Activity","Threat Intelligence"'
  severities: '"High","Medium","Low"'

jobs:
  - job: DeploySentinel
    displayName: 'Deploy Sentinel Resources'
    steps:
      - task: AzurePowerShell@5
        displayName: 'Deploy Sentinel Solutions and Rules'
        inputs:
          azureSubscription: $(azureSubscription)
          ScriptType: 'FilePath'
          ScriptPath: './Set-SentinelContent.ps1'
          ScriptArguments: >
            -ResourceGroup '$(resourceGroup)' 
            -Workspace '$(workspaceName)' 
            -Region '$(region)' 
            -Solutions $(solutions) 
            -SeveritiesToInclude $(severities) 
          azurePowerShellVersion: 'LatestVersion'
```

## Tested Solutions

The script has been tested with the following Microsoft Sentinel solutions:

- Azure Activity
- Azure Key Vault
- Azure Logic Apps
- Azure Network Security Groups
- Microsoft 365
- Microsoft Defender for Cloud
- Microsoft Defender for Cloud Apps
- Microsoft Defender for Endpoint
- Microsoft Defender for Identity
- Microsoft Defender Threat Intelligence
- Microsoft Defender XDR
- Microsoft Entra ID
- Microsoft Purview Insider Risk Management
- Syslog
- Threat Intelligence
- Windows Security Events
- Windows Server DNS

## Known Limitations

- Solutions requiring specific permissions or prerequisites may need additional configuration
- Analytics rules referencing tables/columns not present in your environment will be skipped
- Deprecated rules are skipped by design to prevent deploying outdated content
- Authentication context is required before running the script (Connect-AzAccount or equivalent)
- Some workbooks may have dependencies on specific data sources being configured

## How It Works

The script follows a structured deployment process:

1. **Authentication and Setup**:
   - Validates Azure authentication
   - Sets up the environment based on parameters
   - Determines the appropriate API endpoints for Commercial or Government cloud

2. **Solution Deployment**:
   - Retrieves available solutions from the Content Hub
   - Checks which solutions are installed vs. need installation
   - Deploys or updates solutions based on parameters

3. **Analytics Rule Deployment**:
   - Fetches rule templates for deployed solutions
   - Filters rules by severity
   - Checks rule status using the testing framework
   - Deploys missing rules and updates outdated ones

4. **Workbook Deployment**:
   - Retrieves workbook templates for deployed solutions
   - Tests workbook status using the testing framework
   - Deploys, updates, or skips workbooks based on parameters

5. **Status Reporting**:
   - Provides detailed deployment summaries for each resource type
   - Color-codes output for easy status identification

## Conclusion

This Microsoft Sentinel deployment script provides a reliable, efficient, and flexible way to automate the deployment of Sentinel resources. With its comprehensive approach to handling solutions, rules, and workbooks, it significantly reduces the manual effort required to set up and maintain a Sentinel environment, while providing granular control over the deployment process.
