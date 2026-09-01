#
# Sentinel-As-Code/Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1
#
# Created by noodlemctwoodle on 01/09/2026.
#

#
# Sentinel-As-Code/Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1
#
# Originated as the Sentinel-CLv1-Analyzer project (MIT, by noodlemctwoodle),
# now folded into Sentinel-As-Code (Apache-2.0) as the assess-and-plan stage
# of the ClassicToDcr migration toolkit.
#

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.13.0' }

<#
.SYNOPSIS
    Discover classic custom log tables, assess dependency impact, and map to Content Hub solutions.

.DESCRIPTION
    Interactive PowerShell script that mirrors the Table Migration Manager web app.

    Step 1 - Discover classic V1 custom log tables (CLv1) in a Microsoft Sentinel workspace.
    Step 2 - Assess impact across Analytics Rules, Workbooks, Hunting Queries, Parsers,
             Saved Searches, SOAR Playbooks, and Data Collection Rules.
    Step 3 - Map classic tables to Content Hub solutions and classify each connector as
             CCF (Codeless Connector Framework), Azure Functions, Platform, or Unknown.
             Flag legacy Azure Functions connectors that have no CCF equivalent.

    Outputs: pipeline objects, per-step CSV files, a combined JSON file, and a
    self-contained HTML report.

.PARAMETER SubscriptionId
    Azure subscription containing the Sentinel workspace. Prompted if omitted.

.PARAMETER ResourceGroupName
    Resource group of the Log Analytics workspace. Prompted if omitted.

.PARAMETER WorkspaceName
    Log Analytics workspace name. Prompted if omitted.

.PARAMETER OutputPath
    Directory for CSV / JSON / HTML output. Defaults to ./migration-report.

.PARAMETER NonInteractive
    Skip all prompts - fails if required parameters are missing.

.PARAMETER MaxParserChainDepth
    How many parser hops to follow when resolving content that reaches a
    classic table through a parser function rather than by name. Defaults to
    10, which is more than double the deepest hierarchy Microsoft ships.
    A chain deeper than this is reported as truncated rather than dropped
    silently; raise the value if that happens.

.EXAMPLE
    ./Invoke-TableMigrationReview.ps1

    Interactive mode - prompts for subscription, resource group, and workspace.

