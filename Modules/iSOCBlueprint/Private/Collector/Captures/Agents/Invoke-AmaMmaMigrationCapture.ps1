#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'ama-mma-migration': writes ama-mma-migration.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Agents/Invoke-AmaMmaMigrationCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# AMA vs MMA migration status broken down by machine type. Categorises every
# machine that heartbeated in the last 7 days into Azure VM / VMSS / Arc-enabled
# / Hybrid-without-Arc / Containers / Other, and reports per-category counts
# plus the migration state (Not Started / In Progress / Completed) based on
# the presence of Direct Agent (MMA) vs Azure Monitor Agent records.
function Invoke-AmaMmaMigrationCapture {
    <#
    .SYNOPSIS
        Capture 'ama-mma-migration': writes ama-mma-migration.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    $kql = @'
Heartbeat
| where TimeGenerated > ago(lookback)
| summarize arg_max(TimeGenerated, *) by Category, Computer
| extend MachineType = case(
    ComputerEnvironment == "Non-Azure" and isempty(_ResourceId), "Hybrid without Arc",
    ResourceProvider == "Microsoft.ContainerService", "Containers",
    ComputerEnvironment == "Non-Azure" and ResourceProvider == "Microsoft.HybridCompute", "Arc-enabled",
    ComputerEnvironment == "Azure" and ResourceType == "virtualMachines", "Azure VM",
    ComputerEnvironment == "Azure" and ResourceType == "virtualMachineScaleSets", "VMSS",
    "Other")
| summarize
    MachineCount = count(),
    MMACount     = countif(Category == "Direct Agent"),
    AMACount     = countif(Category == "Azure Monitor Agent")
    by MachineType
| extend MigrationStatus = case(
    MMACount != 0 and AMACount != 0, "In Progress",
    AMACount != 0 and MMACount == 0, "Completed",
    "Not Started")
'@
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
        Save-Json -FileName 'ama-mma-migration.json' -Data ($result.Results)
    } catch {
        Skip-Capture -FileName 'ama-mma-migration.json' -ErrorRecord $_
    }
}
