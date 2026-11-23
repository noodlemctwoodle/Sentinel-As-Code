#Requires -Version 7.6

<#
.SYNOPSIS
    The Defender XDR custom detection content type: where the files live,
    how they reach Microsoft Graph and how they are compared.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Get-iSOCDefenderDetectionDefinition.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Docs/Modules/iSOCDeployments/Architecture.md describes every key of a
    content type definition.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCDefenderDetectionDefinition {
    <#
    .SYNOPSIS
        Return the Defender XDR custom detection definition.

    .DESCRIPTION
        Detections are YAML files anywhere under
        Content/DefenderCustomDetections/, one rule per file, written in the
        Graph detectionRule shape in place since 2026-10-01. They are sent
        to the Graph beta detectionRules collection for the tenant, last of
        every type, as Deploy-DefenderDetections.ps1 ran after the content
        stage. A rule is matched to the tenant's rules by its display name:
        updated in place when one exists, created with the file's id when
        none does. Nothing is checked against dependencies.json, as before.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCDefenderDetectionDefinition
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Name              = 'DefenderDetection'
        DisplayName       = 'Defender XDR custom detections'
        RepoFolder        = 'Content/DefenderCustomDetections'
        Layout            = 'File'
        Format            = 'Yaml'
        FilePattern       = @('*.yaml', '*.yml')
        Recurse           = $true
        Endpoint          = 'Graph'
        Scope             = 'Tenant'
        CollectionPath    = '/security/rules/detectionRules'
        ApiVersion        = 'GraphSecurity'
        IdentityKey       = 'displayName'
        DeployOrder       = 90
        SettleSeconds     = 0
        MissingDependency = 'Deploy'
        Capabilities      = @('Deploy')
        Prerequisites     = @('powershell-yaml')
        Handlers          = @{
            ReadRepo  = 'Read-iSOCDefenderDetectionRepo'
            Validate  = 'Test-iSOCDefenderDetection'
            ToRequest = 'ConvertTo-iSOCDefenderDetectionRequest'
            Deploy    = 'Invoke-iSOCDefenderDetectionDeploy'
        }
        Fields            = @(
            @{ Name = 'displayName'; Comparer = 'Exact' }
            @{ Name = 'status'; Comparer = 'CaseInsensitive' }
            @{ Name = 'queryCondition.queryText'; Comparer = 'Whitespace' }
            @{ Name = 'schedule.frequency'; Comparer = 'Duration' }
            @{ Name = 'detectionAction.alertTemplate.title'; Comparer = 'Exact' }
            @{ Name = 'detectionAction.alertTemplate.severity'; Comparer = 'CaseInsensitive' }
        )
    }
}
