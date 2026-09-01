#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.OperationalInsights, Az.Resources

<#
.SYNOPSIS
    Wizard that turns a JSON table schema into a Log Analytics custom table
    and a Direct Data Collection Rule for the Logs Ingestion API.

.DESCRIPTION
    Point this at a JSON file describing the table you want to ingest into:

        {
          "tableName": "ThreatIntelAlert_CL",
          "columns": [
            { "name": "TimeGenerated", "type": "datetime" },
            { "name": "AlertId",       "type": "string"   },
            { "name": "Highlights",    "type": "dynamic"  }
          ]
        }

    The script walks you through the rest: Azure context, workspace, a
    review-and-edit pass over the schema, table retention, DCR naming and
    the ingestion-time transform. It then writes two ARM templates and
    offers to deploy them.

    Two templates, not one, because the table and the DCR can live in
    different resource groups and an ARM resource-group deployment only
    reaches one. They are also strictly ordered: a DCR whose outputStream
    names a table that does not exist yet fails with InvalidOutputTable, so
    the table template always deploys first.

    A schema is usually pasted from somewhere: a vendor's API page, a wiki, a
    colleague's message. That journey adds things JSON does not allow, so if
    the file will not parse the wizard repairs the known-safe cases before
    giving up: a byte order mark, curly quotes, no-break spaces, // and
    /* */ comments, and trailing commas. Comment and comma removal tracks
    string state, so a '//' inside a description is left alone. A file that is
    already valid JSON is never rewritten, and every repair is reported.

    The same applies to the free text inside the schema. Descriptions and
    display names are the fields most likely to carry paste damage, and ARM
    accepts all of it, so an embedded newline or a zero-width joiner would be
    deployed and then live in the portal. Those values have control and format
    characters removed, whitespace collapsed, and length capped. Any other
    key a pasted schema carried (a "note", a "required" flag, whatever the
    source tool added) is dropped: the templates emit only the properties the
    Tables API and the DCR schema define. The transform is treated as code
    rather than prose, so only its curly quotes and no-break spaces are
    substituted, and its length is checked against the documented limit.

    What the wizard checks before it writes anything:

      - Table name ends '_CL', starts with a letter, and is 4 to 63
        characters. Custom log tables that do not carry the suffix cannot
        be created.
      - Every column name starts with an ASCII letter, is alphanumeric plus
        underscore, is 2 to 45 characters, and does not conflict with a
        system or reserved column name.
      - Every column type is one of the eight the Tables API accepts.
        Common aliases ('bool', 'integer', 'double') are normalised rather
        than rejected. A dataTypeHint is validated against its enum but is
        NOT sent, because the live service rejects the values its own
        documentation prescribes; see -IncludeDataTypeHint.
      - No exact duplicate column names. Names differing only by case are a
        warning, because Analytics and Basic tables are case sensitive and
        treat them as two columns, but they become a hard failure on an
        Auxiliary table, where ingestion drops rows because of them.
      - No more than 500 columns, and a transform no longer than 15,360
        characters.
      - Descriptions no longer than 256 characters, on both the table and
        the rule. That limit is undocumented and is only visible as a
        preflight rejection, so it is enforced here instead.
      - TimeGenerated exists. A custom table without it cannot be created,
        so the wizard adds it rather than letting the deployment fail.
      - If the table already exists, the wizard diffs the live schema
        against the spec and refuses a type change, which Azure rejects
        anyway, while allowing new columns to be added. That read is
        advisory: if it cannot be read or parsed, the run continues with a
        warning naming the guards that were skipped.

    Errors block the run and the editor makes you resolve them. Warnings
    (a classic '_s' style type suffix, a large column count) are reported
    and can be accepted.

    Before each deployment the template is validated with
    Test-AzResourceGroupDeployment, because a preflight rejection creates no
    deployment to inspect afterwards and its cause is otherwise reported
    only as "See inner errors for details".

    Two API versions matter, for different reasons:

      Tables   2025-07-01. At 2023-09-01 the Tables API knows only the
               'Analytics' and 'Basic' plans, so an Auxiliary table cannot
               be authored against it.
      DCR      2023-03-11. The earliest version carrying the 'endpoints'
               property, so a 'kind: Direct' rule gets its own logsIngestion
               endpoint and needs no Data Collection Endpoint unless the
               workspace sits behind Private Link.

    A DCR stream declaration cannot express 'guid'. Guid columns are
    therefore declared as 'string' in the stream and cast back in the
    transform (EventId = toguid(EventId)), because Azure Monitor validates
    that every transform output column type matches the destination table
    column type and a plain 'source' passthrough would fail with
    InvalidTransformOutput.

    This script is standalone. It does not import the repository's
    Sentinel.Common module, so the single file can be copied to a jump box
    or an automation account and run with only the Az modules present.

    Related but different: Tools/ClassicToDcr/ migrates tables that already
    exist as classic (MMA / Data Collector API) tables. This script creates
    a new table from a schema you wrote.

.PARAMETER SchemaPath
    Path to the JSON schema file. Prompted for if omitted.

    Three shapes are accepted:
      - { "tableName": "...", "columns": [ { "name", "type" } ] }
      - the Tables API resource shape, { "properties": { "schema": { ... } } },
        so a table exported from Azure can be fed straight back in
      - a bare array of { "name", "type" } objects, in which case the table
        name is taken from -TableName or prompted for

    Optional keys the wizard will use as defaults if present: description,
    dcrName, location, plan, retentionInDays, totalRetentionInDays,
    transformKql.

.PARAMETER TableName
    Overrides the table name in the schema file. The '_CL' suffix is
    appended if omitted.

.PARAMETER SubscriptionId
    Subscription holding the workspace. Prompted for if omitted.

.PARAMETER ResourceGroupName
    Resource group of the Log Analytics workspace. Resolved from the
    workspace picker if omitted.

.PARAMETER WorkspaceName
    Log Analytics workspace name. Prompted for if omitted.

.PARAMETER DcrName
    Name for the data collection rule. Defaults to 'dcr-' plus the table
    name with '_CL' stripped and lower-cased.

.PARAMETER DcrResourceGroupName
    Resource group to create the DCR in. Defaults to the workspace's.

.PARAMETER Location
    Azure region for the DCR. Defaults to the workspace region. A DCR must
    be in the same region as its destination workspace.

.PARAMETER DataCollectionEndpointResourceId
    Resource ID of a Data Collection Endpoint. Only needed when the
    workspace is behind Private Link (AMPLS), or a sender shares DNS with
    AMPLS resources. Otherwise a Direct DCR carries its own endpoint.

.PARAMETER TransformKql
    Ingestion-time transform. Defaults to a passthrough with casts added
    for any column whose stream type differs from its table type.

.PARAMETER TablePlan
    'Analytics' (default), 'Basic' or 'Auxiliary'. Basic and Auxiliary
    tables have service-fixed interactive retention, so -RetentionInDays
    is ignored for those and only -TotalRetentionInDays is sent.

.PARAMETER RetentionInDays
    Interactive retention for an Analytics table, 4 to 730 days. Omit to
    inherit the workspace default.

.PARAMETER TotalRetentionInDays
    Interactive plus long-term retention, up to 4383 days. Omit to inherit
    the workspace default.

.PARAMETER Description
    Description recorded on the table schema and the DCR.

.PARAMETER OutputDirectory
    Where to write the two ARM templates. Defaults to the current
    directory, which is the useful default for a standalone copy.

.PARAMETER GrantIngestionRoleTo
    One or more identities to grant 'Monitoring Metrics Publisher' on the
    new DCR. Accepts a service principal application (client) ID or any
    principal object ID. Requires Owner or User Access Administrator on
    the DCR.

.PARAMETER IncludeDataTypeHint
    Emit each column's dataTypeHint into the table template. Off by default,
    because the live service rejects the values its own documentation
    prescribes:

        MSG 1011: Invalid value provided for data type hint (Code: InvalidParameter)

    A hint is a display annotation with no effect on storage or queryability,
    so it is dropped rather than allowed to fail the table creation. Use this
    switch to retest the behaviour without editing the script.

.PARAMETER SkipTable
    Do not create or update the table. Use when the table already exists
    and you only want the DCR. The wizard still reads the live table to
    validate the schema against it.

.PARAMETER Deploy
    Deploy the templates without asking. In interactive mode the wizard
    asks at the end regardless; this switch pre-answers it, which is what
    makes an unattended run possible.

.PARAMETER NonInteractive
    Never prompt. Anything the wizard would have asked for must be
    supplied as a parameter, and any schema error is fatal rather than
    editable.

.PARAMETER Force
    Bypass the confirmation on the deploy step.

.EXAMPLE
    ./New-DcrFromSchema.ps1 -SchemaPath ./Examples/threat-intel-alerts.json

    Full wizard. Prompts for subscription, workspace, retention, DCR name
    and transform, shows the schema for review, then offers to deploy. Every
    prompt that has a default says so and takes Enter to accept it.

