#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.OperationalInsights, Az.Resources

<#
.SYNOPSIS
    Discovers classic (MMA / Data Collector API) custom log tables, migrates
    them to DCR-based tables, and exports a Data Collection Rule for each.

.DESCRIPTION
    Classic "_CL v1" tables are the ones created by the MMA Custom Log Wizard
    or fed by the HTTP Data Collector API. Their tableSubType is 'Classic',
    and Data Collection Rules refuse to target them:

        Classic (MMA-based) custom log tables for stream 'Custom-Foo_CL' with
        destination '...' are not supported in Data Collection Rules.
        (Code: InvalidOutputTable)

    Deleting and recreating the table loses the data and often collides with
    retained schema metadata. The supported fix is the one-way migrate
    operation, wrapped here by Invoke-AzOperationalInsightsMigrateTable.

    This script covers the whole migration, for one table or the entire
    workspace:

      1. DISCOVER. Lists every table whose tableSubType is 'Classic', with
         its column count and 90-day billable volume, so you can see which
         tables are actually carrying data before changing anything. Use
         -ListOnly to stop here.
      2. MIGRATE. Converts each selected table with the migrate API. This is
         irreversible, so it runs behind ShouldProcess plus an explicit
         confirmation that -Force bypasses.
      3. EXPORT. Derives a DCR stream declaration from the post-migration
         schema and writes an ARM template per table, ready to commit.
      4. DEPLOY (optional). Deploys the templates and reports each DCR's
         immutable ID and logs ingestion endpoint.

    Empty tables are skipped by default during discovery. Emptiness is
    judged by counting actual rows over 90 days, not by billable GB: the
    Usage table lags for hours, so a freshly populated table can report zero
    GB while already holding queryable rows. A table with genuinely no rows
    is usually an abandoned forwarder, and migrating it just carries legacy
    cruft forward. -IncludeEmptyTables overrides the skip.

    Two DCR shapes are supported through -DcrKind:

      Direct   kind: Direct. For data pushed over the Logs Ingestion API, the
               successor to the HTTP Data Collector API. The stream is built
               from the table schema and the DCR gets its own built-in
               logsIngestion endpoint, so no Data Collection Endpoint is
               required unless you use private link.

      TextLog  kind: Windows or Linux with a logFiles data source, for tables
               populated by the MMA Custom Log Wizard reading files off
               machines and now collected by Azure Monitor Agent.

    After migration the Log Analytics agent can no longer write to a table,
    and any Custom Fields defined against it stop receiving new data. Migrate
    the agents before you migrate the tables.

.PARAMETER ResourceGroupName
    Resource group containing the Log Analytics workspace.

.PARAMETER WorkspaceName
    Log Analytics workspace name.

.PARAMETER TableName
    One or more custom log tables to process, for example 'MyApp_CL'. The
    '_CL' suffix is appended automatically if omitted. Mutually exclusive
    with -AllClassicTables.

.PARAMETER AllClassicTables
    Process every table in the workspace whose tableSubType is 'Classic'.
    Mutually exclusive with -TableName.

.PARAMETER ListOnly
    Report the classic tables and stop. Nothing is migrated, written, or
    deployed. Safe to run against production at any time.

.PARAMETER IncludeEmptyTables
    Include classic tables with no rows in the last 90 days.
    By default those are listed but skipped, because migrating a dead table
    preserves legacy cruft rather than removing it.

.PARAMETER SubscriptionId
    Subscription to operate in. Defaults to the current Az context.

.PARAMETER DcrKind
    'Direct' for a Logs Ingestion API DCR (default), or 'TextLog' for an
    Azure Monitor Agent file-collection DCR.

.PARAMETER Platform
    Agent platform for -DcrKind TextLog: 'Windows' (default) or 'Linux'.

.PARAMETER FilePattern
    One or more file patterns the agent should collect, for example
    'C:\logs\*.txt'. Required for -DcrKind TextLog.

.PARAMETER LogFormat
    'text' (default) or 'json' for -DcrKind TextLog.

.PARAMETER RecordStartTimestampFormat
    Timestamp format that marks the start of a record in a multi-line text
    log. Defaults to 'ISO 8601'. Only used for -LogFormat text.

.PARAMETER DcrNamePrefix
    Prefix for generated DCR names. Defaults to 'dcr-'. The table name with
    the '_CL' suffix stripped and lower-cased is appended.

.PARAMETER DcrResourceGroupName
    Resource group to create the DCRs in. Defaults to -ResourceGroupName.

.PARAMETER Location
    Azure region for the DCRs. Defaults to the workspace region. A DCR must
    be in the same region as its destination workspace.

.PARAMETER TransformKql
    Override the generated ingestion-time transform. The transform must
    output the schema of the destination table. Only valid for a single
    table, since a transform is schema-specific.

.PARAMETER DataCollectionEndpointResourceId
    Resource ID of an existing Data Collection Endpoint. Usually unnecessary:
    Direct DCRs expose their own endpoint, and AMA only needs a DCE for
    private link, Windows Firewall Logs, or Prometheus metrics.

.PARAMETER OutputDirectory
    Directory to write the generated ARM templates into, one file per table
    named '<DcrName>.json'. Defaults to the current directory. Point it at
    the repo's Infra/dcr when you want the templates committed.

.PARAMETER Deploy
    Deploy each generated template after writing it.

.PARAMETER GrantIngestionRoleTo
    One or more identities to grant the Monitoring Metrics Publisher role on
    each deployed DCR, so they can send to its Logs Ingestion endpoint. Each
    value may be a service principal application (client) ID or any principal
    object ID (user, group, managed identity, or SP object ID). Generic on
    purpose: name whatever real sender will use the DCR, not a test-specific
    identity. Only takes effect with -Deploy. Requires Owner or User Access
    Administrator on the DCR; if you lack it, the grant is skipped with the
    manual command reported, and the deployment still succeeds.

.PARAMETER SkipTableMigration
    Export the DCR templates only and leave the tables alone. Tables are
    still read, because stream declarations derive from their schemas, but
    nothing is written to the workspace.

    Note a DCR cannot be deployed against a table that is still Classic, so
    -SkipTableMigration and -Deploy together will be refused per table.

.PARAMETER Force
    Skip the confirmation prompt on the irreversible table migration.
    Required when running non-interactively.

