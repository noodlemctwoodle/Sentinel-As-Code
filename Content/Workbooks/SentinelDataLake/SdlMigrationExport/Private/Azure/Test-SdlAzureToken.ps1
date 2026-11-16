#Requires -Version 7.2

<#
.SYNOPSIS
    Tests whether the current Az context can issue tokens for both APIs
    the exporter calls.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Azure/Test-SdlAzureToken.ps1
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

function Test-SdlAzureToken {
    <#
    .SYNOPSIS
        Tests whether the current Az context can issue tokens for both
        APIs the exporter calls.

    .DESCRIPTION
        A context can exist while its token has expired or needs MFA
        or conditional access. The exporter calls Azure Resource
        Manager and the Log Analytics query API, so both are probed.

    .OUTPUTS
        [bool] True when both tokens were issued.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([bool])]
    param ()

    foreach ($resource in @('https://management.azure.com/', 'https://api.loganalytics.io/')) {
        try {
            $null = Get-AzAccessToken -ResourceUrl $resource -ErrorAction Stop -WarningAction SilentlyContinue
        } catch {
            Write-Verbose -Message "No token for ${resource}: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}
