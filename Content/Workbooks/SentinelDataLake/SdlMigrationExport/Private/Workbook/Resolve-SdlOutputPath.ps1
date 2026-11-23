#Requires -Version 7.6

<#
.SYNOPSIS
    Works out where the workbook is written.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Workbook/Resolve-SdlOutputPath.ps1
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

function Resolve-SdlOutputPath {
    <#
    .SYNOPSIS
        Works out where the workbook is written.

    .DESCRIPTION
        Without -OutputPath the file goes into the current directory: a
        module has no script folder to write beside, and its own folder is
        inside the repository. A Windows drive path is rejected on macOS and
        Linux up front, instead of failing later with "Cannot find
        drive".

    .PARAMETER WorkspaceName
        The workspace name, used in the default file name.

    .PARAMETER Timestamp
        The run start, used in the default file name.

    .PARAMETER OutputPath
        The path the caller asked for, if any.

    .OUTPUTS
        [string] The output path.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkspaceName,

        [Parameter(Mandatory)]
        [datetime]$Timestamp,

        [Parameter()]
        [AllowEmptyString()]
        [string]$OutputPath
    )

    if (-not $OutputPath) {
        $baseDirectory = (Get-Location).Path
        $fileName = 'SdlMigrationExport_{0}_{1}.xlsx' -f $WorkspaceName, $Timestamp.ToString('yyyyMMdd-HHmm')
        $OutputPath = Join-Path -Path $baseDirectory -ChildPath $fileName
    }
    if (-not $IsWindows -and $OutputPath -match '^[A-Za-z]:[\\/]') {
        throw "OutputPath '$OutputPath' uses a Windows drive path, which is not valid on macOS/Linux. Use a forward-slash path instead, e.g. '/tmp/report.xlsx' or './report.xlsx'."
    }
    # .NET resolves relative paths against the process directory, which
    # Set-Location does not change; resolve against PowerShell's location.
    return $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)
}
