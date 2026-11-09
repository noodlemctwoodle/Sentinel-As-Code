#Requires -Version 7.6

<#
.SYNOPSIS
    Migrate classic custom log tables to DCR-based tables and write a data collection rule for each.

.DESCRIPTION
    Invoke-iSOCClassicTableMigration replaces
    Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Public/Invoke-iSOCClassicTableMigration.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCClassicTableMigration {
    <#
    .SYNOPSIS
        Migrate classic custom log tables to DCR-based tables and write a
        data collection rule for each.

    .DESCRIPTION
        Classic (MMA or Data Collector API) _CL tables have the sub type
        Classic, and a data collection rule refuses to target them
        (InvalidOutputTable). The supported fix is the Tables API's migrate
        operation, which cannot be undone. For one table or every classic
        table:

          1. Discover: each table's sub type, columns, rows over 90 days and
             billable volume. -ListOnly stops here and changes nothing.
          2. Migrate: each Classic table, behind ShouldProcess and a
             confirmation that -Force skips.
          3. Export: a data collection rule template per table, from the
             schema after migration, written to -Path.
          4. Deploy, with -Deploy: the template, then the rule's immutable id
             and logs ingestion endpoint; with -GrantIngestionRoleTo, the
             ingestion role for the identities that will send.

        With -AllClassicTables only _CL tables are taken (a platform table
        reports Classic once Custom Fields are made against it), and a table
        with no rows in 90 days is skipped unless -IncludeEmptyTables:
        emptiness is judged by rows, not billable GB, which lag. -DcrKind
        Direct makes a Logs Ingestion API rule with its own endpoint;
        TextLog an Azure Monitor Agent file collection rule, whose transform
        is a placeholder to edit. Migrate the agents before the tables:
        afterwards the Log Analytics agent cannot write to them.

        Run Get-iSOCTableMigrationImpact first for what depends on each
        table.

    .PARAMETER TableName
        The tables, for example MyApp_CL; _CL is added when it is missing.
        Letters, digits and underscores only.

    .PARAMETER AllClassicTables
        Every classic _CL table in the workspace.

    .PARAMETER ListOnly
        List the tables and stop. Nothing is migrated, written or deployed.

    .PARAMETER IncludeEmptyTables
        With -AllClassicTables, take tables with no rows in 90 days too.

    .PARAMETER DcrKind
        Direct (default), for the Logs Ingestion API, or TextLog, for Azure
        Monitor Agent file collection.

    .PARAMETER Platform
        Windows (default) or Linux, for TextLog.

    .PARAMETER FilePattern
        The files the agent collects, for TextLog, which needs it.

    .PARAMETER LogFormat
        text (default) or json, for TextLog.

    .PARAMETER RecordStartTimestampFormat
        The timestamp that starts a record in a multi-line text log.
        Default ISO 8601.

    .PARAMETER DcrNamePrefix
        The prefix of each rule's name, before the table name without _CL,
        in lower case. Default dcr-.

    .PARAMETER DcrResourceGroupName
        The resource group for the rules. Defaults to the workspace's.

    .PARAMETER Location
        The rules' region. Defaults to the workspace's, which a rule must
        share.

    .PARAMETER TransformKql
        A transform to use instead of the one built. It must output the
        table's schema, so it is for one table only.

    .PARAMETER DataCollectionEndpointResourceId
        A data collection endpoint. Usually not needed: a Direct rule has
        its own endpoint, and Azure Monitor Agent needs one only for private
        link.

    .PARAMETER Path
        The folder the templates are written to, one <rule>.json each.
        Defaults to the current folder.

    .PARAMETER Deploy
        Deploy each template after writing it.

    .PARAMETER GrantIngestionRoleTo
        Identities (application ids or any principal's object ids) to give
        Monitoring Metrics Publisher on each deployed rule, so they can send
        to it. Needs Owner or User Access Administrator on the rule; a grant
        that cannot be made is a warning with the command to run.

    .PARAMETER SkipTableMigration
        Write the templates only and leave the tables. A rule cannot be
        deployed to a table that is still Classic, so with -Deploy each
        such table fails.

    .PARAMETER Force
        Migrate without the confirmation.

    .PARAMETER Context
        The workspace, from Connect-iSOCWorkspace. Defaults to the
        connected one.

    .OUTPUTS
        [pscustomobject] An iSOCDeployments.TableMigrationRun: Tables (the
        inventory), Results (one per table processed: TableName,
        SubTypeAfter, Migrated, RowCount, GB90d, DcrName, TemplatePath,
        Deployed, ImmutableId, Endpoint, Granted, Error), Migrated,
        Deployed, Failed and ExitCode.

    .EXAMPLE
        Invoke-iSOCClassicTableMigration -AllClassicTables -ListOnly

        Lists every classic table with its columns, rows and volume.
        Changes nothing. Start here.

    .EXAMPLE
        Invoke-iSOCClassicTableMigration -TableName MyApp_CL -SkipTableMigration -Path ./Infra/dcr

        Writes the rule template for one table without touching the
        workspace.

    .EXAMPLE
        Invoke-iSOCClassicTableMigration -TableName MyApp_CL -Deploy -GrantIngestionRoleTo 11111111-1111-1111-1111-111111111111

        Migrates the table after asking, deploys its rule, and lets the
        application send to it.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_]+$')]
        [string[]] $TableName,

        [Parameter(ParameterSetName = 'All', Mandatory)]
        [switch] $AllClassicTables,

        [switch] $ListOnly,

        [switch] $IncludeEmptyTables,

        [ValidateSet('Direct', 'TextLog')]
        [string] $DcrKind = 'Direct',

        [ValidateSet('Windows', 'Linux')]
        [string] $Platform = 'Windows',

        [string[]] $FilePattern,

        [ValidateSet('text', 'json')]
        [string] $LogFormat = 'text',

        [string] $RecordStartTimestampFormat = 'ISO 8601',

        [string] $DcrNamePrefix = 'dcr-',

        [string] $DcrResourceGroupName,

        [string] $Location,

        [string] $TransformKql,

        [string] $DataCollectionEndpointResourceId,

        [string] $Path,

        [switch] $Deploy,

        [string[]] $GrantIngestionRoleTo,

        [switch] $SkipTableMigration,

        [switch] $Force,

        [psobject] $Context
    )

    $ctx = Resolve-iSOCContext -Context $Context
    $steps = @('Connect', 'Migrate')
    if ($Deploy -and -not $ListOnly) { $steps += 'Deploy' }
    Assert-iSOCPrerequisite -Step $steps

    Write-iSOCLog 'Classic table to DCR migration' -Level Section
    if (-not $Location) { $Location = $ctx.Region }
    if (-not $DcrResourceGroupName) { $DcrResourceGroupName = $ctx.ResourceGroup }
    if (-not $Path) { $Path = (Get-Location).Path }
    Write-iSOCLog "Workspace    : $($ctx.WorkspaceName) ($Location)"

    if ($DcrKind -eq 'TextLog' -and (-not $FilePattern -or $FilePattern.Count -eq 0)) {
        throw '-FilePattern is required when -DcrKind is TextLog.'
    }

    Write-iSOCLog 'Discovering tables' -Level Section
    $volumeByTable = Get-iSOCTableIngestionVolume -Context $ctx

    if ($AllClassicTables) {
        $allClassic = @(Get-iSOCClassicTableName -Context $ctx)
        Write-iSOCLog "Classic tables found: $($allClassic.Count)"
        $targetTables = @($allClassic | Where-Object { $_ -like '*_CL' })
        $notCustomLogs = @($allClassic | Where-Object { $_ -notlike '*_CL' })
        if ($notCustomLogs.Count -gt 0) {
            Write-iSOCLog "Excluding $($notCustomLogs.Count) non-custom table(s) reported as Classic: $($notCustomLogs -join ', ')." -Level Warning
            Write-iSOCLog 'These are platform tables that report Classic because Custom Fields were created against them. They are fed by diagnostic settings, not the Data Collector API, and must not be migrated.' -Level Warning
        }
        if ($targetTables.Count -eq 0) {
            Write-iSOCLog 'No classic custom log tables in this workspace. Nothing to migrate.' -Level Success
            return (New-iSOCTableMigrationRun)
        }
    }
    else {
        $targetTables = @($TableName | ForEach-Object { if ($_.EndsWith('_CL')) { $_ } else { "${_}_CL" } })
    }

    if ($TransformKql -and $targetTables.Count -gt 1) {
        throw '-TransformKql applies to a single table only, because a transform is specific to one schema.'
    }

    $inventory = @(Get-iSOCClassicTableInventory -Context $ctx -TableName $targetTables -Volume $volumeByTable)
    Write-iSOCClassicTableInventory -Inventory $inventory

    if ($ListOnly) {
        Write-iSOCLog ''
        Write-iSOCLog 'Report only (-ListOnly). Nothing was migrated, written, or deployed.' -Level Success
        return (New-iSOCTableMigrationRun -Tables $inventory)
    }

    $queue = @(foreach ($row in $inventory) {
            if ($row.Error) {
                Write-iSOCLog "Skipping $($row.Name): $($row.Error)" -Level Warning
                continue
            }
            if ($row.Name -notlike '*_CL') {
                Write-iSOCLog "Skipping $($row.Name): not a custom log table (no _CL suffix). Platform tables cannot be migrated to DCR-based custom logs." -Level Warning
                continue
            }
            if ($AllClassicTables -and -not $IncludeEmptyTables -and $row.RowCount -eq 0) {
                Write-iSOCLog "Skipping $($row.Name): no rows in the last 90 days (use -IncludeEmptyTables to override)." -Level Warning
                continue
            }
            $row
        })

    if ($queue.Count -eq 0) {
        Write-iSOCLog 'Nothing left to process.' -Level Warning
        return (New-iSOCTableMigrationRun -Tables $inventory)
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, 'Create output directory')) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
    }

    $confirmBypassed = $Force -or ($PSBoundParameters.ContainsKey('Confirm') -and (-not $PSBoundParameters['Confirm']))
    $item = @{
        Context                          = $ctx
        SkipTableMigration               = $SkipTableMigration
        DcrKind                          = $DcrKind
        Platform                         = $Platform
        FilePattern                      = $FilePattern
        LogFormat                        = $LogFormat
        RecordStartTimestampFormat       = $RecordStartTimestampFormat
        DcrNamePrefix                    = $DcrNamePrefix
        DcrResourceGroupName             = $DcrResourceGroupName
        Location                         = $Location
        TransformKql                     = $TransformKql
        DataCollectionEndpointResourceId = $DataCollectionEndpointResourceId
        Path                             = $Path
        Deploy                           = $Deploy
        GrantIngestionRoleTo             = $GrantIngestionRoleTo
        ConfirmBypassed                  = $confirmBypassed
    }
    $results = @(foreach ($row in $queue) { Invoke-iSOCTableMigrationItem -Row $row @item })

    Write-iSOCTableMigrationRunSummary -Results $results -DcrKind $DcrKind -DcrResourceGroupName $DcrResourceGroupName
    New-iSOCTableMigrationRun -Tables $inventory -Results $results
}
