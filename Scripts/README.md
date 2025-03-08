# Sentinel Deployment Automation

## Overview

This script automates the deployment of Microsoft Sentinel solutions, analytical rules, and workbooks within an Azure environment. It simplifies the process of configuring and enabling security solutions, reducing manual effort and ensuring consistent deployments across environments.

## Features

- **Automated Deployment of Solutions**: Retrieves and deploys Microsoft Sentinel solutions from the Content Hub.  
- **Automated Deployment of Analytics Rules**: Deploys analytics rules based on severity and ensures proper configuration.
- **Automated Deployment of Workbooks**: Deploys associated workbooks for each solution.
- **Consolidated Status Testing**: Unified mechanism for checking status of all resource types.
- **Intelligent Update Management**: Granular control over which resources to update vs. skip.
- **Error Handling and Logging**: Catches and handles API errors gracefully with detailed status reporting.
- **Metadata Association**: Links deployed solutions, rules, and workbooks with their metadata for better tracking.
- **Professional Documentation**: Comment-based help for all functions supporting PowerShell Get-Help.

## What's New in This Version

### Core Architecture Improvements

- **Consolidated Testing Framework**: New `Test-SentinelResource` function provides consistent status testing for solutions, rules, and workbooks.
- **Improved Parameter Management**: Logical parameter grouping and clear documentation.
- **Professional Code Documentation**: Added comment-based help for all functions supporting PowerShell Get-Help.
- **Consistent Terminology**: Standardized naming across the codebase (Analytics vs Analytical).

### Enhanced Controls

- **Granular Update Control**: 
  - New `ForceSolutionUpdate` parameter to explicitly control solution updates
  - Renamed `SkipExistingWorkbooks` to `DeployExistingWorkbooks` for intuitive behavior
  - Fixed switch parameter handling to follow PowerShell best practices

- **Standardized Status Reporting**:
  - Consistent summary format across solutions, rules, and workbooks
  - Clear color coding for different status types (installed, updated, skipped, failed)

### Improved Workbook Management

- **Proper Workbook Update Handling**: Better management of workbook updates with proper error handling
- **Enhanced Workbook Error Handling**: Proper status checking for workbook and metadata deletion operations
- **Workbook Deployment Controls**: Options to force redeployment of existing workbooks

### Solution Deployment Improvements

- **Fixed Force Update Behavior**: Solutions are only updated when explicitly requested
- **Better Status Tracking**: More accurate status reporting for solutions
- **Improved Error Handling**: More detailed error messages and status checks

### Analytics Rule Enhancements

- **Clear Resource Type Distinction**: Clear separation between deployed rules and rule templates
- **Consistent Status Reporting**: Standardized status messages across all rule operations
- **Improved Rule Processing**: Better handling of special cases and errors

## New Features & Fixes vs. Previous Version

| Feature / Fix                                     | Previous Behavior                        | Current Behavior                                                  |
|---------------------------------------------------|------------------------------------------|-------------------------------------------------------------------|
| **Solution update control**                       | Ambiguous, force updates by default     | Explicit control with `ForceSolutionUpdate` parameter              |
| **Workbook deployment naming**                    | Confusing use of `SkipExistingWorkbooks`| Intuitive `DeployExistingWorkbooks` parameter                     |
| **Resource status checking**                      | Separate functions for each resource    | Unified `Test-SentinelResource` for all resource types            |
| **Workbook deletion handling**                    | No status checking                      | Proper error handling and status reporting                         |
| **Status reporting**                              | Inconsistent formats                    | Standardized summary format across all resource types              |
| **Code documentation**                            | Basic comments                          | Professional comment-based help for all functions                  |
| **Parameter descriptions**                        | Basic descriptions                      | Detailed parameter documentation and alignment                     |
| **Resource type naming**                          | Mixed Analytics/Analytical terminology  | Consistent terminology throughout codebase                         |

### Tested with these Solutions

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

```powershell
"Azure Activity","Azure Key Vault","Azure Logic Apps","Azure Network Security Groups","Microsoft 365","Microsoft Defender for Cloud","Microsoft Defender for Cloud Apps","Microsoft Defender for Endpoint","Microsoft Defender for Identity","Microsoft Defender Threat Intelligence","Microsoft Defender XDR","Microsoft Entra ID","Microsoft Purview Insider Risk Management","Syslog","Threat Intelligence","Windows Security Events","Windows Server DNS"
```

