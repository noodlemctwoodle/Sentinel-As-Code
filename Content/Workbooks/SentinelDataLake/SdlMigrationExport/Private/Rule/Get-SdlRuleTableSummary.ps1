#Requires -Version 7.6

<#
.SYNOPSIS
    Summarises the rule references per table.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Rule/Get-SdlRuleTableSummary.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SdlRuleTableSummary {
    <#
    .SYNOPSIS
        Summarises the rule references per table.

    .DESCRIPTION
        Counts the distinct enabled rules per table by ARM rule ID, split
        into direct references and references through a workspace
        function, with the rule kinds and up to five rule names.

    .PARAMETER Reference
        Rows from Get-SdlRuleReference.

    .OUTPUTS
        [pscustomobject] One row per table, most-referenced first.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Reference = @()
    )

    # Rules are counted by ARM rule ID: display names are not unique, so two
    # rules sharing a name are still two detection dependencies.
    $summary = foreach ($group in ($Reference | Group-Object -Property 'Table')) {
        $rows = @($group.Group)
        $allIds = @($rows.RuleId | Sort-Object -Unique)
        $direct = @($rows | Where-Object -FilterScript { $_.Via -eq 'Direct' } | ForEach-Object -Process { $_.RuleId } | Sort-Object -Unique)
        $viaFunction = @($rows | Where-Object -FilterScript { $_.Via -like 'Function *' } | ForEach-Object -Process { $_.RuleId } | Sort-Object -Unique)
        $names = @($rows.RuleName | Sort-Object -Unique)
        [pscustomobject]@{
            Table                = $group.Name
            EnabledRuleCount     = $allIds.Count
            DirectRuleCount      = $direct.Count
            ViaFunctionRuleCount = $viaFunction.Count
            RuleKinds            = (@($rows.Kind | Sort-Object -Unique) -join ', ')
            TopRuleNames         = (($names | Select-Object -First 5) -join '; ')
        }
    }
    $summary | Sort-Object -Property 'EnabledRuleCount' -Descending
}