.EXAMPLE
    ./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-sentinel `
        -WorkspaceName law-sentinel -AllClassicTables -ListOnly

    Reports every classic table in the workspace with its column count and
    90-day volume, and flags the empty ones. Changes nothing. Start here.

.EXAMPLE
    ./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-sentinel `
        -WorkspaceName law-sentinel -TableName MyApp_CL -SkipTableMigration

    Exports the DCR template for one table without touching the workspace.

.EXAMPLE
    ./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-sentinel `
        -WorkspaceName law-sentinel -AllClassicTables -Deploy -Force

    Migrates every non-empty classic table and deploys a DCR for each.
    Irreversible. Run the -ListOnly form first.

.EXAMPLE
    ./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-sentinel `
        -WorkspaceName law-sentinel -TableName MyApp_CL -Deploy -Force `
        -GrantIngestionRoleTo 11111111-1111-1111-1111-111111111111

    Migrates, deploys the DCR, and grants Monitoring Metrics Publisher on it
    to the given service principal (by application ID) so it can send to the
    ingestion endpoint.

.EXAMPLE
    ./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-sentinel `
        -WorkspaceName law-sentinel -TableName IisCustom_CL `
        -DcrKind TextLog -FilePattern 'C:\inetpub\logs\*.log'

    Migrates one table and exports an Azure Monitor Agent text-log DCR. The
    generated transform is a passthrough placeholder: edit it to parse
    RawData into the table's columns before associating any machines.

.NOTES
    File:         Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Created:      2026-07-20
    Version:      2.0.1
    Last Updated: 2026-09-01
    Website:      https://sentinel.blog
    Requires:     PowerShell 7.2+, Az.Accounts, Az.OperationalInsights, Az.Resources

    Runs standalone. Nothing from this repository needs to be alongside it.

    Required RBAC:
      - Log Analytics Contributor on the workspace (table migration)
      - Log Analytics Reader on the workspace (volume lookup, optional)
      - Contributor on the DCR resource group (deployment)

    API versions:
      - Log Analytics tables  : 2023-09-01
      - Data collection rules : 2023-03-11 (the version that added
                                'endpoints', so Direct DCRs authored here
                                receive a built-in logsIngestion endpoint)

    Reference:
      https://learn.microsoft.com/powershell/module/az.operationalinsights/invoke-azoperationalinsightsmigratetable
      https://learn.microsoft.com/azure/azure-monitor/logs/custom-logs-migrate
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
param (
    [Parameter(Mandatory)]
    [string] $ResourceGroupName

  , [Parameter(Mandatory)]
    [string] $WorkspaceName

  , [Parameter(ParameterSetName = 'ByName', Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_]+$')]
    [string[]] $TableName

  , [Parameter(ParameterSetName = 'All', Mandatory)]
    [switch] $AllClassicTables

  , [Parameter()]
    [switch] $ListOnly

  , [Parameter()]
    [switch] $IncludeEmptyTables

  , [Parameter()]
    [string] $SubscriptionId

  , [Parameter()]
    [ValidateSet('Direct', 'TextLog')]
    [string] $DcrKind = 'Direct'

  , [Parameter()]
    [ValidateSet('Windows', 'Linux')]
    [string] $Platform = 'Windows'

  , [Parameter()]
    [string[]] $FilePattern

  , [Parameter()]
    [ValidateSet('text', 'json')]
    [string] $LogFormat = 'text'

  , [Parameter()]
    [string] $RecordStartTimestampFormat = 'ISO 8601'

  , [Parameter()]
    [string] $DcrNamePrefix = 'dcr-'

  , [Parameter()]
    [string] $DcrResourceGroupName

  , [Parameter()]
    [string] $Location

  , [Parameter()]
    [string] $TransformKql

  , [Parameter()]
    [string] $DataCollectionEndpointResourceId

  , [Parameter()]
    [string] $OutputDirectory

  , [Parameter()]
    [switch] $Deploy

  , [Parameter()]
    [string[]] $GrantIngestionRoleTo

  , [Parameter()]
    [switch] $SkipTableMigration

  , [Parameter()]
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region -- Logging ------------------------------------------------------------

# Self-contained by design. This kit deliberately does NOT import the repo's
# Sentinel.Common module: it must run unchanged on a jump box or in an
# automation account where that module is absent. Write-PipelineMessage is
# defined locally to mirror Sentinel.Common's behaviour.

function Write-PipelineMessage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Console output is the point; mirrors Sentinel.Common.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Section', 'Success', 'Debug')]
        [string]$Level = 'Info'
    )

    $isAdo = $null -ne $env:BUILD_BUILDID

    switch ($Level) {
        'Info'    { Write-Host $Message }
        'Warning' {
            if ($isAdo) { Write-Host "##[warning]$Message" } else { Write-Warning $Message }
        }
        'Error'   {
            if ($isAdo) { Write-Host "##[error]$Message" } else { Write-Error $Message -ErrorAction Continue }
        }
        'Section' {
            if ($isAdo) { Write-Host "##[section]$Message" } else { Write-Host "`n$Message" -ForegroundColor Cyan }
        }
        'Success' {
            if ($isAdo) { Write-Host $Message } else { Write-Host $Message -ForegroundColor Green }
        }
        'Debug'   { Write-Verbose $Message }
    }
}

#endregion

#region -- Constants -----------------------------------------------------------

$script:TablesApiVersion = '2023-09-01'

# 2023-03-11 is the API version that added the 'endpoints' property to
# DataCollectionRuleResourceProperties, so a Direct DCR authored here receives
# its own logsIngestion endpoint and needs no Data Collection Endpoint.
$script:DcrApiVersion = '2023-03-11'

# Column names a DCR stream declaration may never contain. Some are reserved by
# Azure Monitor outright, the rest are populated by the platform rather than the
# caller. Matching is case-insensitive, which is what -contains does by default.
$script:ReservedColumns = @(
    'TenantId'
    'Type'
    'UniqueId'
    'Title'
    'id'
    'MG'
    'ManagementGroupName'
    'SourceSystem'
)

# Tables API column types -> DCR stream declaration types. 'guid' has no stream
# equivalent: Azure Monitor stores GUIDs as strings, and both ingestion APIs
# read and write them as strings, so guid columns must be declared as string.
$script:ColumnTypeMap = @{
    'string'   = 'string'
    'int'      = 'int'
    'long'     = 'long'
    'real'     = 'real'
    'boolean'  = 'boolean'
    'bool'     = 'boolean'
    'datetime' = 'datetime'
    'dynamic'  = 'dynamic'
    'guid'     = 'string'
}

