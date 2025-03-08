# Sentinel-Deployment-CI

## Overview

This repository provides a complete CI/CD solution for deploying Microsoft Sentinel environments using Azure DevOps pipelines. It combines infrastructure-as-code (Bicep) for resource provisioning with PowerShell automation for deploying Sentinel solutions, analytics rules, and workbooks.

## Repository Structure

```
├── Bicep/                   # Bicep templates for infrastructure
│   ├── main.bicep           # Main deployment template
│   └── sentinel.bicep       # Sentinel-specific resources
├── Scripts/                 # PowerShell automation scripts
│   ├── README.md            # Documentation for Set-SentinelContent.ps1
│   └── Set-SentinelContent.ps1  # Sentinel content deployment script
├── README.md                # This file
└── azure-pipelines.yml      # Azure DevOps pipeline definition
```

## Features

- **Complete Sentinel Deployment**: Automate end-to-end deployment from infrastructure to content
- **Infrastructure as Code**: Bicep templates for consistent infrastructure provisioning
- **Content Automation**: PowerShell scripts for deploying Sentinel solutions, rules, and workbooks
- **Resource Verification**: Checks for existing resources to prevent duplicate deployments
- **CI/CD Integration**: Ready-to-use Azure DevOps pipeline configuration

## Pipeline Workflow

The pipeline consists of three main stages:

1. **Check Existing Resources**: Verifies if Sentinel resources already exist in the target environment
2. **Deploy Bicep**: Provisions infrastructure (skipped if resources already exist)
3. **Enable Sentinel Content**: Deploys solutions, analytics rules, and workbooks

## Pipeline Variables

| Variable Name | Description |
|---------------|-------------|
| `resourceGroup` | Azure Resource Group name |
| `workspaceName` | Log Analytics workspace name |
| `region` | Azure region (e.g., uksouth) |
| `dailyQuota` | Daily data ingestion quota in GB |
| `sentinelSolutions` | Comma-separated list of Sentinel solutions to deploy |
| `arSeverities` | Severity levels for analytics rules (High, Medium, Low, Informational) |

## Setup Instructions

### Prerequisites
- Azure subscription
- Azure DevOps organization and project
- Service Principal with contributor permissions

### Configuration Steps

1. **Import Repository**
   - Clone or import this repository into your Azure DevOps project

2. **Configure Pipeline Variables**
   - Create a pipeline with the following variables:
     ```
     resourceGroup: "YourResourceGroupName"
     workspaceName: "YourWorkspaceName"
     region: "YourAzureRegion"
     dailyQuota: "10"
     sentinelSolutions: "Azure Activity","Microsoft 365","Threat Intelligence"
     arSeverities: "High","Medium","Low"
     ```

3. **Set Up Service Connection**
   - Create an Azure service connection named "DevelopmentDeployments" 
   - Or update the `azureSubscription` variable in the pipeline YAML

4. **Run the Pipeline**
   - The pipeline will automatically:
     - Check for existing resources
     - Deploy infrastructure if needed
     - Deploy Sentinel solutions and content

## Sentinel Content Deployment Script

The `Set-SentinelContent.ps1` script handles the deployment of Microsoft Sentinel content including solutions, analytics rules, and workbooks. For detailed information about the script's capabilities, parameters, and examples, refer to the [script README](./Scripts/README.md).

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License.
