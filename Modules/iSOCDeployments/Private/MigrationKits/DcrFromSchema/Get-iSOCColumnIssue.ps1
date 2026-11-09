#Requires -Version 7.6

<#
.SYNOPSIS
    Check one column, returning its errors and warnings.

.DESCRIPTION
    Errors are what Azure refuses on create; warnings are legal but worth
    saying.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Get-iSOCColumnIssue.ps1
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

function Get-iSOCColumnIssue {
    <#
    .SYNOPSIS
        Check one column, returning its errors and warnings.

    .DESCRIPTION
        Errors: an empty name, a reserved or system name (matched without
        case), a name that does not start with an ASCII letter or holds
        anything but letters, digits and underscores, a name shorter than 2
        or longer than 45 characters, a type the Tables API does not take,
        and a dataTypeHint that is not one of the documented values.
        Warning: a classic Custom Log Wizard type suffix (_s, _d, _b, _g,
        _t), which a DCR-based table does not need.

    .PARAMETER Name
        The column name.

    .PARAMETER DeclaredType
        The type the schema declares.

    .PARAMETER DataTypeHint
        The dataTypeHint, if any.

    .OUTPUTS
        [pscustomobject[]] Severity (Error or Warning) and Message.

    .EXAMPLE
        Get-iSOCColumnIssue -Name 'Message_s' -DeclaredType 'string'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $DeclaredType,

        [AllowEmptyString()]
        [AllowNull()]
        [string] $DataTypeHint
    )

    $setting = Get-iSOCTableSchemaSetting
    $issues = [System.Collections.Generic.List[pscustomobject]]::new()

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $issues.Add([pscustomobject]@{ Severity = 'Error'; Message = 'the column name is empty' })
    }
    else {
        if ($setting.ReservedColumns -contains $Name) {
            $issues.Add([pscustomobject]@{ Severity = 'Error'; Message = "'$Name' conflicts with a system or reserved column name" })
        }
        if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
            $issues.Add([pscustomobject]@{ Severity = 'Error'; Message = 'must start with an ASCII letter and then contain only letters, digits and underscores' })
        }
        if ($Name.Length -lt $setting.MinColumnNameLength) {
            $issues.Add([pscustomobject]@{ Severity = 'Error'; Message = "is $($Name.Length) character; column names must be $($setting.MinColumnNameLength) to $($setting.MaxColumnNameLength) characters" })
        }
        if ($Name.Length -gt $setting.MaxColumnNameLength) {
            $issues.Add([pscustomobject]@{ Severity = 'Error'; Message = "is $($Name.Length) characters; the limit is $($setting.MaxColumnNameLength)" })
        }
        foreach ($suffix in $setting.ClassicTypeSuffixes) {
            if ($Name.EndsWith($suffix)) {
                $issues.Add([pscustomobject]@{ Severity = 'Warning'; Message = "'$suffix' is a classic Custom Log Wizard type suffix; a DCR-based table carries real types and does not need it" })
                break
            }
        }
    }

    if ($null -eq (Get-iSOCTableColumnType -DeclaredType $DeclaredType)) {
        $known = $setting.TableColumnTypes -join ', '
        $shown = if ([string]::IsNullOrWhiteSpace($DeclaredType)) { '(none)' } else { $DeclaredType }
        $issues.Add([pscustomobject]@{ Severity = 'Error'; Message = "type '$shown' is not a Log Analytics column type. Use one of: $known" })
    }

    if (-not [string]::IsNullOrWhiteSpace($DataTypeHint) -and $setting.DataTypeHints -notcontains $DataTypeHint) {
        $issues.Add([pscustomobject]@{ Severity = 'Error'; Message = "dataTypeHint '$DataTypeHint' is not valid. Use one of: $($setting.DataTypeHints -join ', ')" })
    }

    $issues.ToArray()
}
