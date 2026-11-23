#Requires -Version 7.6

<#
.SYNOPSIS
    Wait for a fixture table to appear, and say its sub type.

.DESCRIPTION
    Polls the table every 15 seconds until it has a sub type or the timeout
    passes.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Wait-iSOCFixtureTable.ps1
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

function Wait-iSOCFixtureTable {
    <#
    .SYNOPSIS
        Wait for a fixture table to appear, and say its sub type.

    .DESCRIPTION
        Reads the table every 15 seconds until it reports a sub type or
        -TimeoutSeconds pass; a table not there yet (404) is polled again.
        The table usually appears within a few minutes of the first post;
        its data becomes queryable separately.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Table
        The table.

    .PARAMETER TimeoutSeconds
        How long to wait.

    .OUTPUTS
        [string] The sub type; nothing when the table did not appear.

    .EXAMPLE
        Wait-iSOCFixtureTable -Context $ctx -Table SacMigrationTest_CL -TimeoutSeconds 300
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $Table,

        [Parameter(Mandatory)]
        [int] $TimeoutSeconds
    )

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([datetime]::UtcNow -lt $deadline) {
        try {
            $detail = Invoke-iSOCRestRequest -Method GET -Path "$($Context.WorkspaceResourceId)/tables/$Table" -ApiVersion (Get-iSOCApiVersion OperationalInsights)
            $subType = [string](Get-iSOCPropertyValue -InputObject $detail -Path 'properties.schema.tableSubType')
            if ($subType) { return $subType }
        } catch {
            Write-iSOCLog "Table not present yet: $($_.Exception.Message.Split([char]10)[0])" -Level Debug
        }
        Start-Sleep -Seconds 15
    }
    $null
}