.EXAMPLE
    ./New-DcrFromSchema.ps1 -SchemaPath ./schema.json -OutputDirectory ../Infra/dcr -NonInteractive `
        -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -ResourceGroupName 'rg-sentinel' -WorkspaceName 'law-sentinel'

    Unattended. Writes both templates and stops without deploying, which
    is the shape to use from a pipeline that commits the artefacts and
    deploys them in a later stage.

.EXAMPLE
    ./New-DcrFromSchema.ps1 -SchemaPath ./schema.json -Deploy -Force `
        -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -ResourceGroupName 'rg-sentinel' -WorkspaceName 'law-sentinel' `
        -GrantIngestionRoleTo '11111111-1111-1111-1111-111111111111'

    Creates the table, deploys the DCR, grants the sender the ingestion
    role, and prints the ready-to-use Logs Ingestion URL.

.OUTPUTS
    A single PSCustomObject describing the table, the DCR, both template
    paths and, when deployed, the immutable ID and ingestion endpoint.

.NOTES
    File:         Tools/DcrFromSchema/New-DcrFromSchema.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-07-30
    Version:      0.1.0
    Last Updated: 2026-09-01
    Requires:     PowerShell 7.2+, Az.Accounts, Az.OperationalInsights, Az.Resources

    API versions:
      - Log Analytics tables  : 2025-07-01
      - Data collection rules : 2023-03-11 (the version that added
                                'endpoints', so Direct DCRs authored here
                                receive a built-in logsIngestion endpoint)
      - Logs Ingestion        : 2023-01-01

    Run Connect-AzAccount before invoking.

    RBAC:
      - Log Analytics Contributor on the workspace, to create the table
      - Contributor on the DCR resource group, to deploy the rule
      - Owner or User Access Administrator on the DCR, only for
        -GrantIngestionRoleTo

    The sending identity needs nothing on the workspace, only Monitoring
    Metrics Publisher on the DCR. Data-plane RBAC can take a few minutes
    to take effect, so early POSTs may return 403.

.LINK
    https://learn.microsoft.com/azure/azure-monitor/logs/logs-ingestion-api-overview
#>
[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NonInteractive',
    Justification = 'Consumed by the prompt helpers through script scope, which the analyzer cannot see.')]
param (
    [Parameter()]
    [string] $SchemaPath

  , [Parameter()]
    [string] $TableName

  , [Parameter()]
    [string] $SubscriptionId

  , [Parameter()]
    [string] $ResourceGroupName

  , [Parameter()]
    [string] $WorkspaceName

  , [Parameter()]
    [string] $DcrName

  , [Parameter()]
    [string] $DcrResourceGroupName

  , [Parameter()]
    [string] $Location

  , [Parameter()]
    [string] $DataCollectionEndpointResourceId

  , [Parameter()]
    [string] $TransformKql

  , [Parameter()]
    [ValidateSet('Analytics', 'Basic', 'Auxiliary')]
    [string] $TablePlan

    # -1 is documented as "use the default", so it has to survive validation
    # alongside the real range. 0 is this script's "not supplied" sentinel and
    # is never emitted.
  , [Parameter()]
    [ValidateScript({ $_ -eq -1 -or ($_ -ge 4 -and $_ -le 730) },
        ErrorMessage = 'Interactive retention must be 4 to 730 days, or -1 for the workspace default.')]
    [int] $RetentionInDays

  , [Parameter()]
    [ValidateScript({ $_ -eq -1 -or ($_ -ge 4 -and $_ -le 4383) },
        ErrorMessage = 'Total retention must be 4 to 4383 days, or -1 to match interactive retention.')]
    [int] $TotalRetentionInDays

  , [Parameter()]
    [string] $Description

  , [Parameter()]
    [string] $OutputDirectory

  , [Parameter()]
    [string[]] $GrantIngestionRoleTo

  , [Parameter()]
    [switch] $IncludeDataTypeHint

  , [Parameter()]
    [switch] $SkipTable

  , [Parameter()]
    [switch] $Deploy

  , [Parameter()]
    [switch] $NonInteractive

  , [Parameter()]
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region -- Logging --------------------------------------------------------------

# Self-contained by design. This script deliberately does NOT import the repo's
# Sentinel.Common module: it must run unchanged on a jump box or in an
# automation account where that module is absent. Write-PipelineMessage is
# defined locally to mirror Sentinel.Common's behaviour.

function Write-PipelineMessage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Console output is the point; mirrors Sentinel.Common.')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message

      , [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Section', 'Success', 'Debug')]
        [string] $Level = 'Info'
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

#region -- Constants ------------------------------------------------------------

# 2025-07-01, not 2023-09-01. At 2023-09-01 the Tables API documents 'plan' as
# only 'Analytics' or 'Basic': the Auxiliary plan does not exist at that version,
# so authoring an Auxiliary table against it fails. 2025-07-01 is the version
# Microsoft's own Auxiliary examples use.
$script:TablesApiVersion = '2025-07-01'

# 2023-03-11 is the API version that added the 'endpoints' property to
# DataCollectionRuleResourceProperties, so a Direct DCR authored here receives
# its own logsIngestion endpoint and needs no Data Collection Endpoint.
$script:DcrApiVersion = '2023-03-11'

# Every limit and enum below is taken from the Azure Monitor documentation
# rather than from experience, so the wizard rejects what Azure rejects and
# nothing more. Sources:
#
#   Column type / dataTypeHint / plan enums, retention ranges:
#     https://learn.microsoft.com/azure/templates/microsoft.operationalinsights/workspaces/tables
#   Column naming rules, TimeGenerated requirement, reserved names:
#     https://learn.microsoft.com/azure/azure-monitor/logs/create-custom-table
#   Column count, column name length, transform length:
#     https://learn.microsoft.com/azure/azure-monitor/fundamentals/service-limits
#   Stream declaration column types:
#     https://learn.microsoft.com/azure/templates/microsoft.insights/datacollectionrules

# "Column names must be 2 to 45 characters long" (create-custom-table), which
# the service-limits page restates as "Maximum characters for column name: 45".
$script:MinColumnNameLength = 2
$script:MaxColumnNameLength = 45

# The table's ARM resource name constraint is min 4, max 63, pattern
# ^[A-Za-z0-9-_]+$. The pattern is looser than what is usable: a name starting
# with a digit, or containing a hyphen, needs bracket-quoting in every KQL
# query that touches it. The length bounds are taken as documented; the
# character rule is tightened deliberately, and Test-TableName says so.
$script:MinTableNameLength = 4
$script:MaxTableNameLength = 63

# "Maximum columns in a table: 500". For a custom log the page adds "contact
# support to increase limit", so this is a real ceiling rather than a soft one.
$script:MaxColumnCount = 500

# "Maximum number of characters in a transformation: 15,360" (data collection
# rule limits).
$script:MaxTransformLength = 15360

# A data collection rule's properties.description is capped at 256 characters.
# This one is NOT documented: the DCR structure reference lists 'description'
# as "Optional description of the data collection rule defined by the user"
# with no constraint. The limit is only visible when preflight rejects the
# deployment:
#
#   InvalidProperty: 'Description' length should be 256 characters or less.
#   Specified value has 261 characters. (Target: Properties.Description)
#
# The table's schema.description and the rule's description are fed from the
# same text, so capping at the tighter of the two keeps both valid.
$script:MaxDescriptionLength = 256

# Column names Azure Monitor reserves. The first block is the documented list
# from create-custom-table ("Don't use names that conflict with system or
# reserved columns"). The second block is platform-populated columns that the
# list omits but that Azure Monitor still fills in itself, carried over from
# Tools/ClassicToDcr where they were hit in practice. Matching is
# case-insensitive, which is what -contains does by default.
$script:ReservedColumns = @(
    'id'
    'BilledSize'
    'IsBillable'
    'InvalidTimeGenerated'
    'TenantId'
    'Title'
    'Type'
    'UniqueId'
    '_ItemId'
    '_ResourceGroup'
    '_ResourceId'
    '_SubscriptionId'
    '_TimeReceived'

    'MG'
    'ManagementGroupName'
    'SourceSystem'
)

# The Tables API Column.type enum, exactly as documented:
#   'boolean' 'dateTime' 'dynamic' 'guid' 'int' 'long' 'real' 'string'
$script:TableColumnTypes = @('boolean', 'dateTime', 'dynamic', 'guid', 'int', 'long', 'real', 'string')

# The documented Column.dataTypeHint enum. A hint is a logical annotation on a
# string column (an IP address, a URI, an ARM resource path) that the portal
# and entity mapping understand; it does not change how the value is stored.
$script:DataTypeHints = @('armPath', 'guid', 'ip', 'uri')

# Canonical Tables API column type, keyed by every spelling worth accepting.
# The eight canonical values are the enum above; everything else here is an
# alias a hand-written schema is likely to use. Aliases are normalised rather
# than rejected because 'bool' or 'integer' is a typo of intent, not of
# meaning. Note the Tables API spells it camelCase 'dateTime' while a DCR
# stream declaration documents lower-case 'datetime'; the two maps keep that
# difference straight.
$script:TableTypeMap = @{
    'string'    = 'string'
    'int'       = 'int'
    'integer'   = 'int'
    'int32'     = 'int'
    'long'      = 'long'
    'int64'     = 'long'
    'real'      = 'real'
    'double'    = 'real'
    'float'     = 'real'
    'decimal'   = 'real'
    'boolean'   = 'boolean'
    'bool'      = 'boolean'
    'datetime'  = 'dateTime'
    'date'      = 'dateTime'
    'timestamp' = 'dateTime'
    'guid'      = 'guid'
    'uuid'      = 'guid'
    'dynamic'   = 'dynamic'
    'object'    = 'dynamic'
    'array'     = 'dynamic'
}

# Tables API column types -> DCR stream declaration types. The documented
# ColumnDefinition enum is 'boolean' 'datetime' 'dynamic' 'int' 'long' 'real'
# 'string': there is no 'guid'. Azure Monitor stores and queries GUIDs as
# strings even when the table column is declared guid, so a guid column is
# declared string in the stream and cast back by the transform.
$script:StreamTypeMap = @{
    'string'   = 'string'
    'int'      = 'int'
    'long'     = 'long'
    'real'     = 'real'
    'boolean'  = 'boolean'
    'datetime' = 'datetime'
    'guid'     = 'string'
    'dynamic'  = 'dynamic'
}

# KQL cast function per destination (table) column type. The transform output
# must land as the table's type; cast to it when the stream declares something
# else.
$script:CastByType = @{
    'string'   = 'tostring'
    'int'      = 'toint'
    'long'     = 'tolong'
    'real'     = 'toreal'
    'boolean'  = 'tobool'
    'datetime' = 'todatetime'
    'guid'     = 'toguid'
    'dynamic'  = 'todynamic'
}

# Suffixes the classic Custom Log Wizard bolted on to encode a column's type.
# A DCR-based table carries real types, so the suffix is now just noise in the
# column name. Worth flagging, never worth blocking.
$script:ClassicTypeSuffixes = @('_s', '_d', '_b', '_g', '_t')

$script:Interactive = -not $NonInteractive

#endregion

#region -- Prompt helpers -------------------------------------------------------

function Read-Value {
    <#
    .SYNOPSIS
        Prompts for a value, offering a default, and enforces non-interactive
        mode by failing rather than hanging.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Wizard prompt; console output is the point.')]
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $Prompt
      , [Parameter()] [AllowEmptyString()] [string] $Default = ''
      , [Parameter()] [switch] $AllowEmpty
    )

    if (-not $script:Interactive) {
        if ($Default -or $AllowEmpty) { return $Default }
        throw "'$Prompt' is required in non-interactive mode. Supply it as a parameter."
    }

    while ($true) {
        # Spell out that Enter takes the default rather than relying on the
        # bracket convention. A free-text prompt showing "[rg-sentinel]"
        # sitting between two [y/N] questions was answered 'y', which became a
        # resource group literally named 'y'. Saying what Enter does is the fix;
        # annotating one prompt with "not a yes/no answer" was not.
        $suffix = if ($Default) { " [$Default] (Enter to accept)" } else { '' }
        Write-Host "  $Prompt$suffix" -NoNewline -ForegroundColor Gray
        Write-Host ': ' -NoNewline
        $entered = Read-Host

        if ([string]::IsNullOrWhiteSpace($entered)) {
            if ($Default)    { return $Default }
            if ($AllowEmpty) { return '' }
            Write-Host '  A value is required.' -ForegroundColor Yellow
            continue
        }

        return $entered.Trim()
    }
}

function Read-YesNo {
    <#
    .SYNOPSIS
        Prompts for a yes/no answer. Returns the default unattended.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Wizard prompt; console output is the point.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)] [string] $Prompt
      , [Parameter()] [bool] $Default = $false
    )

    if (-not $script:Interactive) { return $Default }

    $hint = if ($Default) { 'Y/n' } else { 'y/N' }

    while ($true) {
        Write-Host "  $Prompt [$hint]: " -NoNewline -ForegroundColor Gray
        $entered = Read-Host

        if ([string]::IsNullOrWhiteSpace($entered)) { return $Default }

        switch ($entered.Trim().ToLowerInvariant()) {
            'y'   { return $true }
            'yes' { return $true }
            'n'   { return $false }
            'no'  { return $false }
            default { Write-Host '  Answer y or n.' -ForegroundColor Yellow }
        }
    }
}

function Read-MenuChoice {
    <#
    .SYNOPSIS
        Renders a numbered menu and returns the chosen zero-based index.

    .DESCRIPTION
        Long lists are printed in full rather than paged: a truncated
        subscription or workspace list is worse than a long one, because the
        entry you want silently is not there.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Wizard menu; console output is the point.')]
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)] [string]   $Title
      , [Parameter(Mandatory)] [string[]] $Option
      , [Parameter()]          [int]      $DefaultIndex = 0
    )

    if ($Option.Count -eq 0) { throw "Menu '$Title' has no options." }
    if ($Option.Count -eq 1) { return 0 }

    if (-not $script:Interactive) { return $DefaultIndex }

    Write-Host ''
    Write-Host "  $Title" -ForegroundColor Gray

    for ($i = 0; $i -lt $Option.Count; $i++) {
        Write-Host ('    {0,3}. {1}' -f ($i + 1), $Option[$i])
    }

    while ($true) {
        $entered = Read-Value -Prompt 'Choice' -Default ([string]($DefaultIndex + 1))

        $parsed = 0
        if ([int]::TryParse($entered, [ref] $parsed) -and $parsed -ge 1 -and $parsed -le $Option.Count) {
            return $parsed - 1
        }

        Write-Host "  Enter a number between 1 and $($Option.Count)." -ForegroundColor Yellow
    }
}

#endregion

#region -- Schema helpers -------------------------------------------------------

function ConvertTo-StraightPunctuation {
    <#
    .SYNOPSIS
        Substitutes typographic punctuation for its ASCII equivalent.

    .DESCRIPTION
        Word, most wikis and several chat clients replace straight quotes with
        curly ones and ordinary spaces with no-break spaces as you type. The
        results are indistinguishable on screen and rejected by both JSON and
        KQL, which makes them one of the most annoying classes of paste damage
        to diagnose by eye.

        The characters are written as explicit code points rather than
        literally. Pasting them into the source would make this file non-ASCII,
        so it would need a byte order mark to stay readable everywhere, and an
        invisible no-break space in a replacement expression is impossible to
        review and trivially lost to a later edit.

    .OUTPUTS
        The substituted string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text
    )

    $substitutions = @(
        @{ From = [char]0x201C; To = '"' }   # left double quotation mark
        @{ From = [char]0x201D; To = '"' }   # right double quotation mark
        @{ From = [char]0x2018; To = "'" }   # left single quotation mark
        @{ From = [char]0x2019; To = "'" }   # right single quotation mark
        @{ From = [char]0x00A0; To = ' ' }   # no-break space
    )

    foreach ($substitution in $substitutions) {
        $Text = $Text.Replace([string]$substitution.From, $substitution.To)
    }

    return $Text
}

function Remove-JsonNoise {
    <#
    .SYNOPSIS
        Strips the artefacts a hand-pasted schema picks up on its way through a
        browser, a wiki, a chat client or Word.

    .DESCRIPTION
        A schema is usually pasted from somewhere: a vendor's API page, an
        internal wiki, a colleague's message. That journey adds things JSON
        does not allow. Rather than tell the operator their file is invalid and
        make them hunt for the character, this repairs the known-safe cases and
        reports exactly which it applied.

        Handled:
          - a UTF-8 BOM at the start of the file
          - curly quotes, which Word and most wikis substitute for straight
            ones and which are never valid JSON punctuation
          - no-break spaces, which web pastes leave between tokens
          - // line comments and /* block */ comments, the JSONC dialect people
            write by hand and every documentation sample uses
          - trailing commas before } or ]

        Comments and trailing commas are removed by a single pass that tracks
        string state, so a '//' or a ', ]' inside a string value is left alone.
        That matters: a description reading "see http://wiki/x" would otherwise
        lose the rest of the line.

        Only called after a straight parse has already failed, so a file that
        parses is never touched.

        Worth knowing which repairs actually fire: PowerShell's own
        ConvertFrom-Json is already lenient about comments and trailing commas
        and accepts them without complaint, so those two branches usually run
        only alongside a failure caused by something else (curly quotes being
        the common one). They are kept because the reporting has to be honest
        about everything the file contained, and because that leniency is a
        property of the current parser rather than a guarantee.

    .OUTPUTS
        PSCustomObject with Text (the repaired JSON) and Applied (the list of
        repairs, for reporting).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: returns a repaired copy of the text, changes no state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text
    )

    $applied = [System.Collections.Generic.List[string]]::new()

    if ($Text.Length -gt 0 -and $Text[0] -eq [char]0xFEFF) {
        $Text = $Text.Substring(1)
        $applied.Add('byte order mark')
    }

    # Curly quotes and no-break spaces can never be JSON punctuation, so
    # substituting them across the whole file is safe even though it also
    # touches string contents.
    $straightened = ConvertTo-StraightPunctuation -Text $Text
    if ($straightened -ne $Text) {
        $Text = $straightened
        $applied.Add('curly quotes or no-break spaces')
    }

    $builder         = [System.Text.StringBuilder]::new($Text.Length)
    $inString        = $false
    $escaped         = $false
    $strippedComment = $false
    $strippedComma   = $false
    $index           = 0

    while ($index -lt $Text.Length) {
        $char = $Text[$index]

        if ($inString) {
            [void]$builder.Append($char)

            if ($escaped)          { $escaped = $false }
            elseif ($char -eq '\') { $escaped = $true }
            elseif ($char -eq '"') { $inString = $false }

            $index++
            continue
        }

        if ($char -eq '"') {
            $inString = $true
            [void]$builder.Append($char)
            $index++
            continue
        }

        if ($char -eq '/' -and ($index + 1) -lt $Text.Length) {
            $next = $Text[$index + 1]

            if ($next -eq '/') {
                while ($index -lt $Text.Length -and $Text[$index] -ne "`n") { $index++ }
                $strippedComment = $true
                continue
            }

            if ($next -eq '*') {
                $index += 2
                while (($index + 1) -lt $Text.Length -and -not ($Text[$index] -eq '*' -and $Text[$index + 1] -eq '/')) {
                    $index++
                }
                $index += 2
                $strippedComment = $true
                continue
            }
        }

        if ($char -eq ',') {
            # Look past whitespace for a closing brace or bracket. A comma
            # there is trailing, and dropping it is the whole repair.
            $lookahead = $index + 1
            while ($lookahead -lt $Text.Length -and [char]::IsWhiteSpace($Text[$lookahead])) { $lookahead++ }

            if ($lookahead -lt $Text.Length -and ($Text[$lookahead] -eq '}' -or $Text[$lookahead] -eq ']')) {
                $strippedComma = $true
                $index++
                continue
            }
        }

        [void]$builder.Append($char)
        $index++
    }

    if ($strippedComment) { $applied.Add('JSON comments') }
    if ($strippedComma)   { $applied.Add('trailing commas') }

    return [pscustomobject] @{
        Text    = $builder.ToString()
        Applied = $applied.ToArray()
    }
}

