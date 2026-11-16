#Requires -Version 7.2

<#
.SYNOPSIS
    Reads every analytic rule in the workspace.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Inventory/Get-SdlRuleInventory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SdlRuleInventory {
    <#
    .SYNOPSIS
        Reads every analytic rule in the workspace.

    .DESCRIPTION
        Lists the Sentinel alert rules and returns one row per rule
        with its name, kind, state, severity, MITRE mapping, schedule
        and query text.

    .PARAMETER Connection
        The connection object.

    .OUTPUTS
        [pscustomobject] One row per rule.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection
    )

    $path = "$(Get-SdlBaseUri -Connection $Connection)/providers/Microsoft.SecurityInsights/alertRules?api-version=$($Connection.AlertRulesApiVersion)"
    foreach ($rule in @(Get-SdlArmList -Connection $Connection -Path $path)) {
        $properties = Get-SdlPropertyValue -InputObject $rule -Name 'properties'
        $name = Get-SdlPropertyValue -InputObject $properties -Name 'displayName'
        $tactics = Get-SdlPropertyValue -InputObject $properties -Name 'tactics'
        $techniques = Get-SdlPropertyValue -InputObject $properties -Name 'techniques'
        [pscustomobject]@{
            RuleId         = $rule.name
            RuleName       = if ($name) { $name } else { $rule.name }
            Kind           = $rule.kind
            Enabled        = Get-SdlPropertyValue -InputObject $properties -Name 'enabled'
            Severity       = Get-SdlPropertyValue -InputObject $properties -Name 'severity'
            Tactics        = if ($tactics) { @($tactics) -join '; ' } else { '' }
            Techniques     = if ($techniques) { @($techniques) -join '; ' } else { '' }
            QueryFrequency = Get-SdlPropertyValue -InputObject $properties -Name 'queryFrequency'
            QueryPeriod    = Get-SdlPropertyValue -InputObject $properties -Name 'queryPeriod'
            LastModified   = Get-SdlPropertyValue -InputObject $properties -Name 'lastModifiedUtc'
            QueryText      = Get-SdlPropertyValue -InputObject $properties -Name 'query'
        }
    }
}