# Fixed incoming schema for AMA text log collection. Not derived from the
# table: the agent always emits these four columns for -LogFormat text.
$script:TextLogStreamColumns = @(
    [pscustomobject] @{ name = 'TimeGenerated'; type = 'datetime' }
    [pscustomobject] @{ name = 'RawData';       type = 'string'   }
    [pscustomobject] @{ name = 'FilePath';      type = 'string'   }
    [pscustomobject] @{ name = 'Computer';      type = 'string'   }
)

#endregion

#region -- Helpers -------------------------------------------------------------

function Invoke-ArmRequest {
    <#
    .SYNOPSIS
        Thin wrapper around Invoke-AzRestMethod with consistent error handling.

    .DESCRIPTION
        Accepts either an ARM-relative path ('/subscriptions/...') or a fully
        qualified URL, and routes to the matching Invoke-AzRestMethod
        parameter set. -Uri rejects a relative URI outright ("This operation
        is not supported for a relative URI"), while -Path expects the
        Resource Manager hostname to be absent.

        Relative is the preferred form: -Path resolves against the current Az
        environment's Resource Manager endpoint, so the same call works in
        Azure Government and other sovereign clouds without the caller
        hardcoding a hostname.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Uri

      , [Parameter()]
        [string] $Method = 'GET'

      , [Parameter()]
        [int[]] $SuccessCodes = @(200, 201, 202, 204)
    )

    $response = if ([System.Uri]::IsWellFormedUriString($Uri, [System.UriKind]::Absolute)) {
        Invoke-AzRestMethod -Uri $Uri -Method $Method
    }
    else {
        Invoke-AzRestMethod -Path $Uri -Method $Method
    }

    if ($response.StatusCode -notin $SuccessCodes) {
        throw "ARM request failed [$Method $Uri]: HTTP $($response.StatusCode) $($response.Content)"
    }

    return $response
}

function Get-DcrColumnType {
    <#
    .SYNOPSIS
        Maps a Tables API column type onto a DCR stream declaration type.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $TableColumnType
    )

    $key = $TableColumnType.ToLowerInvariant()

    if ($script:ColumnTypeMap.ContainsKey($key)) {
        return $script:ColumnTypeMap[$key]
    }

    Write-PipelineMessage "Unrecognised column type '$TableColumnType'. Declaring it as 'string'." -Level Warning
    return 'string'
}

function ConvertTo-StreamColumn {
    <#
    .SYNOPSIS
        Converts Tables API schema columns into DCR stream declaration
        columns, reporting anything it had to leave behind.

    .DESCRIPTION
        Drops reserved, platform and hidden columns, and any column whose name
        does not start with a letter. Stream column names must start with a
        letter, so classic artefacts like '_ResourceId_s' and '_table_s'
        cannot be carried across at all: they are returned in Dropped so the
        caller can tell the operator those columns stop receiving data.

        Guarantees TimeGenerated is present, since the destination table needs
        it either in the input stream or produced by the transform.

    .OUTPUTS
        PSCustomObject with Columns (the stream declaration) and Dropped
        (name/reason pairs).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $SchemaColumn
    )

    $columns = [System.Collections.Generic.List[pscustomobject]]::new()
    $dropped = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($column in $SchemaColumn) {
        if (-not $column) { continue }

        $name = $column.name

        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $reason = $null

        if ($script:ReservedColumns -contains $name) {
            $reason = 'reserved column name'
        }
        elseif ($name -notmatch '^[A-Za-z]') {
            $reason = 'stream column names must start with a letter'
        }
        else {
            $hiddenProperty = $column.PSObject.Properties['isHidden']
            if ($hiddenProperty -and $hiddenProperty.Value -eq $true) {
                $reason = 'hidden column'
            }
        }

        if ($reason) {
            $dropped.Add([pscustomobject] @{ Name = $name; Reason = $reason })
            continue
        }

        $typeProperty = $column.PSObject.Properties['type']
        $type = if ($typeProperty -and $typeProperty.Value) { [string]$typeProperty.Value } else { 'string' }

        $columns.Add([pscustomobject] @{
            name = $name
            type = Get-DcrColumnType -TableColumnType $type
        })
    }

    $declaredNames = @($columns | ForEach-Object { $_.name })

    if ($declaredNames -notcontains 'TimeGenerated') {
        $columns.Insert(0, [pscustomobject] @{ name = 'TimeGenerated'; type = 'datetime' })
    }

    return [pscustomobject] @{
        Columns = $columns.ToArray()
        Dropped = $dropped.ToArray()
    }
}

function Get-DefaultTransform {
    <#
    .SYNOPSIS
        Builds the ingestion-time transform that reconciles the stream
        declaration types with the destination table's column types.

    .DESCRIPTION
        Azure Monitor validates that every transform OUTPUT column type
        matches the destination table column type. A plain 'source'
        passthrough fails whenever the stream declares a column as a
        different type from the table:

            Types of transform output columns do not match the ones defined
            by the output stream: EventId_g [produced:'String', output:'Guid']
            (Code: InvalidTransformOutput)

        The most common cause is 'guid': a DCR stream declaration cannot
        express guid, so guid columns are declared as string, but the table
        column stays guid. The passthrough then sends string to a guid
        column and the deployment fails. Rather than special-case guid, this
        compares each surviving column's declared stream type against its
        table type and, on any mismatch, casts back to the table type with
        the matching KQL function (toguid, toint, todatetime, and so on).
        This catches every type divergence, not just the guid one seen
        first, which matters when migrating unknown production schemas.

        A table whose columns all match gets a plain 'source'.

    .PARAMETER SchemaColumn
        The destination table's columns with their real Tables API types.

    .PARAMETER StreamColumn
        The stream declaration columns as they will be declared in the DCR
        (guid already remapped to string). A column absent here was dropped
        from the stream and needs no cast.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $SchemaColumn
      , [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $StreamColumn
    )

    # KQL cast function per destination (table) column type. The transform
    # output must land as the table's type; cast to it when the stream
    # declares something else.
    $castByType = @{
        'string'   = 'tostring'
        'int'      = 'toint'
        'long'     = 'tolong'
        'real'     = 'toreal'
        'boolean'  = 'tobool'
        'datetime' = 'todatetime'
        'guid'     = 'toguid'
        'dynamic'  = 'todynamic'
    }

    $streamTypeByName = @{}
    foreach ($stream in $StreamColumn) {
        if ($stream) { $streamTypeByName[$stream.name] = ([string]$stream.type).ToLowerInvariant() }
    }

    $casts = foreach ($column in $SchemaColumn) {
        if (-not $column) { continue }

        $name = $column.name
        if (-not $streamTypeByName.ContainsKey($name)) { continue }   # dropped from the stream

        $tableType = ([string]$column.type).ToLowerInvariant()
        if ($tableType -eq 'bool') { $tableType = 'boolean' }

        $streamType = $streamTypeByName[$name]

        if ($streamType -ne $tableType) {
            if ($castByType.ContainsKey($tableType)) {
                '{0} = {1}({0})' -f $name, $castByType[$tableType]
            }
            else {
                # A type we cannot cast (should not occur with the fixed
                # Tables API type set). Warn rather than emit a broken cast;
                # the deployment will surface it precisely if it is real.
                Write-PipelineMessage "Column '$name' has table type '$tableType' with no known cast; leaving it to passthrough." -Level Warning
            }
        }
    }

    $casts = @($casts)

    if ($casts.Count -eq 0) {
        return 'source'
    }

    return 'source | extend ' + ($casts -join ', ')
}

