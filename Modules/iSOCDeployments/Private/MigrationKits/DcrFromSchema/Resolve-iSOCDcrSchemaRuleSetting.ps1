#Requires -Version 7.6

<#
.SYNOPSIS
    Settle the data collection rule's name, resource group and transform, checking the resource group exists.

.DESCRIPTION
    A mistyped resource group is otherwise found by ARM only after the table
    has been made.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Resolve-iSOCDcrSchemaRuleSetting.ps1
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

function Resolve-iSOCDcrSchemaRuleSetting {
    <#
    .SYNOPSIS
        Settle the data collection rule's name, resource group and
        transform, checking the resource group exists.

    .DESCRIPTION
        The name is the parameter's, else the schema file's dcrName, else
        'dcr-' and the table name without _CL, in lower case. The resource
        group is read, and a run naming one that cannot be read stops
        before anything is written. The streams are Custom-<table>. The
        transform is the parameter's, else the schema file's, else one that
        casts each stream column back to its table type
        (Get-iSOCSchemaTransform); its curly quotes and no-break spaces are
        replaced, with a warning, and one too long is refused
        (Repair-iSOCTransformKql).

    .PARAMETER Context
        The workspace context.

    .PARAMETER TableName
        The table name.

    .PARAMETER Spec
        The schema file, from Import-iSOCTableSpec.

    .PARAMETER Column
        The accepted columns.

    .PARAMETER StreamColumn
        The stream columns.

    .PARAMETER DcrName
        The -DcrName given.

    .PARAMETER DcrResourceGroupName
        The rule's resource group.

    .PARAMETER TransformKql
        The -TransformKql given.

    .OUTPUTS
        [pscustomobject] DcrName, StreamName, OutputStreamName and
        TransformKql.

    .EXAMPLE
        Resolve-iSOCDcrSchemaRuleSetting -Context $ctx -TableName 'MyApp_CL' -Spec $spec -Column $columns -StreamColumn $streamColumns -DcrResourceGroupName rg-sentinel
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $TableName,

        [Parameter(Mandatory)]
        [psobject] $Spec,

        [Parameter(Mandatory)]
        [object[]] $Column,

        [Parameter(Mandatory)]
        [object[]] $StreamColumn,

        [string] $DcrName,

        [Parameter(Mandatory)]
        [string] $DcrResourceGroupName,

        [string] $TransformKql
    )

    Write-iSOCLog 'Data collection rule settings' -Level Section

    if (-not $DcrName) {
        $specDcrName = Get-iSOCSpecDefault -Extra $Spec.Extra -Key 'dcrName'
        $DcrName = if ($specDcrName) { [string]$specDcrName } else { 'dcr-' + ($TableName -replace '_CL$', '').ToLowerInvariant() }
    }

    $group = $null
    try {
        $group = Invoke-iSOCRestRequest -Method GET -Path "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$DcrResourceGroupName" -ApiVersion (Get-iSOCApiVersion ResourceGroups) -Context $Context -AllowNotFound
    }
    catch {
        Write-iSOCLog "Could not read resource group '$DcrResourceGroupName': $($_.Exception.Message.Split([char]10)[0])" -Level Debug
    }
    if (-not $group) {
        throw ("DCR resource group '$DcrResourceGroupName' does not exist in the workspace's subscription. " +
            'Re-run and supply an existing resource group, or pass -DcrResourceGroupName.')
    }

    $streamName = "Custom-$TableName"

    if (-not $TransformKql) {
        $specTransform = Get-iSOCSpecDefault -Extra $Spec.Extra -Key 'transformKql'
        $TransformKql = if ($specTransform) { [string]$specTransform } else { Get-iSOCSchemaTransform -Column $Column -StreamColumn $StreamColumn }
    }

    $transformCheck = Repair-iSOCTransformKql -Transform $TransformKql
    $TransformKql = $transformCheck.Text
    if ($transformCheck.Applied.Count -gt 0) {
        Write-iSOCLog "Cleaned the transform before use: replaced $($transformCheck.Applied -join ', '). KQL does not accept those characters." -Level Warning
    }

    [pscustomobject]@{
        DcrName          = $DcrName
        StreamName       = $streamName
        OutputStreamName = $streamName
        TransformKql     = $TransformKql
    }
}