.EXAMPLE
    ./Invoke-TableMigrationReview.ps1 `
        -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -ResourceGroupName 'rg-sentinel' `
        -WorkspaceName 'ws-sentinel' `
        -OutputPath './reports/2026-04'

    Scripted mode - outputs all reports to ./reports/2026-04.

.NOTES
    Version: 0.2.0
    Author:       noodlemctwoodle
                  https://github.com/noodlemctwoodle

    Data source:
        Azure-Sentinel Solutions Analyzer
        https://github.com/Azure/Azure-Sentinel/tree/master/Tools/Solutions%20Analyzer

.LINK
    https://github.com/noodlemctwoodle/Sentinel-CLv1-Analyzer
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NonInteractive',
    Justification = 'Consumed by Read-Required through script scope, which the analyzer cannot see.')]
[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$WorkspaceName,
    [string]$OutputPath = (Join-Path (Get-Location) 'migration-report'),
    [switch]$NonInteractive,
    [ValidateRange(1, 100)]
    [int]$MaxParserChainDepth = 10
)

$ErrorActionPreference = 'Stop'
$ProgressPreference     = 'Continue'

# -------------------------------------------------------------------------
# Constants
# -------------------------------------------------------------------------

$script:ArmBaseUrl    = 'https://management.azure.com'
$script:ApiTables     = '2023-09-01'
$script:ApiSentinel   = '2024-03-01'
$script:ApiSavedLogs  = '2020-08-01'
$script:ApiInsights   = '2023-06-01'
$script:ApiDcr        = '2022-06-01'
$script:ApiLogic      = '2019-05-01'

# Solution mapping - bundled in data/ subfolder
$script:MappingPath = Join-Path $PSScriptRoot 'data' 'solution-mapping.json'

# -------------------------------------------------------------------------
# UI helpers
# -------------------------------------------------------------------------

function Write-Console {
    # All console output funnels through here so Write-Host lives in one place.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Console output is the point; this is a console-first report tool.')]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray,
        [switch]$NoNewline
    )
    Write-Host $Message -ForegroundColor $Color -NoNewline:$NoNewline
}

function Write-Step {
    param([string]$Message)
    Write-Console ''
    Write-Console "══ $Message " Cyan -NoNewline
    Write-Console ('═' * [Math]::Max(0, 70 - $Message.Length)) Cyan
}

function Write-Info  { param($m) Write-Console "  $m" }
function Write-Ok    { param($m) Write-Console "  ✓ $m" Green }
function Write-Warn2 { param($m) Write-Console "  ⚠ $m" Yellow }
function Write-Err   { param($m) Write-Console "  ✗ $m" Red }

function Read-Required {
    param([string]$Prompt, [string]$Current)
    if ($Current) { return $Current }
    if ($NonInteractive) { throw "Parameter '$Prompt' is required in non-interactive mode." }
    do {
        $value = Read-Host -Prompt "  $Prompt"
    } while (-not $value)
    return $value.Trim()
}

# -------------------------------------------------------------------------
# Authentication
# -------------------------------------------------------------------------

function Initialize-AzContext {
    param([string]$SubscriptionId)

    Write-Info 'Checking Az.Accounts module...'
    Import-Module Az.Accounts -ErrorAction Stop

    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        Write-Info 'No Azure context found - running Connect-AzAccount...'
        $null = Connect-AzAccount -ErrorAction Stop
        $ctx = Get-AzContext
    }

    if ($SubscriptionId -and $ctx.Subscription.Id -ne $SubscriptionId) {
        Write-Info "Switching to subscription $SubscriptionId"
        $null = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
        $ctx = Get-AzContext
    }

    Write-Ok "Authenticated as $($ctx.Account.Id) in subscription $($ctx.Subscription.Name)"
    return $ctx
}

function Get-ArmToken {
    $token = Get-AzAccessToken -ResourceUrl $script:ArmBaseUrl -ErrorAction Stop
    # Handle Az >=12 which returns SecureString
    if ($token.Token -is [System.Security.SecureString]) {
        return [System.Net.NetworkCredential]::new('', $token.Token).Password
    }
    return $token.Token
}

# -------------------------------------------------------------------------
# REST helpers
# -------------------------------------------------------------------------

function Invoke-ArmRequest {
    param(
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Query = @{}
    )
    $token = Get-ArmToken
    $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

    $qs = ($Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }) -join '&'
    $url = "$script:ArmBaseUrl$Path" + ($(if ($qs) { "?$qs" } else { '' }))

    $results = @()
    do {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        if ($response.value) { $results += $response.value }
        elseif ($response -is [array]) { $results += $response }
        else { $results += $response }
        $url = $response.nextLink
    } while ($url)
    return $results
}

# -------------------------------------------------------------------------
# Step 1 - Discover tables
# -------------------------------------------------------------------------

function Get-WorkspaceTableInventory {
    <#
        One /tables call, two answers.

        ClassicTables is the migration candidate list and is the only thing
        this function ever used to return. AllTableNames is every table the
        workspace knows about, built-ins included, and it exists because the
        transitive resolver needs it: a parser aliased 'Update' or
        'SecurityEvent' would otherwise make every query against the genuine
        built-in table look like a dependent of whatever classic table that
        parser happens to read. The call already fetched the whole list and
        threw the non-classic entries away, so the guard costs nothing.
    #>
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$WorkspaceName
    )
    $path = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/tables"
    $tables = Invoke-ArmRequest -Path $path -Query @{ 'api-version' = $script:ApiTables }

    # AzureDiagnostics can appear as CustomLog/Classic but is a Microsoft-managed
    # table that should never be shown as a migration candidate. It is still a
    # real table, so it stays in AllTableNames.
    $EXCLUDED_TABLES = @('AzureDiagnostics')

    $classic = $tables | Where-Object {
        $_.properties.schema.tableType    -eq 'CustomLog' -and
        $_.properties.schema.tableSubType -eq 'Classic' -and
        $_.name -notin $EXCLUDED_TABLES
    }

    $projected = foreach ($t in $classic) {
        [PSCustomObject]@{
            Name            = $t.name
            TableType       = $t.properties.schema.tableType
            TableSubType    = $t.properties.schema.tableSubType
            Plan            = $t.properties.plan
            RetentionInDays = $t.properties.retentionInDays
            TotalRetention  = $t.properties.totalRetentionInDays
            ColumnCount     = $t.properties.schema.columns.Count
            ResourceId      = $t.id
        }
    }

    # Column names come back on the same call, so collecting them costs nothing.
    # They matter because a bare identifier in a column position, for example
    # 'SigninLogs | project Location', is indistinguishable from a function
    # invocation without a real KQL parser. Treating an alias that collides with
    # a known column name as ambiguous removes that whole class, and it removes
    # it for exactly the names that cause it: Location, IPAddress, User, Status.
    $columnName = foreach ($t in @($tables)) {
        foreach ($c in @($t.properties.schema.columns)) {
            if ($c -and $c.name) { $c.name }
        }
    }

    [PSCustomObject]@{
        ClassicTables  = @($projected)
        AllTableNames  = @(@($tables) | ForEach-Object { $_.name } | Where-Object { $_ })
        AllColumnNames = @($columnName | Where-Object { $_ } | Sort-Object -Unique)
    }
}

function Get-ClassicCustomLogTable {
    <#
        Unchanged contract: the classic custom-log tables, one object each.
        Kept as a thin wrapper over Get-WorkspaceTableInventory so a caller
        that only wants the migration candidates still reads the same.
    #>
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$WorkspaceName
    )
    $inventory = Get-WorkspaceTableInventory -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName
    return @($inventory.ClassicTables)
}

# -------------------------------------------------------------------------
# Workspace content loaders
# -------------------------------------------------------------------------

function Get-WorkspaceContent {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$WorkspaceName
    )

    $sentinelBase = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights"
    $opLogsBase   = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"

    Write-Info 'Loading Analytics Rules...'
    $alertRules = Invoke-ArmRequest -Path "$sentinelBase/alertRules" -Query @{ 'api-version' = $script:ApiSentinel }

    Write-Info 'Loading Saved Searches (hunting + parsers)...'
    $savedSearches = Invoke-ArmRequest -Path "$opLogsBase/savedSearches" -Query @{ 'api-version' = $script:ApiSavedLogs }

    Write-Info 'Loading Workbooks...'
    $workbookPath = "/subscriptions/$SubscriptionId/providers/Microsoft.Insights/workbooks"
    try {
        $workbooks = Invoke-ArmRequest -Path $workbookPath -Query @{
            'api-version' = $script:ApiInsights
            'category'    = 'sentinel'
        }
    } catch {
        Write-Warn2 "Workbook load failed: $($_.Exception.Message)"
        $workbooks = @()
    }

    Write-Info 'Loading Data Collection Rules...'
    $dcrPath = "/subscriptions/$SubscriptionId/providers/Microsoft.Insights/dataCollectionRules"
    try {
        $dcrs = Invoke-ArmRequest -Path $dcrPath -Query @{ 'api-version' = $script:ApiDcr }
    } catch {
        Write-Warn2 "DCR load failed: $($_.Exception.Message)"
        $dcrs = @()
    }

    Write-Info 'Loading Logic Apps (playbooks)...'
    $logicPath = "/subscriptions/$SubscriptionId/providers/Microsoft.Logic/workflows"
    try {
        $logicApps = Invoke-ArmRequest -Path $logicPath -Query @{ 'api-version' = $script:ApiLogic }
    } catch {
        Write-Warn2 "Logic App load failed: $($_.Exception.Message)"
        $logicApps = @()
    }

    [PSCustomObject]@{
        AlertRules    = @($alertRules)
        SavedSearches = @($savedSearches)
        HuntingQueries = @($savedSearches | Where-Object { $_.properties.category -eq 'Hunting Queries' })
        Parsers        = @($savedSearches | Where-Object { $_.properties.functionAlias })
        Workbooks     = @($workbooks)
        Dcrs          = @($dcrs)
        Playbooks     = @($logicApps)
    }
}

# -------------------------------------------------------------------------
# KQL scanning
# -------------------------------------------------------------------------

function Test-KqlReferencesTable {
    param([string]$Query, [string]$TableName)
    if (-not $Query) { return $false }
    # Word-boundary match on the table name, case-insensitive
    return $Query -match "(?i)(?<![a-zA-Z0-9_])$([regex]::Escape($TableName))(?![a-zA-Z0-9_])"
}

function Get-MatchedTable {
    param([string]$Query, [string[]]$TableNames)
    if (-not $Query) { return @() }
    $matched = @()
    foreach ($t in $TableNames) {
        if (Test-KqlReferencesTable -Query $Query -TableName $t) { $matched += $t }
    }
    return $matched
}

function Get-WorkbookQueryText {
    param([string]$SerializedData)
    if (-not $SerializedData) { return @() }
    try {
        $parsed = $SerializedData | ConvertFrom-Json -Depth 20
    } catch { return @() }

    function Walk($node) {
        if ($null -eq $node) { return }
        if ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string])) {
            foreach ($c in $node) { Walk $c }
            return
        }
        if ($node -is [PSCustomObject] -or $node -is [hashtable]) {
            $props = if ($node -is [hashtable]) { $node.Keys } else { $node.PSObject.Properties.Name }
            foreach ($p in $props) {
                $val = $node.$p
                if ($p -eq 'query' -and $val -is [string]) { $script:__queries += $val }
                Walk $val
            }
        }
    }
    $script:__queries = @()
    Walk $parsed
    return $script:__queries
}

# -------------------------------------------------------------------------
# Parser alias resolution (transitive dependencies)
#
# A Log Analytics parser is a saved search that carries a functionAlias.
# Everything else invokes it by that alias exactly as if it were a table, so
# an analytics rule reading "OfficeActivityParser | where ..." never names the
# classic table the parser sits on top of. Direct name matching misses it, and
# the operator migrates the table believing the rule is safe.
#
# These helpers build a single index of which content item references which
# alias, then walk that graph outward from each classic table so the chain
# rule -> parser -> table is reported alongside the direct hits.
# -------------------------------------------------------------------------

function Get-ReservedAliasName {
    <#
        Alias names that cannot be resolved by name alone.

        Transitive resolution treats a functionAlias as if it were a table
        name: content whose KQL names that identifier is reported as a
        dependent. Everything on this list is an identifier that appears in
        code position in essentially every query, so a match carries no
        information about a real dependency.

        The list is deliberately much shorter than it was. It used to carry a
        second block of "ubiquitous identifiers" - alert, body, data, name,
        status, user, workspace and thirty more - which were standing in for
        two problems that are now fixed properly:

          - names colliding with a real table (Update, SecurityEvent) are now
            caught by the workspace table-name guard in Get-FunctionAliasSafety
          - names colliding with Logic App JSON keys are now caught by
            restricting playbook alias matching to values that look like KQL

        Suppressing an alias is not free. A parser aliased 'Alerts' that reads
        a classic table used to sever the whole chain below it and report
        nothing, which is the silent breakage this feature exists to prevent.
        What is left earns its place:

          - KQL keywords, tabular operators, literals and scalar type names.
            An alias called 'where' or 'summarize' matches every query in the
            workspace, and KQL itself requires such a name to be bracket-quoted
            at every use site, so it is a pathological alias to begin with.
          - The scoping functions cluster, database, workspace and app, which
            introduce a cross-cluster reference rather than name local content.
          - The standard columns Log Analytics puts on EVERY table. An alias
            equal to one of those is guaranteed to appear in unrelated queries
            in a position this analyzer cannot rule out (a column reference).

        Entries are compared case-insensitively - a KQL keyword is itself
        case-sensitive, but an alias differing only in case from one is still
        a name no operator can read unambiguously. Suppression only ever
        affects the INDIRECT pass; direct table matching is untouched, and
        every suppression is reported with its reason and its lost dependents.
    #>
    return @(
        # KQL keywords, tabular operators, literals and scalar type names.
        'and', 'asc', 'between', 'bool', 'by', 'consume', 'contains', 'count',
        'datatable', 'datetime', 'decimal', 'desc', 'distinct', 'dynamic',
        'endswith', 'evaluate', 'extend', 'externaldata', 'facet', 'false',
        'find', 'fork', 'getschema', 'guid', 'has', 'in', 'int', 'invoke', 'join',
        'let', 'limit', 'long', 'lookup', 'matches', 'materialize', 'mvexpand',
        'not', 'null', 'on', 'or', 'order', 'parse', 'partition', 'print',
        'project', 'query', 'range', 'real', 'reduce', 'render', 'restrict',
        'sample', 'scan', 'search', 'serialize', 'set', 'sort', 'source',
        'startswith', 'string', 'summarize', 'take', 'timespan', 'top',
        'toscalar', 'true', 'union', 'view', 'where',
        # Scoping functions. These name something outside the workspace.
        'app', 'cluster', 'database', 'workspace',
        # Standard columns present on every Log Analytics table, so an alias
        # equal to one of them matches queries that have nothing to do with it.
        'timegenerated', 'tenantid', 'sourcesystem', 'type', 'computer',
        'rawdata', 'managementgroupname'
    )
}

function Get-FunctionAliasSafety {
    <#
        Decide whether a parser's functionAlias can be resolved transitively,
        and say why not when it cannot. Returns Alias (trimmed), IsSafe and
        Reason.

        WorkspaceTableName is every table the workspace knows about, from
        Get-WorkspaceTableInventory. An alias that collides with a real table
        name is not resolvable: a query naming 'Update' overwhelmingly means
        the Update table, not a parser someone aliased over the top of it, and
        resolving it would make every such query an indirect dependent of
        whatever classic table that parser reads. The comparison is
        case-insensitive on purpose even though alias matching downstream is
        case-sensitive, because a near-miss on a table name is ambiguous to a
        human reader too. Omitting the list disables only this check.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Alias,
        [int]$MinimumLength = 4,
        [AllowNull()][string[]]$WorkspaceTableName,
        [AllowNull()][string[]]$WorkspaceColumnName
    )

    $trimmed = if ($null -eq $Alias) { '' } else { $Alias.Trim() }

    if (-not $trimmed) {
        return [PSCustomObject]@{ Alias = ''; IsSafe = $false; Reason = 'alias is empty' }
    }
    if ($trimmed -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        return [PSCustomObject]@{
            Alias  = $trimmed
            IsSafe = $false
            Reason = 'not a plain KQL identifier, so a word-boundary match is not reliable'
        }
    }
    if ($trimmed.Length -lt $MinimumLength) {
        return [PSCustomObject]@{
            Alias  = $trimmed
            IsSafe = $false
            Reason = "shorter than $MinimumLength characters, too generic to match safely"
        }
    }
    if ((Get-ReservedAliasName) -contains $trimmed.ToLowerInvariant()) {
        return [PSCustomObject]@{
            Alias  = $trimmed
            IsSafe = $false
            Reason = 'reserved KQL keyword, scoping function or universal Log Analytics column name'
        }
    }
    foreach ($tableName in @($WorkspaceTableName)) {
        if ($tableName -and [string]::Equals([string]$tableName, $trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [PSCustomObject]@{
                Alias  = $trimmed
                IsSafe = $false
                Reason = "collides with the workspace table '$tableName', so a query naming it far more likely means the table"
            }
        }
    }
    foreach ($columnName in @($WorkspaceColumnName)) {
        if ($columnName -and [string]::Equals([string]$columnName, $trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [PSCustomObject]@{
                Alias  = $trimmed
                IsSafe = $false
                Reason = "collides with the column name '$columnName', and a bare identifier in a column position cannot be told apart from a function call without a full KQL parser"
            }
        }
    }
    return [PSCustomObject]@{ Alias = $trimmed; IsSafe = $true; Reason = '' }
}

function Test-SafeFunctionAlias {
    param(
        [AllowNull()][AllowEmptyString()][string]$Alias,
        [int]$MinimumLength = 4,
        [AllowNull()][string[]]$WorkspaceTableName,
        [AllowNull()][string[]]$WorkspaceColumnName
    )
    return (Get-FunctionAliasSafety -Alias $Alias -MinimumLength $MinimumLength `
        -WorkspaceTableName $WorkspaceTableName -WorkspaceColumnName $WorkspaceColumnName).IsSafe
}