function ConvertTo-SafeText {
    <#
    .SYNOPSIS
        Cleans a free-text value out of a pasted schema before it is written
        into an Azure resource.

    .DESCRIPTION
        Descriptions and display names in a pasted schema are the fields most
        likely to carry paste damage: a hard-wrapped sentence with embedded
        newlines, a zero-width joiner from a wiki, a bidi mark from a copied
        table cell, three paragraphs where a sentence was wanted. None of that
        is rejected by ARM, so it is deployed and then lives in the portal
        forever.

        Control and format characters become spaces, runs of whitespace
        collapse to one, and the result is trimmed and truncated. The length
        cap is this tool's, not a documented Azure limit; it exists so a
        pasted essay does not become a table description.

    .OUTPUTS
        The cleaned string, or an empty string when there was nothing usable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string] $Text
      , [Parameter()] [int] $MaxLength = 256
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    # \p{Cc} is control characters (newlines, tabs, NUL), \p{Cf} is format
    # characters (zero-width joiner, bidi marks, a stray BOM mid-string).
    $clean = [regex]::Replace($Text, '[\p{Cc}\p{Cf}]', ' ')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()

    if ($clean.Length -gt $MaxLength) {
        $clean = $clean.Substring(0, $MaxLength - 3).TrimEnd() + '...'
    }

    return $clean
}

function Import-TableSpec {
    <#
    .SYNOPSIS
        Reads the JSON schema file and normalises it into a table name plus a
        column list, whichever of the accepted shapes it arrived in.

    .DESCRIPTION
        Three shapes are recognised, in this order:

          1. { "tableName": "...", "columns": [ ... ] }, the shape this tool
             documents.
          2. The Tables API resource shape, { "properties": { "schema": {
             "name": "...", "columns": [ ... ] } } }, so a table exported from
             Azure with 'az monitor log-analytics workspace table show' can be
             fed straight back in.
          3. A bare array of column objects, in which case the caller supplies
             the table name.

        A file that parses as JSON but matches none of these is far more often
        a sample of the data than a schema, so the error says so instead of
        reporting a missing property.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Schema file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Schema file is empty: $Path"
    }

    try {
        $json = $raw | ConvertFrom-Json
    }
    catch {
        # Valid JSON never reaches here, so nothing is rewritten unless the
        # file was already unparseable. Repair the known paste artefacts and
        # try once more, reporting what was done so the operator can fix the
        # source file rather than rely on this every run.
        $repaired = Remove-JsonNoise -Text $raw

        if ($repaired.Applied.Count -eq 0) {
            throw "Schema file is not valid JSON ($Path): $($_.Exception.Message.Split([char]10)[0])"
        }

        try {
            $json = $repaired.Text | ConvertFrom-Json
        }
        catch {
            throw ("Schema file is not valid JSON ($Path), even after removing $($repaired.Applied -join ', '): " +
                   $_.Exception.Message.Split([char]10)[0])
        }

        Write-PipelineMessage "Schema file needed cleaning up before it would parse: removed $($repaired.Applied -join ', '). Fix the source file so this is not needed next time." -Level Warning
    }

    $name    = $null
    $columns = $null
    $extra   = [ordered] @{}

    if ($json -is [array]) {
        $columns = $json
    }
    else {
        $properties = $json.PSObject.Properties

        if ($properties['properties'] -and $properties['properties'].Value) {
            $inner = $properties['properties'].Value
            $schemaProperty = $inner.PSObject.Properties['schema']

            if (-not $schemaProperty -or -not $schemaProperty.Value) {
                throw "Schema file has a 'properties' block but no 'properties.schema' ($Path)."
            }

            $schema = $schemaProperty.Value
            $name   = if ($schema.PSObject.Properties['name']) { [string]$schema.name } else { $null }

            # Present-but-empty has to stay distinguishable from absent, so the
            # empty-list error below is reachable rather than reported as a
            # missing column list.
            $columns = if ($schema.PSObject.Properties['columns'] -and
                           $null -ne $schema.PSObject.Properties['columns'].Value) { $schema.columns }
                       else { $null }

            foreach ($key in @('description')) {
                if ($schema.PSObject.Properties[$key]) { $extra[$key] = $schema.$key }
            }
            foreach ($key in @('plan', 'retentionInDays', 'totalRetentionInDays')) {
                if ($inner.PSObject.Properties[$key]) { $extra[$key] = $inner.$key }
            }
        }
        # ConvertFrom-Json unrolls a single-element array, so a bare column
        # list holding exactly one column arrives here as a lone object rather
        # than as an array and never reaches the branch above. This has to be
        # tested before the tableName lookup, because 'name' is one of the
        # tableName aliases: a lone column would otherwise be read as the
        # table's name and its columns reported missing.
        elseif ($properties['name'] -and $properties['type'] -and
                -not $properties['columns'] -and -not $properties['tableName']) {
            $columns = @($json)
        }
        else {
            foreach ($key in @('tableName', 'name', 'table')) {
                if ($properties[$key] -and $properties[$key].Value) {
                    $name = [string]$properties[$key].Value
                    break
                }
            }

            # -ne $null rather than a truthiness test: an empty array is
            # falsy, so a truthiness test would treat '"columns": []' as
            # "no column list at all" and report the misleading "this tool
            # takes a schema, not a sample of the data". The empty case has
            # its own error below and deserves to reach it.
            foreach ($key in @('columns', 'schema', 'fields')) {
                if ($properties[$key] -and $null -ne $properties[$key].Value) {
                    $columns = $properties[$key].Value
                    break
                }
            }

            foreach ($key in @('description', 'dcrName', 'location', 'plan',
                               'retentionInDays', 'totalRetentionInDays', 'transformKql')) {
                if ($properties[$key]) { $extra[$key] = $properties[$key].Value }
            }
        }
    }

    if ($null -eq $columns) {
        throw ("Schema file has no column list ($Path). Expected " +
               "{ `"tableName`": `"MyTable_CL`", `"columns`": [ { `"name`": `"...`", `"type`": `"...`" } ] }. " +
               'This tool takes a schema, not a sample of the data.')
    }

    $columns = @($columns)

    if ($columns.Count -eq 0) {
        throw "Schema file declares an empty column list ($Path)."
    }

    $malformed = @($columns | Where-Object {
        $null -eq $_ -or -not $_.PSObject.Properties['name']
    })

    if ($malformed.Count -gt 0) {
        throw ("$($malformed.Count) of $($columns.Count) entries in the column list have no 'name' property " +
               "($Path). Every column must be { `"name`": `"...`", `"type`": `"...`" }. " +
               'This tool takes a schema, not a sample of the data.')
    }

    return [pscustomobject] @{
        TableName = $name
        Columns   = $columns
        Extra     = $extra
    }
}

function Get-SpecDefault {
    <#
    .SYNOPSIS
        Reads an optional default out of the schema file's extra properties.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [AllowNull()] [object] $Extra
      , [Parameter(Mandatory)] [string] $Key
    )

    if ($null -eq $Extra) { return $null }
    if (-not $Extra.Contains($Key)) { return $null }

    return $Extra[$Key]
}

function Get-TableColumnType {
    <#
    .SYNOPSIS
        Normalises a declared column type to a canonical Tables API type.

    .OUTPUTS
        The canonical type, or $null when the type is not one the Tables API
        accepts. Callers turn $null into a blocking error rather than guessing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string] $DeclaredType
    )

    if ([string]::IsNullOrWhiteSpace($DeclaredType)) { return $null }

    $key = $DeclaredType.Trim().ToLowerInvariant()

    if ($script:TableTypeMap.ContainsKey($key)) { return $script:TableTypeMap[$key] }

    return $null
}

function Get-DcrColumnType {
    <#
    .SYNOPSIS
        Maps a canonical Tables API column type onto a DCR stream declaration
        type.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $TableColumnType
    )

    $key = $TableColumnType.ToLowerInvariant()

    if ($script:StreamTypeMap.ContainsKey($key)) { return $script:StreamTypeMap[$key] }

    Write-PipelineMessage "Unrecognised column type '$TableColumnType'. Declaring it as 'string'." -Level Warning
    return 'string'
}

function Test-TableName {
    <#
    .SYNOPSIS
        Validates a custom log table name.

    .OUTPUTS
        An array of problem strings. Empty means the name is usable.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Name
    )

    $problems = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $problems.Add('the table name is empty')
        return $problems.ToArray()
    }

    if (-not $Name.EndsWith('_CL')) {
        $problems.Add("'$Name' does not end with '_CL', which every custom log table name must")
    }

    # ARM's own pattern for the table resource name is ^[A-Za-z0-9-_]+$, which
    # would accept '9-my-table_CL'. That deploys and is then unusable without
    # bracket-quoting it in every KQL query, so this is deliberately stricter.
    if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
        $problems.Add("'$Name' must start with a letter and contain only letters, digits and underscores, so KQL can reference it unquoted")
    }

    if ($Name.Length -lt $script:MinTableNameLength) {
        $problems.Add("'$Name' is $($Name.Length) characters; the minimum is $script:MinTableNameLength")
    }

    if ($Name.Length -gt $script:MaxTableNameLength) {
        $problems.Add("'$Name' is $($Name.Length) characters; the limit is $script:MaxTableNameLength")
    }

    return $problems.ToArray()
}

function Get-ColumnIssue {
    <#
    .SYNOPSIS
        Validates one column, returning severity-tagged findings.

    .DESCRIPTION
        Errors are the ones Azure will reject on create: a bad name, a name
        Azure Monitor reserves, an over-long name, an unmappable type.
        Warnings are legal but worth saying out loud, chiefly a classic
        Custom Log Wizard type suffix, which a DCR-based table no longer
        needs because it carries real column types.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string] $Name
      , [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string] $DeclaredType
      , [Parameter()] [AllowEmptyString()] [AllowNull()] [string] $DataTypeHint
    )

    $issues = [System.Collections.Generic.List[pscustomobject]]::new()

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $issues.Add([pscustomobject] @{ Severity = 'Error'; Message = 'the column name is empty' })
    }
    else {
        if ($script:ReservedColumns -contains $Name) {
            $issues.Add([pscustomobject] @{
                Severity = 'Error'
                Message  = "'$Name' conflicts with a system or reserved column name"
            })
        }

        # "Column names must start with a letter (A-Z or a-z). After the first
        # character, use only letters, digits, or underscores." The ASCII-only
        # ranges also enforce "Non-ASCII letters aren't supported".
        if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
            $issues.Add([pscustomobject] @{
                Severity = 'Error'
                Message  = 'must start with an ASCII letter and then contain only letters, digits and underscores'
            })
        }

        if ($Name.Length -lt $script:MinColumnNameLength) {
            $issues.Add([pscustomobject] @{
                Severity = 'Error'
                Message  = "is $($Name.Length) character; column names must be $script:MinColumnNameLength to $script:MaxColumnNameLength characters"
            })
        }

        if ($Name.Length -gt $script:MaxColumnNameLength) {
            $issues.Add([pscustomobject] @{
                Severity = 'Error'
                Message  = "is $($Name.Length) characters; the limit is $script:MaxColumnNameLength"
            })
        }

        foreach ($suffix in $script:ClassicTypeSuffixes) {
            if ($Name.EndsWith($suffix)) {
                $issues.Add([pscustomobject] @{
                    Severity = 'Warning'
                    Message  = "'$suffix' is a classic Custom Log Wizard type suffix; a DCR-based table carries real types and does not need it"
                })
                break
            }
        }
    }

    if ($null -eq (Get-TableColumnType -DeclaredType $DeclaredType)) {
        $known = $script:TableColumnTypes -join ', '
        $shown = if ([string]::IsNullOrWhiteSpace($DeclaredType)) { '(none)' } else { $DeclaredType }
        $issues.Add([pscustomobject] @{
            Severity = 'Error'
            Message  = "type '$shown' is not a Log Analytics column type. Use one of: $known"
        })
    }

    if (-not [string]::IsNullOrWhiteSpace($DataTypeHint) -and $script:DataTypeHints -notcontains $DataTypeHint) {
        $issues.Add([pscustomobject] @{
            Severity = 'Error'
            Message  = "dataTypeHint '$DataTypeHint' is not valid. Use one of: $($script:DataTypeHints -join ', ')"
        })
    }

    return $issues.ToArray()
}