## Pipeline Variables

| Variable Name         | Example Value                                                          | Description                                                                                         |
|-----------------------|------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| **resourceGroup**     | `ResourceGroupName`                                                    | The name of the Resource Group that contains (or will contain) the Sentinel workspace.              |
| **workspaceName**     | `LogAnalyticsWorkspaceName`                                            | The name of the Sentinel workspace to which solutions and rules are deployed.                       |
| **resourceGroup**     | `ResourceGroupName`                                                    | The name of the Resource Group that contains (or will contain) the Sentinel workspace.              |
| **sentinelSolutions** | `"Azure Activity","Azure Key Vault","Azure Logic Apps","..."`          | A list of Sentinel solutions to deploy from the Content Hub.                                        |
| **arSeverities**      | `"High","Medium","Low","Informational"`                                | List of severities to include when deploying analytics rules.                                       |


### Example Usage in YAML

```yaml
variables:
  azureSubscription: 'MSSPSentinelDeployments'

stages:
  - stage: EnableSentinelContentHub
    displayName: 'Enable Sentinel Solutions and Configure Alert Rules'
    dependsOn: DeployBicep
    condition: succeeded()
    jobs:
      - job: EnableContentHub
        displayName: 'Enable Sentinel Solutions and Alert Rules'
        steps:
          - task: AzurePowerShell@5
            continueOnError: true
            inputs:
              azureSubscription: $(azureSubscription)
              ScriptType: 'FilePath'
              ScriptPath: '$(Build.SourcesDirectory)/Scripts/Set-SentinelContent.ps1'
              ScriptArguments: >
                -ResourceGroup '$(RESOURCEGROUP)' 
                -Workspace '$(WORKSPACENAME)' 
                -Region '$(REGION)' 
                -Solutions $(SENTINELSOLUTIONS) 
                -SeveritiesToInclude $(ARSEVERITIES) 
                -IsGov 'false'
              azurePowerShellVersion: 'LatestVersion'
            displayName: "Sentinel Solution Deployment"
```

### How to Use the Script Locally

1. Ensure you have the necessary Azure permissions to deploy Sentinel solutions and rules.
2. Run the script with the required parameters:

    ```powershell
    .\Set-SentinelContent.ps1 `
        -ResourceGroup "Security-RG" `
        -Workspace "MySentinelWorkspace" `
        -Region "EastUS" `
        -Solutions "Syslog","Threat Intelligence" `
        -SeveritiesToInclude "High","Medium","Low"
    ```

3. The script will:
   - Fetch available Sentinel solutions and deploy them
   - Deploy associated analytics rules for each solution based on selected severities
   - Deploy workbooks that complement the solutions
   - Handle errors gracefully with detailed status reporting

### Advanced Parameter Usage

For more granular control, you can use these additional parameters:

```powershell
.\Set-SentinelContent.ps1 `
    -ResourceGroup "Security-RG" `
    -Workspace "MySentinelWorkspace" `
    -Region "EastUS" `
    -Solutions "Syslog","Threat Intelligence" `
    -SeveritiesToInclude "High","Medium","Low" `
    -ForceSolutionUpdate `            # Force update of already installed solutions
    -SkipSolutionUpdates `            # Skip solutions that need updates
    -ForceRuleDeployment `            # Deploy rules for already installed solutions
    -SkipRuleUpdates `                # Skip rule updates
    -ForceWorkbookDeployment          # Force redeployment of existing workbooks
```

## Known Limitations

- Some solutions may require additional permissions to deploy.
- If a rule depends on a missing table or column, it will be skipped with a warning.
- Deprecated rules will not be deployed.
- Ensure that the necessary Azure authentication is in place before execution.

## Conclusion

The updated Sentinel deployment script is now more reliable, efficient, and resilient. With improved code organization, better error handling, and a consistent status reporting framework, it provides a smoother deployment experience across various environments. The script follows PowerShell best practices with professional documentation and intuitive parameter naming.

🚀 Upgrade now and streamline your Sentinel deployments!
