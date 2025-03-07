# Sentinel Deployment Automation

## Overview

This script automates the deployment of Microsoft Sentinel solutions and analytical rules within an Azure environment. It simplifies the process of configuring and enabling security solutions, reducing manual effort and ensuring consistent deployments across environments.

## Features

- **Automated Deployment of Solutions**: Retrieves and deploys Microsoft Sentinel solutions from the Content Hub.  
- **Automated Deployment of Analytical Rules**: Deploys analytical rules based on severity and ensures proper configuration.  
- **Error Handling and Logging**: Catches and handles API errors, missing tables, or deprecated rules gracefully.  
- **Metadata Association**: Links deployed solutions and rules with their respective metadata for better tracking.  
- **Pipeline-Friendly Output**: Removes unnecessary console noise while preserving relevant error and status messages.

## What's New in This Version

### General Enhancements

- **Optimized API Calls**: Ensured correct `api-version` parameters are included to prevent errors.
- **Refined Logging**: Removed unnecessary console output, making logs pipeline-friendly.
- **Improved Debugging Messages**: Key changes and fixes are logged for troubleshooting.

### Solution Deployment Improvements

- **Parallel Execution**: Solutions are deployed in parallel to improve efficiency.
- **Dynamic Resource Handling**: Automatically processes packaged content for seamless deployments.
- **Error Handling**: Solutions not found in the Content Hub are skipped with a warning instead of failing the script.

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

"Azure Activity","Azure Key Vault","Azure Logic Apps","Azure Network Security Groups","Microsoft 365","Microsoft Defender for Cloud","Microsoft Defender for Cloud Apps","Microsoft Defender for Endpoint","Microsoft Defender for Identity","Microsoft Defender Threat Intelligence","Microsoft Defender XDR","Microsoft Entra ID","Microsoft Purview Insider Risk Management","Syslog","Threat Intelligence","Windows Security Events","Windows Server DNS"

### Analytical Rule Enhancements

- **Deprecated Rules Handling**: Deprecated rules are skipped with a warning message.
- **Fix for Missing `groupingConfiguration` Fields**: Default values are applied when missing.
- **Lookback Duration Format Fix**: Converted `h/d/m` durations to ISO 8601 format (`PT1H`, `P1D`, etc.).
- **Better Error Handling for Missing Tables/Columns**: Rules failing due to missing tables or columns are skipped with an appropriate message instead of breaking the script.
- **Semantic Error Handling**: Rules with invalid KQL expressions are skipped with a clear message.
- **Metadata Updates**: Sources for rules are now linked correctly to their respective Sentinel solutions.

## New Features & Fixes vs. Sentinel-All-In-One

| Feature / Fix                                     | Old Script Behaviour                        | Updated Script Behaviour                                           |
|---------------------------------------------------|--------------------------------------------|---------------------------------------------------------------------|
| **Handles deprecated rules**                      | Causes failure                             | Skips and logs a warning                                            |
| **Handles missing tables in rules**               | Causes failure                             | Skips and logs a warning                                            |
| **Handles missing columns in rules**              | Causes failure                             | Skips and logs a warning                                            |
| **Handles invalid expressions**                   | Causes failure                             | Skips and logs a warning                                            |
| **Fixes missing `matchingMethod`**                | Causes API validation failure              | Ensures `matchingMethod='AllEntities'`                              |
| **Fixes incorrect `lookbackDuration` format**     | Causes API validation failure              | Converts to ISO 8601 format                                         |
| **Extracts correct metadata for rules**           | Displays `Unknown Source`                  | Extracts actual solution details                                    |
| **Reduces console noise**                         | Excessive debug output                     | Cleaner, structured logs                                           |

## Known Limitations

- Some solutions may require additional permissions to deploy.
- If a rule depends on a missing table or column, it will be skipped with a warning.
- Deprecated rules will not be deployed.
- Ensure that the necessary Azure authentication is in place before execution.

## Pipeline Variables

Below are the pipeline variables shown in the attached image and how they might be used:

| Variable Name         | Example Value                                                          | Description                                                                                         |
|-----------------------|------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| **arSeverities**      | `"High","Medium","Low"`                                                | List of severities to include when deploying analytical rules.                                      |
| **clientId**          | `00000000-0000-0000-0000-000000000000`                                | The Azure AD App (Service Principal) Client ID.                                                      |
| **clientSecret**      | `************`                                                         | The secret key for your Service Principal.                                                           |
| **dailyQuota**        | `10`                                                                   | Daily ingestion quota (used by some scripts or environment settings, if applicable).                 |
| **region**            | `uksouth`                                                              | Azure region in which the Sentinel workspace is located.                                            |
| **resourceGroup**     | `ResourceGroupName`                                                       | The name of the Resource Group that contains (or will contain) the Sentinel workspace.               |
| **sentinelSolutions** | `"Azure Activity","Azure Key Vault","Azure Logic Apps","..."`          | A list of Sentinel solutions to deploy from the Content Hub.                                         |
| **tenantId**          | `00000000-0000-0000-0000-000000000000`                                | The Azure AD tenant ID where Sentinel is hosted.                                                     |
| **workspaceName**     | `LogAnalyticsWorkspaceName`                                                    | The name of the Sentinel workspace to which solutions and rules are deployed.                        |

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
              ScriptPath: '$(Build.SourcesDirectory)/DeploymentScripts/Create-SentinelSolutions.ps1'
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

    ```Powershell
    .\Create-SentinelSolutions.ps1 `
        -ResourceGroup "Security-RG" `
        -Workspace "MySentinelWorkspace" `
        -Region "EastUS" `
        -Solutions "Syslog","Threat Intelligence" `
        -SeveritiesToInclude "High","Medium","Low"
    ```

3. The script will:

- Fetch available Sentinel solutions and deploy them.
- Fetch and deploy analytical rules based on selected severities.
- Handle missing dependencies gracefully.
- Log relevant information while skipping problematic rules.

## Conclusion

The updated Sentinel deployment script is now more reliable, efficient, and resilient. It can handle missing components, deprecated rules, and data structure inconsistencies, ensuring a smoother deployment experience in various environments.

🚀 Upgrade now and streamline your Sentinel deployments!