function New-SchemaColumn {
    <#
    .SYNOPSIS
        Builds a working column object with every property the rest of the
        script expects.

    .DESCRIPTION
        Under Set-StrictMode -Version Latest, reading a property that is not
        there is a terminating error, so every column has to carry the same
        shape whether it came from the schema file, the editor or a repair.
        One constructor keeps that true.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: builds an in-memory object, changes no state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Name
      , [Parameter(Mandatory)] [AllowEmptyString()] [string] $Type
      , [Parameter()] [AllowEmptyString()] [string] $DeclaredType = ''
      , [Parameter()] [AllowEmptyString()] [string] $Description = ''
      , [Parameter()] [AllowEmptyString()] [string] $DisplayName = ''
      , [Parameter()] [AllowEmptyString()] [string] $DataTypeHint = ''
    )

    return [pscustomobject] @{
        Name         = $Name
        Type         = $Type
        DeclaredType = if ($DeclaredType) { $DeclaredType } else { $Type }
        Description  = $Description
        DisplayName  = $DisplayName
        DataTypeHint = $DataTypeHint
        Issues       = @()
    }
}

function Resolve-TableSchema {
    <#
    .SYNOPSIS
        Turns the raw column list into normalised columns plus a findings list.

    .DESCRIPTION
        Normalises each column's type where it can, records every problem
        against the column it belongs to, and adds schema-wide findings for
        duplicates, a missing TimeGenerated and an over-long column list.

        Duplicates are compared case-SENSITIVELY, which is what Log Analytics
        does for Analytics and Basic tables: 'Foo' and 'foo' are two real
        columns there, so only an exact repeat is an error. A case-only
        difference is reported as a warning instead, and becomes fatal in step
        5 if the plan turns out to be Auxiliary, where ingestion drops rows
        over it.

        Every name comparison in this script uses an ordinal comparer for that
        reason. PowerShell's defaults are all case insensitive - @{},
        -contains, Group-Object, Sort-Object -Unique - and each one silently
        breaks this invariant in a different place.

    .OUTPUTS
        PSCustomObject with Columns (name / type / declared type / issues) and
        SchemaIssues.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Column
    )

    $resolved     = [System.Collections.Generic.List[pscustomobject]]::new()
    $schemaIssues = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($entry in $Column) {
        if ($null -eq $entry) { continue }

        $name = if ($entry.PSObject.Properties['name']) { [string]$entry.name } else { '' }

        $declaredType = ''
        foreach ($key in @('type', 'columnType', 'dataType')) {
            if ($entry.PSObject.Properties[$key] -and $entry.PSObject.Properties[$key].Value) {
                $declaredType = [string]$entry.PSObject.Properties[$key].Value
                break
            }
        }

        # An entry with a name but no type is a schema a human half-finished,
        # not a broken one. String is the type Log Analytics itself falls back
        # to, so default to it and say so rather than failing the whole file.
        if ([string]::IsNullOrWhiteSpace($declaredType)) { $declaredType = 'string' }

        $canonical = Get-TableColumnType -DeclaredType $declaredType

        # Free text out of a pasted schema goes into the deployed resource, so
        # it is cleaned here rather than forwarded verbatim. Anything else in
        # the entry (a "note", a "required" flag, whatever the source tool
        # added) is simply not carried: the template emits only the properties
        # the Tables API defines.
        $columnDescription = ''
        foreach ($key in @('description', 'desc', 'comment', 'note', 'notes')) {
            if ($entry.PSObject.Properties[$key] -and $entry.PSObject.Properties[$key].Value) {
                $columnDescription = ConvertTo-SafeText -Text ([string]$entry.PSObject.Properties[$key].Value)
                break
            }
        }

        $displayName = if ($entry.PSObject.Properties['displayName']) {
            ConvertTo-SafeText -Text ([string]$entry.displayName) -MaxLength 128
        } else { '' }

        $hint = if ($entry.PSObject.Properties['dataTypeHint']) {
            ConvertTo-SafeText -Text ([string]$entry.dataTypeHint) -MaxLength 32
        } else { '' }

        $resolved.Add([pscustomobject] @{
            Name         = if ($name) { $name.Trim() } else { $name }
            Type         = if ($canonical) { $canonical } else { $declaredType }
            DeclaredType = $declaredType
            Description  = $columnDescription
            DisplayName  = $displayName
            DataTypeHint = $hint
            Issues       = @(Get-ColumnIssue -Name $name -DeclaredType $declaredType -DataTypeHint $hint)
        })
    }

    $named = @($resolved | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) })

    # -CaseSensitive is essential, not decoration. Group-Object folds case by
    # default, so without it 'Case' and 'case' are reported as an exact
    # duplicate (which they are not) and the case-collision check below never
    # fires (because the inner grouping collapses them too).
    foreach ($group in @($named | Group-Object -Property Name -CaseSensitive | Where-Object { $_.Count -gt 1 })) {
        $schemaIssues.Add([pscustomobject] @{
            Severity = 'Error'
            Message  = "duplicate column name '$($group.Name)' appears $($group.Count) times."
        })
    }

    # Case is significant for Analytics and Basic tables, so Alert and alert
    # really are two columns and this is not an error. It is still almost
    # always a mistake, and on an Auxiliary table it is worse than a mistake:
    # ingestion drops rows whose column names differ only by case. Step 5
    # turns this into a hard failure once the plan is known to be Auxiliary.
    $caseCollisions = @($named |
        Group-Object -Property { $_.Name.ToLowerInvariant() } |
        Where-Object { $_.Count -gt 1 -and @($_.Group | Group-Object -Property Name -CaseSensitive).Count -gt 1 })

    foreach ($group in $caseCollisions) {
        # -CaseSensitive again: a plain -Unique would collapse the very pair
        # this message exists to show, and report "Case" instead of "Case, case".
        $names = (@($group.Group | ForEach-Object { $_.Name }) | Sort-Object -Unique -CaseSensitive) -join ', '
        $schemaIssues.Add([pscustomobject] @{
            Severity = 'Warning'
            Message  = "column names differ only by case: $names. Analytics and Basic tables treat these as separate columns; an Auxiliary table drops rows because of them."
            Kind     = 'CaseCollision'
        })
    }

    $names = @($resolved | ForEach-Object { $_.Name })

    if ($names -notcontains 'TimeGenerated') {
        $schemaIssues.Add([pscustomobject] @{
            Severity = 'Error'
            Message  = 'no TimeGenerated column. Every custom table needs one, of type datetime.'
            Fix      = 'AddTimeGenerated'
        })
    }
    else {
        $timeGenerated = @($resolved | Where-Object { $_.Name -eq 'TimeGenerated' })[0]
        if ($timeGenerated.Type -ne 'dateTime') {
            $schemaIssues.Add([pscustomobject] @{
                Severity = 'Error'
                Message  = "TimeGenerated is declared '$($timeGenerated.DeclaredType)'. It must be datetime."
                Fix      = 'FixTimeGeneratedType'
            })
        }
    }

    if ($resolved.Count -gt $script:MaxColumnCount) {
        $schemaIssues.Add([pscustomobject] @{
            Severity = 'Error'
            Message  = "$($resolved.Count) columns; a Log Analytics table is capped at $script:MaxColumnCount."
        })
    }

    return [pscustomobject] @{
        Columns      = $resolved
        SchemaIssues = $schemaIssues.ToArray()
    }
}

function Repair-TableSchema {
    <#
    .SYNOPSIS
        Applies the fixes that have exactly one sensible answer.

    .DESCRIPTION
        Adds a missing TimeGenerated, corrects its type if it was declared as
        something else, and drops columns whose name Azure will never accept.
        A bad type is deliberately NOT auto-fixed: guessing between 'long' and
        'real' for a column called Count silently changes what gets stored, so
        that one stays a decision for the operator.

    .OUTPUTS
        The repaired column list, as a plain array. PowerShell unrolls a
        collection on the way out of a function, so returning a List here
        would hand the caller an object[] anyway; saying so in the signature
        stops a caller believing it can still call .Add on the result.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Column
    )

    $kept = [System.Collections.Generic.List[pscustomobject]]::new()

    # Ordinal, not OrdinalIgnoreCase: on Analytics and Basic tables a
    # case-only difference is two real columns, so collapsing them here would
    # silently drop one the operator meant to keep. Only an exact repeat is a
    # duplicate. The case-only case is reported as a warning instead.
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    foreach ($entry in $Column) {
        # A bad name means the column cannot exist, so the column goes. A bad
        # type or a bad hint is a property problem on a column that is
        # otherwise fine, so it is handled separately below rather than
        # costing the operator the whole column.
        $nameErrors = @($entry.Issues | Where-Object {
            $_.Severity -eq 'Error' -and $_.Message -notlike 'type *' -and $_.Message -notlike 'dataTypeHint *'
        })

        if ($nameErrors.Count -gt 0) {
            Write-PipelineMessage "Dropping column '$($entry.Name)': $($nameErrors[0].Message)." -Level Warning
            continue
        }

        if (-not $seen.Add($entry.Name)) {
            Write-PipelineMessage "Dropping duplicate column '$($entry.Name)'." -Level Warning
            continue
        }

        # A dataTypeHint is a logical annotation the portal reads; dropping an
        # invalid one loses a display nicety, which is a far better trade than
        # dropping the column or refusing the whole schema.
        $hintErrors = @($entry.Issues | Where-Object {
            $_.Severity -eq 'Error' -and $_.Message -like 'dataTypeHint *'
        })

        if ($hintErrors.Count -gt 0) {
            Write-PipelineMessage "Removing the invalid dataTypeHint '$($entry.DataTypeHint)' from column '$($entry.Name)'. The column is kept." -Level Warning
            $entry.DataTypeHint = ''
        }

        if ($entry.Name -eq 'TimeGenerated' -and $entry.Type -ne 'dateTime') {
            Write-PipelineMessage "Correcting TimeGenerated from '$($entry.DeclaredType)' to datetime." -Level Warning
            $entry.Type         = 'dateTime'
            $entry.DeclaredType = 'datetime'
        }

        $kept.Add($entry)
    }

    if (-not $seen.Contains('TimeGenerated')) {
        Write-PipelineMessage 'Adding the required TimeGenerated column.' -Level Warning
        $kept.Insert(0, (New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime'))
    }

    return $kept.ToArray()
}

function ConvertTo-ColumnList {
    <#
    .SYNOPSIS
        Wraps a column array in a mutable list.

    .DESCRIPTION
        The unary comma is load-bearing. PowerShell unrolls a collection on
        the way out of a function, so a bare 'return $list' would hand the
        caller an object[] with no .Add, and the schema editor would fail the
        first time someone added a column. Returning a one-element array
        containing the list survives the unroll intact.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Column
    )

    $list = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($entry in $Column) { $list.Add($entry) }

    return , $list
}

function Show-SchemaTable {
    <#
    .SYNOPSIS
        Renders the working column list with its issues.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Wizard rendering; console output is the point.')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Column
      , [Parameter()] [AllowEmptyCollection()] [object[]] $SchemaIssue = @()
    )

    $widest = 4
    foreach ($entry in $Column) {
        if ($entry.Name -and $entry.Name.Length -gt $widest) { $widest = $entry.Name.Length }
    }

    Write-Host ''
    Write-Host ('  {0,3}  {1}  {2}  {3}' -f '#', 'COLUMN'.PadRight($widest), 'TABLE'.PadRight(9), 'STREAM') -ForegroundColor DarkGray

    for ($i = 0; $i -lt $Column.Count; $i++) {
        $entry  = $Column[$i]
        $stream = if (Get-TableColumnType -DeclaredType $entry.Type) { Get-DcrColumnType -TableColumnType $entry.Type } else { '?' }

        $errors   = @($entry.Issues | Where-Object Severity -EQ 'Error')
        $warnings = @($entry.Issues | Where-Object Severity -EQ 'Warning')

        $colour = if ($errors.Count -gt 0) { 'Red' } elseif ($warnings.Count -gt 0) { 'Yellow' } else { 'Gray' }

        Write-Host ('  {0,3}  {1}  {2}  {3}' -f
            ($i + 1), $entry.Name.PadRight($widest), $entry.Type.PadRight(9), $stream) -ForegroundColor $colour

        foreach ($issue in $errors)   { Write-Host ('       - ' + $issue.Message) -ForegroundColor Red }
        foreach ($issue in $warnings) { Write-Host ('       - ' + $issue.Message) -ForegroundColor Yellow }
    }

    foreach ($issue in $SchemaIssue) {
        $colour = if ($issue.Severity -eq 'Error') { 'Red' } else { 'Yellow' }
        Write-Host ('  schema: ' + $issue.Message) -ForegroundColor $colour
    }

    Write-Host ''
}