function Resolve-PrincipalObjectId {
    <#
    .SYNOPSIS
        Resolves an identity string to an Entra principal object ID.

    .DESCRIPTION
        Accepts either a service principal application (client) ID, which is
        resolved to its object ID, or any principal object ID (user, group,
        managed identity, or SP object ID), which is returned unchanged. The
        object ID is the universal identifier that New-AzRoleAssignment takes
        for every principal type.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $Identity
    )

    try {
        $sp = Get-AzADServicePrincipal -ApplicationId $Identity -ErrorAction Stop
        if ($sp -and $sp.Id) { return [string]$sp.Id }
    }
    catch {
        Write-Verbose "Not an application ID, treating '$Identity' as an object ID: $($_.Exception.Message.Split([char]10)[0])"
    }

    return $Identity
}

function Build-DcrArmTemplate {
    <#
    .SYNOPSIS
        Builds the ARM template object for a Data Collection Rule.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [string]   $Name
      , [Parameter(Mandatory)] [string]   $Region
      , [Parameter(Mandatory)] [string]   $Kind
      , [Parameter(Mandatory)] [string]   $Stream
      , [Parameter(Mandatory)] [object[]] $StreamColumn
      , [Parameter(Mandatory)] [string]   $WorkspaceResourceId
      , [Parameter(Mandatory)] [string]   $OutputStream
      , [Parameter(Mandatory)] [string]   $Transform
      , [Parameter()]          [string]   $EndpointResourceId
      , [Parameter()]          [object]   $LogFilesDataSource
      , [Parameter()]          [string]   $Description
    )

    $properties = [ordered] @{}

    if ($Description) {
        $properties['description'] = $Description
    }

    if ($EndpointResourceId) {
        $properties['dataCollectionEndpointId'] = $EndpointResourceId
    }

    $properties['streamDeclarations'] = [ordered] @{
        $Stream = [ordered] @{ columns = @($StreamColumn) }
    }

    if ($LogFilesDataSource) {
        $properties['dataSources'] = [ordered] @{ logFiles = @($LogFilesDataSource) }
    }

    $properties['destinations'] = [ordered] @{
        logAnalytics = @(
            [ordered] @{
                workspaceResourceId = $WorkspaceResourceId
                name                = 'workspaceDestination'
            }
        )
    }

    $properties['dataFlows'] = @(
        [ordered] @{
            streams      = @($Stream)
            destinations = @('workspaceDestination')
            transformKql = $Transform
            outputStream = $OutputStream
        }
    )

    return @{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        metadata       = [ordered] @{
            description = "Data collection rule for $OutputStream, generated by Invoke-ClassicTableMigration.ps1."
        }
        resources      = @(
            [ordered] @{
                type       = 'Microsoft.Insights/dataCollectionRules'
                apiVersion = $script:DcrApiVersion
                name       = $Name
                location   = $Region
                kind       = $Kind
                properties = $properties
            }
        )
    }
}

function Get-WorkspaceTableDetail {
    <#
    .SYNOPSIS
        Reads one workspace table and normalises the bits this script needs.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [string] $SubscriptionId
      , [Parameter(Mandatory)] [string] $ResourceGroupName
      , [Parameter(Mandatory)] [string] $WorkspaceName
      , [Parameter(Mandatory)] [string] $Table
    )

    $uri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" +
           "/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName" +
           "/tables/$Table" + "?api-version=$script:TablesApiVersion"

    $body   = (Invoke-ArmRequest -Uri $uri -SuccessCodes @(200)).Content | ConvertFrom-Json
    $schema = $body.properties.schema

    $subTypeProp = $schema.PSObject.Properties['tableSubType']
    $typeProp    = $schema.PSObject.Properties['tableType']
    $planProp    = $body.properties.PSObject.Properties['plan']
    $columnsProp = $schema.PSObject.Properties['columns']

    return [pscustomobject] @{
        Name     = $Table
        SubType  = if ($subTypeProp -and $subTypeProp.Value) { [string]$subTypeProp.Value } else { 'Unknown' }
        TableType= if ($typeProp -and $typeProp.Value) { [string]$typeProp.Value } else { 'Unknown' }
        Plan     = if ($planProp -and $planProp.Value) { [string]$planProp.Value } else { 'Analytics' }
        Columns  = if ($columnsProp -and $columnsProp.Value) { @($columnsProp.Value) } else { @() }
    }
}

function Get-ClassicTableName {
    <#
    .SYNOPSIS
        Lists every table in the workspace whose tableSubType is 'Classic'.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter(Mandatory)] [string] $SubscriptionId
      , [Parameter(Mandatory)] [string] $ResourceGroupName
      , [Parameter(Mandatory)] [string] $WorkspaceName
    )

    $uri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" +
           "/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName" +
           "/tables?api-version=$script:TablesApiVersion"

    $body = (Invoke-ArmRequest -Uri $uri -SuccessCodes @(200)).Content | ConvertFrom-Json

    $valueProp = $body.PSObject.Properties['value']
    if (-not $valueProp -or -not $valueProp.Value) { return @() }

    $names = foreach ($table in @($valueProp.Value)) {
        $schemaProp = $table.properties.PSObject.Properties['schema']
        if (-not $schemaProp -or -not $schemaProp.Value) { continue }

        $subTypeProp = $schemaProp.Value.PSObject.Properties['tableSubType']
        if (-not $subTypeProp) { continue }

        if ([string]$subTypeProp.Value -eq 'Classic') { [string]$table.name }
    }

    return @($names | Sort-Object)
}

