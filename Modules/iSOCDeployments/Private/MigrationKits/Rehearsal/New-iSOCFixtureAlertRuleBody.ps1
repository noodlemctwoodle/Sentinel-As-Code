#Requires -Version 7.6

<#
.SYNOPSIS
    Build the PUT body of a dependency fixture analytics rule.

.DESCRIPTION
    A Scheduled rule at Informational severity, incidents off, disabled
    unless asked; the clamp in its query keeps it from returning rows.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCFixtureAlertRuleBody.ps1
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

function New-iSOCFixtureAlertRuleBody {
    <#
    .SYNOPSIS
        Build the PUT body of a dependency fixture analytics rule.

    .DESCRIPTION
        A Scheduled rule with every required property, suppressionDuration
        and suppressionEnabled included (leaving either out is a 400, the
        duration even when suppression is off), and ISO 8601 durations.
        Informational severity, incident creation off and, with the query's
        zero-row clamp, nothing a fixture rule does can page anyone even if
        it is enabled by hand.

    .PARAMETER DisplayName
        The rule's display name.

    .PARAMETER Description
        Its description, from New-iSOCFixtureDescription.

    .PARAMETER Query
        Its KQL.

    .PARAMETER Enabled
        Whether it is enabled. Default no.

    .PARAMETER QueryFrequency
        Default PT24H.

    .PARAMETER QueryPeriod
        Default PT24H.

    .PARAMETER Severity
        Default Informational.

    .OUTPUTS
        [hashtable]

    .EXAMPLE
        New-iSOCFixtureAlertRuleBody -DisplayName $name -Description $description -Query $query
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a request body; changes nothing.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $DisplayName,

        [Parameter(Mandatory)]
        [string] $Description,

        [Parameter(Mandatory)]
        [string] $Query,

        [bool] $Enabled = $false,

        [string] $QueryFrequency = 'PT24H',

        [string] $QueryPeriod = 'PT24H',

        [string] $Severity = 'Informational'
    )

    [ordered]@{
        kind       = 'Scheduled'
        properties = [ordered]@{
            displayName           = $DisplayName
            description           = $Description
            severity              = $Severity
            enabled               = $Enabled
            query                 = $Query
            queryFrequency        = $QueryFrequency
            queryPeriod           = $QueryPeriod
            triggerOperator       = 'GreaterThan'
            triggerThreshold      = 0
            suppressionDuration   = 'PT1H'
            suppressionEnabled    = $false
            eventGroupingSettings = [ordered]@{ aggregationKind = 'SingleAlert' }
            incidentConfiguration = [ordered]@{
                createIncident        = $false
                groupingConfiguration = [ordered]@{
                    enabled              = $false
                    reopenClosedIncident = $false
                    lookbackDuration     = 'PT5H'
                    matchingMethod       = 'AllEntities'
                }
            }
        }
    }
}