# -------------------------------------------------------------------------
# KQL-aware text preparation
#
# Splitting raw query text on [^A-Za-z0-9_] finds an identifier wherever it
# appears, including places KQL never resolves a name: inside a comment,
# inside a string literal, behind a cross-cluster qualifier, on the left of an
# assignment, after a dot, or bound by a let in the same query. Every one of
# those produced a false indirect dependency, and a false dependency on a
# parser propagates to every genuine user of that parser at the next hop.
#
# These functions remove the positions KQL provably does not resolve a stored
# function in. They are deliberately conservative: each rule removes text that
# cannot be a function reference, so a genuine reference is never lost. What
# they do NOT do is prove the remaining occurrence IS in tabular source
# position - a bare column reference such as `SigninLogs | project MyParser`
# still counts. Proving that needs a real KQL parser, which this standalone
# script does not carry.
# -------------------------------------------------------------------------

function Expand-KqlQuotedIdentifier {
    <#
        Rewrite the bracket-quoted identifier forms ['Name'] and ["Name"] to a
        bare Name, so the reference survives the string-literal stripper that
        runs next. KQL uses this form for names containing special characters
        or clashing with a keyword, but it is legal for any identifier.

        Guarded against the far more common dynamic-index expression: a
        bracket preceded by an identifier, ')' or ']' is an index into a value
        (parse_json(x)["foo"], Properties['bar']), not a quoted entity name,
        and is left alone so its key does not become a bare identifier.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return [regex]::Replace(
        $Text,
        '(?<![A-Za-z0-9_)\]])\[\s*([''"])([A-Za-z_][A-Za-z0-9_]*)\1\s*\]',
        ' $2 ')
}

function Get-KqlCodeText {
    <#
        Return the text with every comment and string literal replaced by a
        single space, so identifier extraction only ever sees code.

        The forms handled are exactly the ones KQL defines, verified against
        the Kusto string data type and comment reference:

          //              line comment, runs to end of line. KQL has NO block
                          comment form, so none is invented here.
          '...' "..."     escapes with backslash
          @'...' @"..."   verbatim: backslash is literal, the enclosing quote
                          is escaped by doubling it
          ```...```       multi-line literal, no escapes at all
          h'...' h"..."   obfuscated: the h/H prefix wraps a standard or
          h@'...'         verbatim literal, so the body is handled by the
                          rules above and the prefix character is left in
                          place (a one-character token cannot collide with an
                          alias, which has a four-character floor)

        A single-line literal is also terminated by an unescaped newline. KQL
        requires a newline inside one to be escaped, so an unterminated quote
        is malformed text; stopping at the line end bounds the damage to that
        line instead of swallowing the rest of the query.

        Comments are recognised before quotes and quotes before comments in
        the same pass, so a // inside a string does not open a comment and an
        apostrophe inside a comment does not open a string.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }

    $sb  = [System.Text.StringBuilder]::new($Text.Length)
    $len = $Text.Length
    $i   = 0

    while ($i -lt $len) {
        $ch = $Text[$i]

        # Line comment.
        if ($ch -eq '/' -and ($i + 1) -lt $len -and $Text[$i + 1] -eq '/') {
            while ($i -lt $len -and $Text[$i] -ne "`n" -and $Text[$i] -ne "`r") { $i++ }
            [void]$sb.Append(' ')
            continue
        }

        # Multi-line string literal.
        if ($ch -eq '`' -and ($i + 2) -lt $len -and $Text[$i + 1] -eq '`' -and $Text[$i + 2] -eq '`') {
            $close = $Text.IndexOf('``' + '`', $i + 3)
            $i = if ($close -lt 0) { $len } else { $close + 3 }
            [void]$sb.Append(' ')
            continue
        }

        if ($ch -eq "'" -or $ch -eq '"') {
            # A preceding @ makes this literal verbatim. The @ itself is not an
            # identifier character, so leaving it in the output changes nothing.
            $verbatim = ($i -gt 0 -and $Text[$i - 1] -eq '@')
            $quote = $ch
            $i++
            while ($i -lt $len) {
                $c = $Text[$i]
                if ($c -eq "`n" -or $c -eq "`r") { break }
                if ($verbatim) {
                    if ($c -eq $quote) {
                        if (($i + 1) -lt $len -and $Text[$i + 1] -eq $quote) { $i += 2; continue }
                        $i++
                        break
                    }
                    $i++
                }
                else {
                    if ($c -eq '\') { $i += 2; continue }
                    if ($c -eq $quote) { $i++; break }
                    $i++
                }
            }
            [void]$sb.Append(' ')
            continue
        }

        [void]$sb.Append($ch)
        $i++
    }

    return $sb.ToString()
}

function ConvertTo-KqlNameSearchText {
    <#
        Blank out the identifier positions that provably never resolve to a
        stored function in THIS workspace. Runs on the output of
        Get-KqlCodeText, so comments and string literals are already gone.

          cluster(...).X       a reference into another cluster, database,
          database(...).X      workspace or app. Never a local function. The
          workspace(...).X     argument pattern stays permissive so a variable
          app(...).X           or parameter argument is handled too.

          Something.Name       member access on a dynamic value or a returned
                               object. A workspace function is referenced bare,
                               never dotted.

          Name =               an assignment target, so a NEW column or
                               variable being named. == and =~ are excluded;
                               != <= >= cannot match because the character
                               before the = would not be an identifier.

        One function rather than three because each step feeds the next and
        splitting them bought nothing but three names to keep in sync.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }

    $qualifier = '(?:cluster|database|workspace|app)\s*\([^()]*\)\s*\.\s*'
    $out = [regex]::Replace($Text, "(?<![A-Za-z0-9_])(?:$qualifier)+[A-Za-z_][A-Za-z0-9_]*", ' ')
    $out = [regex]::Replace($out, '\.\s*[A-Za-z_][A-Za-z0-9_]*', ' ')
    $out = [regex]::Replace($out, '(?<![A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*(\s*=(?![=~]))', ' $1')
    return $out
}

function Get-KqlLetBoundName {
    <#
        Names introduced by a let statement in this query. A let binding
        shadows a stored function of the same name for the rest of the query,
        so an occurrence of that name is a local, not a parser reference.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ([string]::IsNullOrEmpty($Text)) { return , $names }
    foreach ($m in [regex]::Matches($Text, '(?<![A-Za-z0-9_])let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=')) {
        [void]$names.Add($m.Groups[1].Value)
    }
    return , $names
}

function Get-KqlIdentifierSet {
    <#
        Split text into the maximal runs of [A-Za-z0-9_] it contains.

        That split class is the exact complement of the lookaround class in
        Test-KqlReferencesTable, so for any needle made only of those
        characters - which every table name and every alias that passes
        Get-FunctionAliasSafety is - membership of this set and a positive
        Test-KqlReferencesTable are the same answer. The set is used because
        the transitive pass asks the same text about many names at once.

        Case-insensitive by default so it keeps answering the same question as
        Test-KqlReferencesTable. Pass -CaseSensitive for the transitive pass,
        which matches KQL's own rule for identifiers.
    #>
    param(
        [AllowNull()][string[]]$Text,
        [switch]$CaseSensitive
    )

    $comparer = if ($CaseSensitive) { [System.StringComparer]::Ordinal } else { [System.StringComparer]::OrdinalIgnoreCase }
    $set = [System.Collections.Generic.HashSet[string]]::new($comparer)
    foreach ($t in @($Text)) {
        if ([string]::IsNullOrEmpty($t)) { continue }
        foreach ($token in ($t -split '[^A-Za-z0-9_]+')) {
            if ($token) { [void]$set.Add($token) }
        }
    }
    return , $set
}

function Get-KqlReferenceIdentifierSet {
    <#
        The identifiers a KQL body could actually resolve to a workspace
        entity, as an ORDINAL (case-sensitive) set.

        Case sensitivity is not a style choice. KQL entity names are
        case-sensitive - "you can't refer to a table called ThisTable as
        thisTABLE" - so 'officeparser' does not resolve to a parser aliased
        'OfficeParser' and must not be reported as a dependent of it.

        This is deliberately ASYMMETRIC with Test-KqlReferencesTable, which
        stays case-insensitive. That matcher decides DIRECT hits, its
        behaviour is inherited and pinned by tests, and a case variant of a
        table name is nearly always a human typo aimed at the real table, so
        reporting it errs safe. Indirect resolution chains off its own
        matches, where one false hit multiplies across every later hop, so it
        errs precise instead.
    #>
    param([AllowNull()][string[]]$Text)

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($t in @($Text)) {
        if ([string]::IsNullOrEmpty($t)) { continue }

        $code = Get-KqlCodeText -Text (Expand-KqlQuotedIdentifier -Text $t)

        # Collected before the assignment-target pass erases the binding site.
        $bound = Get-KqlLetBoundName -Text $code

        foreach ($token in ((ConvertTo-KqlNameSearchText -Text $code) -split '[^A-Za-z0-9_]+')) {
            if ($token -and -not $bound.Contains($token)) { [void]$set.Add($token) }
        }
    }
    return , $set
}

function Get-PlaybookKqlText {
    <#
        The strings inside a Logic App definition that are plausibly KQL.

        Scanning the whole serialised definition - which is what the direct
        pass does, and what the indirect pass used to do - means a JSON KEY or
        a word in an action name counts as a reference. That is tolerable for
        a distinctive table name and useless for an alias, so the indirect
        pass looks only at string VALUES, and only those shaped like a query:
        a pipe followed by a KQL tabular operator, or a query that opens with
        one. That is the shape of every Run-query action body.

        The trade is stated plainly in the README: a playbook that builds its
        query by string concatenation, or passes it in a form this test does
        not recognise, is not matched indirectly. Direct table matching over
        playbooks is unchanged and still reads the whole definition.
    #>
    param([AllowNull()]$Definition)

    $operators = 'where|project|project-away|project-keep|project-rename|project-reorder|' +
                 'summarize|extend|take|limit|count|join|union|parse|parse-where|parse-kv|' +
                 'mv-expand|mv-apply|distinct|top|top-nested|order|sort|render|lookup|' +
                 'evaluate|make-series|serialize|invoke|sample|search|find|getschema|scan|partition'
    $looksLikeKql = [regex]::new(
        "(\|\s*(?:$operators)(?![A-Za-z0-9_-]))|(^\s*(?:search|find|print|union|range|datatable|externaldata)(?![A-Za-z0-9_-]))",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $found = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Definition) { return @($found) }

    # Iterative walk: a Logic App definition nests deeply and a recursive
    # helper inside a script function is awkward to keep tail-safe.
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push($Definition)
    $guard = 0
    while ($stack.Count -gt 0 -and $guard -lt 200000) {
        $guard++
        $node = $stack.Pop()
        if ($null -eq $node) { continue }
        if ($node -is [string]) {
            if ($looksLikeKql.IsMatch($node)) { $found.Add($node) }
            continue
        }
        if ($node -is [System.Collections.IDictionary]) {
            # Values only. A key is a name, never a query.
            foreach ($v in $node.Values) { $stack.Push($v) }
            continue
        }
        if ($node -is [System.Collections.IEnumerable]) {
            foreach ($v in $node) { $stack.Push($v) }
            continue
        }
        if ($node -is [psobject] -and $node.PSObject.Properties) {
            foreach ($p in $node.PSObject.Properties) { $stack.Push($p.Value) }
        }
    }
    return @($found)
}

