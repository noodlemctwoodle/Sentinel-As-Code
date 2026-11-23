#Requires -Version 7.6

<#
.SYNOPSIS
    Accept a schema with no errors, or repair it and accept it, or refuse it.

.DESCRIPTION
    The script's unattended schema review: nothing prompts, so a schema still
    wrong after the repairs stops the run.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Invoke-iSOCSchemaRepair.ps1
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

function Invoke-iSOCSchemaRepair {
    <#
    .SYNOPSIS
        Accept a schema with no errors, or repair it and accept it, or
        refuse it.

    .DESCRIPTION
        Checks the columns (Resolve-iSOCTableSchema). With no errors they
        are returned as they are. Otherwise a warning counts the problems,
        Repair-iSOCTableSchema makes the fixes that have one answer, and the
        columns are checked again: anything still an error stops the run,
        naming each column and its first error, or each schema problem.
        This is the unattended path of New-DcrFromSchema.ps1's schema
        review; the interactive editor is not ported, as nothing prompts.

    .PARAMETER Column
        The entries of the schema's column list.

    .OUTPUTS
        [pscustomobject[]] The accepted columns.

    .EXAMPLE
        $columns = @(Invoke-iSOCSchemaRepair -Column @($spec.Columns))
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]], [object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Column
    )

    $analysis = Resolve-iSOCTableSchema -Column $Column
    $working = $analysis.Columns.ToArray()

    $errorCount = @($analysis.Columns | Where-Object { @($_.Issues | Where-Object { $_.Severity -eq 'Error' }).Count -gt 0 }).Count +
    @($analysis.SchemaIssues | Where-Object { $_.Severity -eq 'Error' }).Count

    if ($errorCount -eq 0) { return $working }

    Write-iSOCLog "Schema has $errorCount blocking problem(s). Repairing what can be repaired without guessing." -Level Warning
    $working = @(Repair-iSOCTableSchema -Column $working)

    $recheck = Resolve-iSOCTableSchema -Column $working
    $stillWrong = @($recheck.Columns | Where-Object { @($_.Issues | Where-Object { $_.Severity -eq 'Error' }).Count -gt 0 }) +
    @($recheck.SchemaIssues | Where-Object { $_.Severity -eq 'Error' })

    if (@($stillWrong).Count -gt 0) {
        $detail = @($stillWrong | ForEach-Object {
                if ($_.PSObject.Properties['Name']) { "$($_.Name): $(@($_.Issues | Where-Object { $_.Severity -eq 'Error' })[0].Message)" }
                else { $_.Message }
            }) -join '; '
        throw "Schema cannot be used and non-interactive mode cannot ask: $detail"
    }

    $working
}