function Get-TableIngestionVolume {
    <#
    .SYNOPSIS
        Best-effort 90-day billable volume per table, from the Usage table.

    .DESCRIPTION
        Used only to tell live tables from abandoned ones. Requires read
        access to the workspace data; if the query fails (no permission,
        Usage unavailable) the caller falls back to treating volume as
        unknown rather than failing the run.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [string] $WorkspaceId
    )

    $result = @{}

    $query = @'
Usage
| where TimeGenerated > ago(90d)
| where IsBillable == true
| summarize GB = round(sum(Quantity) / 1024, 4) by DataType
'@

    try {
        $response = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $query -ErrorAction Stop

        foreach ($row in $response.Results) {
            $result[[string]$row.DataType] = [double]$row.GB
        }
    }
    catch {
        Write-PipelineMessage "Could not read ingestion volume ($($_.Exception.Message.Split([char]10)[0])). Continuing without it." -Level Warning
        return $null
    }

    return $result
}

function Get-TableRowCount {
    <#
    .SYNOPSIS
        Counts rows actually present in a table over a lookback window.

    .DESCRIPTION
        This is the authoritative "does the table have data" signal, and it
        drives the empty-table decision. It queries the table directly, not
        the Usage table: Usage is a billing rollup that lags for hours, so a
        table with live rows can report zero billable GB long after the data
        is queryable. Counting rows avoids that false negative.

        Returns the row count, or $null if the query cannot run (no query
        permission, workspace unreachable), in which case the caller treats
        emptiness as unknown rather than assuming the table is empty.
    #>
    [CmdletBinding()]
    [OutputType([int])]   # returns an int row count, or $null when unknown
    param (
        [Parameter(Mandatory)] [string] $WorkspaceId
      , [Parameter(Mandatory)] [string] $Table
      , [Parameter()]          [int]    $LookbackDays = 90
    )

    if ([string]::IsNullOrWhiteSpace($WorkspaceId)) { return $null }

    # Table name is a KQL identifier built from validated input (_CL custom
    # tables), not free text, so it is safe to interpolate here.
    $query = "$Table | where TimeGenerated > ago($($LookbackDays)d) | count"

    try {
        $response = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $query -ErrorAction Stop
        $first    = @($response.Results)[0]
        if ($first -and $first.PSObject.Properties['Count']) {
            return [int]$first.Count
        }
        return 0
    }
    catch {
        Write-PipelineMessage "Could not count rows in $Table ($($_.Exception.Message.Split([char]10)[0])). Emptiness unknown." -Level Warning
        return $null
    }
}

function Invoke-ClassicTableMigration {
    <#
    .SYNOPSIS
        Migrates one classic table, behind ShouldProcess and an explicit
        confirmation.

    .OUTPUTS
        Boolean. True if the migration ran.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)] [string] $ResourceGroupName
      , [Parameter(Mandatory)] [string] $WorkspaceName
      , [Parameter(Mandatory)] [string] $Table
      , [Parameter()]          [switch] $Force
    )

    $continueQuery = "Migrate $Table in $WorkspaceName to a DCR-based table? " +
                     'This cannot be undone, and the Log Analytics agent will no longer be able to write to it.'

    if (-not $PSCmdlet.ShouldProcess("$WorkspaceName/$Table", 'Migrate classic table to DCR-based (irreversible)')) {
        return $false
    }

    if (-not ($Force -or $PSCmdlet.ShouldContinue($continueQuery, 'Confirm irreversible table migration'))) {
        return $false
    }

    Invoke-AzOperationalInsightsMigrateTable -ResourceGroupName $ResourceGroupName `
                                             -WorkspaceName $WorkspaceName `
                                             -TableName $Table `
                                             -Confirm:$false | Out-Null

    return $true
}

#endregion

#region -- Context -------------------------------------------------------------

Write-PipelineMessage 'Classic table to DCR migration' -Level Section

$context = Get-AzContext
if (-not $context) {
    throw 'No Az context found. Run Connect-AzAccount first.'
}

if ($SubscriptionId -and $context.Subscription.Id -ne $SubscriptionId) {
    Write-PipelineMessage "Switching context to subscription $SubscriptionId"

    # Set-AzContext returns a PSAzureContext directly. It has no .Context
    # property (that belongs to the PSAzureProfile that Connect-AzAccount
    # returns), so unwrapping one here would yield $null and blow up on the
    # next line under strict mode.
    $context = Set-AzContext -Subscription $SubscriptionId
}

if (-not $context.Subscription) {
    throw 'Az context has no subscription selected. Run Connect-AzAccount or Set-AzContext -Subscription <id> first.'
}

$resolvedSubscriptionId = $context.Subscription.Id

$workspace           = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName
$workspaceResourceId = $workspace.ResourceId

if (-not $Location)             { $Location             = $workspace.Location }
if (-not $DcrResourceGroupName) { $DcrResourceGroupName = $ResourceGroupName }

if (-not $OutputDirectory) {
    # Standalone default: write templates to the current directory. Pass
    # -OutputDirectory to target the repo's Infra/dcr (or anywhere else)
    # when you want the templates committed.
    $OutputDirectory = (Get-Location).Path
}

Write-PipelineMessage "Subscription : $resolvedSubscriptionId"
Write-PipelineMessage "Workspace    : $WorkspaceName ($Location)"

if ($DcrKind -eq 'TextLog' -and (-not $FilePattern -or $FilePattern.Count -eq 0)) {
    throw '-FilePattern is required when -DcrKind is TextLog.'
}

#endregion

#region -- Select tables -------------------------------------------------------

Write-PipelineMessage 'Discovering tables' -Level Section

$volumeByTable = Get-TableIngestionVolume -WorkspaceId $workspace.CustomerId

if ($AllClassicTables) {
    $allClassic = Get-ClassicTableName -SubscriptionId $resolvedSubscriptionId `
                                       -ResourceGroupName $ResourceGroupName `
                                       -WorkspaceName $WorkspaceName

    Write-PipelineMessage "Classic tables found: $($allClassic.Count)"

    # tableSubType 'Classic' is NOT the same as "custom log table". Any table
    # against which Custom Fields were created reports as Classic, including
    # platform tables like AzureDiagnostics that are fed by diagnostic
    # settings. Those must never be migrated or given a Custom- stream: the
    # '_CL' suffix is enforced at table creation and is the authoritative
    # custom-table marker.
    $targetTables  = @($allClassic | Where-Object { $_ -like '*_CL' })
    $notCustomLogs = @($allClassic | Where-Object { $_ -notlike '*_CL' })

    if ($notCustomLogs.Count -gt 0) {
        Write-PipelineMessage "Excluding $($notCustomLogs.Count) non-custom table(s) reported as Classic: $($notCustomLogs -join ', ')." -Level Warning
        Write-PipelineMessage 'These are platform tables that report Classic because Custom Fields were created against them. They are fed by diagnostic settings, not the Data Collector API, and must not be migrated.' -Level Warning
    }

    if ($targetTables.Count -eq 0) {
        Write-PipelineMessage 'No classic custom log tables in this workspace. Nothing to migrate.' -Level Success
        return
    }
}
else {
    # Normalise names. Custom log tables always carry the _CL suffix and the
    # Tables API is case-sensitive about it.
    $targetTables = @($TableName | ForEach-Object {
        if ($_.EndsWith('_CL')) { $_ } else { "${_}_CL" }
    })
}

if ($TransformKql -and $targetTables.Count -gt 1) {
    throw '-TransformKql applies to a single table only, because a transform is specific to one schema.'
}

# Build the inventory up front so -ListOnly and the migration loop see the
# same picture, and so an unreadable table is reported rather than fatal.
$inventory = foreach ($table in $targetTables) {
    try {
        $detail = Get-WorkspaceTableDetail -SubscriptionId $resolvedSubscriptionId `
                                           -ResourceGroupName $ResourceGroupName `
                                           -WorkspaceName $WorkspaceName `
                                           -Table $table

        $gb = if ($null -eq $volumeByTable) { $null }
              elseif ($volumeByTable.ContainsKey($table)) { $volumeByTable[$table] }
              else { 0.0 }

        # Authoritative presence signal: count actual rows, not billable GB.
        $rows = Get-TableRowCount -WorkspaceId $workspace.CustomerId -Table $table

        [pscustomobject] @{
            Name        = $detail.Name
            SubType     = $detail.SubType
            Plan        = $detail.Plan
            ColumnCount = $detail.Columns.Count
            RowCount    = $rows
            GB90d       = $gb
            Columns     = $detail.Columns
            Error       = $null
        }
    }
    catch {
        [pscustomobject] @{
            Name        = $table
            SubType     = 'Unreadable'
            Plan        = ''
            ColumnCount = 0
            RowCount    = $null
            GB90d       = $null
            Columns     = @()
            Error       = $_.Exception.Message.Split([char]10)[0]
        }
    }
}

