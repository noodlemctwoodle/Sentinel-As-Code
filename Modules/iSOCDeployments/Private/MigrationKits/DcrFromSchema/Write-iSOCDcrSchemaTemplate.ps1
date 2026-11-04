#Requires -Version 7.2

<#
.SYNOPSIS
    Write the table template and the data collection rule template.

.DESCRIPTION
    Two templates, as the table and the rule can be in different resource
    groups and must deploy in order.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Write-iSOCDcrSchemaTemplate.ps1
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

function Write-iSOCDcrSchemaTemplate {
    <#
    .SYNOPSIS
        Write the table template and the data collection rule template.

    .DESCRIPTION
        Asking ShouldProcess for each, the output folder is made when it is
        missing, then (unless -SkipTable) table-<table without _CL, lower
        case>.json from ConvertTo-iSOCTableArmTemplate, with a warning when
        dataTypeHints are dropped, then <rule>.json, a Direct rule from
        ConvertTo-iSOCDcrArmTemplate. The rule's description is the table
        description (or 'Logs Ingestion API rule for <table>.'), cut to 256
        characters with a warning when that shortened it. Both are UTF-8
        without a byte order mark, with LF line endings and one final
        newline.

    .PARAMETER Context
        The workspace context.

    .PARAMETER OutputDirectory
        The folder the templates go in.

    .PARAMETER TableName
        The table name.

    .PARAMETER Column
        The accepted columns.

    .PARAMETER StreamColumn
        The stream columns.

    .PARAMETER Table
        The table settings, from Resolve-iSOCDcrSchemaTableSetting.

    .PARAMETER Rule
        The rule settings, from Resolve-iSOCDcrSchemaRuleSetting.

    .PARAMETER Location
        The rule's region.

    .PARAMETER DataCollectionEndpointResourceId
        A data collection endpoint, if the rule needs one.

    .PARAMETER IncludeDataTypeHint
        Send each column's dataTypeHint.

    .PARAMETER SkipTable
        Write no table template.

    .OUTPUTS
        [pscustomobject] TablePath, DcrPath and WroteTable.

    .EXAMPLE
        Write-iSOCDcrSchemaTemplate -Context $ctx -OutputDirectory ./out -TableName 'MyApp_CL' -Column $columns -StreamColumn $streams -Table $table -Rule $rule -Location uksouth
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $OutputDirectory,

        [Parameter(Mandatory)]
        [string] $TableName,

        [Parameter(Mandatory)]
        [object[]] $Column,

        [Parameter(Mandatory)]
        [object[]] $StreamColumn,

        [Parameter(Mandatory)]
        [psobject] $Table,

        [Parameter(Mandatory)]
        [psobject] $Rule,

        [Parameter(Mandatory)]
        [string] $Location,

        [string] $DataCollectionEndpointResourceId,

        [switch] $IncludeDataTypeHint,

        [switch] $SkipTable
    )

    Write-iSOCLog 'Templates' -Level Section
    $maxDescription = (Get-iSOCTableSchemaSetting).MaxDescriptionLength

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        if ($PSCmdlet.ShouldProcess($OutputDirectory, 'Create output directory')) {
            New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
        }
    }

    $slug = ($TableName -replace '_CL$', '').ToLowerInvariant()
    $tablePath = Join-Path -Path $OutputDirectory -ChildPath "table-$slug.json"
    $dcrPath = Join-Path -Path $OutputDirectory -ChildPath "$($Rule.DcrName).json"
    $wroteTable = $false

    if (-not $SkipTable) {
        $hintedColumns = @($Column | Where-Object { $_.DataTypeHint })
        if ($hintedColumns.Count -gt 0 -and -not $IncludeDataTypeHint) {
            Write-iSOCLog "Dropping the dataTypeHint on $($hintedColumns.Count) column(s): $(@($hintedColumns.Name) -join ', '). The live service rejects the documented enum values, and a hint only affects display. Pass -IncludeDataTypeHint to send them anyway." -Level Warning
        }

        $tableTemplate = ConvertTo-iSOCTableArmTemplate -WorkspaceName $Context.WorkspaceName -Table $TableName -Column $Column -Plan $Table.TablePlan -Retention $Table.RetentionInDays -TotalRetention $Table.TotalRetentionInDays -TableDescription $Table.Description -IncludeDataTypeHint:$IncludeDataTypeHint

        if ($PSCmdlet.ShouldProcess($tablePath, 'Write table ARM template')) {
            Write-iSOCTextFile -Path $tablePath -Content (ConvertTo-Json -InputObject $tableTemplate -Depth 30)
            Write-iSOCLog "Table    : $tablePath" -Level Success
            $wroteTable = $true
        }
    }

    $ruleDescription = if ($Table.Description) { $Table.Description } else { "Logs Ingestion API rule for $TableName." }
    $trimmed = ConvertTo-iSOCSafeText -Text $ruleDescription -MaxLength $maxDescription
    if ($trimmed.Length -lt $ruleDescription.Length) {
        Write-iSOCLog "Truncated the rule description to $maxDescription characters; a data collection rule rejects anything longer." -Level Warning
    }

    $dcrTemplate = ConvertTo-iSOCDcrArmTemplate -Name $Rule.DcrName -Region $Location -Kind 'Direct' -Stream $Rule.StreamName -StreamColumn $StreamColumn -WorkspaceResourceId $Context.WorkspaceResourceId -OutputStream $Rule.OutputStreamName -Transform $Rule.TransformKql -EndpointResourceId $DataCollectionEndpointResourceId -Description $trimmed -GeneratedBy 'New-iSOCDcrFromSchema'

    if ($PSCmdlet.ShouldProcess($dcrPath, 'Write DCR ARM template')) {
        Write-iSOCTextFile -Path $dcrPath -Content (ConvertTo-Json -InputObject $dcrTemplate -Depth 30)
        Write-iSOCLog "DCR      : $dcrPath" -Level Success
    }

    Write-iSOCLog "Stream   : $($Rule.StreamName) ($($StreamColumn.Count) columns)"
    Write-iSOCLog "Transform: $($Rule.TransformKql)"

    [pscustomobject]@{
        TablePath  = $tablePath
        DcrPath    = $dcrPath
        WroteTable = $wroteTable
    }
}
