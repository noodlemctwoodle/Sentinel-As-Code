#Requires -Version 7.6

<#
.SYNOPSIS
    Runs a KQL query against the workspace.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Azure/Invoke-SdlKqlQuery.ps1
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

function Invoke-SdlKqlQuery {
    <#
    .SYNOPSIS
        Runs a KQL query against the workspace.

    .DESCRIPTION
        Resolves the workspace customer ID (GUID) once and caches it
        on the connection object, then runs the query through the Log
        Analytics query API.

    .PARAMETER Connection
        The connection object; WorkspaceCustomerId is filled on first
        use.

    .PARAMETER Query
        The KQL text.

    .OUTPUTS
        The result rows.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Query
    )

    if (-not $Connection.WorkspaceCustomerId) {
        $workspacePath = "$(Get-SdlBaseUri -Connection $Connection)?api-version=$($Connection.WorkspaceApiVersion)"
        $workspace = Invoke-SdlArmRequest -Connection $Connection -Path $workspacePath
        $Connection.WorkspaceCustomerId = $workspace.properties.customerId
        if (-not $Connection.WorkspaceCustomerId) {
            throw "Could not resolve workspace customerId (GUID) for $($Connection.WorkspaceName)."
        }
    }
    Write-Verbose -Message "KQL query ($($Query.Length) characters) against workspace $($Connection.WorkspaceName)"
    try {
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $Connection.WorkspaceCustomerId -Query $Query -ErrorAction Stop
    } catch {
        $message = "Log Analytics query failed against workspace '$($Connection.WorkspaceName)' ($($Connection.WorkspaceCustomerId)): $($_.Exception.Message) Check the workspace read permission and that the tables the query names exist."
        throw [System.InvalidOperationException]::new($message, $_.Exception)
    }
    if ($null -eq $result.Results) {
        return
    }
    return $result.Results
}