$inventory = @($inventory)

Write-PipelineMessage ''
Write-PipelineMessage ('{0,-42} {1,-24} {2,6} {3,12} {4,12}' -f 'TABLE', 'SUBTYPE', 'COLS', 'ROWS (90d)', 'GB (Usage)')
foreach ($row in $inventory) {
    $rowsText = if ($null -eq $row.RowCount) { 'unknown' } else { '{0:N0}' -f $row.RowCount }
    $gbText   = if ($null -eq $row.GB90d) { 'n/a' } else { '{0:N4}' -f $row.GB90d }
    Write-PipelineMessage ('{0,-42} {1,-24} {2,6} {3,12} {4,12}' -f $row.Name, $row.SubType, $row.ColumnCount, $rowsText, $gbText)
    if ($row.Error) {
        Write-PipelineMessage "    ! $($row.Error)" -Level Warning
    }
}

# Emptiness is decided by ACTUAL ROWS, not billable GB. Usage lags for hours,
# so a table with live data reports 0 GB long after it is queryable; keying
# the "empty" decision on rows avoids branding a populated table abandoned.
# RowCount -eq $null means the count query could not run: emptiness unknown,
# so the table is not treated as empty.
$emptyTables = @($inventory | Where-Object { $_.RowCount -eq 0 -and -not $_.Error })

if ($emptyTables.Count -gt 0) {
    Write-PipelineMessage ''
    Write-PipelineMessage "$($emptyTables.Count) table(s) have no rows in the last 90 days: $(($emptyTables.Name) -join ', ')." -Level Warning
    Write-PipelineMessage 'An empty classic table is usually an abandoned forwarder. Migrating it carries legacy cruft forward rather than removing it. Consider deleting those tables instead.' -Level Warning
}

if ($ListOnly) {
    Write-PipelineMessage ''
    Write-PipelineMessage 'Report only (-ListOnly). Nothing was migrated, written, or deployed.' -Level Success
    return $inventory | Select-Object Name, SubType, Plan, ColumnCount, RowCount, GB90d, Error
}

# Decide what actually gets processed.
$queue = foreach ($row in $inventory) {
    if ($row.Error) {
        Write-PipelineMessage "Skipping $($row.Name): $($row.Error)" -Level Warning
        continue
    }

    # Belt and braces for the explicitly-named path: only custom log tables
    # can carry a Custom- stream or be migrated by the custom-logs migrate
    # API. A platform table reporting Classic must never get here.
    if ($row.Name -notlike '*_CL') {
        Write-PipelineMessage "Skipping $($row.Name): not a custom log table (no _CL suffix). Platform tables cannot be migrated to DCR-based custom logs." -Level Warning
        continue
    }

    if ($AllClassicTables -and -not $IncludeEmptyTables -and $row.RowCount -eq 0) {
        Write-PipelineMessage "Skipping $($row.Name): no rows in the last 90 days (use -IncludeEmptyTables to override)." -Level Warning
        continue
    }

    $row
}

$queue = @($queue)

if ($queue.Count -eq 0) {
    Write-PipelineMessage 'Nothing left to process.' -Level Warning
    return
}

#endregion

#region -- Process each table --------------------------------------------------

if (-not (Test-Path -Path $OutputDirectory)) {
    if ($PSCmdlet.ShouldProcess($OutputDirectory, 'Create output directory')) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }
}

