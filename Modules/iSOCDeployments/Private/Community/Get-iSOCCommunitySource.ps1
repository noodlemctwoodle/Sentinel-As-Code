#Requires -Version 7.6

<#
.SYNOPSIS
    The community rule sources the module can import.

.DESCRIPTION
    Replaces the constants at the top of Tools/Import-CommunityRules.ps1: the attribution, the tags, the
    folder maps and the README text, which the script wrote for David Alonso's
    repository only. A source is a definition here, so another contributor is
    one more entry (MIGRATION.md edit E28).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Get-iSOCCommunitySource.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCCommunitySource {
    <#
    .SYNOPSIS
        Return a community source's definition, or every one.

    .DESCRIPTION
        A definition holds:
        - Name: what -Source takes, and the folder rules go to under
          Content/AnalyticalRules/Community/;
        - Repository and Branch: what is cloned;
        - Attribution: the paragraph put before every rule's description;
        - Tags: the tags every rule gets;
        - YamlFolders: source folder to category, for folders of YAML rules;
        - ArmFolders: source folder to category, for folders of ARM
          templates (imported with -IncludeKqlConversion);
        - Title, About and Licence: the README's heading and its
          attribution and licence sections.

    .PARAMETER Name
        The source, in any case. Without it every source is returned.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCCommunitySource -Name Dalonso
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $Name
    )

    $sources = [ordered]@{
        Dalonso = @{
            Name        = 'Dalonso'
            Repository  = 'https://github.com/davidalonsod/Dalonso-Security-Repo.git'
            Branch      = 'main'
            Attribution = "Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense.`n`n"
            Tags        = @('Community', 'Dalonso', 'ThreatHunting')
            YamlFolders = [ordered]@{
                'Use Cases Threat Hunting/SigninLogs-ThreatHunting'                          = 'SigninLogs'
                'Use Cases Threat Hunting/AadNonInteractiveUserSigninLogs/rules'             = 'NonInteractiveSigninLogs'
                'Use Cases Threat Hunting/ADFSSignInLogs/Sentinel-AnalyticRules-ADFS/rules' = 'ADFSSignInLogs'
                'Use Cases Threat Hunting/CommonSecurityLog-ThreatHunting'                   = 'CommonSecurityLog'
                'Use Cases Threat Hunting/DNSEvents/Analytic-Rules/rules'                    = 'DNSEvents'
            }
            ArmFolders  = [ordered]@{
                'Use Cases Threat Hunting/ADSecurityEvents/AnalyticRules'      = 'ADSecurityEvents'
                'Use Cases Threat Hunting/AzureCustomDetections/AnalyticRules' = 'AzureActivity'
                'Use Cases Threat Hunting/M365OfficeActivity/AnalyticRules'    = 'M365OfficeActivity'
                'Use Cases Threat Hunting/Non-Human_Identities_Detections'     = 'NonHumanIdentities'
            }
            Title       = 'David Alonso - Threat Hunting'
            About       = @(
                'These analytical rules were authored by **David Alonso** and sourced from the'
                '[Dalonso Security Repository](https://github.com/davidalonsod/Dalonso-Security-Repo).'
                'David maintains a comprehensive collection of Microsoft Sentinel threat-hunting'
                'detections across identity, endpoint, cloud, and network data sources.'
            )
            Licence     = @(
                'All rules in this directory are released under **The Unlicense** (public domain).'
                'You are free to use, modify, and distribute them without restriction.'
                'See [The Unlicense](https://unlicense.org) for full terms.'
            )
        }
    }

    if (-not $Name) { return @($sources.Values) }
    foreach ($key in $sources.Keys) {
        if ($key -ieq $Name) { return $sources[$key] }
    }
    throw "There is no community source '$Name'. The sources are: $(@($sources.Keys) -join ', ')."
}
