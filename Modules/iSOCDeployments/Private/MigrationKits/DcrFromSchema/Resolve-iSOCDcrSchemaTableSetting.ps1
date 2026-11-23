#Requires -Version 7.6

<#
.SYNOPSIS
    Settle the table's description, plan and retention from the parameters, then the schema file, then the defaults.

.DESCRIPTION
    Values from the schema file have not been through the parameters'
    validation, so they are checked here.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Resolve-iSOCDcrSchemaTableSetting.ps1
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

function Resolve-iSOCDcrSchemaTableSetting {
    <#
    .SYNOPSIS
        Settle the table's description, plan and retention from the
        parameters, then the schema file, then the defaults.

    .DESCRIPTION
        The description is the parameter's, else the schema file's, else
        'Custom log table <table>.', cleaned (ConvertTo-iSOCSafeText, 256
        characters) with a warning when that changed it. With -SkipTable
        the rest is skipped, with a warning. Otherwise the plan is the
        parameter's, else the schema file's (one of Analytics, Basic and
        Auxiliary), else Analytics; an Auxiliary table with names that
        differ only by case is refused, as it drops rows over them. Each
        retention not given as a parameter comes from the schema file when
        it has one, checked against the documented range (4 to 730
        interactive, 4 to 4383 total, -1 for the default); otherwise it is
        left out (0). Total retention shorter than interactive is refused.

    .PARAMETER TableName
        The table name.

    .PARAMETER Spec
        The schema file, from Import-iSOCTableSpec.

    .PARAMETER CaseCollision
        The schema's case-only name collisions.

    .PARAMETER Description
        The -Description given.

    .PARAMETER TablePlan
        The -TablePlan given.

    .PARAMETER RetentionInDays
        The -RetentionInDays given, or nothing.

    .PARAMETER TotalRetentionInDays
        The -TotalRetentionInDays given, or nothing.

    .PARAMETER SkipTable
        The table is not written.

    .OUTPUTS
        [pscustomobject] Description, TablePlan, RetentionInDays and
        TotalRetentionInDays (0 when left out).

    .EXAMPLE
        Resolve-iSOCDcrSchemaTableSetting -TableName 'MyApp_CL' -Spec $spec -CaseCollision @()
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $TableName,

        [Parameter(Mandatory)]
        [psobject] $Spec,

        [AllowEmptyCollection()]
        [object[]] $CaseCollision = @(),

        [string] $Description,

        [string] $TablePlan,

        [Nullable[int]] $RetentionInDays,

        [Nullable[int]] $TotalRetentionInDays,

        [switch] $SkipTable
    )

    Write-iSOCLog 'Table settings' -Level Section
    $setting = Get-iSOCTableSchemaSetting

    if (-not $Description) {
        $specDescription = Get-iSOCSpecDefault -Extra $Spec.Extra -Key 'description'
        $Description = if ($specDescription) { [string]$specDescription } else { "Custom log table $TableName." }
    }
    $cleanDescription = ConvertTo-iSOCSafeText -Text $Description -MaxLength $setting.MaxDescriptionLength
    if ($cleanDescription -ne $Description) {
        Write-iSOCLog 'Cleaned the description before use (collapsed line breaks or removed non-printing characters).' -Level Warning
        $Description = $cleanDescription
    }

    $retention = if ($null -ne $RetentionInDays) { [int]$RetentionInDays } else { 0 }
    $total = if ($null -ne $TotalRetentionInDays) { [int]$TotalRetentionInDays } else { 0 }

    if ($SkipTable) {
        Write-iSOCLog 'Skipping table creation (-SkipTable). The DCR will target the existing table.' -Level Warning
    } else {
        if (-not $TablePlan) {
            $specPlan = Get-iSOCSpecDefault -Extra $Spec.Extra -Key 'plan'
            if ($specPlan) {
                $TablePlan = [string]$specPlan
                if ($TablePlan -notin 'Analytics', 'Basic', 'Auxiliary') {
                    throw "The schema file's plan '$TablePlan' is not one of Analytics, Basic and Auxiliary."
                }
            } else {
                $TablePlan = 'Analytics'
            }
        }

        if ($TablePlan -eq 'Auxiliary' -and $CaseCollision.Count -gt 0) {
            throw ('An Auxiliary table drops rows when column names differ only by case, so this schema cannot ' +
                "use the Auxiliary plan: $(@($CaseCollision | ForEach-Object { $_.Message }) -join ' ') " +
                'Rename the columns, or choose Analytics or Basic.')
        }

        if ($null -eq $RetentionInDays) {
            $specRetention = Get-iSOCSpecDefault -Extra $Spec.Extra -Key 'retentionInDays'
            $candidate = 0
            if ($null -ne $specRetention -and "$specRetention" -ne '') { $candidate = [int]$specRetention }
            if ($candidate -ne 0 -and $candidate -ne -1 -and ($candidate -lt 4 -or $candidate -gt 730)) {
                throw "Interactive retention must be between 4 and 730 days, or -1 for the workspace default; got $candidate."
            }
            $retention = $candidate
        }

        if ($null -eq $TotalRetentionInDays) {
            $specTotal = Get-iSOCSpecDefault -Extra $Spec.Extra -Key 'totalRetentionInDays'
            $candidate = 0
            if ($null -ne $specTotal -and "$specTotal" -ne '') { $candidate = [int]$specTotal }
            if ($candidate -ne 0 -and $candidate -ne -1 -and ($candidate -lt 4 -or $candidate -gt 4383)) {
                throw "Total retention must be between 4 and 4383 days, or -1 to match interactive retention; got $candidate."
            }
            $total = $candidate
        }

        if ($retention -gt 0 -and $total -gt 0 -and $total -lt $retention) {
            throw "Total retention ($total days) cannot be shorter than interactive retention ($retention days)."
        }
    }

    [pscustomobject]@{
        Description          = $Description
        TablePlan            = $TablePlan
        RetentionInDays      = $retention
        TotalRetentionInDays = $total
    }
}
