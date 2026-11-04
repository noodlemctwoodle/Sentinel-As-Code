#Requires -Version 7.2

<#
.SYNOPSIS
    Check a custom log table name, returning what is wrong with it.

.DESCRIPTION
    Stricter than ARM's own pattern, so the name can be used in KQL without
    quoting.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Get-iSOCTableNameProblem.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCTableNameProblem {
    <#
    .SYNOPSIS
        Check a custom log table name, returning what is wrong with it.

    .DESCRIPTION
        The name must end _CL, start with a letter and hold only letters,
        digits and underscores (ARM's pattern also allows a leading digit
        and hyphens, which then need bracket-quoting in every query), and be
        4 to 63 characters.

    .PARAMETER Name
        The table name.

    .OUTPUTS
        [string[]] One message a problem; none when the name is usable.

    .EXAMPLE
        Get-iSOCTableNameProblem -Name 'MyApp_CL'
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name
    )

    $setting = Get-iSOCTableSchemaSetting
    $problems = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $problems.Add('the table name is empty')
        return $problems.ToArray()
    }
    if (-not $Name.EndsWith('_CL')) {
        $problems.Add("'$Name' does not end with '_CL', which every custom log table name must")
    }
    if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
        $problems.Add("'$Name' must start with a letter and contain only letters, digits and underscores, so KQL can reference it unquoted")
    }
    if ($Name.Length -lt $setting.MinTableNameLength) {
        $problems.Add("'$Name' is $($Name.Length) characters; the minimum is $($setting.MinTableNameLength)")
    }
    if ($Name.Length -gt $setting.MaxTableNameLength) {
        $problems.Add("'$Name' is $($Name.Length) characters; the limit is $($setting.MaxTableNameLength)")
    }
    $problems.ToArray()
}