function Invoke-SchemaEditor {
    <#
    .SYNOPSIS
        Review-and-edit loop over the column list.

    .DESCRIPTION
        Runs until the schema has no errors and the operator accepts it.
        Unattended, it auto-repairs what it safely can and throws if anything
        blocking survives, because a wizard that silently ships a broken
        schema from a pipeline is worse than one that stops.

    .OUTPUTS
        The accepted column list.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Wizard rendering; console output is the point.')]
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Column
    )

    $working = ConvertTo-ColumnList -Column $Column

    while ($true) {
        $analysis = Resolve-TableSchema -Column $working.ToArray()
        $working  = ConvertTo-ColumnList -Column $analysis.Columns.ToArray()

        $errorCount = @($analysis.Columns | Where-Object { @($_.Issues | Where-Object Severity -EQ 'Error').Count -gt 0 }).Count +
                      @($analysis.SchemaIssues | Where-Object Severity -EQ 'Error').Count

        if (-not $script:Interactive) {
            if ($errorCount -eq 0) { return $working.ToArray() }

            Write-PipelineMessage "Schema has $errorCount blocking problem(s). Repairing what can be repaired without guessing." -Level Warning
            $working = ConvertTo-ColumnList -Column @(Repair-TableSchema -Column $working.ToArray())

            $recheck    = Resolve-TableSchema -Column $working.ToArray()
            $stillWrong = @($recheck.Columns | Where-Object { @($_.Issues | Where-Object Severity -EQ 'Error').Count -gt 0 }) +
                          @($recheck.SchemaIssues | Where-Object Severity -EQ 'Error')

            if (@($stillWrong).Count -gt 0) {
                $detail = @($stillWrong | ForEach-Object {
                    if ($_.PSObject.Properties['Name']) { "$($_.Name): $(@($_.Issues | Where-Object Severity -EQ 'Error')[0].Message)" }
                    else { $_.Message }
                }) -join '; '
                throw "Schema cannot be used and non-interactive mode cannot ask: $detail"
            }

            return $working.ToArray()
        }

        Show-SchemaTable -Column $working.ToArray() -SchemaIssue $analysis.SchemaIssues

        $options = [System.Collections.Generic.List[string]]::new()
        $actions = [System.Collections.Generic.List[string]]::new()

        if ($errorCount -eq 0) {
            $options.Add("Accept this schema ($($working.Count) columns)"); $actions.Add('Accept')
        }
        else {
            $options.Add("Fix what can be fixed automatically ($errorCount problem(s) outstanding)"); $actions.Add('Repair')
        }

        $options.Add('Rename a column');      $actions.Add('Rename')
        $options.Add('Change a column type'); $actions.Add('Retype')
        $options.Add('Remove a column');      $actions.Add('Remove')
        $options.Add('Add a column');         $actions.Add('Add')
        $options.Add('Abort');                $actions.Add('Abort')

        $choice = Read-MenuChoice -Title 'Schema review' -Option $options.ToArray()

        switch ($actions[$choice]) {
            'Accept' { return $working.ToArray() }

            'Repair' { $working = ConvertTo-ColumnList -Column @(Repair-TableSchema -Column $working.ToArray()) }

            'Rename' {
                $index = Read-ColumnIndex -Column $working
                if ($index -ge 0) {
                    $new = Read-Value -Prompt "New name for '$($working[$index].Name)'"
                    $working[$index].Name = $new
                }
            }

            'Retype' {
                $index = Read-ColumnIndex -Column $working
                if ($index -ge 0) {
                    $pick = Read-MenuChoice -Title "New type for '$($working[$index].Name)'" -Option $script:TableColumnTypes
                    $working[$index].Type         = $script:TableColumnTypes[$pick]
                    $working[$index].DeclaredType = $script:TableColumnTypes[$pick]
                }
            }

            'Remove' {
                $index = Read-ColumnIndex -Column $working
                if ($index -ge 0) {
                    Write-PipelineMessage "Removed '$($working[$index].Name)'." -Level Warning
                    $working.RemoveAt($index)
                }
            }

            'Add' {
                $name = Read-Value -Prompt 'Column name'
                $pick = Read-MenuChoice -Title "Type for '$name'" -Option $script:TableColumnTypes
                $working.Add((New-SchemaColumn -Name $name -Type $script:TableColumnTypes[$pick]))
            }

            'Abort' { throw 'Aborted at the schema review. Nothing was written.' }
        }
    }
}

function Read-ColumnIndex {
    <#
    .SYNOPSIS
        Asks which column to act on, by number or by name.

    .OUTPUTS
        The zero-based index, or -1 when the answer matched nothing.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)] [System.Collections.Generic.List[pscustomobject]] $Column
    )

    $answer = Read-Value -Prompt 'Column number or name'

    $parsed = 0
    if ([int]::TryParse($answer, [ref] $parsed)) {
        if ($parsed -ge 1 -and $parsed -le $Column.Count) { return $parsed - 1 }
        Write-PipelineMessage "There is no column $parsed." -Level Warning
        return -1
    }

    for ($i = 0; $i -lt $Column.Count; $i++) {
        if ($Column[$i].Name -eq $answer) { return $i }
    }

    Write-PipelineMessage "No column named '$answer'." -Level Warning
    return -1
}

function ConvertTo-StreamColumn {
    <#
    .SYNOPSIS
        Converts the accepted table columns into DCR stream declaration
        columns.

    .DESCRIPTION
        By this point the schema has already been validated, so nothing needs
        dropping. The one transformation left is the type map: a stream
        declaration cannot express guid, so guid becomes string and the
        transform casts it back.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Column
    )

    return @($Column | ForEach-Object {
        [pscustomobject] @{
            name = $_.Name
            type = Get-DcrColumnType -TableColumnType $_.Type
        }
    })
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
            by the output stream: EventId [produced:'String', output:'Guid']
            (Code: InvalidTransformOutput)

        The usual cause is guid, which a stream declaration cannot express.
        Rather than special-case guid, this compares each column's declared
        stream type against its table type and casts back on any mismatch, so
        a future divergence in the type maps is handled too.

        A schema whose columns all match gets a plain 'source'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Column
      , [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $StreamColumn
    )

    # Ordinal, not @{}. A default PowerShell hashtable is case insensitive, so
    # a schema carrying both 'Foo' and 'foo' - which this tool deliberately
    # permits, because Analytics and Basic tables treat them as two real
    # columns - would collapse to one entry. The second would overwrite the
    # first and one column's cast would be derived from the other's type,
    # producing InvalidTransformOutput at deploy time.
    $streamTypeByName = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)

    foreach ($stream in $StreamColumn) {
        if ($stream) { $streamTypeByName[[string]$stream.name] = ([string]$stream.type).ToLowerInvariant() }
    }

    $casts = foreach ($entry in $Column) {
        if (-not $entry) { continue }

        $name = $entry.Name
        if (-not $streamTypeByName.ContainsKey($name)) { continue }

        $tableType  = ([string]$entry.Type).ToLowerInvariant()
        $streamType = $streamTypeByName[$name]

        if ($streamType -ne $tableType) {
            if ($script:CastByType.ContainsKey($tableType)) {
                '{0} = {1}({0})' -f $name, $script:CastByType[$tableType]
            }
            else {
                Write-PipelineMessage "Column '$name' has table type '$tableType' with no known cast; leaving it to passthrough." -Level Warning
            }
        }
    }

    $casts = @($casts)

    if ($casts.Count -eq 0) { return 'source' }

    return 'source | extend ' + ($casts -join ', ')
}

#endregion

#region -- Azure helpers --------------------------------------------------------

function Test-TransformKql {
    <#
    .SYNOPSIS
        Repairs paste damage in a transform and enforces the documented length
        limit.

    .DESCRIPTION
        A transform pasted out of the portal, a wiki or a chat client picks up
        curly quotes, no-break spaces and smart apostrophes. KQL accepts
        none of them, and the resulting failure arrives at deployment time as
        a parse error pointing at a character that looks correct on screen.
        They are substituted here and reported.

        The transform body is otherwise left exactly as written. It is code:
        collapsing its whitespace, as ConvertTo-SafeText does for prose, would
        change a multi-line query into one line and could alter behaviour
        inside a string literal.

        The length limit is documented as 15,360 characters per transformation
        in the data collection rule limits.

    .OUTPUTS
        PSCustomObject with Text and Applied.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Transform
    )

    $applied = [System.Collections.Generic.List[string]]::new()

    $repaired = ConvertTo-StraightPunctuation -Text $Transform
    if ($repaired -ne $Transform) { $applied.Add('curly quotes or no-break spaces') }

    if ($repaired.Length -gt $script:MaxTransformLength) {
        throw ("The transform is $($repaired.Length) characters; a data collection rule allows " +
               "$script:MaxTransformLength. Move the logic into a workspace function, or trim it.")
    }

    return [pscustomobject] @{
        Text    = $repaired
        Applied = $applied.ToArray()
    }
}

function Invoke-ArmRequest {
    <#
    .SYNOPSIS
        Thin wrapper around Invoke-AzRestMethod with consistent error handling.

    .DESCRIPTION
        Accepts an ARM-relative path so the call resolves against the current
        Az environment's Resource Manager endpoint, which keeps the same code
        working in Azure Government and other sovereign clouds.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $Uri
      , [Parameter()] [string] $Method = 'GET'
      , [Parameter()] [int[]]  $SuccessCodes = @(200, 201, 202, 204)
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

function Get-WorkspaceTableSchema {
    <#
    .SYNOPSIS
        Reads an existing table's columns, or returns $null when it does not
        exist.

    .DESCRIPTION
        A 404 is the expected answer for a table this tool is about to create,
        so it is not an error. Any other failure is, and is rethrown: silently
        treating a 403 as "table absent" would let the wizard try to create a
        table it has no permission to see.

        Every hop through the response is guarded rather than dereferenced.
        Under Set-StrictMode -Version Latest a missing property is a
        terminating error, not $null, so a single unexpected response shape
        turns into

            The property 'properties' cannot be found on this object.

        which says nothing about which call failed or what came back. Each
        guard therefore fails with the status code and the body instead, which
        is the only thing that makes an unexpected shape diagnosable.
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
           "/tables/$Table`?api-version=$script:TablesApiVersion"

    $response = Invoke-AzRestMethod -Path $uri -Method GET

    if ($null -eq $response) {
        throw "No response reading table '$Table' from $uri."
    }

    if ($response.StatusCode -eq 404) { return $null }

    if ($response.StatusCode -ne 200) {
        throw "Could not read table '$Table': HTTP $($response.StatusCode) $($response.Content)"
    }

    # A 200 with nothing in it is not a table. Left unguarded, ConvertFrom-Json
    # returns $null here and the next dereference is the confusing failure.
    if ([string]::IsNullOrWhiteSpace($response.Content)) {
        throw "Reading table '$Table' returned HTTP 200 with an empty body."
    }

    $body = if ($response.Content.Length -gt 600) { $response.Content.Substring(0, 600) + '...' }
            else { $response.Content }

    # NOT $table. PowerShell variable names are case insensitive, so assigning
    # to $table silently overwrites the $Table parameter, and every error
    # message below then prints the deserialised response object where the
    # table name should be.
    try {
        $parsed = $response.Content | ConvertFrom-Json
    }
    catch {
        throw "Reading table '$Table' returned HTTP 200 with a body that is not JSON: $body"
    }

    $propertiesProperty = if ($parsed) { $parsed.PSObject.Properties['properties'] } else { $null }

    if (-not $propertiesProperty -or -not $propertiesProperty.Value) {
        throw "Unexpected response reading table '$Table': no 'properties' object. Body: $body"
    }

    $schemaProperty = $propertiesProperty.Value.PSObject.Properties['schema']

    if (-not $schemaProperty -or -not $schemaProperty.Value) {
        throw "Unexpected response reading table '$Table': no 'properties.schema' object. Body: $body"
    }

    $schema  = $schemaProperty.Value
    $columns = if ($schema.PSObject.Properties['columns'] -and $schema.PSObject.Properties['columns'].Value) {
                   @($schema.PSObject.Properties['columns'].Value)
               } else { @() }

    $subType = if ($schema.PSObject.Properties['tableSubType'] -and $schema.PSObject.Properties['tableSubType'].Value) {
                   [string]$schema.PSObject.Properties['tableSubType'].Value
               } else { 'Any' }

    $name = if ($schema.PSObject.Properties['name'] -and $schema.PSObject.Properties['name'].Value) {
                [string]$schema.PSObject.Properties['name'].Value
            } else { $Table }

    return [pscustomobject] @{
        Name    = $name
        SubType = $subType
        Columns = $columns
    }
}

function Compare-TableSchema {
    <#
    .SYNOPSIS
        Diffs the desired schema against a table that already exists.

    .DESCRIPTION
        Adding a column to an existing table is supported. Changing an
        existing column's type is not: Azure rejects it, and the useful thing
        is to say which column and to what, rather than let the deployment
        return a generic conflict.

        Columns the live table has and the spec does not are reported but not
        treated as a problem. The Tables API PUT sends the union, so they
        survive; and a spec that covers only the columns you care about is a
        legitimate way to add to a table.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $DesiredColumn
      , [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $ExistingColumn
    )

    # Ordinal for the same reason as Get-DefaultTransform: a default hashtable
    # conflates 'Foo' and 'foo', which either invents a type conflict between
    # two unrelated columns or hides a genuinely new one.
    $existingByName = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)

    foreach ($column in $ExistingColumn) {
        if ($column -and $column.PSObject.Properties['name']) {
            $existingByName[[string]$column.name] = $column
        }
    }

    $added     = [System.Collections.Generic.List[string]]::new()
    $conflicts = [System.Collections.Generic.List[string]]::new()

    foreach ($column in $DesiredColumn) {
        if (-not $existingByName.ContainsKey($column.Name)) {
            $added.Add($column.Name)
            continue
        }

        $live         = $existingByName[$column.Name]
        $liveTypeRaw  = if ($live.PSObject.Properties['type']) { [string]$live.type } else { 'string' }
        $liveType     = Get-TableColumnType -DeclaredType $liveTypeRaw

        if ($liveType -and $liveType -ne $column.Type) {
            $conflicts.Add("$($column.Name): live table has '$liveType', the schema says '$($column.Type)'")
        }
    }

    # -notcontains is case insensitive too, so the live-only set needs an
    # ordinal comparison or a case-differing pair is misreported here as well.
    $desiredNames = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] @($DesiredColumn | ForEach-Object { [string]$_.Name }), [StringComparer]::Ordinal)

    $onlyLive = @($existingByName.Keys | Where-Object {
        -not $desiredNames.Contains($_) -and $_ -notlike '_*'
    })

    return [pscustomobject] @{
        Added     = $added.ToArray()
        Conflicts = $conflicts.ToArray()
        OnlyLive  = @($onlyLive | Sort-Object)
    }
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

