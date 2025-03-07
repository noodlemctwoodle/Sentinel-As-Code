# Sentinel-Deployment-CI

## Overview

This repository contains the necessary scripts and templates to deploy Microsoft Sentinel infrastructure and configure alert rules using Azure DevOps CI/CD pipelines. The deployment process leverages both Bicep templates for infrastructure provisioning and PowerShell scripts for deploying Sentinel solutions and analytical rules.

## Repository Structure

- **azure-pipelines.yml**: Azure DevOps pipeline configuration file.
- **Deployment/**: Directory containing Bicep templates for deploying resources.
  - **main.bicep**: Main Bicep template for deploying the resource group and Sentinel.
  - **sentinel.bicep**: Bicep template for deploying the Log Analytics workspace and enabling Microsoft Sentinel.
- **DeploymentScripts/**: Directory containing PowerShell scripts for additional configurations.
  - **Create-SentinelSolutions.ps1**: Script to deploy Sentinel solutions and configure alert rules.
- **README.md**: This file.

## Prerequisites

- Azure subscription with appropriate permissions.
- Azure DevOps account.
- Service Principal for Azure authentication.

## Setup Instructions

1. Clone this repository to your local machine.
2. Update the **azure-pipelines.yml** file with your Azure subscription details and resource names.
3. Commit and push your changes to the repository.

## Pipeline Variables

The following variables can be set in your Azure DevOps pipeline. The example values below correspond to the hardcoded values used in the pipeline snippet provided later.

| Variable Name         | Example Value                       | Description                                                                                         |
|-----------------------|-------------------------------------|-----------------------------------------------------------------------------------------------------|
| **arSeverities**      | `"High","Medium","Low"`             | List of severities to include when deploying analytical rules.                                      |
| **clientId**          | `00000000-0000-0000-0000-000000000000`| The Azure AD App (Service Principal) Client ID.                                                   |
| **clientSecret**      | `************`                      | The secret key for your Service Principal.                                                        |
| **dailyQuota**        | `10`                                | Daily ingestion quota (used by some scripts or environment settings, if applicable).                |
| **region**            | `uksouth`                           | Azure region in which the Sentinel workspace is located.                                           |
| **resourceGroup**     | `ResourceGroupName`                 | The name of the Resource Group that contains (or will contain) the Sentinel workspace.              |
| **sentinelSolutions** | `"Azure Activity","Azure Key Vault","Azure Logic Apps"` | A list of Sentinel solutions to deploy from the Content Hub.                          |
| **tenantId**          | `00000000-0000-0000-0000-000000000000`| The Azure AD tenant ID where Sentinel is hosted.                                                   |
| **workspaceName**     | `LogAnalyticsWorkspaceName`         | The name of the Sentinel workspace to which solutions and rules are deployed.                      |

## Pipeline Stages

### DeployBicep

This stage deploys the Microsoft Sentinel infrastructure using Bicep templates.

### EnableSentinelContentHub

This stage enables Sentinel solutions and configures alert rules. It runs only if the **DeployBicep** stage succeeds.

#### Pipeline Code

```yaml
trigger:
- main  # Change this to your branch name

pool:
  vmImage: 'ubuntu-latest'

variables:
  azureSubscription: 'MSSPSentinelDeployments'

# =============================================================================
# Stage: DeployBicep
# This stage deploys the Microsoft Sentinel infrastructure via a Bicep template.
# =============================================================================
stages:
  - stage: DeployBicep
    displayName: 'Deploy Microsoft Sentinel Infrastructure via Bicep'
    jobs:
      - job: DeploySentinelResources
        displayName: 'Deploy Microsoft Sentinel Resources'
        steps:
          - task: AzureCLI@2
            displayName: 'Deploy Sentinel Infrastructure with Bicep Template'
            name: DeployBicepTask
            inputs:
              azureSubscription: $(azureSubscription)
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                echo "Starting Bicep Deployment..."
                az deployment sub create \
                  --location '$(REGION)' \
                  --template-file Deployment/main.bicep \
                  --parameters Deployment/main.bicepparam \
                  --parameters rgLocation='$(REGION)' rgName='$(RESOURCEGROUP)' lawName='$(WORKSPACENAME)' dailyQuota='$(DAILYQUOTA)'

# =============================================================================
# Stage: EnableSentinelContentHub
# This stage enables Sentinel solutions and configures alert rules.
# It is executed only if the previous stage succeeds.
# =============================================================================
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

## Running the Pipeline

1. Navigate to your Azure DevOps project.
2. Create a new pipeline and select this repository.
3. Run the pipeline to deploy the Sentinel infrastructure and configure alert rules.

## Troubleshooting

- Ensure that the Service Principal has the necessary permissions to deploy resources.
- Verify that the Azure subscription, resource group, and workspace names are correct.
- Check the pipeline logs for any errors and address them as needed.

### Contributing

Contributions are welcome! Please submit a pull request with your changes.

### License

This project is licensed under the MIT License.