function Get-ParserAliasIndex {
    <#
        One pass over the workspace content, producing:

          Aliases        resolvable parser aliases, ordinal-sorted
          SkippedAliases aliases deliberately not resolved, with the reason
          Nodes          one record per content item, in ARM enumeration order
          References     alias -> ascending node ids that reference it
          ProviderIds    alias -> node ids that DEFINE it
          Warnings       fan-out warnings for suspiciously popular aliases

        Data Collection Rules are deliberately absent. An ingestion-time
        transformKql runs in the pipeline before data reaches the workspace and
        cannot invoke a workspace function, so an alias appearing in one is a
        false positive by construction. DCRs are still scanned for direct table
        references exactly as before.

        Every alias that is NOT resolvable is still indexed, into
        SkippedAliases rather than References. Suppressing a bridge silently is
        the failure this whole feature exists to prevent, so each skipped alias
        carries its reason AND the content that references it, which is exactly
        the list an operator has to follow up by hand.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Content,
        [int]$MinimumAliasLength = 4,
        [AllowNull()][string[]]$WorkspaceTableName,
        [AllowNull()][string[]]$WorkspaceColumnName,
        [int]$FanoutMinimumHits = 20,
        [int]$FanoutMinimumScale = 50,
        [double]$FanoutWarnRatio = 0.30
    )

    # Ordinal throughout. KQL entity names are case-sensitive, so 'MyParser'
    # and 'myparser' are two different functions and neither resolves the
    # other. An OrdinalIgnoreCase vocabulary also collapsed two parsers whose
    # aliases differed only in case and dropped one of them without a record.
    $cmp = [System.StringComparer]::Ordinal

    # 1. Vocabulary - every distinct alias safe to resolve by name.
    $safe      = [System.Collections.Generic.HashSet[string]]::new($cmp)
    $seenSkip  = [System.Collections.Generic.HashSet[string]]::new($cmp)
    $skipInfo  = [System.Collections.Generic.List[object]]::new()
    $verdictOf = [System.Collections.Generic.Dictionary[string, object]]::new($cmp)

    foreach ($parser in @($Content.Parsers)) {
        $rawAlias = $parser.properties.functionAlias
        $verdict  = Get-FunctionAliasSafety -Alias $rawAlias -MinimumLength $MinimumAliasLength `
            -WorkspaceTableName $WorkspaceTableName `
            -WorkspaceColumnName $WorkspaceColumnName
        if ($verdict.Alias) { $verdictOf[$verdict.Alias] = $verdict }
        if ($verdict.IsSafe) {
            [void]$safe.Add($verdict.Alias)
        }
        elseif ($verdict.Alias -and $seenSkip.Add($verdict.Alias)) {
            $skipInfo.Add([PSCustomObject]@{
                Alias  = $verdict.Alias
                Parser = ($parser.properties.displayName ?? $parser.name)
                Reason = $verdict.Reason
            })
        }
    }

    $vocabulary = [string[]]@($safe)
    if ($vocabulary.Count -gt 1) {
        [array]::Sort($vocabulary, [System.StringComparer]::Ordinal)
    }

    # Skipped aliases are counted too, so the report can name the dependents
    # that were NOT resolved because of the skip. They never enter References,
    # so they can never seed or extend a chain.
    $skippedTerms = [string[]]@($skipInfo | ForEach-Object { $_.Alias })
    if ($skippedTerms.Count -gt 1) {
        [array]::Sort($skippedTerms, [System.StringComparer]::Ordinal)
    }

    # One lookup for the counting pass: iterate a node's tokens and test
    # membership, rather than iterating every term against every node.
    $allTerms = [System.Collections.Generic.HashSet[string]]::new($cmp)
    foreach ($term in $vocabulary)   { [void]$allTerms.Add($term) }
    foreach ($term in $skippedTerms) { [void]$allTerms.Add($term) }

    # 2. Nodes - mirrors exactly how Get-TableImpactAnalysis enumerates each
    #    collection, so the direct and indirect views cannot disagree about
    #    what an item is called or which bucket it belongs in.
    $raw = [System.Collections.Generic.List[object]]::new()

    foreach ($rule in @($Content.AlertRules)) {
        $raw.Add([PSCustomObject]@{
            Type = 'AnalyticsRules'; Name = ($rule.properties.displayName ?? $rule.name)
            ResourceId = $rule.id; Alias = $null; Parts = @([string]$rule.properties.query)
            Enabled = $rule.properties.enabled; Severity = $rule.properties.severity
            Category = $null; State = $null
        })
    }
    foreach ($hq in @($Content.HuntingQueries)) {
        $raw.Add([PSCustomObject]@{
            Type = 'HuntingQueries'; Name = ($hq.properties.displayName ?? $hq.name)
            ResourceId = $hq.id; Alias = $hq.properties.functionAlias
            Parts = @([string]$hq.properties.query)
            Enabled = $null; Severity = $null; Category = $hq.properties.category; State = $null
        })
    }
    foreach ($parser in @($Content.Parsers)) {
        $raw.Add([PSCustomObject]@{
            Type = 'Parsers'
            Name = ($parser.properties.functionAlias ?? $parser.properties.displayName ?? $parser.name)
            ResourceId = $parser.id; Alias = $parser.properties.functionAlias
            Parts = @([string]$parser.properties.query)
            Enabled = $null; Severity = $null; Category = $null; State = $null
        })
    }
    foreach ($ss in @($Content.SavedSearches)) {
        if ($ss.properties.category -eq 'Hunting Queries' -or $ss.properties.functionAlias) { continue }
        $raw.Add([PSCustomObject]@{
            Type = 'SavedSearches'; Name = ($ss.properties.displayName ?? $ss.name)
            ResourceId = $ss.id; Alias = $null; Parts = @([string]$ss.properties.query)
            Enabled = $null; Severity = $null; Category = $ss.properties.category; State = $null
        })
    }
    foreach ($wb in @($Content.Workbooks)) {
        $raw.Add([PSCustomObject]@{
            Type = 'Workbooks'; Name = ($wb.properties.displayName ?? $wb.name)
            ResourceId = $wb.id; Alias = $null
            Parts = @(Get-WorkbookQueryText -SerializedData $wb.properties.serializedData)
            Enabled = $null; Severity = $null; Category = $null; State = $null
        })
    }
    foreach ($pb in @($Content.Playbooks)) {
        # Only the strings in the definition that look like KQL, not the whole
        # serialised JSON. Scanning the JSON made an alias appearing as an
        # action name or an object key into a dependency. The direct pass still
        # reads the whole definition; see Get-PlaybookKqlText.
        $raw.Add([PSCustomObject]@{
            Type = 'Playbooks'; Name = $pb.name; ResourceId = $pb.id; Alias = $null
            Parts = @(Get-PlaybookKqlText -Definition $pb.properties.definition)
            Enabled = $null; Severity = $null; Category = $null; State = $pb.properties.state
        })
    }

    # 3. Invert - alias to the node ids that reference it. Postings come out in
    #    ascending id order, which is ARM enumeration order.
    $refs        = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[int]]]::new($cmp)
    $skippedRefs = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[int]]]::new($cmp)
    $providers   = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[int]]]::new($cmp)
    foreach ($term in $vocabulary)   { $refs[$term] = [System.Collections.Generic.List[int]]::new() }
    foreach ($term in $skippedTerms) { $skippedRefs[$term] = [System.Collections.Generic.List[int]]::new() }

    $nodes = [System.Collections.Generic.List[object]]::new()
    for ($id = 0; $id -lt $raw.Count; $id++) {
        $n      = $raw[$id]
        $counts = [System.Collections.Generic.Dictionary[string, int]]::new($cmp)

        foreach ($part in @($n.Parts)) {
            if ([string]::IsNullOrEmpty($part)) { continue }
            # Comments, string literals, cross-cluster qualifiers, assignment
            # targets, member access and let-bound locals are all removed here,
            # so a name mentioned in prose or shadowed by a local never counts.
            $tokens = Get-KqlReferenceIdentifierSet -Text @($part)
            foreach ($token in $tokens) {
                if (-not $allTerms.Contains($token)) { continue }
                if ($counts.ContainsKey($token)) { $counts[$token] = $counts[$token] + 1 }
                else { $counts[$token] = 1 }
            }
        }
        foreach ($term in $counts.Keys) {
            if ($refs.ContainsKey($term))             { $refs[$term].Add($id) }
            elseif ($skippedRefs.ContainsKey($term))  { $skippedRefs[$term].Add($id) }
        }

        $nodeAlias    = $null
        $trimmedAlias = if ($n.Alias) { ([string]$n.Alias).Trim() } else { $null }
        if ($n.Alias) {
            $aliasVerdict = if ($trimmedAlias -and $verdictOf.ContainsKey($trimmedAlias)) {
                $verdictOf[$trimmedAlias]
            } else {
                Get-FunctionAliasSafety -Alias ([string]$n.Alias) -MinimumLength $MinimumAliasLength `
                    -WorkspaceTableName $WorkspaceTableName `
                    -WorkspaceColumnName $WorkspaceColumnName
            }
            if ($aliasVerdict.IsSafe) {
                $nodeAlias = $aliasVerdict.Alias
                if (-not $providers.ContainsKey($nodeAlias)) {
                    $providers[$nodeAlias] = [System.Collections.Generic.HashSet[int]]::new()
                }
                [void]$providers[$nodeAlias].Add($id)
            }
        }

        $nodes.Add([PSCustomObject]@{
            Id = $id; Type = $n.Type; Name = $n.Name; ResourceId = $n.ResourceId
            # Alias is the resolvable alias, or null. RawAlias is what the
            # parser actually declares, so a severed bridge can be named.
            Alias = $nodeAlias; RawAlias = $trimmedAlias
            Enabled = $n.Enabled; Severity = $n.Severity
            Category = $n.Category; State = $n.State; MatchCounts = $counts
        })
    }

    # 3b. Attach the dependents each skipped alias would have produced, so the
    #     console and the HTML can name what an operator has to check by hand.
    $skipped = [System.Collections.Generic.List[object]]::new()
    foreach ($s in $skipInfo) {
        $ids = if ($skippedRefs.ContainsKey($s.Alias)) { $skippedRefs[$s.Alias] } else { @() }
        $dependents = foreach ($id in $ids) {
            $node = $nodes[$id]
            if ($node.RawAlias -and [string]::Equals($node.RawAlias, $s.Alias, [System.StringComparison]::Ordinal)) { continue }
            [PSCustomObject]@{ Type = $node.Type; Name = $node.Name; ResourceId = $node.ResourceId }
        }
        $skipped.Add([PSCustomObject]@{
            Alias          = $s.Alias
            Parser         = $s.Parser
            Reason         = $s.Reason
            ReferenceCount = @($dependents).Count
            Dependents     = @($dependents)
        })
    }

    # 4. Fan-out warnings. An alias referenced by a large share of the whole
    #    workspace is more likely a name collision than a real hub parser, but
    #    suppressing it would hide a real dependency, so say so loudly and
    #    leave the finding in place.
    #
    #    The old test - 5 hits AND over 25% of nodes - was unreachable at real
    #    scale (a 1000-item workspace needed 251 references) and fired on
    #    legitimate parsers in small ones (5 of 18 items is 28%). Both bounds
    #    are now meaningful:
    #      FanoutMinimumHits  20  below this an operator can just read the
    #                             chain list, so a warning is only noise
    #      FanoutMinimumScale 50  floors the denominator, so a handful of items
    #                             in a small workspace cannot produce a big
    #                             ratio
    #      FanoutWarnRatio  0.30  content items include workbooks, playbooks
    #                             and saved searches, so even a heavily shared
    #                             ASIM-style parser rarely reaches a third of
    #                             everything
    $warnings = [System.Collections.Generic.List[string]]::new()
    if ($nodes.Count -gt 0) {
        $scale = [Math]::Max($nodes.Count, $FanoutMinimumScale)
        foreach ($term in $vocabulary) {
            $hitCount = $refs[$term].Count
            if ($hitCount -ge $FanoutMinimumHits -and (($hitCount / $scale) -gt $FanoutWarnRatio)) {
                $pct = [Math]::Round((($hitCount / $nodes.Count) * 100))
                $warnings.Add("Parser alias '$term' is referenced by $hitCount of $($nodes.Count) content items ($pct%) - treat the chains it produces as suspect")
            }
        }
    }

    return [PSCustomObject]@{
        Aliases        = @($vocabulary)
        SkippedAliases = @($skipped)
        Nodes          = @($nodes)
        References     = $refs
        ProviderIds    = $providers
        Warnings       = @($warnings)
    }
}