#endregion

#region -- Template builders ----------------------------------------------------

function Build-TableArmTemplate {
    <#
    .SYNOPSIS
        Builds the ARM template that creates or updates the custom table.

    .DESCRIPTION
        Deployed as a template rather than a direct Tables API PUT so the
        long-running create is handled by ARM, and so the artefact can be
        committed and redeployed like everything else in the repository.

        Basic and Auxiliary tables have service-fixed interactive retention,
        so retentionInDays is only emitted for Analytics. Sending it for the
        other plans is rejected.

        dataTypeHint is NOT emitted unless -IncludeDataTypeHint is passed, and
        that is a deliberate refusal to trust the documentation. Both the ARM
        template reference and the REST reference document the enum as
        'armPath', 'guid', 'ip' and 'uri' at every api-version. Sending exactly
        those values was rejected by the live service:

            Table validation failed with following 3 errors:
            MSG 1011: Invalid value provided for data type hint (Code: InvalidParameter)

        A hint is a display annotation with no effect on what is stored or
        queryable, so it is not worth failing a table creation over. The switch
        exists so the behaviour can be retested without editing the script.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [string]   $WorkspaceName
      , [Parameter(Mandatory)] [string]   $Table
      , [Parameter(Mandatory)] [object[]] $Column
      , [Parameter()]          [string]   $Plan
      , [Parameter()]          [int]      $Retention
      , [Parameter()]          [int]      $TotalRetention
      , [Parameter()]          [string]   $TableDescription
      , [Parameter()]          [switch]   $IncludeDataTypeHint
    )

    # Only the properties the Tables API Column object defines are emitted:
    # name, type, and the optional description, displayName and dataTypeHint.
    # Anything else a pasted schema carried is dropped here rather than sent.
    $schema = [ordered] @{
        name    = $Table
        columns = @($Column | ForEach-Object {
            $entry = [ordered] @{ name = $_.Name; type = $_.Type }

            if ($IncludeDataTypeHint -and $_.DataTypeHint) { $entry['dataTypeHint'] = $_.DataTypeHint }
            if ($_.Description) { $entry['description'] = $_.Description }
            if ($_.DisplayName) { $entry['displayName'] = $_.DisplayName }

            $entry
        })
    }

    if ($TableDescription) { $schema['description'] = $TableDescription }

    $properties = [ordered] @{ schema = $schema }

    if ($Plan) { $properties['plan'] = $Plan }

    # 0 means "not supplied". -1 is a real value meaning "use the default", so
    # it is emitted. retentionInDays is read-only on Basic and Auxiliary
    # tables, so it is never sent for those.
    if ($Retention -ne 0) {
        if ($Plan -and $Plan -ne 'Analytics') {
            Write-PipelineMessage "Ignoring -RetentionInDays: retentionInDays is read-only on a $Plan table." -Level Warning
        }
        else {
            $properties['retentionInDays'] = $Retention
        }
    }

    if ($TotalRetention -ne 0) { $properties['totalRetentionInDays'] = $TotalRetention }

    return @{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        metadata       = [ordered] @{
            description = "Custom log table $Table, generated by New-DcrFromSchema.ps1."
        }
        resources      = @(
            [ordered] @{
                type       = 'Microsoft.OperationalInsights/workspaces/tables'
                apiVersion = $script:TablesApiVersion
                name       = "$WorkspaceName/$Table"
                properties = $properties
            }
        )
    }
}

function Build-DcrArmTemplate {
    <#
    .SYNOPSIS
        Builds the ARM template object for a Direct Data Collection Rule.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [string]   $Name
      , [Parameter(Mandatory)] [string]   $Region
      , [Parameter(Mandatory)] [string]   $Stream
      , [Parameter(Mandatory)] [object[]] $StreamColumn
      , [Parameter(Mandatory)] [string]   $WorkspaceResourceId
      , [Parameter(Mandatory)] [string]   $OutputStream
      , [Parameter(Mandatory)] [string]   $Transform
      , [Parameter()]          [string]   $EndpointResourceId
      , [Parameter()]          [string]   $RuleDescription
    )

    $properties = [ordered] @{}

    # Enforced here rather than trusted from the caller, because exceeding it
    # is a preflight rejection with no deployment to inspect afterwards. The
    # limit is undocumented; see $script:MaxDescriptionLength.
    if ($RuleDescription) {
        $trimmed = ConvertTo-SafeText -Text $RuleDescription -MaxLength $script:MaxDescriptionLength

        if ($trimmed.Length -lt $RuleDescription.Length) {
            Write-PipelineMessage "Truncated the rule description to $script:MaxDescriptionLength characters; a data collection rule rejects anything longer." -Level Warning
        }

        $properties['description'] = $trimmed
    }

    if ($EndpointResourceId) { $properties['dataCollectionEndpointId'] = $EndpointResourceId }

    $properties['streamDeclarations'] = [ordered] @{
        $Stream = [ordered] @{
            columns = @($StreamColumn | ForEach-Object {
                [ordered] @{ name = $_.name; type = $_.type }
            })
        }
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
            description = "Data collection rule for $OutputStream, generated by New-DcrFromSchema.ps1."
        }
        resources      = @(
            [ordered] @{
                type       = 'Microsoft.Insights/dataCollectionRules'
                apiVersion = $script:DcrApiVersion
                name       = $Name
                location   = $Region
                kind       = 'Direct'
                properties = $properties
            }
        )
    }
}

#endregion

#region -- Deployment -----------------------------------------------------------

function Format-DeploymentError {
    <#
    .SYNOPSIS
        Flattens an ARM error object, including its nested Details, into one
        readable line.

    .DESCRIPTION
        ARM nests the useful message. A preflight failure arrives as
        "The following resource provider(s) reported preflight validation
        errors ... See inner errors for details", and the inner errors are
        one or more levels down in Details[]. Walking that recursively is the
        difference between a message you can act on and one you cannot.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [AllowNull()] [object] $ErrorObject
      , [Parameter()] [int] $Depth = 0
    )

    if ($null -eq $ErrorObject -or $Depth -gt 6) { return '' }

    # Already a message.
    if ($ErrorObject -is [string]) { return $ErrorObject }

    # Test-AzResourceGroupDeployment returns a List<PSResourceManagerError>,
    # which PowerShell hands over as one object rather than enumerating it. So
    # the input here can be the collection rather than an error, and without
    # this branch the whole list falls through to the raw-dump fallback: the
    # information survives, but as unreadable JSON instead of a chain.
    if ($ErrorObject -is [System.Collections.IEnumerable] -and
        $ErrorObject -isnot [System.Collections.IDictionary]) {

        $items = @(@($ErrorObject | ForEach-Object {
            Format-DeploymentError -ErrorObject $_ -Depth $Depth
        }) | Where-Object { $_ })

        if ($items.Count -gt 0) { return ($items -join ' | ') }
    }

    $parts = [System.Collections.Generic.List[string]]::new()

    # Both casings appear in the wild: ARM's REST payloads use camelCase, the
    # Az cmdlets project PascalCase. PSObject.Properties indexing is
    # case-insensitive, so one lookup covers both.
    $code    = $ErrorObject.PSObject.Properties['Code']
    $message = $ErrorObject.PSObject.Properties['Message']
    $target  = $ErrorObject.PSObject.Properties['Target']

    $label = @()
    if ($code -and $code.Value)       { $label += "[$($code.Value)]" }
    if ($target -and $target.Value)   { $label += "($($target.Value))" }
    if ($message -and $message.Value) { $label += [string]$message.Value }

    if ($label.Count -gt 0) { $parts.Add(($label -join ' ')) }

    foreach ($name in @('Details', 'details', 'InnerError', 'AdditionalInfo')) {
        $collection = $ErrorObject.PSObject.Properties[$name]
        if (-not $collection -or -not $collection.Value) { continue }

        foreach ($inner in @($collection.Value)) {
            $nested = Format-DeploymentError -ErrorObject $inner -Depth ($Depth + 1)
            if ($nested) { $parts.Add($nested) }
        }
        break
    }

    $flattened = ($parts | Where-Object { $_ }) -join ' -> '

    # Never return nothing for a real object. An unrecognised error type is
    # exactly when the caller most needs to see something, and an empty string
    # here produced the useless "Template validation failed:" with no reason
    # at all. Dump whatever it is instead, and let the shape be diagnosable.
    if (-not $flattened -and $Depth -eq 0) {
        $flattened = try { $ErrorObject | ConvertTo-Json -Depth 10 -Compress }
                     catch { ($ErrorObject | Out-String).Trim() }

        if ($flattened) {
            $flattened = "unrecognised error shape ($($ErrorObject.GetType().Name)): $flattened"
        }
    }

    return $flattened
}