$confirmBypassed = $Force -or ($PSBoundParameters.ContainsKey('Confirm') -and (-not $PSBoundParameters['Confirm']))
$results         = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($row in $queue) {
    $table = $row.Name
    Write-PipelineMessage ''
    Write-PipelineMessage "Processing $table" -Level Section

    $migrated          = $false
    $deployed          = $false
    $dcrName           = $null
    $immutableId       = $null
    $endpoint          = $null
    $templatePath      = $null
    $failure           = $null
    $grantedIdentities = @()

    try {
        $schemaColumns = $row.Columns
        $subType       = $row.SubType

        # ---- migrate ----------------------------------------------------
        if ($SkipTableMigration) {
            Write-PipelineMessage 'Skipping migration (-SkipTableMigration).' -Level Warning
        }
        elseif ($subType -eq 'DataCollectionRuleBased') {
            Write-PipelineMessage 'Already DCR-based. Nothing to migrate.' -Level Success
        }
        elseif ($subType -eq 'Classic') {
            Write-PipelineMessage 'Migration is one-way. The Log Analytics agent will no longer be able to write to this table, and any Custom Fields defined against it stop receiving data.' -Level Warning

            $migrated = Invoke-ClassicTableMigration -ResourceGroupName $ResourceGroupName `
                                                     -WorkspaceName $WorkspaceName `
                                                     -Table $table `
                                                     -Force:$confirmBypassed

            if ($migrated) {
                Write-PipelineMessage "Migrated $table to a DCR-based table." -Level Success

                # Re-read so the stream reflects the post-migration schema.
                $refreshed     = Get-WorkspaceTableDetail -SubscriptionId $resolvedSubscriptionId `
                                                          -ResourceGroupName $ResourceGroupName `
                                                          -WorkspaceName $WorkspaceName `
                                                          -Table $table
                $schemaColumns = $refreshed.Columns
                $subType       = $refreshed.SubType
            }
            else {
                Write-PipelineMessage 'Migration declined or previewed. The table is still Classic.' -Level Warning
            }
        }
        else {
            Write-PipelineMessage "Table subtype is '$subType', not 'Classic'. Skipping migration." -Level Warning
        }

        # ---- build the stream -------------------------------------------
        $conversion   = ConvertTo-StreamColumn -SchemaColumn $schemaColumns
        $tableColumns = @($conversion.Columns)

        foreach ($drop in $conversion.Dropped) {
            Write-PipelineMessage "Column '$($drop.Name)' cannot be carried into the DCR ($($drop.Reason)). It will stop receiving data." -Level Warning
        }

        $streamName       = "Custom-$table"
        $outputStreamName = "Custom-$table"
        $dcrName          = $DcrNamePrefix + ($table -replace '_CL$', '').ToLowerInvariant()

        $logFilesDataSource = $null
        $dcrResourceKind    = 'Direct'
        $streamColumns      = $tableColumns
        # Reconcile every type divergence between the stream and the table
        # (guid declared as string is the common one), casting each back to
        # the table type, or the deployment fails with InvalidTransformOutput.
        $defaultTransform   = Get-DefaultTransform -SchemaColumn $schemaColumns -StreamColumn $tableColumns

        if ($DcrKind -eq 'TextLog') {
            $dcrResourceKind = $Platform

            if ($LogFormat -eq 'text') {
                # The agent emits a fixed four-column stream for text logs.
                # Turning RawData into the table's columns needs knowledge of
                # the log format that only the operator has, so project what
                # overlaps and leave real parsing as an explicit follow-up.
                $streamColumns = $script:TextLogStreamColumns

                $tableColumnNames = @($tableColumns | ForEach-Object { $_.name })
                $projectable      = @($script:TextLogStreamColumns |
                                        Where-Object { $tableColumnNames -contains $_.name } |
                                        ForEach-Object { $_.name })

                $defaultTransform = if ($projectable.Count -eq 0) { 'source' }
                                    else { 'source | project ' + ($projectable -join ', ') }

                Write-PipelineMessage 'Text log transform is a passthrough placeholder. Edit transformKql to parse RawData into the destination columns before associating machines.' -Level Warning
            }

            $logFileSettings = [ordered] @{
                name         = "$($table -replace '_CL$', '')-logfile"
                streams      = @($streamName)
                filePatterns = @($FilePattern)
                format       = $LogFormat
            }

            if ($LogFormat -eq 'text') {
                $logFileSettings['settings'] = [ordered] @{
                    text = [ordered] @{ recordStartTimestampFormat = $RecordStartTimestampFormat }
                }
            }

            $logFilesDataSource = $logFileSettings
        }

        $effectiveTransform = if ($TransformKql) { $TransformKql } else { $defaultTransform }

        $template = Build-DcrArmTemplate -Name $dcrName `
                                         -Region $Location `
                                         -Kind $dcrResourceKind `
                                         -Stream $streamName `
                                         -StreamColumn $streamColumns `
                                         -WorkspaceResourceId $workspaceResourceId `
                                         -OutputStream $outputStreamName `
                                         -Transform $effectiveTransform `
                                         -EndpointResourceId $DataCollectionEndpointResourceId `
                                         -LogFilesDataSource $logFilesDataSource `
                                         -Description "Ingestion into $table, migrated from a classic custom log table."

        $templatePath = Join-Path -Path $OutputDirectory -ChildPath "$dcrName.json"
        $templateJson = $template | ConvertTo-Json -Depth 30

        if ($PSCmdlet.ShouldProcess($templatePath, 'Write DCR ARM template')) {
            Set-Content -Path $templatePath -Value $templateJson -Encoding utf8NoBOM
            Write-PipelineMessage "Template : $templatePath" -Level Success
        }

        Write-PipelineMessage "Stream   : $streamName ($($streamColumns.Count) columns)"
        Write-PipelineMessage "Transform: $effectiveTransform"

        # ---- deploy ------------------------------------------------------
        if ($Deploy) {
            # A DCR cannot target a table that is still Classic. Catch that
            # here rather than letting ARM fail the deployment with
            # InvalidOutputTable, which reads like a template problem.
            if ($subType -ne 'DataCollectionRuleBased') {
                throw "Cannot deploy: $table is still '$subType'. A DCR only accepts a DataCollectionRuleBased destination. Re-run without -SkipTableMigration, or migrate the table first."
            }

            if ($PSCmdlet.ShouldProcess("$DcrResourceGroupName/$dcrName", 'Deploy data collection rule')) {
                $deploymentName = "$dcrName-$(Get-Date -Format 'yyyyMMddHHmmss')"

                # New-AzResourceGroupDeployment throws only a generic summary
                # ("failed with 1 error"); the real cause lives in the
                # deployment operations. Capture it so the failure is
                # actionable rather than opaque.
                try {
                    $deployment = New-AzResourceGroupDeployment -Name $deploymentName `
                                                                -ResourceGroupName $DcrResourceGroupName `
                                                                -TemplateFile $templatePath `
                                                                -Force -ErrorAction Stop
                }
                catch {
                    $detail = $null
                    try {
                        $ops = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $DcrResourceGroupName `
                                                                      -DeploymentName $deploymentName -ErrorAction Stop
                        $detail = @($ops |
                            Where-Object { $_.ProvisioningState -eq 'Failed' } |
                            ForEach-Object {
                                $m = $_.StatusMessage
                                if ($m -is [string]) { $m } else { ($m | ConvertTo-Json -Depth 8 -Compress) }
                            }) -join ' | '
                    }
                    catch {
                        Write-Verbose "Could not read deployment operations: $($_.Exception.Message.Split([char]10)[0])"
                    }

                    if ($detail) { throw "Deployment failed: $detail" }
                    throw
                }

                if ($deployment.ProvisioningState -ne 'Succeeded') {
                    throw "Deployment finished with state $($deployment.ProvisioningState)."
                }

                $deployed = $true
                Write-PipelineMessage "Deployed $dcrName." -Level Success

                $dcrId  = "/subscriptions/$resolvedSubscriptionId/resourceGroups/$DcrResourceGroupName" +
                          "/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
                $dcr    = (Invoke-ArmRequest -Uri "$dcrId`?api-version=$script:DcrApiVersion" -SuccessCodes @(200)).Content | ConvertFrom-Json

                $immutableProp = $dcr.properties.PSObject.Properties['immutableId']
                if ($immutableProp) {
                    $immutableId = [string]$immutableProp.Value
                    Write-PipelineMessage "ImmutableId: $immutableId"
                }

                $endpointsProp = $dcr.properties.PSObject.Properties['endpoints']
                if ($endpointsProp -and $endpointsProp.Value) {
                    $ingestProp = $endpointsProp.Value.PSObject.Properties['logsIngestion']
                    if ($ingestProp) {
                        $endpoint = [string]$ingestProp.Value
                        Write-PipelineMessage "Ingestion  : $endpoint"
                    }
                }

                if ($DcrKind -eq 'Direct' -and -not $endpoint) {
                    Write-PipelineMessage 'No logsIngestion endpoint was returned for this Direct DCR. Endpoints cannot be added to an existing DCR, so this one needs a Data Collection Endpoint or a replacement DCR.' -Level Warning
                }

                # Optionally grant the sending identity the ingestion role on
                # this DCR. Generic: whatever principal the caller names. This
                # automates the first "Next:" step; the actual POST is a
                # separate test concern and stays out of this tool.
                if ($GrantIngestionRoleTo) {
                    $roleName = 'Monitoring Metrics Publisher'
                    Write-PipelineMessage "Granting $roleName on the DCR"

                    foreach ($identity in $GrantIngestionRoleTo) {
                        try {
                            $objectId = Resolve-PrincipalObjectId -Identity $identity
                            $existing = Get-AzRoleAssignment -ObjectId $objectId -Scope $dcrId `
                                                             -RoleDefinitionName $roleName -ErrorAction SilentlyContinue

                            if ($existing) {
                                Write-PipelineMessage "  $identity already holds $roleName." -Level Success
                                $grantedIdentities += $identity
                            }
                            elseif ($PSCmdlet.ShouldProcess("$dcrName / $identity", "Grant $roleName")) {
                                New-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName $roleName `
                                                     -Scope $dcrId -ErrorAction Stop | Out-Null
                                Write-PipelineMessage "  Granted $roleName to $identity. Data-plane RBAC can take a few minutes to take effect." -Level Success
                                $grantedIdentities += $identity
                            }
                        }
                        catch {
                            Write-PipelineMessage "  Could not grant $roleName to $identity (need Owner or User Access Administrator on the DCR): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
                            Write-PipelineMessage "  Grant it manually: New-AzRoleAssignment -ObjectId <objectId> -RoleDefinitionName '$roleName' -Scope $dcrId" -Level Warning
                        }
                    }
                }
            }
        }
    }
    catch {
        $failure = $_.Exception.Message.Split([char]10)[0]
        Write-PipelineMessage "Failed: $failure" -Level Error
    }

    $results.Add([pscustomobject] @{
        TableName    = $table
        SubTypeAfter = if ($migrated) { 'DataCollectionRuleBased' } else { $row.SubType }
        Migrated     = $migrated
        RowCount     = $row.RowCount
        GB90d        = $row.GB90d
        DcrName      = $dcrName
        TemplatePath = $templatePath
        Deployed     = $deployed
        ImmutableId  = $immutableId
        Endpoint     = $endpoint
        Granted      = $grantedIdentities
        Error        = $failure
    })
}