function Resolve-IndirectTableImpact {
    <#
        Breadth-first walk outward from a classic table along parser aliases.

        Seeds with the aliases of the parsers that read the table directly, so
        the seed set can never disagree with the direct result. Each level
        expands the aliases tainted by the previous one.

        Guards:
          - a node already reported as a DIRECT dependent is never repeated
          - a parser is never an indirect dependent of its own alias, and two
            parsers sharing an alias never depend on each other
          - first visit wins, which also terminates alias cycles (A -> B -> A)
          - MaxDepth bounds the reported chain length; termination does not
            depend on it, so hitting it means a genuinely deep chain exists and
            ChainTruncated is set

        Determinism: alias frontiers are sorted with an ordinal comparer and
        the emitted lists are sorted by (Depth, Name, ResourceId), so the same
        input always produces the same report regardless of ARM ordering.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TableName,
        [Parameter(Mandatory)]$Index,
        [Parameter(Mandatory)]$DirectImpact,
        [int]$MaxDepth = 10
    )

    # Alias identity is ORDINAL: KQL entity names are case-sensitive, so two
    # aliases differing only in case are two different functions. Resource
    # identity stays case-insensitive, because ARM resource ids are.
    $aliasCmp = [System.StringComparer]::Ordinal
    $idCmp    = [System.StringComparer]::OrdinalIgnoreCase
    $types    = @('AnalyticsRules', 'HuntingQueries', 'Parsers', 'SavedSearches', 'Workbooks', 'Playbooks', 'Dcrs')

    $hits       = [System.Collections.Generic.List[object]]::new()
    $truncated  = $false
    $nodes      = @($Index.Nodes)
    $severed    = [System.Collections.Generic.List[object]]::new()
    $seenSever  = [System.Collections.Generic.HashSet[string]]::new($aliasCmp)
    $skipByName = [System.Collections.Generic.Dictionary[string, object]]::new($aliasCmp)
    foreach ($s in @($Index.SkippedAliases)) {
        if ($s.Alias) { $skipByName[[string]$s.Alias] = $s }
    }

    if ($nodes.Count -gt 0) {
        $claimed = [System.Collections.Generic.HashSet[string]]::new($idCmp)
        foreach ($type in $types) {
            foreach ($item in @($DirectImpact.$type)) {
                [void]$claimed.Add("$type|$($item.ResourceId)|$($item.Name)")
            }
        }

        $visited = [System.Collections.Generic.HashSet[int]]::new()
        $seen    = [System.Collections.Generic.HashSet[string]]::new($aliasCmp)
        $chainOf = [System.Collections.Generic.Dictionary[string, object]]::new($aliasCmp)

        # The table name itself counts as already expanded. A parser aliased
        # identically to the table would otherwise be walked as though it were
        # a separate hop, and everything it reaches is already a direct hit.
        [void]$seen.Add($TableName)

        # A local function so a bridge severed at the seed and one severed
        # mid-chain are recorded identically.
        $recordSevered = {
            param([string]$Alias, [string]$ParserName, [string[]]$Chain)
            if (-not $Alias) { return }
            if (-not $seenSever.Add($Alias)) { return }
            $info = if ($skipByName.ContainsKey($Alias)) { $skipByName[$Alias] } else { $null }
            $severed.Add([PSCustomObject]@{
                Alias          = $Alias
                Parser         = $ParserName
                Reason         = if ($info) { $info.Reason } else { 'alias is not in the resolvable set' }
                ReferenceCount = if ($info) { [int]$info.ReferenceCount } else { 0 }
                Dependents     = if ($info) { @($info.Dependents) } else { @() }
                ViaChain       = [string[]]@($Chain)
            })
        }

        $frontier = [System.Collections.Generic.List[string]]::new()
        foreach ($p in @($DirectImpact.Parsers)) {
            if (-not $p.FunctionAlias) { continue }
            $alias = ([string]$p.FunctionAlias).Trim()
            if (-not $Index.References.ContainsKey($alias)) {
                # This parser reads the table directly, and everything that
                # calls it therefore breaks too - but the alias cannot be
                # resolved by name, so those callers are invisible here.
                # Saying nothing would reproduce exactly the silent breakage
                # this resolver exists to surface.
                & $recordSevered $alias ([string]$p.Name) ([string[]]@())
                continue
            }
            if ($seen.Add($alias)) {
                $chainOf[$alias] = [string[]]@($alias)
                $frontier.Add($alias)
            }
        }

        $depth = 0
        while ($frontier.Count -gt 0) {
            if ($depth -ge $MaxDepth) { $truncated = $true; break }
            $depth++

            $terms = [string[]]@($frontier)
            if ($terms.Count -gt 1) { [array]::Sort($terms, [System.StringComparer]::Ordinal) }
            $next = [System.Collections.Generic.List[string]]::new()

            foreach ($term in $terms) {
                # Compare against $null explicitly: a single-element collection
                # holding node id 0 is falsy in PowerShell, which would drop the
                # first item in ARM order.
                $postings = $Index.References[$term]
                if ($null -eq $postings -or $postings.Count -eq 0) { continue }
                $providerIds = $null
                if ($Index.ProviderIds.ContainsKey($term)) { $providerIds = $Index.ProviderIds[$term] }
                $via = [string[]]@($chainOf[$term])

                foreach ($id in $postings) {
                    if ($null -ne $providerIds -and $providerIds.Contains($id)) { continue }
                    $node = $nodes[$id]
                    if ($claimed.Contains("$($node.Type)|$($node.ResourceId)|$($node.Name)")) { continue }
                    if (-not $visited.Add($id)) { continue }

                    $hits.Add([PSCustomObject]@{ Node = $node; Via = $via; Term = $term })

                    if ($node.Alias -and $Index.References.ContainsKey($node.Alias) -and $seen.Add($node.Alias)) {
                        $chainOf[$node.Alias] = [string[]](@($node.Alias) + @($via))
                        $next.Add($node.Alias)
                    }
                    elseif (-not $node.Alias -and $node.RawAlias) {
                        # A parser reached through the chain whose own alias is
                        # not resolvable. The walk stops here, so anything that
                        # calls IT is unreported - name the break.
                        & $recordSevered ([string]$node.RawAlias) ([string]$node.Name) $via
                    }
                }
            }
            $frontier = $next
        }
    }

    $byType = @{}
    foreach ($type in $types) { $byType[$type] = [System.Collections.Generic.List[object]]::new() }

    foreach ($hit in $hits) {
        $node  = $hit.Node
        $chain = [string[]]@($hit.Via)
        $item  = [ordered]@{ Name = $node.Name }
        switch ($node.Type) {
            'AnalyticsRules' { $item['Enabled'] = $node.Enabled; $item['Severity'] = $node.Severity }
            'HuntingQueries' { $item['Category'] = $node.Category }
            'Parsers'        { $item['FunctionAlias'] = $node.Alias }
            'SavedSearches'  { $item['Category'] = $node.Category }
            'Workbooks'      { $item['QueryCount'] = $node.MatchCounts[$hit.Term] }
            'Playbooks'      { $item['State'] = $node.State }
        }
        $item['ResourceId']     = $node.ResourceId
        $item['DependencyKind'] = 'Indirect'
        $item['Via']            = $chain[0]
        $item['ViaChain']       = $chain
        $item['Depth']          = $chain.Count
        $byType[$node.Type].Add([PSCustomObject]$item)
    }

    $ordering = [System.Comparison[object]] {
        param($a, $b)
        $c = [int]$a.Depth - [int]$b.Depth
        if ($c -ne 0) { return $c }
        $c = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$a.Name, [string]$b.Name)
        if ($c -ne 0) { return $c }
        return [System.StringComparer]::Ordinal.Compare([string]$a.ResourceId, [string]$b.ResourceId)
    }

    $result = [ordered]@{}
    $total  = 0
    foreach ($type in $types) {
        $list = [object[]]@($byType[$type])
        if ($list.Count -gt 1) { [array]::Sort($list, $ordering) }
        $result["Indirect$type"] = @($list)
        $total += $list.Count
    }

    $severedList = [object[]]@($severed)
    if ($severedList.Count -gt 1) {
        [array]::Sort($severedList, [System.Comparison[object]] {
            param($a, $b)
            return [System.StringComparer]::Ordinal.Compare([string]$a.Alias, [string]$b.Alias)
        })
    }

    $result['TotalIndirect']     = $total
    $result['ChainTruncated']    = $truncated
    $result['UnresolvedBridges'] = @($severedList)

    return [PSCustomObject]$result
}

