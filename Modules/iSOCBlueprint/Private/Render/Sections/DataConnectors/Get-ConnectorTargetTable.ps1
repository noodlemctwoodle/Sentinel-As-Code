#Requires -Version 7.6

<#
.SYNOPSIS
    Name the table a connector kind and data type writes to.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataConnectors/Get-ConnectorTargetTable.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-ConnectorTargetTable {
    <#
    .SYNOPSIS
        Name the table a connector kind and data type writes to.

    .DESCRIPTION
        Maps (Kind, dataType) to the Log Analytics table the connector writes to.
        Returns $null when no known mapping exists; the renderer then leaves the
        activity columns blank for that data type rather than guessing wrong.

    .PARAMETER Kind
        The connector kind.

    .PARAMETER DataType
        The data type name, matched without regard to case.

    .OUTPUTS
        [string], or $null.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param([string]$Kind, [string]$DataType)
    $dt = if ($DataType) { $DataType.ToLowerInvariant() } else { '' }
    switch ("$Kind/$dt") {
        'Office365/sharepoint' { 'OfficeActivity' }
        'Office365/exchange' { 'OfficeActivity' }
        'Office365/teams' { 'OfficeActivity' }
        'AzureActiveDirectory/signinlogs' { 'SigninLogs' }
        'AzureActiveDirectory/auditlogs' { 'AuditLogs' }
        'AzureActiveDirectory/noninteractiveusersigninlogs' { 'AADNonInteractiveUserSignInLogs' }
        'MicrosoftCloudAppSecurity/alerts' { 'SecurityAlert' }
        'MicrosoftCloudAppSecurity/discoverylogs' { 'McasShadowItReporting' }
        'MicrosoftDefenderAdvancedThreatProtection/alerts' { 'SecurityAlert' }
        'MicrosoftThreatProtection/alerts' { 'SecurityAlert' }
        'MicrosoftThreatProtection/incidents' { 'SecurityIncident' }
        'MicrosoftThreatIntelligence/microsoftemergingthreatfeed' { 'ThreatIntelligenceIndicator' }
        'MicrosoftPurviewInformationProtection/logs' { 'InformationProtectionLogs_CL' }
        'AzureSecurityCenter/alerts' { 'SecurityAlert' }
        default { $null }
    }
}
