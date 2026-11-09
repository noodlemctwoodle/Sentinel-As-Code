#Requires -Version 7.6

<#
.SYNOPSIS
    The dependency fixture's fixed names: its marker, tags, marker column, rule id namespace, query clamp, scenarios and reserved table floor.

.DESCRIPTION
    Constant across prefixes: the prefix says which fixture an object belongs
    to, the marker that it is a fixture at all.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCDependencyFixtureSetting.ps1
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

function Get-iSOCDependencyFixtureSetting {
    <#
    .SYNOPSIS
        The dependency fixture's fixed names: its marker, tags, marker
        column, rule id namespace, query clamp, scenarios and reserved table
        floor.

    .DESCRIPTION
        The same values as Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1
        uses, so a fixture made by either is recognised and removed by the
        other:

          FixtureMarker      ClassicToDcr-DependencyFixture, the same for
                             every prefix: the prefix says which fixture, the
                             marker that it is one; a prefix alone never
                             justifies a delete
          FixtureTagName,    the saved search tags (SacFixture,
          FixtureRunTag,     SacFixtureRun, SacFixtureScenario)
          FixtureScenTag
          MarkerFieldName,   the field every record carries and the column it
          MarkerColumnName   becomes, the only marker a table can hold
          RuleIdNamespace    folded into the rule ids, so ownership is
                             recomputed rather than pattern matched
          QueryClamp         '| where 1 == 0', appended to every rule query,
                             so a rule enabled by hand still returns no rows
          ScenarioOrder      the create order
          ReservedTableFloor table names no alias may take, whatever the
                             workspace and the mapping say

    .OUTPUTS
        [hashtable]

    .EXAMPLE
        (Get-iSOCDependencyFixtureSetting).FixtureMarker
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        FixtureMarker      = 'ClassicToDcr-DependencyFixture'
        FixtureTagName     = 'SacFixture'
        FixtureRunTag      = 'SacFixtureRun'
        FixtureScenTag     = 'SacFixtureScenario'
        MarkerFieldName    = 'SacFixtureMarker'
        MarkerColumnName   = 'SacFixtureMarker_s'
        RuleIdNamespace    = 'Sentinel-As-Code/ClassicToDcr/DependencyFixture'
        QueryClamp         = '| where 1 == 0'
        ScenarioOrder      = @('Direct', 'OneHop', 'TwoHop', 'Cycle', 'Orphan', 'Hunt')
        ReservedTableFloor = @(
            'Alert', 'AlertEvidence', 'AlertInfo', 'AuditLogs', 'AzureActivity',
            'AzureDiagnostics', 'AzureMetrics', 'AADNonInteractiveUserSignInLogs',
            'AADServicePrincipalSignInLogs', 'CloudAppEvents', 'CommonSecurityLog',
            'ConfigurationData', 'ContainerLog', 'DeviceEvents', 'DeviceFileEvents',
            'DeviceImageLoadEvents', 'DeviceInfo', 'DeviceLogonEvents',
            'DeviceNetworkEvents', 'DeviceNetworkInfo', 'DeviceProcessEvents',
            'DeviceRegistryEvents', 'DeviceTvmSoftwareVulnerabilities', 'DnsEvents',
            'DnsInventory', 'EmailAttachmentInfo', 'EmailEvents',
            'EmailPostDeliveryEvents', 'EmailUrlInfo', 'Event', 'Heartbeat',
            'IdentityDirectoryEvents', 'IdentityInfo', 'IdentityLogonEvents',
            'IdentityQueryEvents', 'InsightsMetrics', 'KubeEvents', 'KubePodInventory',
            'LAQueryLogs', 'OfficeActivity', 'Operation', 'Perf', 'ProtectionStatus',
            'SecurityAlert', 'SecurityBaseline', 'SecurityEvent', 'SecurityIncident',
            'SentinelAudit', 'SentinelHealth', 'SigninLogs', 'Syslog',
            'ThreatIntelligenceIndicator', 'Update', 'UpdateSummary', 'Usage',
            'UrlClickEvents', 'W3CIISLog', 'Watchlist', 'WindowsEvent',
            'WindowsFirewall'
        )
    }
}
