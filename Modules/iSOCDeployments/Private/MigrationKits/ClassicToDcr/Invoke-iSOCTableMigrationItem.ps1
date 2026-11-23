#Requires -Version 7.6

<#
.SYNOPSIS
    Migrate one table, write its data collection rule template and, when asked, deploy it.

.DESCRIPTION
    The per-table step of Invoke-iSOCClassicTableMigration. A failure is the
    result's Error, not a stop of the run.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Invoke-iSOCTableMigrationItem.ps1
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

function Invoke-iSOCTableMigrationItem {
    <#
    .SYNOPSIS
        Migrate one table, write its data collection rule template and, when
        asked, deploy it.

    .DESCRIPTION
        1. Migrate: unless -SkipTableMigration, a Classic table is migrated
           (Convert-iSOCClassicTable) and read again, so the stream follows
           the schema after migration; a DCR-based one needs nothing.
        2. Stream: the columns a stream can declare
           (ConvertTo-iSOCDcrStreamColumn), each one left behind warned of,
           and the transform that casts them back to the table's types. A
           TextLog rule takes the agent's four columns instead, with a
           passthrough transform to edit, and a logFiles data source.
        3. Template: written to <Path>/<rule>.json, asking ShouldProcess.
        4. Deploy, with -Deploy: refused while the table is still Classic,
           since a rule accepts only a DCR-based destination; else deployed
           asking ShouldProcess, then the rule's immutable id and endpoint
           are read, and with -GrantIngestionRoleTo the ingestion role is
           granted.

        The rule is <DcrNamePrefix><table without _CL, lower case>, its
        streams Custom-<table>. A step that fails ends the item, with the
        first line of the error in the result.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Row
        The table's inventory row, from Get-iSOCClassicTableInventory.

    .PARAMETER SkipTableMigration
        Leave the table as it is.

    .PARAMETER DcrKind
        Direct or TextLog.

    .PARAMETER Platform
        Windows or Linux, for TextLog.

    .PARAMETER FilePattern
        The files a TextLog rule collects.

    .PARAMETER LogFormat
        text or json, for TextLog.

    .PARAMETER RecordStartTimestampFormat
        The timestamp a text record starts with.

    .PARAMETER DcrNamePrefix
        The rule name's prefix.

    .PARAMETER DcrResourceGroupName
        The resource group the rule goes in.

    .PARAMETER Location
        The rule's region.

    .PARAMETER TransformKql
        A transform to use instead of the one built.

    .PARAMETER DataCollectionEndpointResourceId
        A data collection endpoint for the rule.

    .PARAMETER Path
        The folder the template is written to.

    .PARAMETER Deploy
        Deploy the template.

    .PARAMETER GrantIngestionRoleTo
        Identities to give the ingestion role on the deployed rule.

    .PARAMETER ConfirmBypassed
        Migrate without the confirmation (-Force or -Confirm:$false).

    .OUTPUTS
        [pscustomobject] TableName, SubTypeAfter, Migrated, RowCount, GB90d,
        DcrName, TemplatePath, Deployed, ImmutableId, Endpoint, Granted and
        Error.

    .EXAMPLE
        Invoke-iSOCTableMigrationItem -Context $ctx -Row $row -DcrKind Direct -Platform Windows -LogFormat text -RecordStartTimestampFormat 'ISO 8601' -DcrNamePrefix dcr- -DcrResourceGroupName rg-dcr -Location uksouth -Path .
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $Row,

        [switch] $SkipTableMigration,

        [Parameter(Mandatory)]
        [string] $DcrKind,

        [Parameter(Mandatory)]
        [string] $Platform,

        [string[]] $FilePattern,

        [Parameter(Mandatory)]
        [string] $LogFormat,

        [Parameter(Mandatory)]
        [string] $RecordStartTimestampFormat,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $DcrNamePrefix,

        [Parameter(Mandatory)]
        [string] $DcrResourceGroupName,

        [Parameter(Mandatory)]
        [string] $Location,

        [string] $TransformKql,

        [string] $DataCollectionEndpointResourceId,

        [Parameter(Mandatory)]
        [string] $Path,

        [switch] $Deploy,

        [string[]] $GrantIngestionRoleTo,

        [switch] $ConfirmBypassed
    )

    $table = $Row.Name
    Write-iSOCLog ''
    Write-iSOCLog "Processing $table" -Level Section

    $migrated = $false
    $deployed = $false
    $dcrName = $null
    $immutableId = $null
    $endpoint = $null
    $templatePath = $null
    $failure = $null
    $grantedIdentities = @()

    try {
        $schemaColumns = $Row.Columns
        $subType = $Row.SubType

        if ($SkipTableMigration) {
            Write-iSOCLog 'Skipping migration (-SkipTableMigration).' -Level Warning
        } elseif ($subType -eq 'DataCollectionRuleBased') {
            Write-iSOCLog 'Already DCR-based. Nothing to migrate.' -Level Success
        } elseif ($subType -eq 'Classic') {
            Write-iSOCLog 'Migration is one-way. The Log Analytics agent will no longer be able to write to this table, and any Custom Fields defined against it stop receiving data.' -Level Warning
            $migrated = Convert-iSOCClassicTable -Context $Context -Table $table -Force:$ConfirmBypassed
            if ($migrated) {
                Write-iSOCLog "Migrated $table to a DCR-based table." -Level Success
                $refreshed = Get-iSOCWorkspaceTableDetail -Context $Context -Table $table
                $schemaColumns = $refreshed.Columns
                $subType = $refreshed.SubType
            } else {
                Write-iSOCLog 'Migration declined or previewed. The table is still Classic.' -Level Warning
            }
        } else {
            Write-iSOCLog "Table subtype is '$subType', not 'Classic'. Skipping migration." -Level Warning
        }

        $conversion = ConvertTo-iSOCDcrStreamColumn -SchemaColumn $schemaColumns
        $tableColumns = @($conversion.Columns)
        foreach ($drop in $conversion.Dropped) {
            Write-iSOCLog "Column '$($drop.Name)' cannot be carried into the DCR ($($drop.Reason)). It will stop receiving data." -Level Warning
        }

        $streamName = "Custom-$table"
        $outputStreamName = "Custom-$table"
        $dcrName = $DcrNamePrefix + ($table -replace '_CL$', '').ToLowerInvariant()

        $logFilesDataSource = $null
        $dcrResourceKind = 'Direct'
        $streamColumns = $tableColumns
        $defaultTransform = Get-iSOCDcrDefaultTransform -SchemaColumn $schemaColumns -StreamColumn $tableColumns

        if ($DcrKind -eq 'TextLog') {
            $dcrResourceKind = $Platform
            if ($LogFormat -eq 'text') {
                $textColumns = Get-iSOCDcrTextLogStreamColumn
                $streamColumns = $textColumns
                $tableColumnNames = @($tableColumns | ForEach-Object { $_.name })
                $projectable = @($textColumns | Where-Object { $tableColumnNames -contains $_.name } | ForEach-Object { $_.name })
                $defaultTransform = if ($projectable.Count -eq 0) { 'source' } else { 'source | project ' + ($projectable -join ', ') }
                Write-iSOCLog 'Text log transform is a passthrough placeholder. Edit transformKql to parse RawData into the destination columns before associating machines.' -Level Warning
            }

            $logFileSettings = [ordered]@{
                name         = "$($table -replace '_CL$', '')-logfile"
                streams      = @($streamName)
                filePatterns = @($FilePattern)
                format       = $LogFormat
            }
            if ($LogFormat -eq 'text') {
                $logFileSettings['settings'] = [ordered]@{
                    text = [ordered]@{ recordStartTimestampFormat = $RecordStartTimestampFormat }
                }
            }
            $logFilesDataSource = $logFileSettings
        }

        $effectiveTransform = if ($TransformKql) { $TransformKql } else { $defaultTransform }

        $template = ConvertTo-iSOCDcrArmTemplate -Name $dcrName -Region $Location -Kind $dcrResourceKind `
            -Stream $streamName -StreamColumn $streamColumns -WorkspaceResourceId $Context.WorkspaceResourceId `
            -OutputStream $outputStreamName -Transform $effectiveTransform -EndpointResourceId $DataCollectionEndpointResourceId `
            -LogFilesDataSource $logFilesDataSource -Description "Ingestion into $table, migrated from a classic custom log table."

        $templatePath = Join-Path -Path $Path -ChildPath "$dcrName.json"
        $templateJson = $template | ConvertTo-Json -Depth 30
        if ($PSCmdlet.ShouldProcess($templatePath, 'Write DCR ARM template')) {
            Write-iSOCTextFile -Path $templatePath -Content $templateJson
            Write-iSOCLog "Template : $templatePath" -Level Success
        }

        Write-iSOCLog "Stream   : $streamName ($($streamColumns.Count) columns)"
        Write-iSOCLog "Transform: $effectiveTransform"

        if ($Deploy) {
            if ($subType -ne 'DataCollectionRuleBased') {
                throw "Cannot deploy: $table is still '$subType'. A DCR only accepts a DataCollectionRuleBased destination. Re-run without -SkipTableMigration, or migrate the table first."
            }

            if ($PSCmdlet.ShouldProcess("$DcrResourceGroupName/$dcrName", 'Deploy data collection rule')) {
                Deploy-iSOCDcrTemplate -Context $Context -ResourceGroupName $DcrResourceGroupName -Name $dcrName -TemplatePath $templatePath | Out-Null
                $deployed = $true
                Write-iSOCLog "Deployed $dcrName." -Level Success

                $dcrId = "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$DcrResourceGroupName/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
                $ingestion = Get-iSOCDcrIngestionEndpoint -Context $Context -DcrId $dcrId
                $immutableId = $ingestion.ImmutableId
                if ($null -ne $immutableId) { Write-iSOCLog "ImmutableId: $immutableId" }
                $endpoint = $ingestion.Endpoint
                if ($endpoint) { Write-iSOCLog "Ingestion  : $endpoint" }

                if ($DcrKind -eq 'Direct' -and -not $endpoint) {
                    Write-iSOCLog 'No logsIngestion endpoint was returned for this Direct DCR. Endpoints cannot be added to an existing DCR, so this one needs a Data Collection Endpoint or a replacement DCR.' -Level Warning
                }

                if ($GrantIngestionRoleTo) {
                    $grantedIdentities = @(Grant-iSOCDcrIngestionRole -Context $Context -DcrId $dcrId -DcrName $dcrName -Identity $GrantIngestionRoleTo)
                }
            }
        }
    } catch {
        $failure = $_.Exception.Message.Split([char]10)[0]
        Write-iSOCLog "Failed: $failure" -Level Error
    }

    [pscustomobject]@{
        TableName    = $table
        SubTypeAfter = if ($migrated) { 'DataCollectionRuleBased' } else { $Row.SubType }
        Migrated     = $migrated
        RowCount     = $Row.RowCount
        GB90d        = $Row.GB90d
        DcrName      = $dcrName
        TemplatePath = $templatePath
        Deployed     = $deployed
        ImmutableId  = $immutableId
        Endpoint     = $endpoint
        Granted      = $grantedIdentities
        Error        = $failure
    }
}