# -------------------------------------------------------------------------
# Step 2 - Impact analysis
# -------------------------------------------------------------------------

function Get-TableImpactAnalysis {
    <#
        Direct dependents (the item's own KQL names the table) are found
        exactly as they always were. When an -AliasIndex is supplied, the
        result also carries the items that reach the table only through one or
        more parser functions, in parallel Indirect* lists.

        TotalImpacted keeps its original meaning - direct hits only - so a
        consumer written against the old shape reads the same number. The
        honest blast radius is TotalAffected.
    #>
    param(
        [Parameter(Mandatory)][string]$TableName,
        [Parameter(Mandatory)]$Content,
        [Parameter()]$AliasIndex,
        [int]$MaxDepth = 10
    )

    $result = [ordered]@{
        TableName       = $TableName
        AnalyticsRules  = @()
        HuntingQueries  = @()
        Parsers         = @()
        SavedSearches   = @()
        Workbooks       = @()
        Playbooks       = @()
        Dcrs            = @()
    }

    foreach ($rule in $Content.AlertRules) {
        $query = $rule.properties.query
        if (Test-KqlReferencesTable -Query $query -TableName $TableName) {
            $result.AnalyticsRules += [PSCustomObject]@{
                Name           = ($rule.properties.displayName ?? $rule.name)
                Enabled        = $rule.properties.enabled
                Severity       = $rule.properties.severity
                ResourceId     = $rule.id
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($hq in $Content.HuntingQueries) {
        $query = $hq.properties.query
        if (Test-KqlReferencesTable -Query $query -TableName $TableName) {
            $result.HuntingQueries += [PSCustomObject]@{
                Name           = ($hq.properties.displayName ?? $hq.name)
                Category       = $hq.properties.category
                ResourceId     = $hq.id
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($parser in $Content.Parsers) {
        $query = $parser.properties.query
        if (Test-KqlReferencesTable -Query $query -TableName $TableName) {
            $result.Parsers += [PSCustomObject]@{
                Name           = ($parser.properties.functionAlias ?? $parser.properties.displayName ?? $parser.name)
                FunctionAlias  = $parser.properties.functionAlias
                ResourceId     = $parser.id
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($ss in $Content.SavedSearches) {
        # Exclude items already counted as hunting queries or parsers
        if ($ss.properties.category -eq 'Hunting Queries' -or $ss.properties.functionAlias) { continue }
        $query = $ss.properties.query
        if (Test-KqlReferencesTable -Query $query -TableName $TableName) {
            $result.SavedSearches += [PSCustomObject]@{
                Name           = ($ss.properties.displayName ?? $ss.name)
                Category       = $ss.properties.category
                ResourceId     = $ss.id
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($wb in $Content.Workbooks) {
        $queries = Get-WorkbookQueryText -SerializedData $wb.properties.serializedData
        $hits = $queries | Where-Object { Test-KqlReferencesTable -Query $_ -TableName $TableName }
        if ($hits) {
            $result.Workbooks += [PSCustomObject]@{
                Name           = ($wb.properties.displayName ?? $wb.name)
                QueryCount     = @($hits).Count
                ResourceId     = $wb.id
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($pb in $Content.Playbooks) {
        $defJson = $pb.properties.definition | ConvertTo-Json -Depth 100 -Compress -WarningAction SilentlyContinue
        if ($defJson -and $defJson -match "(?i)(?<![a-zA-Z0-9_])$([regex]::Escape($TableName))(?![a-zA-Z0-9_])") {
            $result.Playbooks += [PSCustomObject]@{
                Name           = $pb.name
                State          = $pb.properties.state
                ResourceId     = $pb.id
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($dcr in $Content.Dcrs) {
        $flows = $dcr.properties.dataFlows
        if (-not $flows) { continue }
        $matchedFlowCount = 0
        foreach ($flow in $flows) {
            if (-not $flow.transformKql -or $flow.transformKql -eq 'source') { continue }
            if (Test-KqlReferencesTable -Query $flow.transformKql -TableName $TableName) { $matchedFlowCount++ }
        }
        if ($matchedFlowCount -gt 0) {
            $result.Dcrs += [PSCustomObject]@{
                Name           = $dcr.name
                FlowCount      = $matchedFlowCount
                ResourceId     = $dcr.id
                DependencyKind = 'Direct'
            }
        }
    }

    $totalImpacted = $result.AnalyticsRules.Count + $result.HuntingQueries.Count +
                     $result.Parsers.Count + $result.SavedSearches.Count +
                     $result.Workbooks.Count + $result.Playbooks.Count + $result.Dcrs.Count

    $final = [ordered]@{
        TableName      = $TableName
        # Direct hits only, unchanged from every previous version of this tool.
        TotalImpacted  = $totalImpacted
        TotalIndirect  = 0
        TotalAffected  = $totalImpacted
        AnalyticsRules = $result.AnalyticsRules
        HuntingQueries = $result.HuntingQueries
        Parsers        = $result.Parsers
        SavedSearches  = $result.SavedSearches
        Workbooks      = $result.Workbooks
        Playbooks      = $result.Playbooks
        Dcrs           = $result.Dcrs
        IndirectAnalyticsRules = @()
        IndirectHuntingQueries = @()
        IndirectParsers        = @()
        IndirectSavedSearches  = @()
        IndirectWorkbooks      = @()
        IndirectPlaybooks      = @()
        IndirectDcrs           = @()
        ChainTruncated         = $false
        # Parsers this table reaches whose own alias could not be resolved, so
        # their callers are NOT in the lists above. Empty is the good case.
        UnresolvedBridges      = @()
    }

    if ($AliasIndex) {
        $indirect = Resolve-IndirectTableImpact -TableName $TableName -Index $AliasIndex `
            -DirectImpact ([PSCustomObject]$result) -MaxDepth $MaxDepth
        foreach ($type in 'AnalyticsRules', 'HuntingQueries', 'Parsers', 'SavedSearches', 'Workbooks', 'Playbooks', 'Dcrs') {
            $final["Indirect$type"] = @($indirect."Indirect$type")
        }
        $final['TotalIndirect']     = $indirect.TotalIndirect
        $final['TotalAffected']     = $totalImpacted + $indirect.TotalIndirect
        $final['ChainTruncated']    = $indirect.ChainTruncated
        $final['UnresolvedBridges'] = @($indirect.UnresolvedBridges)
    }

    [PSCustomObject]$final
}

# -------------------------------------------------------------------------
# Step 3 - Content Hub & CCF classification
# -------------------------------------------------------------------------

function Get-ContentHubPackage {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$WorkspaceName
    )
    $path = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/contentProductPackages"
    Invoke-ArmRequest -Path $path -Query @{ 'api-version' = $script:ApiSentinel }
}

function Get-SolutionMapping {
    if (-not (Test-Path $script:MappingPath)) {
        Write-Warn2 "Solution mapping file not found at $script:MappingPath"
        return $null
    }
    $raw = Get-Content $script:MappingPath -Raw | ConvertFrom-Json -Depth 20 -AsHashtable

    # Build a case-insensitive lookup (matching the TS normalizedLookup pattern)
    $normalized = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $raw.tablesToSolutions.GetEnumerator()) {
        $normalized[$entry.Key] = $entry.Value
    }
    $raw['_normalizedLookup'] = $normalized
    return $raw
}

function Resolve-ConnectorKind {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SolutionName',
        Justification = 'Part of the classifier contract; callers pass solution context for future heuristics.')]
    param([string]$ConnectorId, [string]$SolutionName)

    # Heuristic classification based on connector ID naming conventions observed
    # in the Azure-Sentinel Solutions Analyzer data.
    $id = $ConnectorId
    if (-not $id) { return 'Unknown' }

    # CCF (Codeless Connector Framework) - new framework, identified by specific suffixes
    # or prefixes set by Microsoft. CCP was the older name for the same concept.
    if ($id -match '(CCP|CCF|Definition|_Ccp_|_Ccf_)$' -or
        $id -match '(?i)CCPDefinition') { return 'CCF' }

    # Azure Functions-based connectors - typically have "(Serverless)" suffix,
    # or deploy an Azure Function app (identified by AzureFunction* / Func / Polling suffixes).
    if ($id -match '(?i)(Serverless|AzureFunction|Polling|PollingAuth|Func$|_API_FunctionApp)') {
        return 'AzureFunctions'
    }

    # AMA (Azure Monitor Agent) - modern replacement for MMA, uses DCRs
    if ($id -match '(?i)Ama$') { return 'AMA' }

    # Platform-native connectors (Microsoft services) - usually short IDs matching
    # the service name without suffix (e.g. "AzureActiveDirectory", "Office365")
    if ($id -match '^(Azure|Office|Microsoft|Defender|ThreatIntelligence|WindowsEvent|SecurityEvents)') {
        return 'Platform'
    }

    # CEF / Syslog - agent-based
    if ($id -match '(?i)^(CEF|Syslog|CefAma)$') { return 'Agent' }

    return 'Legacy'
}

function Get-SolutionMatchForTable {
    param(
        [Parameter(Mandatory)][string]$TableName,
        [Parameter()]$StaticMapping,
        [Parameter()]$Packages
    )

    # Index packages by displayName (case-insensitive)
    $pkgByName = @{}
    foreach ($p in $Packages) {
        if ($p.properties -and $p.properties.contentKind -eq 'Solution') {
            $pkgByName[$p.properties.displayName.ToLower()] = $p
        }
    }

    $matchedSolutions = @()

    if ($StaticMapping -and $StaticMapping._normalizedLookup) {
        # Case-insensitive lookup with _CL fallback (matches TS lookupSolutionsForTable)
        $lookup = $StaticMapping._normalizedLookup
        $solutionNames = $lookup[$TableName]
        if (-not $solutionNames) {
            $withoutCL = $TableName -replace '_CL$',''
            $solutionNames = $lookup[$withoutCL]
        }
        if ($solutionNames) {
            foreach ($name in $solutionNames) {
                $pkg = $pkgByName[$name.ToLower()]
                $installed = if ($pkg) { [bool]$pkg.properties.installedVersion } else { $false }
                $meta = $StaticMapping.solutionMetadata[$name]
                $githubUrl = if ($meta) { $meta.githubUrl } else { $null }
                $matchedSolutions += [PSCustomObject]@{
                    SolutionName   = $name
                    IsInstalled    = $installed
                    IsInContentHub = [bool]$pkg
                    GithubUrl      = $githubUrl
                    DisplayName    = if ($pkg) { $pkg.properties.displayName } else { $name }
                }
            }
        }
    }

    [PSCustomObject]@{
        TableName        = $TableName
        MatchCount       = $matchedSolutions.Count
        Solutions        = @($matchedSolutions)
    }
}

function Get-ConnectorClassification {
    param(
        [Parameter(Mandatory)][string]$TableName,
        [Parameter()]$StaticMapping,
        [Parameter()]$Packages
    )

    $result = @()
    if (-not ($StaticMapping -and $StaticMapping._normalizedLookup)) { return $result }

    $lookup = $StaticMapping._normalizedLookup
    $solutionNames = $lookup[$TableName]
    if (-not $solutionNames) {
        $withoutCL = $TableName -replace '_CL$',''
        $solutionNames = $lookup[$withoutCL]
    }
    if (-not $solutionNames) { return $result }

    # Index Content Hub packages to check for DataConnector dependency kinds
    $pkgByName = @{}
    foreach ($p in $Packages) {
        if ($p.properties -and $p.properties.contentKind -eq 'Solution') {
            $pkgByName[$p.properties.displayName.ToLower()] = $p
        }
    }

    foreach ($name in $solutionNames) {
        $pkg = $pkgByName[$name.ToLower()]
        $kind = 'Unknown'
        if ($pkg -and $pkg.properties.dependencies.criteria) {
            # Check if any DataConnector dependency exists in the package
            $connectorIds = @()
            foreach ($c in $pkg.properties.dependencies.criteria) {
                if ($c.kind -eq 'DataConnector' -and $c.contentId) {
                    $connectorIds += $c.contentId
                }
            }
            if ($connectorIds.Count -gt 0) {
                # Use Resolve-ConnectorKind on the first connector ID
                $kind = Resolve-ConnectorKind -ConnectorId $connectorIds[0] -SolutionName $name
            }
        }

        $result += [PSCustomObject]@{
            SolutionName  = $name
            ConnectorKind = $kind
        }
    }
    return $result
}

# -------------------------------------------------------------------------
# Output generators
# -------------------------------------------------------------------------

function Export-ReportCsv {
    param($Tables, $Impacts, $SolutionMatches, [string]$OutDir)

    $Tables | Export-Csv -Path (Join-Path $OutDir 'tables.csv') -NoTypeInformation -Encoding UTF8

    # One row per dependency. The first four columns keep their names AND their
    # positions so a positional consumer still works; the dependency-chain
    # columns are appended. Every row carries every column, because Export-Csv
    # takes its header from the first object it sees.
    $impactFlat = foreach ($i in $Impacts) {
        foreach ($type in 'AnalyticsRules','HuntingQueries','Parsers','SavedSearches','Workbooks','Playbooks','Dcrs') {
            foreach ($item in $i.$type) {
                [PSCustomObject]@{
                    TableName      = $i.TableName
                    ContentType    = $type
                    Name           = $item.Name
                    ResourceId     = $item.ResourceId
                    DependencyKind = 'Direct'
                    Via            = ''
                    ViaChain       = ''
                    Depth          = 0
                    ChainTruncated = [bool]$i.ChainTruncated
                }
            }
            foreach ($item in $i."Indirect$type") {
                [PSCustomObject]@{
                    TableName      = $i.TableName
                    ContentType    = $type
                    Name           = $item.Name
                    ResourceId     = $item.ResourceId
                    DependencyKind = 'Indirect'
                    Via            = $item.Via
                    # The table name is appended here, unlike the JSON chain: a
                    # CSV cell is read out of context and needs to name its own
                    # destination. ASCII arrow, so any spreadsheet import survives.
                    ViaChain       = ((@($item.ViaChain) + $i.TableName) -join ' -> ')
                    Depth          = $item.Depth
                    ChainTruncated = [bool]$i.ChainTruncated
                }
            }
        }
    }
    $impactFlat | Export-Csv -Path (Join-Path $OutDir 'impact.csv') -NoTypeInformation -Encoding UTF8

    $matchFlat = foreach ($m in $SolutionMatches) {
        foreach ($s in $m.Solutions) {
            [PSCustomObject]@{
                TableName      = $m.TableName
                SolutionName   = $s.SolutionName
                IsInstalled    = $s.IsInstalled
                IsInContentHub = $s.IsInContentHub
                GithubUrl      = $s.GithubUrl
            }
        }
    }
    $matchFlat | Export-Csv -Path (Join-Path $OutDir 'solution-matches.csv') -NoTypeInformation -Encoding UTF8
}

function Export-ReportJson {
    <#
        Additive only. Every key that existed before still exists and still
        means the same thing - in particular impactAnalysis[].TotalImpacted is
        still the DIRECT count, and the seven per-type arrays still hold only
        direct hits. Indirect dependents live in the parallel Indirect* arrays,
        and TotalAffected is the sum of both.
    #>
    param($Tables, $Impacts, $SolutionMatches, $Context, [string]$OutDir, $AliasResolution)
    $combined = [ordered]@{
        generatedAt       = (Get-Date).ToString('o')
        subscription      = $Context.SubscriptionId
        resourceGroup     = $Context.ResourceGroupName
        workspace         = $Context.WorkspaceName
        classicTables     = $Tables
        impactAnalysis    = $Impacts
        solutionMatches   = $SolutionMatches
    }
    if ($AliasResolution) { $combined['parserAliasResolution'] = $AliasResolution }
    $combined | ConvertTo-Json -Depth 20 | Out-File -FilePath (Join-Path $OutDir 'report.json') -Encoding utf8
}

function ConvertTo-JsStringLiteral {
    <#
        Escapes text for embedding inside a double-quoted JavaScript string
        literal, without System.Web. [System.Web.HttpUtility] is not loaded on
        PowerShell 7, so calling it here would throw rather than fall back.

        ConvertTo-Json on a plain string returns that string already escaped
        and wrapped in quotes, which handles backslash, double quote and the
        control characters. Trim the wrapping quotes, then escape the few
        remaining characters that are legal in JSON but would break out of a
        <script> element or terminate a JS line.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $quoted  = $Value | ConvertTo-Json
    $literal = $quoted.Substring(1, $quoted.Length - 2)

    # '</script>' would close the element early; U+2028/U+2029 are line
    # terminators in JavaScript. Escape them as \uXXXX, built from char codes
    # so the sequences survive any encoding round-trip.
    $u = [char]0x5C  # backslash
    $literal = $literal.Replace('<', "${u}u003c").Replace('>', "${u}u003e")
    $literal = $literal.Replace([string][char]0x2028, "${u}u2028")
    $literal = $literal.Replace([string][char]0x2029, "${u}u2029")

    return $literal
}

function Export-ReportHtml {
    <#
        AliasResolution carries the resolver's own limits into the report:
        which parser aliases were not resolved and why, and any fan-out
        warnings. Those used to reach the console only, which meant an
        operator reading report.html - the artefact that actually gets shared -
        saw a dependency list with no indication of where it stops.
    #>
    param($Tables, $Impacts, $SolutionMatches, $Context, [string]$OutDir, $AliasResolution)

    $templatePath = Join-Path $PSScriptRoot 'Templates' 'report.html.template'
    if (-not (Test-Path $templatePath)) {
        Write-Warn2 "HTML template missing at $templatePath - skipping HTML report"
        return
    }
    $template = Get-Content $templatePath -Raw

    $data = [ordered]@{
        GeneratedAt     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Subscription    = $Context.SubscriptionId
        ResourceGroup   = $Context.ResourceGroupName
        Workspace       = $Context.WorkspaceName
        TotalTables     = $Tables.Count
        TotalImpacted   = ($Impacts | Measure-Object -Property TotalImpacted -Sum).Sum
        TotalIndirect   = ($Impacts | Measure-Object -Property TotalIndirect -Sum).Sum
        Tables          = $Tables
        Impacts         = $Impacts
        SolutionMatches = $SolutionMatches
        AliasResolution = $AliasResolution
    }

    $dataJson = ($data | ConvertTo-Json -Depth 20 -Compress)
    $html     = $template.Replace('{{DATA_JSON}}', (ConvertTo-JsStringLiteral -Value $dataJson))

    $outFile = Join-Path $OutDir 'report.html'
    $html | Out-File -FilePath $outFile -Encoding utf8
    Write-Ok "HTML report: $outFile"
}

# -------------------------------------------------------------------------
# Main flow
# -------------------------------------------------------------------------

try {
    Write-Console ''
    Write-Console '┌────────────────────────────────────────────────────────────────────────┐' Cyan
    Write-Console '│           Sentinel Table Migration Review (PowerShell Edition)         │' Cyan
    Write-Console '└────────────────────────────────────────────────────────────────────────┘' Cyan

    # Auth + inputs
    Write-Step 'Authentication'
    $SubscriptionId    = Read-Required -Prompt 'Subscription ID' -Current $SubscriptionId
    $null = Initialize-AzContext -SubscriptionId $SubscriptionId
    $ResourceGroupName = Read-Required -Prompt 'Resource group' -Current $ResourceGroupName
    $WorkspaceName     = Read-Required -Prompt 'Workspace name' -Current $WorkspaceName

    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }
    Write-Ok "Output directory: $OutputPath"

    $contextInfo = [PSCustomObject]@{
        SubscriptionId    = $SubscriptionId
        ResourceGroupName = $ResourceGroupName
        WorkspaceName     = $WorkspaceName
    }

    # Step 1 - Discover
    Write-Step 'Step 1: Discover classic custom log tables (CLv1)'
    # One call, two answers: the migration candidates, and every table name in
    # the workspace. The second feeds the collision guard that stops a parser
    # aliased over a real table (Update, SecurityEvent) from dragging every
    # query against that table into the chained results.
    $tableInventory = Get-WorkspaceTableInventory `
        -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName `
        -WorkspaceName $WorkspaceName
    $classicTables      = @($tableInventory.ClassicTables)
    $workspaceTableName  = @($tableInventory.AllTableNames)
    $workspaceColumnName = @($tableInventory.AllColumnNames)

    Write-Ok "Found $($classicTables.Count) classic custom log tables"
    if ($classicTables.Count -eq 0) {
        Write-Info 'Nothing to migrate - workspace has no classic V1 tables.'
        return
    }
    Write-Console ($classicTables | Select-Object Name, Plan, RetentionInDays, ColumnCount | Format-Table | Out-String)

    # Step 2 - Impact
    Write-Step 'Step 2: Assess dependency impact'
    $content = Get-WorkspaceContent `
        -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName `
        -WorkspaceName $WorkspaceName

    Write-Info "Scanning $($classicTables.Count) tables against:"
    Write-Info "  Analytics Rules : $($content.AlertRules.Count)"
    Write-Info "  Hunting Queries : $($content.HuntingQueries.Count)"
    Write-Info "  Parsers         : $($content.Parsers.Count)"
    Write-Info "  Saved Searches  : $($content.SavedSearches.Count)"
    Write-Info "  Workbooks       : $($content.Workbooks.Count)"
    Write-Info "  Playbooks       : $($content.Playbooks.Count)"
    Write-Info "  DCRs            : $($content.Dcrs.Count)"

    Write-Info 'Indexing parser function aliases for chained dependencies...'
    $aliasIndex = Get-ParserAliasIndex -Content $content -WorkspaceTableName $workspaceTableName -WorkspaceColumnName $workspaceColumnName
    Write-Info "  Workspace tables known    : $($workspaceTableName.Count)"
    Write-Info "  Parser aliases resolvable : $($aliasIndex.Aliases.Count)"
    if ($aliasIndex.SkippedAliases.Count -gt 0) {
        Write-Warn2 "$($aliasIndex.SkippedAliases.Count) parser alias(es) are not resolved through chains, to avoid false positives:"
        foreach ($s in $aliasIndex.SkippedAliases) {
            # Naming the reference count matters: a skip with dependents is a
            # chain that stops here, and those dependents need checking by hand.
            $tail = if ($s.ReferenceCount -gt 0) { " (referenced by $($s.ReferenceCount) item(s), not resolved)" } else { '' }
            Write-Console "    • $($s.Alias) - $($s.Reason)$tail" Yellow
        }
    }
    foreach ($w in $aliasIndex.Warnings) { Write-Warn2 $w }

    $impacts = @()
    $i = 0
    foreach ($t in $classicTables) {
        $i++
        Write-Progress -Activity 'Impact analysis' -Status $t.Name -PercentComplete (($i / $classicTables.Count) * 100)
        $impacts += Get-TableImpactAnalysis -TableName $t.Name -Content $content `
            -AliasIndex $aliasIndex -MaxDepth $MaxParserChainDepth
    }
    Write-Progress -Activity 'Impact analysis' -Completed

    $directTotal    = [int](($impacts | Measure-Object -Property TotalImpacted -Sum).Sum)
    $indirectTotal  = [int](($impacts | Measure-Object -Property TotalIndirect -Sum).Sum)
    $affectedTables = @($impacts | Where-Object { ($_.TotalImpacted + $_.TotalIndirect) -gt 0 }).Count

    Write-Ok ("Scan complete - $($directTotal + $indirectTotal) dependent items across " +
              "$affectedTables of $($classicTables.Count) tables ($directTotal direct, $indirectTotal via parsers)")

    if ($indirectTotal -gt 0) {
        $bridges = @($impacts | ForEach-Object {
            foreach ($type in 'AnalyticsRules','HuntingQueries','Parsers','SavedSearches','Workbooks','Playbooks','Dcrs') {
                foreach ($item in $_."Indirect$type") { $item.Via }
            }
        } | Sort-Object -Unique)
        Write-Warn2 ("$indirectTotal item(s) reach a classic table only through a parser function " +
                     "($($bridges.Count) parser(s) act as the bridge). They never name the table, and they break on migration.")

        # Searching the workspace for the table name surfaces the parser and
        # stops there. These are the tables where that search under-reports.
        $chained = @($impacts | Where-Object { $_.TotalIndirect -gt 0 })
        Write-Warn2 "$($chained.Count) table(s) have dependents that a search for the table name would not find:"
        foreach ($c in $chained) {
            Write-Console "    • $($c.TableName) - $($c.TotalImpacted) direct, $($c.TotalIndirect) via parser" Yellow
        }
    }

    $truncated = @($impacts | Where-Object { $_.ChainTruncated })
    if ($truncated.Count -gt 0) {
        Write-Warn2 ("Dependency chains for $($truncated.Count) table(s) are deeper than $MaxParserChainDepth parser hops - " +
                     'anything past that depth is not listed. Re-run with a higher -MaxParserChainDepth.')
    }

    # A parser that reads a classic table but whose alias cannot be resolved is
    # a chain that stops dead. Anything calling that parser breaks on migration
    # and appears nowhere in the lists above, so it is called out by name.
    $bridged = @($impacts | Where-Object { @($_.UnresolvedBridges).Count -gt 0 })
    if ($bridged.Count -gt 0) {
        Write-Warn2 ("$($bridged.Count) table(s) reach a parser whose alias could not be resolved. " +
                     'Content calling those parsers is NOT listed and needs checking by hand:')
        foreach ($b in $bridged) {
            foreach ($u in @($b.UnresolvedBridges)) {
                Write-Console "    • $($b.TableName) -> parser '$($u.Parser)' (alias '$($u.Alias)') - $($u.Reason)" Yellow
                if ($u.ReferenceCount -gt 0) {
                    Write-Console "        $($u.ReferenceCount) item(s) name that alias and were not resolved:" Yellow
                    foreach ($d in @($u.Dependents)) {
                        Write-Console "          - [$($d.Type)] $($d.Name)" Yellow
                    }
                }
            }
        }
    }

    # Step 3 - Content Hub + CCF
    Write-Step 'Step 3: Map to Content Hub solutions (with CCF classification)'
    Write-Info 'Loading Content Hub package catalog...'
    try {
        $packages = Get-ContentHubPackage `
            -SubscriptionId $SubscriptionId `
            -ResourceGroupName $ResourceGroupName `
            -WorkspaceName $WorkspaceName
        Write-Ok "Loaded $($packages.Count) Content Hub packages"
    } catch {
        Write-Warn2 "Content Hub query failed: $($_.Exception.Message)"
        $packages = @()
    }

    Write-Info 'Loading static solution mapping (Azure-Sentinel Solutions Analyzer)...'
    $mapping = Get-SolutionMapping
    if ($mapping) { Write-Ok "Mapping loaded - $($mapping.tableCount) tables / $($mapping.solutionCount) solutions" }

    $solutionMatches = foreach ($t in $classicTables) {
        $match = Get-SolutionMatchForTable -TableName $t.Name -StaticMapping $mapping -Packages $packages
        $match | Add-Member -NotePropertyName ConnectorClassification `
                            -NotePropertyValue @(Get-ConnectorClassification -TableName $t.Name -StaticMapping $mapping -Packages $packages) -PassThru
    }

    $unmatched = @($solutionMatches | Where-Object { $_.MatchCount -eq 0 })
    Write-Ok "Matched $($solutionMatches.Count - $unmatched.Count) of $($solutionMatches.Count) tables"
    if ($unmatched.Count -gt 0) {
        Write-Warn2 "$($unmatched.Count) tables have no Content Hub match - consider raising a feature request with your CSAM/SSP:"
        foreach ($u in $unmatched) { Write-Console "    • $($u.TableName)" Yellow }
    }

    # Export
    Write-Step 'Export reports'
    Export-ReportCsv  -Tables $classicTables -Impacts $impacts -SolutionMatches $solutionMatches -OutDir $OutputPath
    Write-Ok "CSV files written to $OutputPath"

    $aliasResolution = [ordered]@{
        resolvedAliases = @($aliasIndex.Aliases)
        skippedAliases  = @($aliasIndex.SkippedAliases)
        warnings        = @($aliasIndex.Warnings)
    }
    Export-ReportJson -Tables $classicTables -Impacts $impacts -SolutionMatches $solutionMatches `
        -Context $contextInfo -OutDir $OutputPath -AliasResolution $aliasResolution
    Write-Ok "JSON report: $(Join-Path $OutputPath 'report.json')"

    Export-ReportHtml -Tables $classicTables -Impacts $impacts -SolutionMatches $solutionMatches `
        -Context $contextInfo -OutDir $OutputPath -AliasResolution $aliasResolution

    Write-Console ''
    Write-Console '┌────────────────────────────────────────────────────────────────────────┐' Green
    Write-Console '│                            Review complete                             │' Green
    Write-Console '└────────────────────────────────────────────────────────────────────────┘' Green
    Write-Console ''

    # Return to pipeline
    [PSCustomObject]@{
        Context         = $contextInfo
        ClassicTables   = $classicTables
        Impacts         = $impacts
        SolutionMatches = $solutionMatches
        OutputPath      = $OutputPath
    }
}
catch {
    Write-Err $_.Exception.Message
    Write-Console $_.ScriptStackTrace DarkGray
    exit 1
}