#endregion

#region -- Summary -------------------------------------------------------------

Write-PipelineMessage ''
Write-PipelineMessage 'Summary' -Level Section

$failed = @($results | Where-Object Error)

Write-PipelineMessage "Processed : $($results.Count)"
Write-PipelineMessage "Migrated  : $(@($results | Where-Object Migrated).Count)"
Write-PipelineMessage "Deployed  : $(@($results | Where-Object Deployed).Count)"

if ($failed.Count -gt 0) {
    Write-PipelineMessage "Failed    : $($failed.Count)" -Level Warning
    foreach ($f in $failed) {
        Write-PipelineMessage "  $($f.TableName): $($f.Error)" -Level Warning
    }
}

$deployedResults = @($results | Where-Object Deployed)

if ($DcrKind -eq 'Direct' -and $deployedResults.Count -gt 0) {
    $anyGranted = @($deployedResults | Where-Object { @($_.Granted).Count -gt 0 }).Count -gt 0

    Write-PipelineMessage ''
    if ($anyGranted) {
        Write-PipelineMessage 'Next: the ingestion role is granted. Send data to:'
    }
    else {
        Write-PipelineMessage 'Next: grant Monitoring Metrics Publisher on each DCR (re-run with -GrantIngestionRoleTo), then send to:'
    }

    foreach ($r in $deployedResults) {
        $stream = "Custom-$($r.TableName)"
        if ($r.Endpoint -and $r.ImmutableId) {
            Write-PipelineMessage "  $($r.Endpoint)/dataCollectionRules/$($r.ImmutableId)/streams/${stream}?api-version=2023-01-01"
        }
        else {
            Write-PipelineMessage "  $($r.TableName): no ingestion endpoint on the DCR (needs a Data Collection Endpoint)." -Level Warning
        }
    }

    Write-PipelineMessage ''
    Write-PipelineMessage 'For a test stream, Rehearsal/Test-DcrIngestion.ps1 builds and sends that POST for you:'
    foreach ($r in $deployedResults) {
        if ($r.DcrName) {
            Write-PipelineMessage "  ./Rehearsal/Test-DcrIngestion.ps1 -DcrName $($r.DcrName) -DcrResourceGroupName $DcrResourceGroupName -Follow"
        }
    }
}

$results

#endregion