function Invoke-TemplateDeployment {
    <#
    .SYNOPSIS
        Validates, deploys, and surfaces the real failure reason.

    .DESCRIPTION
        Two different failure modes need two different sources of truth, and
        an earlier version of this function only handled one of them.

        A RUNTIME failure (the resource provider accepted the template then
        rejected the resource) puts the actionable message in the deployment
        operations, so those are read back.

        A PREFLIGHT failure (the provider rejected the template before the
        deployment existed) has no operations to read at all. That is what
        InvalidTemplateDeployment is, and the original handler produced
        nothing useful for it:

            The template deployment '...' is not valid according to the
            validation procedure. The following resource provider(s) -
            'microsoft.insights/dataCollectionRules (2023-03-11)' reported
            preflight validation errors ... See inner errors for details.

        Those inner errors are reachable, just not where operations live. So
        this validates first with Test-AzResourceGroupDeployment, whose
        returned errors carry the nested Details, and reports them before
        attempting a deployment that would only fail the same way.

        Validation is best-effort: if the validator itself cannot run, the
        deployment is still attempted rather than blocked on a diagnostic.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $TemplatePath
      , [Parameter(Mandatory)] [string] $TargetResourceGroup
      , [Parameter(Mandatory)] [string] $DeploymentName
    )

    $validationErrors = $null
    try {
        $validationErrors = @(Test-AzResourceGroupDeployment -ResourceGroupName $TargetResourceGroup `
                                                            -TemplateFile $TemplatePath -ErrorAction Stop)
    }
    catch {
        Write-Verbose "Pre-deployment validation could not run: $($_.Exception.Message.Split([char]10)[0])"
    }

    if ($validationErrors -and $validationErrors.Count -gt 0) {
        $detail = @(@($validationErrors | ForEach-Object { Format-DeploymentError -ErrorObject $_ }) |
                    Where-Object { $_ })

        # Belt and braces on top of the flattener's own fallback: the one thing
        # this must never do is report a failure without a reason.
        if ($detail.Count -eq 0) {
            $detail = @(try { $validationErrors | ConvertTo-Json -Depth 12 -Compress }
                        catch { ($validationErrors | Out-String).Trim() })
        }

        throw "Template validation failed ($TemplatePath): $($detail -join ' | ')"
    }

    try {
        $deployment = New-AzResourceGroupDeployment -Name $DeploymentName `
                                                    -ResourceGroupName $TargetResourceGroup `
                                                    -TemplateFile $TemplatePath `
                                                    -Force -ErrorAction Stop
    }
    catch {
        $detail = $null
        try {
            $operations = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $TargetResourceGroup `
                                                                 -DeploymentName $DeploymentName -ErrorAction Stop
            $detail = @($operations |
                Where-Object { $_.ProvisioningState -eq 'Failed' } |
                ForEach-Object {
                    $message = $_.StatusMessage
                    if ($message -is [string]) { $message } else { ($message | ConvertTo-Json -Depth 8 -Compress) }
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

    return $deployment
}

#endregion

#region -- Step 1: the schema file ----------------------------------------------

Write-PipelineMessage 'Create a DCR from a JSON schema' -Level Section

if (-not $SchemaPath) {
    $SchemaPath = Read-Value -Prompt 'Path to the JSON schema file'
}

$SchemaPath = (Resolve-Path -Path $SchemaPath -ErrorAction Stop).Path
$spec       = Import-TableSpec -Path $SchemaPath

Write-PipelineMessage "Schema   : $SchemaPath"

$resolvedTableName = if ($TableName) { $TableName }
                     elseif ($spec.TableName) { $spec.TableName }
                     else { Read-Value -Prompt 'Table name (must end _CL)' }

if (-not $resolvedTableName.EndsWith('_CL')) {
    $resolvedTableName = "${resolvedTableName}_CL"
    Write-PipelineMessage "Appended the required '_CL' suffix: $resolvedTableName" -Level Warning
}

$nameProblems = @(Test-TableName -Name $resolvedTableName)
if ($nameProblems.Count -gt 0) {
    throw "Table name is not usable: $($nameProblems -join '; ')."
}

Write-PipelineMessage "Table    : $resolvedTableName"

#endregion

#region -- Step 2: Azure context ------------------------------------------------

Write-PipelineMessage 'Azure context' -Level Section

$context = Get-AzContext -ErrorAction SilentlyContinue

if (-not $context) {
    if (-not $script:Interactive) {
        throw 'No Az context found and non-interactive mode cannot sign in. Run Connect-AzAccount first.'
    }
    Write-PipelineMessage 'No Az context found. Signing in.'
    $null    = Connect-AzAccount -ErrorAction Stop
    $context = Get-AzContext
}

if ($SubscriptionId -and $context.Subscription.Id -ne $SubscriptionId) {
    Write-PipelineMessage "Switching context to subscription $SubscriptionId"

    # Set-AzContext returns a PSAzureContext directly. It has no .Context
    # property (that belongs to the PSAzureProfile that Connect-AzAccount
    # returns), so unwrapping one here would yield $null and blow up on the
    # next line under strict mode.
    $context = Set-AzContext -Subscription $SubscriptionId
}
elseif (-not $SubscriptionId -and $script:Interactive) {
    $subscriptions = @(Get-AzSubscription -ErrorAction Stop | Sort-Object Name)

    if ($subscriptions.Count -gt 1) {
        $current = if ($context.Subscription) { $context.Subscription.Id } else { '' }
        $default = [Math]::Max(0, [array]::IndexOf(@($subscriptions.Id), $current))
        $labels  = @($subscriptions | ForEach-Object { "$($_.Name)  ($($_.Id))" })
        $pick    = Read-MenuChoice -Title 'Subscription' -Option $labels -DefaultIndex $default

        if ($subscriptions[$pick].Id -ne $current) {
            $context = Set-AzContext -Subscription $subscriptions[$pick].Id
        }
    }
}

if (-not $context.Subscription) {
    throw 'Az context has no subscription selected. Run Connect-AzAccount or Set-AzContext -Subscription <id> first.'
}

$resolvedSubscriptionId = $context.Subscription.Id
Write-PipelineMessage "Account  : $($context.Account.Id)"
Write-PipelineMessage "Subscript: $resolvedSubscriptionId"

#endregion

#region -- Step 3: the workspace ------------------------------------------------

Write-PipelineMessage 'Destination workspace' -Level Section

if (-not $WorkspaceName) {
    # One call lists every workspace in the subscription with its resource
    # group and region, so picking the workspace answers all three questions
    # at once and the operator never has to know its resource group.
    $workspaces = @(Get-AzOperationalInsightsWorkspace -ErrorAction Stop | Sort-Object Name)

    if ($workspaces.Count -eq 0) {
        throw "No Log Analytics workspaces found in subscription $resolvedSubscriptionId."
    }

    $labels = @($workspaces | ForEach-Object { "$($_.Name)  ($($_.ResourceGroupName), $($_.Location))" })
    $pick   = Read-MenuChoice -Title 'Log Analytics workspace' -Option $labels

    $workspace         = $workspaces[$pick]
    $WorkspaceName     = $workspace.Name
    $ResourceGroupName = $workspace.ResourceGroupName
}
else {
    if (-not $ResourceGroupName) {
        $ResourceGroupName = Read-Value -Prompt "Resource group holding $WorkspaceName"
    }

    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName `
                                                    -Name $WorkspaceName -ErrorAction Stop
}

$workspaceResourceId = $workspace.ResourceId

if (-not $Location) {
    $specLocation = Get-SpecDefault -Extra $spec.Extra -Key 'location'
    $Location     = if ($specLocation) { [string]$specLocation } else { $workspace.Location }
}

if ($Location -ne $workspace.Location) {
    Write-PipelineMessage "DCR region '$Location' differs from the workspace region '$($workspace.Location)'. A DCR must be in the same region as its destination workspace." -Level Warning
}

if (-not $DcrResourceGroupName) { $DcrResourceGroupName = $ResourceGroupName }

Write-PipelineMessage "Workspace: $WorkspaceName ($ResourceGroupName, $($workspace.Location))"

#endregion

#region -- Step 4: schema review ------------------------------------------------

Write-PipelineMessage 'Schema review' -Level Section

$analysis = Resolve-TableSchema -Column @($spec.Columns)
$columns  = @(Invoke-SchemaEditor -Column $analysis.Columns.ToArray())

if ($columns.Count -eq 0) {
    throw 'The schema has no columns left. Nothing to create.'
}

# Carried through to step 5, where it becomes fatal if the plan is Auxiliary.
$caseCollisionWarnings = @((Resolve-TableSchema -Column $columns).SchemaIssues |
    Where-Object { $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'CaseCollision' })

# This read is advisory: it powers the Classic-table guard and the column-type
# diff, neither of which Azure needs us to perform. So a failure to read or
# parse it must not end the run, or an unexpected response shape from one API
# call blocks a deployment that would have succeeded. It is reported loudly,
# naming exactly which guards were lost, and Azure remains the real backstop
# for both of them.
$existingTable = $null

try {
    $existingTable = Get-WorkspaceTableSchema -SubscriptionId $resolvedSubscriptionId `
                                              -ResourceGroupName $ResourceGroupName `
                                              -WorkspaceName $WorkspaceName `
                                              -Table $resolvedTableName
}
catch {
    # Collapsed to one line, NOT truncated at the first newline. Taking
    # .Split([char]10)[0] of a message that ends in a pretty-printed JSON body
    # reports 'Body: {' and throws away the only diagnostic content.
    $reason = ($_.Exception.Message -replace '\s+', ' ').Trim()

    Write-PipelineMessage "Could not read the existing table: $reason" -Level Warning
    Write-PipelineMessage 'Continuing without it. Two checks are skipped for this run: whether the table is a Classic table a DCR cannot target, and whether any column type differs from the live table. Azure rejects both regardless, so the risk is a less clear error later rather than a bad deployment.' -Level Warning
}

if ($existingTable) {
    Write-PipelineMessage "Table $resolvedTableName already exists in this workspace (subtype $($existingTable.SubType))." -Level Warning

    if ($existingTable.SubType -eq 'Classic') {
        throw ("$resolvedTableName is a classic (MMA / Data Collector API) table. A DCR cannot target one " +
               '(InvalidOutputTable). Migrate it first with Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1.')
    }

    $diff = Compare-TableSchema -DesiredColumn $columns -ExistingColumn $existingTable.Columns

    if ($diff.Conflicts.Count -gt 0) {
        throw ("The live table's column types differ from the schema, and a column type cannot be changed " +
               "after creation: $($diff.Conflicts -join '; '). Align the schema file with the live table, " +
               'or use a new table name.')
    }

    if ($diff.Added.Count -gt 0) {
        Write-PipelineMessage "Adding $($diff.Added.Count) new column(s): $($diff.Added -join ', ')."
    }

    if ($diff.OnlyLive.Count -gt 0) {
        Write-PipelineMessage "The live table has $($diff.OnlyLive.Count) column(s) the schema does not mention; they are left alone and will not appear in the DCR stream: $($diff.OnlyLive -join ', ')." -Level Warning
    }
}

$streamColumns = @(ConvertTo-StreamColumn -Column $columns)
$guidColumns   = @($columns | Where-Object { $_.Type -eq 'guid' })

if ($guidColumns.Count -gt 0) {
    Write-PipelineMessage "$($guidColumns.Count) guid column(s) declared as string in the stream and cast back in the transform: $(@($guidColumns.Name) -join ', ')." -Level Warning
}

#endregion

#region -- Step 5: table settings -----------------------------------------------

Write-PipelineMessage 'Table settings' -Level Section

if (-not $Description) {
    $specDescription = Get-SpecDefault -Extra $spec.Extra -Key 'description'
    $Description     = if ($specDescription) { [string]$specDescription }
                       else { Read-Value -Prompt 'Description' -Default "Custom log table $resolvedTableName." }
}

# Whether it arrived from the schema file, a prompt or the parameter, this
# text is written into the deployed table and rule, so it is cleaned the same
# way as the column descriptions and capped at the rule's 256-character limit.
$cleanDescription = ConvertTo-SafeText -Text $Description -MaxLength $script:MaxDescriptionLength
if ($cleanDescription -ne $Description) {
    Write-PipelineMessage 'Cleaned the description before use (collapsed line breaks or removed non-printing characters).' -Level Warning
    $Description = $cleanDescription
}

if ($SkipTable) {
    Write-PipelineMessage 'Skipping table creation (-SkipTable). The DCR will target the existing table.' -Level Warning
}
else {
    if (-not $TablePlan) {
        $specPlan = Get-SpecDefault -Extra $spec.Extra -Key 'plan'

        if ($specPlan) {
            $TablePlan = [string]$specPlan
        }
        elseif ($script:Interactive) {
            $plans = @(
                'Analytics  - full query and alerting, standard ingestion cost'
                'Basic      - cheaper ingestion, 30-day fixed retention, limited KQL, no alerting'
                'Auxiliary  - cheapest, 30-day fixed retention, low-fidelity query only'
            )
            $pick      = Read-MenuChoice -Title 'Table plan' -Option $plans
            $TablePlan = @('Analytics', 'Basic', 'Auxiliary')[$pick]
        }
        else {
            $TablePlan = 'Analytics'
        }
    }

    if ($TablePlan -eq 'Auxiliary' -and $caseCollisionWarnings.Count -gt 0) {
        throw ('An Auxiliary table drops rows when column names differ only by case, so this schema cannot ' +
               "use the Auxiliary plan: $(@($caseCollisionWarnings | ForEach-Object { $_.Message }) -join ' ') " +
               'Rename the columns, or choose Analytics or Basic.')
    }

    # Documented ranges are 4 to 730 for retentionInDays and 4 to 4383 for
    # totalRetentionInDays, with -1 meaning "use the default". A value that
    # arrives through the schema file or a prompt has not been through the
    # parameter's validation, so it is range-checked here. Azure would reject
    # it too, but later and less clearly.
    # Validated into a local first, then assigned. A parameter's validation
    # attribute is re-evaluated on every later assignment to that variable, so
    # assigning an out-of-range value here throws the framework's own message:
    #
    #   The variable cannot be validated because the value 0 is not a valid
    #   value for the RetentionInDays variable.
    #
    # A schema file carrying "retentionInDays": 0 would hit exactly that, and
    # it names an internal variable rather than the file the operator wrote.
    if (-not $PSBoundParameters.ContainsKey('RetentionInDays')) {
        $specRetention = Get-SpecDefault -Extra $spec.Extra -Key 'retentionInDays'
        $candidate     = 0

        if ($null -ne $specRetention -and "$specRetention" -ne '') {
            $candidate = [int]$specRetention
        }
        elseif ($TablePlan -eq 'Analytics') {
            $answer = Read-Value -Prompt 'Interactive retention in days, 4 to 730, or -1 for the workspace default (blank to omit)' -AllowEmpty
            if ($answer) { $candidate = [int]$answer }
        }

        if ($candidate -ne 0 -and $candidate -ne -1 -and ($candidate -lt 4 -or $candidate -gt 730)) {
            throw "Interactive retention must be between 4 and 730 days, or -1 for the workspace default; got $candidate."
        }

        if ($candidate -ne 0) { $RetentionInDays = $candidate }
    }


    if (-not $PSBoundParameters.ContainsKey('TotalRetentionInDays')) {
        $specTotal = Get-SpecDefault -Extra $spec.Extra -Key 'totalRetentionInDays'
        $candidate = 0

        if ($null -ne $specTotal -and "$specTotal" -ne '') {
            $candidate = [int]$specTotal
        }
        else {
            $answer = Read-Value -Prompt 'Total retention in days, interactive plus archive, 4 to 4383, or -1 to match interactive (blank to omit)' -AllowEmpty
            if ($answer) { $candidate = [int]$answer }
        }

        if ($candidate -ne 0 -and $candidate -ne -1 -and ($candidate -lt 4 -or $candidate -gt 4383)) {
            throw "Total retention must be between 4 and 4383 days, or -1 to match interactive retention; got $candidate."
        }

        if ($candidate -ne 0) { $TotalRetentionInDays = $candidate }
    }


    if ($RetentionInDays -gt 0 -and $TotalRetentionInDays -gt 0 -and $TotalRetentionInDays -lt $RetentionInDays) {
        throw "Total retention ($TotalRetentionInDays days) cannot be shorter than interactive retention ($RetentionInDays days)."
    }
}

#endregion

#region -- Step 6: DCR settings -------------------------------------------------

Write-PipelineMessage 'Data collection rule settings' -Level Section

if (-not $DcrName) {
    $specDcrName = Get-SpecDefault -Extra $spec.Extra -Key 'dcrName'
    $suggested   = if ($specDcrName) { [string]$specDcrName }
                   else { 'dcr-' + ($resolvedTableName -replace '_CL$', '').ToLowerInvariant() }

    $DcrName = Read-Value -Prompt 'DCR name' -Default $suggested
}

if ($script:Interactive -and -not $PSBoundParameters.ContainsKey('DcrResourceGroupName')) {
    # "name" rather than a bare noun, so it is obvious the answer is a value
    # and not a decision. Read-Value adds the "(Enter to accept)" hint.
    $DcrResourceGroupName = Read-Value -Prompt 'DCR resource group name' `
                                       -Default $DcrResourceGroupName
}

# Validate it before anything is written or deployed. A typo here is otherwise
# only caught by ARM, several steps and one created table later, as
# ResourceGroupNotFound.
try {
    $null = Get-AzResourceGroup -Name $DcrResourceGroupName -ErrorAction Stop
}
catch {
    throw ("DCR resource group '$DcrResourceGroupName' does not exist in subscription " +
           "$resolvedSubscriptionId. Re-run and supply an existing resource group, or pass " +
           '-DcrResourceGroupName.')
}

$streamName       = "Custom-$resolvedTableName"
$outputStreamName = "Custom-$resolvedTableName"

if (-not $TransformKql) {
    $specTransform = Get-SpecDefault -Extra $spec.Extra -Key 'transformKql'
    $TransformKql  = if ($specTransform) { [string]$specTransform }
                     else { Get-DefaultTransform -Column $columns -StreamColumn $streamColumns }
}

if ($script:Interactive) {
    Write-PipelineMessage "Transform: $TransformKql"

    if (Read-YesNo -Prompt 'Edit the ingestion-time transform?') {
        $TransformKql = Read-Value -Prompt 'transformKql' -Default $TransformKql
    }
}

$transformCheck = Test-TransformKql -Transform $TransformKql
$TransformKql   = $transformCheck.Text

if ($transformCheck.Applied.Count -gt 0) {
    Write-PipelineMessage "Cleaned the transform before use: replaced $($transformCheck.Applied -join ', '). KQL does not accept those characters." -Level Warning
}

if (-not $DataCollectionEndpointResourceId -and $script:Interactive) {
    Write-PipelineMessage 'A Direct DCR carries its own logsIngestion endpoint. A Data Collection Endpoint is only needed behind Private Link (AMPLS).'

    if (Read-YesNo -Prompt 'Attach a Data Collection Endpoint?') {
        $DataCollectionEndpointResourceId = Read-Value -Prompt 'DCE resource ID'
    }
}

if (-not $OutputDirectory) {
    # Standalone default: write templates to the current directory. Pass
    # -OutputDirectory to land them somewhere tracked.
    $OutputDirectory = (Get-Location).Path
}

#endregion

#region -- Step 7: write the templates ------------------------------------------

Write-PipelineMessage 'Templates' -Level Section

if (-not (Test-Path -Path $OutputDirectory)) {
    if ($PSCmdlet.ShouldProcess($OutputDirectory, 'Create output directory')) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }
}

$slug          = ($resolvedTableName -replace '_CL$', '').ToLowerInvariant()
$tablePath     = Join-Path -Path $OutputDirectory -ChildPath "table-$slug.json"
$dcrPath       = Join-Path -Path $OutputDirectory -ChildPath "$DcrName.json"
$wroteTable    = $false

if (-not $SkipTable) {
    $hintedColumns = @($columns | Where-Object DataTypeHint)

    if ($hintedColumns.Count -gt 0 -and -not $IncludeDataTypeHint) {
        Write-PipelineMessage "Dropping the dataTypeHint on $($hintedColumns.Count) column(s): $(@($hintedColumns.Name) -join ', '). The live service rejects the documented enum values, and a hint only affects display. Pass -IncludeDataTypeHint to send them anyway." -Level Warning
    }

    $tableTemplate = Build-TableArmTemplate -WorkspaceName $WorkspaceName `
                                            -Table $resolvedTableName `
                                            -Column $columns `
                                            -Plan $TablePlan `
                                            -Retention $RetentionInDays `
                                            -TotalRetention $TotalRetentionInDays `
                                            -TableDescription $Description `
                                            -IncludeDataTypeHint:$IncludeDataTypeHint

    if ($PSCmdlet.ShouldProcess($tablePath, 'Write table ARM template')) {
        Set-Content -Path $tablePath -Value ($tableTemplate | ConvertTo-Json -Depth 30) -Encoding utf8NoBOM
        Write-PipelineMessage "Table    : $tablePath" -Level Success
        $wroteTable = $true
    }
}

# The description alone, not a generated prefix plus the description. The old
# form composed "Logs Ingestion API rule for <table>. <description>", which was
# both redundant with the metadata and the reason a 205-character schema
# description became a 261-character rule description and failed preflight.
$ruleDescription = if ($Description) { $Description }
                   else { "Logs Ingestion API rule for $resolvedTableName." }

$dcrTemplate = Build-DcrArmTemplate -Name $DcrName `
                                    -Region $Location `
                                    -Stream $streamName `
                                    -StreamColumn $streamColumns `
                                    -WorkspaceResourceId $workspaceResourceId `
                                    -OutputStream $outputStreamName `
                                    -Transform $TransformKql `
                                    -EndpointResourceId $DataCollectionEndpointResourceId `
                                    -RuleDescription $ruleDescription

if ($PSCmdlet.ShouldProcess($dcrPath, 'Write DCR ARM template')) {
    Set-Content -Path $dcrPath -Value ($dcrTemplate | ConvertTo-Json -Depth 30) -Encoding utf8NoBOM
    Write-PipelineMessage "DCR      : $dcrPath" -Level Success
}

Write-PipelineMessage "Stream   : $streamName ($($streamColumns.Count) columns)"
Write-PipelineMessage "Transform: $TransformKql"

#endregion

#region -- Step 8: deploy -------------------------------------------------------

$shouldDeploy = if ($WhatIfPreference) {
                    # -WhatIf suppressed the template writes, so there is
                    # nothing on disk to deploy. Say so once here rather than
                    # asking for confirmation and then failing on the missing
                    # file, which is what happens if this branch is absent.
                    Write-PipelineMessage 'Deploy' -Level Section
                    Write-PipelineMessage '-WhatIf writes no templates, so there is nothing to deploy. The lines above are what a real run would create.' -Level Warning
                    $false
                }
                elseif ($Deploy) { $true }
                elseif ($script:Interactive) {
                    Write-PipelineMessage 'Deploy' -Level Section
                    Read-YesNo -Prompt "Deploy the table and the DCR to $resolvedSubscriptionId now?"
                }
                else { $false }

$deployed    = $false
$immutableId = $null
$endpoint    = $null
$granted     = @()

if ($shouldDeploy) {
    Write-PipelineMessage 'Deploying' -Level Section

    $confirmBypassed = $Force -or ($PSBoundParameters.ContainsKey('Confirm') -and (-not $PSBoundParameters['Confirm']))

    if (-not $confirmBypassed -and $script:Interactive) {
        $summary = if ($SkipTable) { "DCR $DcrName in $DcrResourceGroupName" }
                   else { "table $resolvedTableName in $WorkspaceName, and DCR $DcrName in $DcrResourceGroupName" }

        if (-not (Read-YesNo -Prompt "This creates $summary. Continue?" -Default $true)) {
            throw 'Deployment declined. The templates are written and can be deployed later.'
        }
    }

    $stamp = Get-Date -Format 'yyyyMMddHHmmss'

    # The table must exist before the DCR: a rule whose outputStream names a
    # missing table fails with InvalidOutputTable, and the message reads like
    # a template problem rather than an ordering one.
    if (-not $SkipTable) {
        if (-not $wroteTable) {
            throw 'The table template was not written, so it cannot be deployed. Re-run without -WhatIf.'
        }

        if ($PSCmdlet.ShouldProcess("$WorkspaceName/$resolvedTableName", 'Deploy custom table')) {
            $null = Invoke-TemplateDeployment -TemplatePath $tablePath `
                                              -TargetResourceGroup $ResourceGroupName `
                                              -DeploymentName "table-$slug-$stamp"
            Write-PipelineMessage "Created $resolvedTableName." -Level Success
        }
    }

    if ($PSCmdlet.ShouldProcess("$DcrResourceGroupName/$DcrName", 'Deploy data collection rule')) {
        $null = Invoke-TemplateDeployment -TemplatePath $dcrPath `
                                          -TargetResourceGroup $DcrResourceGroupName `
                                          -DeploymentName "$DcrName-$stamp"

        $deployed = $true
        Write-PipelineMessage "Deployed $DcrName." -Level Success

        $dcrId = "/subscriptions/$resolvedSubscriptionId/resourceGroups/$DcrResourceGroupName" +
                 "/providers/Microsoft.Insights/dataCollectionRules/$DcrName"
        $dcr   = (Invoke-ArmRequest -Uri "$dcrId`?api-version=$script:DcrApiVersion" -SuccessCodes @(200)).Content |
                 ConvertFrom-Json

        $immutableProperty = $dcr.properties.PSObject.Properties['immutableId']
        if ($immutableProperty) {
            $immutableId = [string]$immutableProperty.Value
            Write-PipelineMessage "ImmutableId: $immutableId"
        }

        $endpointsProperty = $dcr.properties.PSObject.Properties['endpoints']
        if ($endpointsProperty -and $endpointsProperty.Value) {
            $ingestProperty = $endpointsProperty.Value.PSObject.Properties['logsIngestion']
            if ($ingestProperty) {
                $endpoint = [string]$ingestProperty.Value
                Write-PipelineMessage "Ingestion  : $endpoint"
            }
        }

        if (-not $endpoint) {
            Write-PipelineMessage 'No logsIngestion endpoint was returned for this Direct DCR. Endpoints cannot be added to an existing DCR, so this one needs a Data Collection Endpoint or a replacement DCR.' -Level Warning
        }

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
                        $granted += $identity
                    }
                    elseif ($PSCmdlet.ShouldProcess("$DcrName / $identity", "Grant $roleName")) {
                        New-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName $roleName `
                                             -Scope $dcrId -ErrorAction Stop | Out-Null
                        Write-PipelineMessage "  Granted $roleName to $identity. Data-plane RBAC can take a few minutes to take effect." -Level Success
                        $granted += $identity
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

#endregion

#region -- Summary --------------------------------------------------------------

Write-PipelineMessage ''
Write-PipelineMessage 'Summary' -Level Section

Write-PipelineMessage "Table    : $resolvedTableName ($($columns.Count) columns)"
Write-PipelineMessage "DCR      : $DcrName in $DcrResourceGroupName ($Location)"

if ($WhatIfPreference) {
    # Printing deploy commands for paths that were never written would invite
    # the operator to run them and get a file-not-found.
    Write-PipelineMessage ''
    Write-PipelineMessage 'Nothing was written or deployed (-WhatIf). Re-run without -WhatIf to produce the templates.'
}
elseif (-not $deployed) {
    Write-PipelineMessage ''
    Write-PipelineMessage 'Not deployed. Deploy in this order, table first:'

    if (-not $SkipTable) {
        Write-PipelineMessage "  New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile '$tablePath'"
    }

    Write-PipelineMessage "  New-AzResourceGroupDeployment -ResourceGroupName $DcrResourceGroupName -TemplateFile '$dcrPath'"
    Write-PipelineMessage 'A DCR deployed before its table fails with InvalidOutputTable.'
}
elseif ($endpoint -and $immutableId) {
    Write-PipelineMessage ''

    if ($granted.Count -gt 0) {
        Write-PipelineMessage 'Next: the ingestion role is granted. POST your data to:'
    }
    else {
        Write-PipelineMessage 'Next: grant Monitoring Metrics Publisher on the DCR (re-run with -GrantIngestionRoleTo), then POST to:'
    }

    Write-PipelineMessage "  $endpoint/dataCollectionRules/$immutableId/streams/$streamName`?api-version=2023-01-01"
    Write-PipelineMessage ''
    Write-PipelineMessage 'To prove ingestion end to end with synthetic data:'
    Write-PipelineMessage "  ./ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1 -DcrName $DcrName -DcrResourceGroupName $DcrResourceGroupName -Follow"
}

[pscustomobject] @{
    TableName         = $resolvedTableName
    ColumnCount       = $columns.Count
    WorkspaceName     = $WorkspaceName
    ResourceGroupName = $ResourceGroupName
    DcrName           = $DcrName
    DcrResourceGroup  = $DcrResourceGroupName
    Location          = $Location
    StreamName        = $streamName
    TransformKql      = $TransformKql
    TableTemplatePath = if ($SkipTable) { $null } else { $tablePath }
    DcrTemplatePath   = $dcrPath
    Deployed          = $deployed
    ImmutableId       = $immutableId
    Endpoint          = $endpoint
    Granted           = $granted
}

#endregion


