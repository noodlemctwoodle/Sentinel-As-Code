#Requires -Version 7.2

<#
.SYNOPSIS
    Turn a JSON table schema into a Log Analytics custom table and a Direct data collection rule for the Logs Ingestion API.

.DESCRIPTION
    Replaces Tools/DcrFromSchema/New-DcrFromSchema.ps1, without its prompts:
    the workspace comes from Connect-iSOCWorkspace and everything else from the
    parameters, the schema file and the defaults.

.NOTES
    File:         Modules/iSOCDeployments/Public/New-iSOCDcrFromSchema.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCDcrFromSchema {
    <#
    .SYNOPSIS
        Turn a JSON table schema into a Log Analytics custom table and a
        Direct data collection rule for the Logs Ingestion API.

    .DESCRIPTION
        Reads the schema file, checks and repairs it, writes two ARM
        templates (the table, and the rule) and, with -Deploy, deploys them
        in order and grants the senders their role. Two templates, as the
        table and the rule can be in different resource groups and a
        resource group deployment reaches one; the table deploys first, as
        a rule naming a missing table fails with InvalidOutputTable.

        The schema file is { "tableName", "columns": [ { "name", "type" } ] },
        a table as the Tables API returns it, or a bare array of columns
        (then -TableName names the table). It may carry defaults for
        description, dcrName, location, plan, retentionInDays,
        totalRetentionInDays and transformKql. A file that will not parse
        is repaired of paste damage (a byte order mark, curly quotes,
        no-break spaces, comments, trailing commas), with a warning; a file
        that parses is never changed. Free text in it is cleaned before it
        is written into Azure, and keys the Tables API does not define are
        dropped.

        Checked before anything is written:

          - the table name ends _CL (added when missing), starts with a
            letter and is 4 to 63 letters, digits and underscores
          - each column name starts with an ASCII letter, is 2 to 45
            letters, digits and underscores, and is not a system or
            reserved name; each type is one of the Tables API's eight
            (bool, integer, double and other aliases are accepted)
          - no exact repeat; names that differ only by case are a warning,
            and refused on an Auxiliary table, which drops rows over them
          - TimeGenerated exists and is datetime; at most 500 columns; a
            transform of at most 15,360 characters; descriptions of at most
            256 characters
          - an existing table is not classic and no column's type differs
            from it (read as advice: when it cannot be read the run goes on
            with a warning)
          - the rule's resource group exists

        What can be fixed without guessing is (a bad name's column dropped,
        an exact repeat dropped, an invalid dataTypeHint removed,
        TimeGenerated added or made datetime), each with a warning; anything
        else stops the run. dataTypeHints are not sent unless
        -IncludeDataTypeHint, as the live service refuses the documented
        values. A guid column is declared string in the stream and cast back
        in the default transform, as a stream cannot declare guid.

        Each template is validated against its resource group before it
        deploys, so a preflight rejection says why. The table is written at
        Tables API 2025-07-01 (the first with the Auxiliary plan), the rule
        at 2023-03-11 (the first with endpoints, so a Direct rule has its own
        logs ingestion endpoint and needs a data collection endpoint only
        behind Private Link).

        Every write and deployment asks ShouldProcess; -WhatIf reads the
        workspace and writes nothing. Requires Az.Accounts, and Az.Resources
        with -Deploy. The table needs Log Analytics Contributor on the
        workspace, the rule Contributor on its resource group, and
        -GrantIngestionRoleTo Owner or User Access Administrator on the
        rule.

    .PARAMETER SchemaPath
        The JSON schema file.

    .PARAMETER TableName
        The table name, in place of the schema file's; _CL is added when
        missing.

    .PARAMETER DcrName
        The rule's name; the schema file's dcrName, else dcr-<table without
        _CL, lower case>.

    .PARAMETER DcrResourceGroupName
        The rule's resource group; the workspace's unless given.

    .PARAMETER Location
        The rule's region; the schema file's location, else the workspace's
        (a rule must be in its workspace's region).

    .PARAMETER DataCollectionEndpointResourceId
        A data collection endpoint, needed only when the workspace is behind
        Private Link (AMPLS) or a sender shares DNS with AMPLS resources.

    .PARAMETER TransformKql
        The ingestion-time transform; the schema file's, else a passthrough
        with a cast for each column whose stream type differs.

    .PARAMETER TablePlan
        Analytics, Basic or Auxiliary; the schema file's plan, else
        Analytics. Basic and Auxiliary tables have fixed interactive
        retention, so -RetentionInDays is ignored for them.

    .PARAMETER RetentionInDays
        Interactive retention for an Analytics table, 4 to 730 days, or -1
        for the workspace default; the schema file's, else left out.

    .PARAMETER TotalRetentionInDays
        Interactive plus long-term retention, 4 to 4383 days, or -1 to match
        interactive; the schema file's, else left out.

    .PARAMETER Description
        The table's and the rule's description; the schema file's, else
        'Custom log table <table>.'.

    .PARAMETER OutputDirectory
        The folder the templates go in; the current one unless given.

    .PARAMETER GrantIngestionRoleTo
        Identities (an application id or any principal's object id) to give
        Monitoring Metrics Publisher on the new rule.

    .PARAMETER IncludeDataTypeHint
        Send each column's dataTypeHint, which the live service has refused.

    .PARAMETER SkipTable
        Write and deploy no table: the rule targets an existing one, which
        is still read to check the schema against.

    .PARAMETER Deploy
        Deploy the templates; without it they are only written.

    .PARAMETER Context
        The workspace context; the current one (Connect-iSOCWorkspace)
        unless given.

    .OUTPUTS
        [pscustomobject] An iSOCDeployments.DcrFromSchemaRun: TableName,
        ColumnCount, WorkspaceName, ResourceGroupName, DcrName,
        DcrResourceGroup, Location, StreamName, TransformKql,
        TableTemplatePath (none with -SkipTable), DcrTemplatePath, Deployed,
        ImmutableId, Endpoint and Granted.

    .EXAMPLE
        New-iSOCDcrFromSchema -SchemaPath ./threat-intel-alerts.json -OutputDirectory ./Infra/dcr

        Writes the table and rule templates for the workspace connected to,
        and deploys nothing.

    .EXAMPLE
        New-iSOCDcrFromSchema -SchemaPath ./schema.json -Deploy -GrantIngestionRoleTo '11111111-1111-1111-1111-111111111111'

        Creates the table, deploys the rule, grants the sender its role and
        prints the Logs Ingestion URL.

    .EXAMPLE
        New-iSOCDcrFromSchema -SchemaPath ./schema.json -WhatIf

        Reads the workspace and reports what a real run would write.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Each template write and deployment asks ShouldProcess in its private step; -WhatIf and -Confirm reach them through the preference variables.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $SchemaPath,

        [string] $TableName,

        [string] $DcrName,

        [string] $DcrResourceGroupName,

        [string] $Location,

        [string] $DataCollectionEndpointResourceId,

        [string] $TransformKql,

        [ValidateSet('Analytics', 'Basic', 'Auxiliary')]
        [string] $TablePlan,

        [ValidateScript({ $_ -eq -1 -or ($_ -ge 4 -and $_ -le 730) }, ErrorMessage = 'Interactive retention must be 4 to 730 days, or -1 for the workspace default.')]
        [int] $RetentionInDays,

        [ValidateScript({ $_ -eq -1 -or ($_ -ge 4 -and $_ -le 4383) }, ErrorMessage = 'Total retention must be 4 to 4383 days, or -1 to match interactive retention.')]
        [int] $TotalRetentionInDays,

        [string] $Description,

        [string] $OutputDirectory,

        [string[]] $GrantIngestionRoleTo,

        [switch] $IncludeDataTypeHint,

        [switch] $SkipTable,

        [switch] $Deploy,

        [psobject] $Context
    )

    $ctx = Resolve-iSOCContext -Context $Context
    $steps = @('Connect')
    if ($Deploy) { $steps += 'Deploy' }
    Assert-iSOCPrerequisite -Step $steps

    Write-iSOCLog 'Create a DCR from a JSON schema' -Level Section
    $SchemaPath = (Resolve-Path -Path $SchemaPath -ErrorAction Stop).Path
    $spec = Import-iSOCTableSpec -Path $SchemaPath
    Write-iSOCLog "Schema   : $SchemaPath"

    $table = if ($TableName) { $TableName } elseif ($spec.TableName) { $spec.TableName } else { throw 'The schema file names no table, so -TableName is required.' }
    if (-not $table.EndsWith('_CL')) {
        $table = "${table}_CL"
        Write-iSOCLog "Appended the required '_CL' suffix: $table" -Level Warning
    }
    $nameProblems = @(Get-iSOCTableNameProblem -Name $table)
    if ($nameProblems.Count -gt 0) {
        throw "Table name is not usable: $($nameProblems -join '; ')."
    }
    Write-iSOCLog "Table    : $table"

    Write-iSOCLog 'Destination workspace' -Level Section
    if (-not $Location) {
        $specLocation = Get-iSOCSpecDefault -Extra $spec.Extra -Key 'location'
        $Location = if ($specLocation) { [string]$specLocation } else { $ctx.Region }
    }
    if ($Location -ne $ctx.Region) {
        Write-iSOCLog "DCR region '$Location' differs from the workspace region '$($ctx.Region)'. A DCR must be in the same region as its destination workspace." -Level Warning
    }
    if (-not $DcrResourceGroupName) { $DcrResourceGroupName = $ctx.ResourceGroup }
    Write-iSOCLog "Workspace: $($ctx.WorkspaceName) ($($ctx.ResourceGroup), $($ctx.Region))"

    $review = Get-iSOCDcrSchemaReview -Context $ctx -Spec $spec -TableName $table

    $tableSetting = @{
        TableName     = $table
        Spec          = $spec
        CaseCollision = $review.CaseCollisions
        Description   = $Description
        TablePlan     = $TablePlan
        SkipTable     = $SkipTable
    }
    if ($PSBoundParameters.ContainsKey('RetentionInDays')) { $tableSetting.RetentionInDays = $RetentionInDays }
    if ($PSBoundParameters.ContainsKey('TotalRetentionInDays')) { $tableSetting.TotalRetentionInDays = $TotalRetentionInDays }
    $tableSettings = Resolve-iSOCDcrSchemaTableSetting @tableSetting

    $rule = Resolve-iSOCDcrSchemaRuleSetting -Context $ctx -TableName $table -Spec $spec -Column $review.Columns -StreamColumn $review.StreamColumns -DcrName $DcrName -DcrResourceGroupName $DcrResourceGroupName -TransformKql $TransformKql

    if (-not $OutputDirectory) { $OutputDirectory = (Get-Location).Path }
    $OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)

    $files = Write-iSOCDcrSchemaTemplate -Context $ctx -OutputDirectory $OutputDirectory -TableName $table -Column $review.Columns -StreamColumn $review.StreamColumns -Table $tableSettings -Rule $rule -Location $Location -DataCollectionEndpointResourceId $DataCollectionEndpointResourceId -IncludeDataTypeHint:$IncludeDataTypeHint -SkipTable:$SkipTable
    $deployment = Invoke-iSOCDcrSchemaDeploy -Context $ctx -TableName $table -Rule $rule -DcrResourceGroupName $DcrResourceGroupName -Files $files -GrantIngestionRoleTo $GrantIngestionRoleTo -Deploy:$Deploy -SkipTable:$SkipTable
    Write-iSOCDcrSchemaSummary -Context $ctx -TableName $table -ColumnCount $review.Columns.Count -Rule $rule -DcrResourceGroupName $DcrResourceGroupName -Location $Location -Files $files -Deployment $deployment -SkipTable:$SkipTable

    [pscustomobject]@{
        PSTypeName        = 'iSOCDeployments.DcrFromSchemaRun'
        TableName         = $table
        ColumnCount       = $review.Columns.Count
        WorkspaceName     = $ctx.WorkspaceName
        ResourceGroupName = $ctx.ResourceGroup
        DcrName           = $rule.DcrName
        DcrResourceGroup  = $DcrResourceGroupName
        Location          = $Location
        StreamName        = $rule.StreamName
        TransformKql      = $rule.TransformKql
        TableTemplatePath = if ($SkipTable) { $null } else { $files.TablePath }
        DcrTemplatePath   = $files.DcrPath
        Deployed          = $deployment.Deployed
        ImmutableId       = $deployment.ImmutableId
        Endpoint          = $deployment.Endpoint
        Granted           = $deployment.Granted
    }
}
