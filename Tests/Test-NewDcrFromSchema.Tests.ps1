#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for the helper functions in
    Tools/DcrFromSchema/New-DcrFromSchema.ps1.

.DESCRIPTION
    The script's correctness rests on validation that has to match the Azure
    Monitor documentation exactly, and on sanitising that has to repair pasted
    input without corrupting it. Both are pure functions, so both are covered
    here:

      Import-TableSpec            The three accepted schema shapes, and the
                                  refusal when handed a data sample.
      Remove-JsonNoise            Paste repair that respects string state.
      ConvertTo-SafeText          Free text cleaned before it reaches ARM.
      ConvertTo-StraightPunctuation  Typographic to ASCII substitution.
      Get-ColumnIssue             The documented column rules.
      Test-TableName              The documented table name rules.
      Resolve-TableSchema         Duplicate and case handling, TimeGenerated.
      Repair-TableSchema          What is safe to fix without guessing.
      ConvertTo-StreamColumn      Table types to stream types, guid included.
      Get-DefaultTransform        The casts that avoid InvalidTransformOutput.
      Test-TransformKql           Transform repair and the length limit.
      Compare-TableSchema         Diff against a table that already exists.
      Build-TableArmTemplate      The emitted table template shape.
      Build-DcrArmTemplate        The emitted DCR template shape.

    Deliberately not covered: the Azure reads, the deployments and the role
    assignment. Those need a live workspace, so the script gates them behind
    ShouldProcess and they are exercised by running the tool, not by Pester.
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Tools/DcrFromSchema/New-DcrFromSchema.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop

    # Script-scoped constants the extracted functions reference. The AST
    # extractor deliberately skips top-level statements, so the caller
    # restates them (documented pattern in Import-ScriptFunctions.psm1).
    # These are the values under test as much as the code is: they encode the
    # documented Azure Monitor limits, so a drift between this block and the
    # script's own constants block is itself a finding.
    # 2025-07-01: the Auxiliary plan does not exist at 2023-09-01, so an
    # Auxiliary table cannot be authored against the older version.
    $script:TablesApiVersion    = '2025-07-01'
    $script:DcrApiVersion       = '2023-03-11'
    $script:MinColumnNameLength = 2
    $script:MaxColumnNameLength = 45
    $script:MinTableNameLength  = 4
    $script:MaxTableNameLength  = 63
    $script:MaxColumnCount      = 500
    $script:MaxTransformLength  = 15360

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

    $script:TableColumnTypes = @('boolean', 'dateTime', 'dynamic', 'guid', 'int', 'long', 'real', 'string')
    $script:DataTypeHints    = @('armPath', 'guid', 'ip', 'uri')

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

    $script:ClassicTypeSuffixes = @('_s', '_d', '_b', '_g', '_t')

    # Every prompt helper short-circuits on this, so the extracted functions
    # never block waiting for input.
    $script:Interactive = $false

    Import-ScriptFunctions -Path $scriptPath

    # Written per-test into the Pester temp drive rather than the repo.
    $script:workPath = Join-Path ([System.IO.Path]::GetTempPath()) "dcrschema-$([guid]::NewGuid().Guid)"
    New-Item -Path $script:workPath -ItemType Directory -Force | Out-Null

    function New-SpecFile {
        param([Parameter(Mandatory)] $Object)

        $path = Join-Path $script:workPath "$([guid]::NewGuid().Guid).json"
        $Object | ConvertTo-Json -Depth 20 | Set-Content -Path $path -Encoding utf8NoBOM
        return $path
    }

    function New-RawSpecFile {
        param([Parameter(Mandatory)] [string] $Text)

        $path = Join-Path $script:workPath "$([guid]::NewGuid().Guid).json"
        Set-Content -Path $path -Value $Text -Encoding utf8NoBOM
        return $path
    }

    # PSCustomObject, not a hashtable. Every real caller feeds these functions
    # the output of ConvertFrom-Json or an ARM response, both of which are
    # PSCustomObjects, and the functions read fields through
    # PSObject.Properties. A hashtable exposes Keys and Values there rather
    # than its entries, so a hashtable fixture would silently present every
    # column as nameless and test nothing.
    function New-Column {
        param([string] $Name, [string] $Type, [string] $Hint = '')

        $column = [ordered] @{ name = $Name; type = $Type }
        if ($Hint) { $column['dataTypeHint'] = $Hint }
        return [pscustomobject] $column
    }

    function New-LiveColumn {
        param([string] $Name, [string] $Type)

        return [pscustomobject] @{ name = $Name; type = $Type }
    }
}

AfterAll {
    if ($script:workPath -and (Test-Path $script:workPath)) {
        Remove-Item -Path $script:workPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'New-DcrFromSchema: script-level contract' {
    BeforeAll {
        $script:sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/DcrFromSchema/New-DcrFromSchema.ps1'
        $script:sourceText = Get-Content -Path $script:sourcePath -Raw
    }

    It 'parses cleanly' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:sourcePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'gates writes and deployments behind ShouldProcess' {
        $script:sourceText | Should -Match 'SupportsShouldProcess'
    }

    It 'authors the DCR at an API version that carries the endpoints property' {
        # Anything earlier than 2023-03-11 has no 'endpoints' property, so a
        # Direct DCR would deploy without its own logsIngestion endpoint and
        # one cannot be added afterwards.
        $script:sourceText | Should -Match "DcrApiVersion\s*=\s*'2023-03-11'"
    }

    It 'authors the DCR as kind Direct' {
        $script:sourceText | Should -Match "kind\s*=\s*'Direct'"
    }

    It 'authors the table at an API version that knows the Auxiliary plan' {
        # At 2023-09-01 the Tables API documents plan as only 'Analytics' or
        # 'Basic'. Authoring an Auxiliary table against that version fails, so
        # the Auxiliary example would have been undeployable.
        $script:sourceText | Should -Match "TablesApiVersion\s*=\s*'2025-07-01'"
    }

    It 'exposes the switches that make an unattended run possible' {
        $params = (Get-Command $script:sourcePath).Parameters
        $params.Keys | Should -Contain 'NonInteractive'
        $params.Keys | Should -Contain 'Deploy'
        $params.Keys | Should -Contain 'Force'
        $params.Keys | Should -Contain 'SkipTable'
        $params.Keys | Should -Contain 'IncludeDataTypeHint'
    }

    It 'is pure ASCII, so it needs no byte order mark to stay readable' {
        # The sanitiser deals in curly quotes and no-break spaces. Writing them
        # literally would make this file non-ASCII and put an invisible
        # character in a replacement expression, where it cannot be reviewed
        # and is trivially lost to a later edit.
        $offenders = @($script:sourceText.ToCharArray() | Where-Object { [int]$_ -gt 127 })
        $offenders | Should -BeNullOrEmpty
    }

    It 'accepts -1 for retention, which is the documented "use the default"' {
        $script:sourceText | Should -Match '\$_ -eq -1 -or \(\$_ -ge 4 -and \$_ -le 730\)'
        $script:sourceText | Should -Match '\$_ -eq -1 -or \(\$_ -ge 4 -and \$_ -le 4383\)'
    }
}

Describe 'Read-Value: prompt contract' {
    It 'tells the operator that Enter accepts the default' {
        # A free-text prompt showing only "[rg-sentinel]", sitting between
        # two [y/N] questions, was answered 'y' and produced a resource group
        # literally named 'y'. The hint is the guard against that reading.
        $source = Get-Content -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/DcrFromSchema/New-DcrFromSchema.ps1') -Raw
        $source | Should -Match '\(Enter to accept\)'
    }

    It 'returns the default unattended rather than prompting' {
        Read-Value -Prompt 'anything' -Default 'the-default' | Should -Be 'the-default'
    }

    It 'returns empty unattended when empty is allowed and there is no default' {
        Read-Value -Prompt 'anything' -AllowEmpty | Should -Be ''
    }

    It 'refuses unattended when a value is required and no default exists' {
        { Read-Value -Prompt 'DCR resource group name' } |
            Should -Throw '*required in non-interactive mode*'
    }
}

Describe 'Import-TableSpec' {
    It 'reads the documented shape' {
        $path = New-SpecFile -Object @{
            tableName = 'MyApp_CL'
            columns   = @((New-Column -Name 'TimeGenerated' -Type 'datetime'))
        }

        $spec = Import-TableSpec -Path $path
        $spec.TableName | Should -Be 'MyApp_CL'
        @($spec.Columns).Count | Should -Be 1
    }

    It 'reads the Tables API resource shape, so an exported table can be fed back in' {
        $path = New-SpecFile -Object @{
            properties = @{
                schema = @{
                    name    = 'Exported_CL'
                    columns = @(
                        (New-Column -Name 'TimeGenerated' -Type 'dateTime')
                        (New-Column -Name 'Message' -Type 'string')
                    )
                }
                plan                 = 'Basic'
                totalRetentionInDays = 365
            }
        }

        $spec = Import-TableSpec -Path $path
        $spec.TableName | Should -Be 'Exported_CL'
        @($spec.Columns).Count | Should -Be 2
        Get-SpecDefault -Extra $spec.Extra -Key 'plan' | Should -Be 'Basic'
        Get-SpecDefault -Extra $spec.Extra -Key 'totalRetentionInDays' | Should -Be 365
    }

    It 'reads a bare column array and leaves the table name to the caller' {
        $path = New-RawSpecFile -Text '[ { "name": "TimeGenerated", "type": "datetime" }, { "name": "Message", "type": "string" } ]'

        $spec = Import-TableSpec -Path $path
        $spec.TableName | Should -BeNullOrEmpty
        @($spec.Columns).Count | Should -Be 2
    }

    It 'reads a bare array holding exactly one column' {
        # ConvertFrom-Json unrolls a single-element array, so this arrives as a
        # lone object. Its 'name' must not be mistaken for the table name.
        $path = New-RawSpecFile -Text '[ { "name": "TimeGenerated", "type": "datetime" } ]'

        $spec = Import-TableSpec -Path $path
        $spec.TableName | Should -BeNullOrEmpty
        @($spec.Columns).Count | Should -Be 1
        @($spec.Columns)[0].name | Should -Be 'TimeGenerated'
    }

    It 'surfaces the optional keys it uses as defaults' {
        $path = New-SpecFile -Object @{
            tableName    = 'MyApp_CL'
            description  = 'a description'
            dcrName      = 'dcr-custom'
            location     = 'uksouth'
            transformKql = 'source | take 1'
            columns      = @((New-Column -Name 'TimeGenerated' -Type 'datetime'))
        }

        $spec = Import-TableSpec -Path $path
        Get-SpecDefault -Extra $spec.Extra -Key 'description'  | Should -Be 'a description'
        Get-SpecDefault -Extra $spec.Extra -Key 'dcrName'      | Should -Be 'dcr-custom'
        Get-SpecDefault -Extra $spec.Extra -Key 'location'     | Should -Be 'uksouth'
        Get-SpecDefault -Extra $spec.Extra -Key 'transformKql' | Should -Be 'source | take 1'
    }

    It 'returns $null for an absent optional key rather than throwing' {
        $path = New-SpecFile -Object @{
            tableName = 'MyApp_CL'
            columns   = @((New-Column -Name 'TimeGenerated' -Type 'datetime'))
        }

        $spec = Import-TableSpec -Path $path
        Get-SpecDefault -Extra $spec.Extra -Key 'plan' | Should -BeNullOrEmpty
    }

    It 'says a data sample is not a schema, rather than reporting a missing property' {
        # The single most likely wrong input: someone hands it the JSON they
        # want to ingest. A "no columns" error would send them hunting.
        $path = New-RawSpecFile -Text '[ { "AlertID": "abc", "Severity": 3 } ]'

        { Import-TableSpec -Path $path } | Should -Throw '*takes a schema, not a sample of the data*'
    }

    It 'refuses an empty column list' {
        $path = New-SpecFile -Object @{ tableName = 'MyApp_CL'; columns = @() }
        { Import-TableSpec -Path $path } | Should -Throw '*empty column list*'
    }

    It 'refuses a missing file' {
        { Import-TableSpec -Path (Join-Path $script:workPath 'nope.json') } |
            Should -Throw '*Schema file not found*'
    }

    It 'refuses an empty file' {
        $path = New-RawSpecFile -Text '   '
        { Import-TableSpec -Path $path } | Should -Throw '*Schema file is empty*'
    }

    It 'refuses JSON that is broken beyond the repairs it knows' {
        $path = New-RawSpecFile -Text '{ "tableName": '
        { Import-TableSpec -Path $path } | Should -Throw '*not valid JSON*'
    }
}

Describe 'Import-TableSpec: paste repair' {
    It 'parses a file carrying comments and a trailing comma' {
        $path = New-RawSpecFile -Text @'
{
  // pasted from the wiki
  "tableName": "Messy_CL",
  /* and a block comment */
  "columns": [
    { "name": "TimeGenerated", "type": "datetime" },
    { "name": "Message", "type": "string" },
  ]
}
'@

        $spec = Import-TableSpec -Path $path -WarningAction SilentlyContinue
        $spec.TableName | Should -Be 'Messy_CL'
        @($spec.Columns).Count | Should -Be 2
    }

    It 'parses a file whose quotes were curled by a word processor' {
        $straight = '{ "tableName": "Curly_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'

        # Curl every quote the way a word processor does, alternating open and
        # close, so both code points are exercised.
        $isOpening = $true
        $curled    = -join @($straight.ToCharArray() | ForEach-Object {
            if ($_ -ne '"') { return $_ }
            $replacement = if ($isOpening) { [char]0x201C } else { [char]0x201D }
            $isOpening   = -not $isOpening
            $replacement
        })

        $path = New-RawSpecFile -Text $curled
        $spec = Import-TableSpec -Path $path -WarningAction SilentlyContinue
        $spec.TableName | Should -Be 'Curly_CL'
    }

    It 'strips a byte order mark' {
        $path = New-RawSpecFile -Text ([char]0xFEFF + '{ "tableName": "Bom_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }')

        $spec = Import-TableSpec -Path $path -WarningAction SilentlyContinue
        $spec.TableName | Should -Be 'Bom_CL'
    }

    It "does not need the repair path for comments, because PowerShell's parser tolerates them" {
        # Documents why the comment and trailing-comma branches rarely fire on
        # their own: ConvertFrom-Json accepts both, so the first parse
        # succeeds and nothing is rewritten or warned about.
        $path = New-RawSpecFile -Text @'
{
  // a comment
  "tableName": "Tolerated_CL",
  "columns": [ { "name": "TimeGenerated", "type": "datetime" }, ]
}
'@

        $warnings = @(Import-TableSpec -Path $path 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

        $warnings | Should -BeNullOrEmpty
    }

    It 'warns rather than repairing silently' {
        # Curly quotes are the artefact PowerShell genuinely rejects, so this
        # is the input that actually reaches the repair path.
        $isOpening = $true
        $curled    = -join @('{ "tableName": "Warned_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'.ToCharArray() | ForEach-Object {
            if ($_ -ne '"') { return $_ }
            $replacement = if ($isOpening) { [char]0x201C } else { [char]0x201D }
            $isOpening   = -not $isOpening
            $replacement
        })

        $path = New-RawSpecFile -Text $curled

        # Captured off stream 3 rather than with -WarningVariable, which does
        # not reliably collect a warning raised by a nested helper.
        $warnings = @(Import-TableSpec -Path $path 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

        ($warnings.Message -join ' ') | Should -Match 'needed cleaning up'
    }

    It 'leaves valid JSON completely untouched' {
        # The repairs are only ever reached after a failed parse, so a valid
        # file cannot be altered by them.
        $path = New-SpecFile -Object @{
            tableName = 'Clean_CL'
            columns   = @(@{ name = 'Url'; type = 'string'; description = 'see http://example/x, ] and more' })
        }

        $output   = @(Import-TableSpec -Path $path 3>&1)
        $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $spec     = @($output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]

        $warnings | Should -BeNullOrEmpty
        @($spec.Columns)[0].description | Should -Be 'see http://example/x, ] and more'
    }
}

Describe 'Remove-JsonNoise' {
    It 'does not treat a // inside a string as a comment' {
        # The case that makes a naive strip destructive: the rest of the line,
        # including the closing quote and brace, would be eaten.
        $result = Remove-JsonNoise -Text '{ "url": "http://example/x" }'
        $result.Text | Should -Be '{ "url": "http://example/x" }'
        $result.Applied | Should -Not -Contain 'JSON comments'
    }

    It 'does not treat a comma before a bracket inside a string as trailing' {
        $result = Remove-JsonNoise -Text '{ "note": "a, ] b" }'
        $result.Text | Should -Be '{ "note": "a, ] b" }'
        $result.Applied | Should -Not -Contain 'trailing commas'
    }

    It 'respects an escaped quote when tracking string state' {
        $text   = '{ "note": "he said \"hi\" // not a comment" }'
        $result = Remove-JsonNoise -Text $text
        $result.Text | Should -Be $text
    }

    It 'removes a line comment' {
        $result = Remove-JsonNoise -Text "{ // hello`n `"a`": 1 }"
        $result.Applied | Should -Contain 'JSON comments'
        $result.Text | Should -Not -Match 'hello'
        ($result.Text | ConvertFrom-Json).a | Should -Be 1
    }

    It 'removes a block comment' {
        $result = Remove-JsonNoise -Text '{ /* hello */ "a": 1 }'
        $result.Applied | Should -Contain 'JSON comments'
        ($result.Text | ConvertFrom-Json).a | Should -Be 1
    }

    It 'removes a trailing comma before a brace and before a bracket' {
        $result = Remove-JsonNoise -Text '{ "a": [ 1, 2, ], }'
        $result.Applied | Should -Contain 'trailing commas'
        @(($result.Text | ConvertFrom-Json).a).Count | Should -Be 2
    }

    It 'keeps a legitimate separating comma' {
        $result = Remove-JsonNoise -Text '{ "a": 1, "b": 2 }'
        $result.Applied | Should -Not -Contain 'trailing commas'
        ($result.Text | ConvertFrom-Json).b | Should -Be 2
    }

    It 'reports nothing applied for text that needed no repair' {
        $result = Remove-JsonNoise -Text '{ "a": 1 }'
        @($result.Applied).Count | Should -Be 0
    }
}

Describe 'ConvertTo-StraightPunctuation' {
    It 'substitutes curly double quotes' {
        ConvertTo-StraightPunctuation -Text ([char]0x201C + 'x' + [char]0x201D) | Should -Be '"x"'
    }

    It 'substitutes curly single quotes' {
        ConvertTo-StraightPunctuation -Text ([char]0x2018 + 'x' + [char]0x2019) | Should -Be "'x'"
    }

    It 'substitutes a no-break space' {
        ConvertTo-StraightPunctuation -Text ('a' + [char]0x00A0 + 'b') | Should -Be 'a b'
    }

    It 'leaves ASCII alone' {
        ConvertTo-StraightPunctuation -Text 'a "b" c' | Should -Be 'a "b" c'
    }
}

Describe 'ConvertTo-SafeText' {
    It 'collapses an embedded newline, which ARM would otherwise deploy' {
        ConvertTo-SafeText -Text "line one`nline two" | Should -Be 'line one line two'
    }

    It 'removes a zero-width joiner picked up from a wiki' {
        ConvertTo-SafeText -Text ('a' + [char]0x200D + 'b') | Should -Be 'a b'
    }

    It 'collapses runs of whitespace and trims' {
        ConvertTo-SafeText -Text "  a`t`t  b  " | Should -Be 'a b'
    }

    It 'truncates past the cap and marks that it did' {
        $result = ConvertTo-SafeText -Text ('x' * 400) -MaxLength 50
        $result.Length | Should -Be 50
        $result | Should -BeLike '*...'
    }

    It 'returns an empty string for null or whitespace' {
        ConvertTo-SafeText -Text $null | Should -Be ''
        ConvertTo-SafeText -Text '   ' | Should -Be ''
    }
}

Describe 'Get-TableColumnType' {
    It 'passes through each of the eight documented types' -ForEach @(
        @{ Declared = 'boolean' ; Expected = 'boolean'  }
        @{ Declared = 'dateTime'; Expected = 'dateTime' }
        @{ Declared = 'dynamic' ; Expected = 'dynamic'  }
        @{ Declared = 'guid'    ; Expected = 'guid'     }
        @{ Declared = 'int'     ; Expected = 'int'      }
        @{ Declared = 'long'    ; Expected = 'long'     }
        @{ Declared = 'real'    ; Expected = 'real'     }
        @{ Declared = 'string'  ; Expected = 'string'   }
    ) {
        Get-TableColumnType -DeclaredType $Declared | Should -Be $Expected
    }

    It 'normalises the alias a hand-written schema is likely to use' -ForEach @(
        @{ Declared = 'bool'   ; Expected = 'boolean'  }
        @{ Declared = 'integer'; Expected = 'int'      }
        @{ Declared = 'double' ; Expected = 'real'     }
        @{ Declared = 'float'  ; Expected = 'real'     }
        @{ Declared = 'uuid'   ; Expected = 'guid'     }
        @{ Declared = 'object' ; Expected = 'dynamic'  }
        @{ Declared = 'array'  ; Expected = 'dynamic'  }
        @{ Declared = 'date'   ; Expected = 'dateTime' }
    ) {
        Get-TableColumnType -DeclaredType $Declared | Should -Be $Expected
    }

    It 'normalises the lower-case datetime a JSON schema writes to the API camelCase' {
        Get-TableColumnType -DeclaredType 'datetime' | Should -Be 'dateTime'
    }

    It 'is case insensitive about the declared spelling' {
        Get-TableColumnType -DeclaredType 'STRING'   | Should -Be 'string'
        Get-TableColumnType -DeclaredType 'DateTime' | Should -Be 'dateTime'
    }

    It 'returns null for a type the Tables API does not have, rather than guessing' {
        Get-TableColumnType -DeclaredType 'timespan' | Should -BeNullOrEmpty
        Get-TableColumnType -DeclaredType 'varchar'  | Should -BeNullOrEmpty
        Get-TableColumnType -DeclaredType ''         | Should -BeNullOrEmpty
    }
}

Describe 'Get-DcrColumnType' {
    It 'maps guid to string, because a stream declaration cannot express guid' {
        Get-DcrColumnType -TableColumnType 'guid' | Should -Be 'string'
    }

    It 'maps the camelCase table dateTime to the lower-case stream datetime' {
        Get-DcrColumnType -TableColumnType 'dateTime' | Should -Be 'datetime'
    }

    It 'passes every other type through unchanged' -ForEach @(
        @{ Table = 'string'  }
        @{ Table = 'int'     }
        @{ Table = 'long'    }
        @{ Table = 'real'    }
        @{ Table = 'boolean' }
        @{ Table = 'dynamic' }
    ) {
        Get-DcrColumnType -TableColumnType $Table | Should -Be $Table
    }

    It 'never emits a stream type outside the documented enum' {
        $allowed = @('boolean', 'datetime', 'dynamic', 'int', 'long', 'real', 'string')

        foreach ($tableType in $script:TableColumnTypes) {
            Get-DcrColumnType -TableColumnType $tableType | Should -BeIn $allowed
        }
    }
}

Describe 'Test-TableName' {
    It 'accepts a well-formed custom log table name' {
        @(Test-TableName -Name 'ThreatIntelAlert_CL') | Should -BeNullOrEmpty
    }

    It 'requires the _CL suffix' {
        (@(Test-TableName -Name 'MyApp') -join ';') | Should -Match "does not end with '_CL'"
    }

    It 'requires a leading letter, so KQL can reference it unquoted' {
        (@(Test-TableName -Name '9App_CL') -join ';') | Should -Match 'must start with a letter'
    }

    It 'rejects a hyphen even though the ARM pattern allows one' {
        # ^[A-Za-z0-9-_]+$ would accept this; the table would then need
        # bracket-quoting in every query that touched it.
        (@(Test-TableName -Name 'my-app_CL') -join ';') | Should -Match 'must start with a letter'
    }

    It 'enforces the documented length bounds' {
        (@(Test-TableName -Name 'a_CL') -join ';')                  | Should -Not -Match 'minimum'
        (@(Test-TableName -Name ('a' * 61 + '_CL')) -join ';')      | Should -Match 'the limit is 63'
    }

    It 'reports an empty name once and stops' {
        $problems = @(Test-TableName -Name '')
        $problems.Count | Should -Be 1
        $problems[0] | Should -Match 'empty'
    }
}

Describe 'Get-ColumnIssue' {
    It 'accepts a well-formed column' {
        @(Get-ColumnIssue -Name 'AlertID' -DeclaredType 'string') | Should -BeNullOrEmpty
    }

    It 'rejects every documented reserved name' -ForEach @(
        @{ Name = 'Type'         }
        @{ Name = 'TenantId'     }
        @{ Name = 'UniqueId'     }
        @{ Name = 'Title'        }
        @{ Name = 'BilledSize'   }
        @{ Name = 'IsBillable'   }
        @{ Name = '_ResourceId'  }
        @{ Name = '_TimeReceived'}
        @{ Name = 'SourceSystem' }
    ) {
        $issues = @(Get-ColumnIssue -Name $Name -DeclaredType 'string')
        ($issues | Where-Object Severity -EQ 'Error').Message -join ';' | Should -Match 'reserved'
    }

    It 'matches a reserved name case insensitively' {
        $issues = @(Get-ColumnIssue -Name 'tenantid' -DeclaredType 'string')
        ($issues | Where-Object Severity -EQ 'Error').Count | Should -BeGreaterThan 0
    }

    It 'requires an ASCII leading letter' {
        (@(Get-ColumnIssue -Name '1Alert' -DeclaredType 'string').Message -join ';') |
            Should -Match 'must start with an ASCII letter'
    }

    It 'rejects a non-ASCII letter, which the docs say is unsupported' {
        (@(Get-ColumnIssue -Name ('Caf' + [char]0x00E9) -DeclaredType 'string').Message -join ';') |
            Should -Match 'must start with an ASCII letter'
    }

    It 'rejects punctuation in a name' {
        (@(Get-ColumnIssue -Name 'Alert.Id' -DeclaredType 'string').Message -join ';') |
            Should -Match 'only letters, digits and underscores'
        (@(Get-ColumnIssue -Name 'Alert-Id' -DeclaredType 'string').Message -join ';') |
            Should -Match 'only letters, digits and underscores'
    }

    It 'enforces the documented 2 to 45 character range' {
        (@(Get-ColumnIssue -Name 'X' -DeclaredType 'string').Message -join ';') |
            Should -Match '2 to 45 characters'

        (@(Get-ColumnIssue -Name ('A' * 46) -DeclaredType 'string').Message -join ';') |
            Should -Match 'the limit is 45'

        @(Get-ColumnIssue -Name ('A' * 45) -DeclaredType 'string') | Should -BeNullOrEmpty
    }

    It 'rejects a type outside the enum and lists the valid ones' {
        $message = (@(Get-ColumnIssue -Name 'Value' -DeclaredType 'timespan').Message -join ';')
        $message | Should -Match "type 'timespan' is not a Log Analytics column type"
        $message | Should -Match 'boolean, dateTime, dynamic, guid, int, long, real, string'
    }

    It 'accepts each documented dataTypeHint' -ForEach @(
        @{ Hint = 'armPath' }
        @{ Hint = 'guid'    }
        @{ Hint = 'ip'      }
        @{ Hint = 'uri'     }
    ) {
        @(Get-ColumnIssue -Name 'Value' -DeclaredType 'string' -DataTypeHint $Hint) | Should -BeNullOrEmpty
    }

    It 'rejects a dataTypeHint outside the enum' {
        (@(Get-ColumnIssue -Name 'Value' -DeclaredType 'string' -DataTypeHint 'ipaddress').Message -join ';') |
            Should -Match "dataTypeHint 'ipaddress' is not valid"
    }

    It 'warns about a classic type suffix without blocking it' {
        $issues = @(Get-ColumnIssue -Name 'Computer_s' -DeclaredType 'string')
        @($issues | Where-Object Severity -EQ 'Error').Count   | Should -Be 0
        @($issues | Where-Object Severity -EQ 'Warning').Count | Should -Be 1
    }

    It 'reports an empty name' {
        (@(Get-ColumnIssue -Name '' -DeclaredType 'string').Message -join ';') | Should -Match 'empty'
    }
}

Describe 'Resolve-TableSchema' {
    It 'normalises types and keeps what was declared, for the error message' {
        $result = Resolve-TableSchema -Column @((New-Column -Name 'Flag' -Type 'bool'))
        $result.Columns[0].Type         | Should -Be 'boolean'
        $result.Columns[0].DeclaredType | Should -Be 'bool'
    }

    It 'defaults a missing type to string rather than failing the file' {
        $result = Resolve-TableSchema -Column @([pscustomobject] @{ name = 'Message' })
        $result.Columns[0].Type | Should -Be 'string'
    }

    It 'flags a missing TimeGenerated, which every custom table needs' {
        $result = Resolve-TableSchema -Column @((New-Column -Name 'Message' -Type 'string'))
        ($result.SchemaIssues | Where-Object Severity -EQ 'Error').Message -join ';' |
            Should -Match 'no TimeGenerated column'
    }

    It 'flags a TimeGenerated declared as the wrong type' {
        $result = Resolve-TableSchema -Column @((New-Column -Name 'TimeGenerated' -Type 'string'))
        ($result.SchemaIssues | Where-Object Severity -EQ 'Error').Message -join ';' |
            Should -Match 'It must be datetime'
    }

    It 'treats an exact duplicate as an error' {
        $result = Resolve-TableSchema -Column @(
            (New-Column -Name 'TimeGenerated' -Type 'datetime')
            (New-Column -Name 'Dup' -Type 'string')
            (New-Column -Name 'Dup' -Type 'string')
        )

        ($result.SchemaIssues | Where-Object Severity -EQ 'Error').Message -join ';' |
            Should -Match "duplicate column name 'Dup'"
    }

    It 'treats a case-only difference as a warning, not a duplicate' {
        # Analytics and Basic tables are case sensitive, so Case and case are
        # two real columns. Group-Object folds case by default, which would
        # both misreport this as an exact duplicate and hide the real warning.
        $result = Resolve-TableSchema -Column @(
            (New-Column -Name 'TimeGenerated' -Type 'datetime')
            (New-Column -Name 'Case' -Type 'string')
            (New-Column -Name 'case' -Type 'string')
        )

        ($result.SchemaIssues | Where-Object Severity -EQ 'Error').Message -join ';' |
            Should -Not -Match 'duplicate column name'

        $warning = @($result.SchemaIssues | Where-Object { $_.Severity -eq 'Warning' })
        $warning.Count | Should -Be 1
        $warning[0].Kind | Should -Be 'CaseCollision'
    }

    It 'names both spellings in the case-collision warning' {
        $result = Resolve-TableSchema -Column @(
            (New-Column -Name 'TimeGenerated' -Type 'datetime')
            (New-Column -Name 'Case' -Type 'string')
            (New-Column -Name 'case' -Type 'string')
        )

        $warning = @($result.SchemaIssues | Where-Object { $_.Severity -eq 'Warning' })[0]
        $warning.Message | Should -Match 'Case, case'
    }

    It 'flags a column list over the 500 limit' {
        $columns = @((New-Column -Name 'TimeGenerated' -Type 'datetime')) +
                   @(1..501 | ForEach-Object { New-Column -Name "Col$_" -Type 'string' })

        $result = Resolve-TableSchema -Column $columns
        ($result.SchemaIssues | Where-Object Severity -EQ 'Error').Message -join ';' |
            Should -Match 'capped at 500'
    }

    It 'sanitises a column description before it can reach ARM' {
        $result = Resolve-TableSchema -Column @(
            [pscustomobject] @{ name = 'Message'; type = 'string'; description = "line one`nline two" }
        )

        $result.Columns[0].Description | Should -Be 'line one line two'
    }

    It 'reads a description from the alternative keys a pasted schema uses' -ForEach @(
        @{ Key = 'description' }
        @{ Key = 'comment'     }
        @{ Key = 'note'        }
        @{ Key = 'notes'       }
    ) {
        $column = [ordered] @{ name = 'Message'; type = 'string' }
        $column[$Key] = 'the text'

        $result = Resolve-TableSchema -Column @([pscustomobject] $column)
        $result.Columns[0].Description | Should -Be 'the text'
    }

    It 'carries dataTypeHint and displayName through' {
        $result = Resolve-TableSchema -Column @(
            [pscustomobject] @{ name = 'SourceIp'; type = 'string'; dataTypeHint = 'ip'; displayName = 'Source address' }
        )

        $result.Columns[0].DataTypeHint | Should -Be 'ip'
        $result.Columns[0].DisplayName  | Should -Be 'Source address'
    }

    It 'gives every column the same property shape, as strict mode requires' {
        $result = Resolve-TableSchema -Column @((New-Column -Name 'Message' -Type 'string'))
        $names  = @($result.Columns[0].PSObject.Properties.Name)

        foreach ($expected in @('Name', 'Type', 'DeclaredType', 'Description', 'DisplayName', 'DataTypeHint', 'Issues')) {
            $names | Should -Contain $expected
        }
    }
}

Describe 'Repair-TableSchema' {
    It 'adds the required TimeGenerated column at the front' {
        $repaired = @(Repair-TableSchema -Column @((New-SchemaColumn -Name 'Message' -Type 'string')) -WarningAction SilentlyContinue)
        $repaired[0].Name | Should -Be 'TimeGenerated'
        $repaired[0].Type | Should -Be 'dateTime'
    }

    It 'corrects a TimeGenerated declared as the wrong type' {
        $columns  = (Resolve-TableSchema -Column @((New-Column -Name 'TimeGenerated' -Type 'string'))).Columns.ToArray()
        $repaired = @(Repair-TableSchema -Column $columns -WarningAction SilentlyContinue)
        $repaired[0].Type | Should -Be 'dateTime'
    }

    It 'drops a column whose name Azure will never accept' {
        $columns = (Resolve-TableSchema -Column @(
            (New-Column -Name 'TimeGenerated' -Type 'datetime')
            (New-Column -Name '9Bad' -Type 'string')
            (New-Column -Name 'Type' -Type 'string')
        )).Columns.ToArray()

        $repaired = @(Repair-TableSchema -Column $columns -WarningAction SilentlyContinue)
        @($repaired.Name) | Should -Not -Contain '9Bad'
        @($repaired.Name) | Should -Not -Contain 'Type'
    }

    It 'keeps a column with a bad type, because guessing would change what is stored' {
        # long or real for a column called Count is a data decision, not a
        # formatting one, so the repair must not make it.
        $columns = (Resolve-TableSchema -Column @(
            (New-Column -Name 'TimeGenerated' -Type 'datetime')
            (New-Column -Name 'Count' -Type 'numeric')
        )).Columns.ToArray()

        $repaired = @(Repair-TableSchema -Column $columns -WarningAction SilentlyContinue)
        @($repaired.Name) | Should -Contain 'Count'
    }

    It 'strips an invalid dataTypeHint but keeps the column' {
        $columns = (Resolve-TableSchema -Column @(
            (New-Column -Name 'TimeGenerated' -Type 'datetime')
            (New-Column -Name 'SourceIp' -Type 'string' -Hint 'ipaddress')
        )).Columns.ToArray()

        $repaired = @(Repair-TableSchema -Column $columns -WarningAction SilentlyContinue)
        $kept = @($repaired | Where-Object Name -EQ 'SourceIp')
        $kept.Count | Should -Be 1
        $kept[0].DataTypeHint | Should -Be ''
    }

    It 'drops an exact duplicate but keeps a case-only pair' {
        $columns = (Resolve-TableSchema -Column @(
            (New-Column -Name 'TimeGenerated' -Type 'datetime')
            (New-Column -Name 'Dup' -Type 'string')
            (New-Column -Name 'Dup' -Type 'string')
            (New-Column -Name 'Case' -Type 'string')
            (New-Column -Name 'case' -Type 'string')
        )).Columns.ToArray()

        $repaired = @(Repair-TableSchema -Column $columns -WarningAction SilentlyContinue)
        @($repaired | Where-Object Name -EQ 'Dup').Count | Should -Be 1
        @($repaired).Count | Should -Be 4
    }
}

Describe 'Invoke-SchemaEditor: unattended behaviour' {
    It 'accepts a clean schema unchanged' {
        $columns = (Resolve-TableSchema -Column @(
            (New-Column -Name 'TimeGenerated' -Type 'datetime')
            (New-Column -Name 'Message' -Type 'string')
        )).Columns.ToArray()

        $accepted = @(Invoke-SchemaEditor -Column $columns)
        $accepted.Count | Should -Be 2
    }

    It 'repairs what it safely can and returns' {
        $columns = (Resolve-TableSchema -Column @((New-Column -Name 'Message' -Type 'string'))).Columns.ToArray()

        $accepted = @(Invoke-SchemaEditor -Column $columns -WarningAction SilentlyContinue)
        @($accepted.Name) | Should -Contain 'TimeGenerated'
    }

    It 'refuses rather than shipping a schema it cannot repair without guessing' {
        $columns = (Resolve-TableSchema -Column @(
            (New-Column -Name 'TimeGenerated' -Type 'datetime')
            (New-Column -Name 'Count' -Type 'numeric')
        )).Columns.ToArray()

        { Invoke-SchemaEditor -Column $columns -WarningAction SilentlyContinue } |
            Should -Throw '*non-interactive mode cannot ask*'
    }
}

Describe 'ConvertTo-StreamColumn' {
    It 'declares a guid column as string' {
        $stream = @(ConvertTo-StreamColumn -Column @(
            (New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')
            (New-SchemaColumn -Name 'EventId' -Type 'guid')
        ))

        @($stream | Where-Object name -EQ 'EventId').type | Should -Be 'string'
    }

    It 'emits only name and type, so nothing pasted leaks into the stream' {
        $column = New-SchemaColumn -Name 'SourceIp' -Type 'string' -Description 'x' -DataTypeHint 'ip'
        $stream = @(ConvertTo-StreamColumn -Column @($column))

        @($stream[0].PSObject.Properties.Name) | Should -Be @('name', 'type')
    }

    It 'preserves order' {
        $stream = @(ConvertTo-StreamColumn -Column @(
            (New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')
            (New-SchemaColumn -Name 'A' -Type 'string')
            (New-SchemaColumn -Name 'B' -Type 'string')
        ))

        @($stream.name) | Should -Be @('TimeGenerated', 'A', 'B')
    }
}

Describe 'Get-DefaultTransform' {
    It 'is a plain passthrough when every type already matches' {
        $columns = @(
            (New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')
            (New-SchemaColumn -Name 'Message' -Type 'string')
        )
        $stream = @(ConvertTo-StreamColumn -Column $columns)

        Get-DefaultTransform -Column $columns -StreamColumn $stream | Should -Be 'source'
    }

    It 'casts a guid column back, or the deploy fails with InvalidTransformOutput' {
        $columns = @(
            (New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')
            (New-SchemaColumn -Name 'EventId' -Type 'guid')
        )
        $stream = @(ConvertTo-StreamColumn -Column $columns)

        Get-DefaultTransform -Column $columns -StreamColumn $stream |
            Should -Be 'source | extend EventId = toguid(EventId)'
    }

    It 'casts every divergent column, not just the first' {
        $columns = @(
            (New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')
            (New-SchemaColumn -Name 'A' -Type 'guid')
            (New-SchemaColumn -Name 'B' -Type 'guid')
        )
        $stream = @(ConvertTo-StreamColumn -Column $columns)

        $transform = Get-DefaultTransform -Column $columns -StreamColumn $stream
        $transform | Should -Match 'A = toguid\(A\)'
        $transform | Should -Match 'B = toguid\(B\)'
    }

    It 'ignores a column that is not in the stream' {
        $columns = @(
            (New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')
            (New-SchemaColumn -Name 'EventId' -Type 'guid')
        )

        Get-DefaultTransform -Column $columns -StreamColumn @(
            [pscustomobject] (New-LiveColumn -Name 'TimeGenerated' -Type 'datetime')
        ) | Should -Be 'source'
    }
}

Describe 'Case sensitivity across every name comparison' {
    # PowerShell's defaults are all case insensitive: @{}, -contains,
    # Group-Object, Sort-Object -Unique. Analytics and Basic tables treat
    # 'Foo' and 'foo' as two real columns, so each default silently breaks a
    # different part of this tool. These pin all of them at once.

    BeforeAll {
        $script:casePair = @(
            (New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')
            (New-SchemaColumn -Name 'Ref' -Type 'guid')
            (New-SchemaColumn -Name 'ref' -Type 'string')
        )
    }

    It 'derives a cast for the guid column and not for its lowercase twin' {
        # A case-insensitive stream index collapses the pair, so one column's
        # cast gets computed from the other's type. The guid needs toguid();
        # the string must not get one.
        $stream = @(ConvertTo-StreamColumn -Column $script:casePair)
        @($stream).Count | Should -Be 3

        $transform = Get-DefaultTransform -Column $script:casePair -StreamColumn $stream

        # -CMatch, not -Match. Pester's -Match is case insensitive, so it would
        # report the lowercase pattern as present in 'Ref = toguid(Ref)' and
        # this assertion would fail against correct code.
        $transform | Should -CMatch 'Ref = toguid\(Ref\)'
        $transform | Should -Not -CMatch 'ref = toguid\(ref\)'
    }

    It 'does not conflate case-differing columns when diffing a live table' {
        $diff = Compare-TableSchema `
            -DesiredColumn @(
                (New-SchemaColumn -Name 'Alert' -Type 'string')
                (New-SchemaColumn -Name 'alert' -Type 'string')
            ) `
            -ExistingColumn @((New-LiveColumn -Name 'Alert' -Type 'string'))

        # 'alert' is genuinely new; 'Alert' already exists and matches.
        $diff.Added     | Should -Be @('alert')
        $diff.Conflicts | Should -BeNullOrEmpty
        $diff.OnlyLive  | Should -BeNullOrEmpty
    }

    It 'reports a live-only column that differs from a desired one only by case' {
        $diff = Compare-TableSchema `
            -DesiredColumn @((New-SchemaColumn -Name 'alert' -Type 'string')) `
            -ExistingColumn @((New-LiveColumn -Name 'Alert' -Type 'string'))

        $diff.Added    | Should -Be @('alert')
        $diff.OnlyLive | Should -Be @('Alert')
    }

    It 'does not raise a spurious type conflict across a case-differing pair' {
        # 'Count' is long and 'count' is string. Conflated, one would be
        # reported as a type change against the other.
        $diff = Compare-TableSchema `
            -DesiredColumn @(
                (New-SchemaColumn -Name 'Count' -Type 'long')
                (New-SchemaColumn -Name 'count' -Type 'string')
            ) `
            -ExistingColumn @(
                (New-LiveColumn -Name 'Count' -Type 'long')
                (New-LiveColumn -Name 'count' -Type 'string')
            )

        $diff.Conflicts | Should -BeNullOrEmpty
        $diff.Added     | Should -BeNullOrEmpty
    }
}

Describe 'Test-TransformKql' {
    It 'leaves a normal transform alone' {
        $result = Test-TransformKql -Transform 'source | where isnotempty(Id)'
        $result.Text | Should -Be 'source | where isnotempty(Id)'
        @($result.Applied).Count | Should -Be 0
    }

    It 'straightens curly quotes, which KQL will not parse' {
        $curly  = 'source | where Name == ' + [char]0x201C + 'x' + [char]0x201D
        $result = Test-TransformKql -Transform $curly

        $result.Text | Should -Be 'source | where Name == "x"'
        $result.Applied | Should -Not -BeNullOrEmpty
    }

    It 'replaces a no-break space, which is invisible in a diff' {
        $result = Test-TransformKql -Transform ('source' + [char]0x00A0 + '| take 1')
        $result.Text | Should -Be 'source | take 1'
    }

    It 'keeps newlines, because a transform is code and not prose' {
        $result = Test-TransformKql -Transform "source`n| take 1"
        $result.Text | Should -Be "source`n| take 1"
    }

    It 'refuses a transform over the documented 15,360 character limit' {
        { Test-TransformKql -Transform ('x' * 15361) } | Should -Throw '*15360*'
    }

    It 'accepts a transform exactly at the limit' {
        (Test-TransformKql -Transform ('x' * 15360)).Text.Length | Should -Be 15360
    }
}

Describe 'Format-DeploymentError' {
    It 'flattens a single error' {
        $result = Format-DeploymentError -ErrorObject ([pscustomobject] @{
            Code = 'InvalidParameter'; Message = 'something is wrong'; Details = $null
        })

        $result | Should -Be '[InvalidParameter] something is wrong'
    }

    It 'reaches the inner error a preflight failure hides' {
        # This is the shape that defeated the original handler: the useful
        # message is two levels down in Details[], and a preflight failure
        # creates no deployment operations to read it from instead.
        $result = Format-DeploymentError -ErrorObject ([pscustomobject] @{
            Code    = 'InvalidTemplateDeployment'
            Message = 'See inner errors for details.'
            Details  = @(
                [pscustomobject] @{
                    Code    = 'InvalidPayload'
                    Message = 'Data collection rule is invalid'
                    Details = @(
                        [pscustomobject] @{
                            Code    = 'InvalidOutputTable'
                            Message = 'Table for output stream is not available'
                            Details = $null
                        }
                    )
                }
            )
        })

        $result | Should -Match 'InvalidTemplateDeployment'
        $result | Should -Match 'InvalidOutputTable'
        $result | Should -Match 'Table for output stream is not available'
    }

    It 'includes Target when ARM supplies one' {
        $result = Format-DeploymentError -ErrorObject ([pscustomobject] @{
            Code = 'BadRequest'; Target = 'properties.dataFlows[0]'; Message = 'nope'; Details = $null
        })

        $result | Should -Match '\(properties\.dataFlows\[0\]\)'
    }

    It 'handles a null error object without throwing' {
        Format-DeploymentError -ErrorObject $null | Should -Be ''
    }

    It 'returns a plain string unchanged' {
        Format-DeploymentError -ErrorObject 'just a message' | Should -Be 'just a message'
    }

    It 'never returns empty for an unrecognised shape' {
        # The failure that made this necessary: an error object whose
        # properties are none of Code/Message/Target/Details produced an empty
        # string, and the caller reported "Template validation failed:" with no
        # reason whatsoever. Dumping the object is always better than that.
        $result = Format-DeploymentError -ErrorObject ([pscustomobject] @{
            SomethingElse = 'unexpected'; Another = 42
        })

        $result | Should -Not -BeNullOrEmpty
        $result | Should -Match 'unrecognised error shape'
        $result | Should -Match 'unexpected'
    }

    It 'enumerates a List, which is how Test-AzResourceGroupDeployment returns errors' {
        # The cmdlet returns List<PSResourceManagerError> as a single object
        # rather than enumerating it, so the flattener is handed the collection.
        # Without an enumeration branch the whole list fell through to the raw
        # JSON dump: readable enough to debug from, but not a usable message.
        $list = [System.Collections.Generic.List[object]]::new()
        $list.Add([pscustomobject] @{ Code = 'First'; Message = 'first message'; Details = $null })
        $list.Add([pscustomobject] @{ Code = 'Second'; Message = 'second message'; Details = $null })

        $result = Format-DeploymentError -ErrorObject $list

        $result | Should -Match 'First'
        $result | Should -Match 'Second'
        $result | Should -Not -Match 'unrecognised error shape'
    }

    It 'surfaces the real preflight cause through the wrapper layers' {
        # The exact shape that hid a 256-character limit behind
        # "See inner errors for details" across three nesting levels.
        $list = [System.Collections.Generic.List[object]]::new()
        $list.Add([pscustomobject] @{
            Code    = 'InvalidTemplateDeployment'
            Message = 'See inner errors for details.'
            Details = @([pscustomobject] @{
                Code    = 'PreflightValidationCheckFailed'
                Message = 'Preflight validation failed.'
                Details = @([pscustomobject] @{
                    Code    = 'InvalidProperty'
                    Target  = 'Properties.Description'
                    Message = "'Description' length should be 256 characters or less."
                    Details = $null
                })
            })
        })

        $result = Format-DeploymentError -ErrorObject $list

        $result | Should -Match 'InvalidProperty'
        $result | Should -Match 'Properties\.Description'
        $result | Should -Match '256 characters or less'
    }

    It 'reads camelCase details, which the REST payloads use' {
        $result = Format-DeploymentError -ErrorObject ([pscustomobject] @{
            code    = 'Outer'
            message = 'outer message'
            details = @([pscustomobject] @{ code = 'Inner'; message = 'inner message' })
        })

        $result | Should -Match 'Inner'
        $result | Should -Match 'inner message'
    }

    It 'stops recursing on a self-referential chain' {
        # Depth-capped so a cyclic or pathologically deep Details tree cannot
        # hang the failure path, which would turn a bad error message into a
        # hung deployment.
        $deep = [pscustomobject] @{ Code = 'L0'; Message = 'm'; Details = $null }
        foreach ($level in 1..30) {
            $deep = [pscustomobject] @{ Code = "L$level"; Message = 'm'; Details = @($deep) }
        }

        { Format-DeploymentError -ErrorObject $deep } | Should -Not -Throw
    }
}

Describe 'Compare-TableSchema' {
    It 'reports a new column as an addition' {
        $diff = Compare-TableSchema `
            -DesiredColumn @(
                (New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')
                (New-SchemaColumn -Name 'NewCol' -Type 'string')
            ) `
            -ExistingColumn @((New-LiveColumn -Name 'TimeGenerated' -Type 'dateTime'))

        $diff.Added | Should -Contain 'NewCol'
        $diff.Conflicts | Should -BeNullOrEmpty
    }

    It 'reports a type change as a conflict, because Azure will not allow it' {
        $diff = Compare-TableSchema `
            -DesiredColumn @((New-SchemaColumn -Name 'Count' -Type 'long')) `
            -ExistingColumn @((New-LiveColumn -Name 'Count' -Type 'string'))

        ($diff.Conflicts -join ';') | Should -Match "Count: live table has 'string', the schema says 'long'"
    }

    It 'does not treat the API camelCase as a conflict with the same type' {
        $diff = Compare-TableSchema `
            -DesiredColumn @((New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')) `
            -ExistingColumn @((New-LiveColumn -Name 'TimeGenerated' -Type 'datetime'))

        $diff.Conflicts | Should -BeNullOrEmpty
    }

    It 'lists a live-only column without treating it as a problem' {
        $diff = Compare-TableSchema `
            -DesiredColumn @((New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')) `
            -ExistingColumn @(
                (New-LiveColumn -Name 'TimeGenerated' -Type 'dateTime')
                (New-LiveColumn -Name 'Legacy' -Type 'string')
            )

        $diff.OnlyLive  | Should -Contain 'Legacy'
        $diff.Conflicts | Should -BeNullOrEmpty
    }

    It 'ignores the platform underscore columns when listing live-only ones' {
        $diff = Compare-TableSchema `
            -DesiredColumn @((New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')) `
            -ExistingColumn @(
                (New-LiveColumn -Name 'TimeGenerated' -Type 'dateTime')
                (New-LiveColumn -Name '_ResourceId' -Type 'string')
            )

        $diff.OnlyLive | Should -Not -Contain '_ResourceId'
    }
}

Describe 'Build-TableArmTemplate' {
    BeforeAll {
        $script:tableColumns = @(
            (New-SchemaColumn -Name 'TimeGenerated' -Type 'dateTime')
            (New-SchemaColumn -Name 'SourceIp' -Type 'string' -Description 'caller' -DisplayName 'Source' -DataTypeHint 'ip')
        )
    }

    It 'targets the workspaces/tables resource type as a child name' {
        $template = Build-TableArmTemplate -WorkspaceName 'law-x' -Table 'MyApp_CL' -Column $script:tableColumns
        $template.resources[0].type | Should -Be 'Microsoft.OperationalInsights/workspaces/tables'
        $template.resources[0].name | Should -Be 'law-x/MyApp_CL'
    }

    It 'repeats the table name inside the schema, which the API requires' {
        $template = Build-TableArmTemplate -WorkspaceName 'law-x' -Table 'MyApp_CL' -Column $script:tableColumns
        $template.resources[0].properties.schema.name | Should -Be 'MyApp_CL'
    }

    It 'emits the optional column properties only when they are set' {
        $template = Build-TableArmTemplate -WorkspaceName 'law-x' -Table 'MyApp_CL' -Column $script:tableColumns
        $columns  = $template.resources[0].properties.schema.columns

        @($columns[0].Keys) | Should -Be @('name', 'type')
        @($columns[1].Keys) | Should -Contain 'description'
        @($columns[1].Keys) | Should -Contain 'displayName'
    }

    It 'omits dataTypeHint by default, because the live service rejects the documented enum' {
        # Observed against a real workspace at api-version 2023-09-01 and
        # 2025-07-01: sending 'ip', 'armPath' or 'uri', all of which the ARM
        # and REST references list as valid, returns
        #   MSG 1011: Invalid value provided for data type hint
        # A hint only affects display, so it is dropped rather than allowed to
        # fail the table creation.
        $template = Build-TableArmTemplate -WorkspaceName 'law-x' -Table 'MyApp_CL' -Column $script:tableColumns
        $columns  = $template.resources[0].properties.schema.columns

        @($columns[1].Keys) | Should -Not -Contain 'dataTypeHint'
    }

    It 'emits dataTypeHint when -IncludeDataTypeHint is passed' {
        $template = Build-TableArmTemplate -WorkspaceName 'law-x' -Table 'MyApp_CL' `
                        -Column $script:tableColumns -IncludeDataTypeHint
        $columns  = $template.resources[0].properties.schema.columns

        @($columns[1].Keys) | Should -Contain 'dataTypeHint'
        $columns[1]['dataTypeHint'] | Should -Be 'ip'
    }

    It 'omits retention when it was not supplied' {
        $template = Build-TableArmTemplate -WorkspaceName 'law-x' -Table 'MyApp_CL' -Column $script:tableColumns
        $template.resources[0].properties.Contains('retentionInDays')      | Should -BeFalse
        $template.resources[0].properties.Contains('totalRetentionInDays') | Should -BeFalse
    }

    It 'emits -1, which is the documented "use the default"' {
        $template = Build-TableArmTemplate -WorkspaceName 'law-x' -Table 'MyApp_CL' `
                        -Column $script:tableColumns -Plan 'Analytics' -Retention -1
        $template.resources[0].properties['retentionInDays'] | Should -Be -1
    }

    It 'does not send retentionInDays for a plan where it is read-only' -ForEach @(
        @{ Plan = 'Basic'     }
        @{ Plan = 'Auxiliary' }
    ) {
        $template = Build-TableArmTemplate -WorkspaceName 'law-x' -Table 'MyApp_CL' `
                        -Column $script:tableColumns -Plan $Plan -Retention 90 `
                        -TotalRetention 365 -WarningAction SilentlyContinue

        $template.resources[0].properties.Contains('retentionInDays')      | Should -BeFalse
        $template.resources[0].properties['totalRetentionInDays']          | Should -Be 365
    }

    It 'produces JSON that round-trips' {
        $template = Build-TableArmTemplate -WorkspaceName 'law-x' -Table 'MyApp_CL' -Column $script:tableColumns
        { $template | ConvertTo-Json -Depth 30 | ConvertFrom-Json } | Should -Not -Throw
    }
}

Describe 'Build-DcrArmTemplate' {
    BeforeAll {
        $script:streamColumns = @(
            [pscustomobject] (New-LiveColumn -Name 'TimeGenerated' -Type 'datetime')
            [pscustomobject] @{ name = 'Message';       type = 'string'   }
        )

        $script:dcr = Build-DcrArmTemplate -Name 'dcr-myapp' -Region 'uksouth' `
            -Stream 'Custom-MyApp_CL' -StreamColumn $script:streamColumns `
            -WorkspaceResourceId '/subscriptions/s/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law-x' `
            -OutputStream 'Custom-MyApp_CL' -Transform 'source'
    }

    It 'is a Direct rule at the endpoints-capable API version' {
        $script:dcr.resources[0].kind       | Should -Be 'Direct'
        $script:dcr.resources[0].apiVersion | Should -Be '2023-03-11'
    }

    It 'declares the stream under its Custom- name' {
        @($script:dcr.resources[0].properties.streamDeclarations.Keys) | Should -Be @('Custom-MyApp_CL')
    }

    It 'points the data flow at the declared stream and the output table' {
        $flow = $script:dcr.resources[0].properties.dataFlows[0]
        $flow.streams      | Should -Be @('Custom-MyApp_CL')
        $flow.outputStream | Should -Be 'Custom-MyApp_CL'
        $flow.destinations | Should -Be @('workspaceDestination')
        $flow.transformKql | Should -Be 'source'
    }

    It 'names the destination consistently with the data flow reference' {
        $script:dcr.resources[0].properties.destinations.logAnalytics[0].name | Should -Be 'workspaceDestination'
    }

    It 'omits dataCollectionEndpointId unless a DCE was given' {
        $script:dcr.resources[0].properties.Contains('dataCollectionEndpointId') | Should -BeFalse
    }

    It 'wires in the DCE when one is given' {
        $withDce = Build-DcrArmTemplate -Name 'dcr-myapp' -Region 'uksouth' `
            -Stream 'Custom-MyApp_CL' -StreamColumn $script:streamColumns `
            -WorkspaceResourceId '/subscriptions/s/rg/x' -OutputStream 'Custom-MyApp_CL' `
            -Transform 'source' -EndpointResourceId '/subscriptions/s/rg/dce'

        $withDce.resources[0].properties['dataCollectionEndpointId'] | Should -Be '/subscriptions/s/rg/dce'
    }

    It 'emits only name and type per stream column' {
        @($script:dcr.resources[0].properties.streamDeclarations['Custom-MyApp_CL'].columns[0].Keys) |
            Should -Be @('name', 'type')
    }

    It 'produces JSON that round-trips' {
        { $script:dcr | ConvertTo-Json -Depth 30 | ConvertFrom-Json } | Should -Not -Throw
    }
}

Describe 'End to end: the shipped examples' -ForEach @(
    @{ Example = 'minimal.json';                Table = 'MyApp_CL';                  Columns = 2;  Plan = $null;       Transform = 'source' }
    @{ Example = 'threat-intel-alerts.json';    Table = 'ThreatIntelAlert_CL';       Columns = 12; Plan = 'Analytics'; Transform = 'source' }
    @{ Example = 'annotated.json';              Table = 'PaymentAudit_CL';           Columns = 10; Plan = 'Analytics'; Transform = 'source | extend TransactionId = toguid(TransactionId)' }
    @{ Example = 'basic-plan.json';             Table = 'AppTrace_CL';               Columns = 6;  Plan = 'Basic';     Transform = 'source' }
    @{ Example = 'auxiliary-plan.json';         Table = 'NetFlowArchive_CL';         Columns = 8;  Plan = 'Auxiliary'; Transform = 'source' }
) {
    It "accepts $Example without a single repair" {
        $path = Join-Path (Split-Path -Parent $PSScriptRoot) "Tools/DcrFromSchema/Examples/$Example"

        $spec = Import-TableSpec -Path $path
        $spec.TableName | Should -Be $Table
        @(Test-TableName -Name $spec.TableName) | Should -BeNullOrEmpty

        $analysis = Resolve-TableSchema -Column @($spec.Columns)
        @($analysis.SchemaIssues | Where-Object Severity -EQ 'Error') | Should -BeNullOrEmpty
        @($analysis.Columns | Where-Object { @($_.Issues | Where-Object Severity -EQ 'Error').Count -gt 0 }) |
            Should -BeNullOrEmpty

        $accepted = @(Invoke-SchemaEditor -Column $analysis.Columns.ToArray())
        $accepted.Count | Should -Be $Columns
    }

    It "derives the expected transform for $Example" {
        $path    = Join-Path (Split-Path -Parent $PSScriptRoot) "Tools/DcrFromSchema/Examples/$Example"
        $spec    = Import-TableSpec -Path $path
        $columns = @(Invoke-SchemaEditor -Column (Resolve-TableSchema -Column @($spec.Columns)).Columns.ToArray())
        $stream  = @(ConvertTo-StreamColumn -Column $columns)

        Get-DefaultTransform -Column $columns -StreamColumn $stream | Should -Be $Transform
    }

    It "builds deployable templates for $Example" {
        $path    = Join-Path (Split-Path -Parent $PSScriptRoot) "Tools/DcrFromSchema/Examples/$Example"
        $spec    = Import-TableSpec -Path $path
        $columns = @(Invoke-SchemaEditor -Column (Resolve-TableSchema -Column @($spec.Columns)).Columns.ToArray())
        $stream  = @(ConvertTo-StreamColumn -Column $columns)

        $table = Build-TableArmTemplate -WorkspaceName 'law-x' -Table $spec.TableName -Column $columns
        $dcr   = Build-DcrArmTemplate -Name 'dcr-x' -Region 'uksouth' `
                    -Stream "Custom-$($spec.TableName)" -StreamColumn $stream `
                    -WorkspaceResourceId '/subscriptions/s/rg/x' `
                    -OutputStream "Custom-$($spec.TableName)" -Transform 'source'

        ($table | ConvertTo-Json -Depth 30 | ConvertFrom-Json).resources[0].properties.schema.columns.Count |
            Should -Be $columns.Count
        ($dcr | ConvertTo-Json -Depth 30 | ConvertFrom-Json).resources[0].kind | Should -Be 'Direct'
    }

    It "carries the declared plan for $Example into the table template" {
        $path = Join-Path (Split-Path -Parent $PSScriptRoot) "Tools/DcrFromSchema/Examples/$Example"
        $spec = Import-TableSpec -Path $path

        Get-SpecDefault -Extra $spec.Extra -Key 'plan' | Should -Be $Plan

        if ($Plan) {
            $columns = @(Invoke-SchemaEditor -Column (Resolve-TableSchema -Column @($spec.Columns)).Columns.ToArray())
            $table   = Build-TableArmTemplate -WorkspaceName 'law-x' -Table $spec.TableName `
                            -Column $columns -Plan $Plan -WarningAction SilentlyContinue

            $table.resources[0].properties['plan'] | Should -Be $Plan

            # retentionInDays is read-only on Basic and Auxiliary, so no
            # example for those plans may set it.
            if ($Plan -ne 'Analytics') {
                Get-SpecDefault -Extra $spec.Extra -Key 'retentionInDays' | Should -BeNullOrEmpty
            }
        }
    }

    It "declares every $Example stream column with a documented stream type" {
        $allowed = @('boolean', 'datetime', 'dynamic', 'int', 'long', 'real', 'string')
        $path    = Join-Path (Split-Path -Parent $PSScriptRoot) "Tools/DcrFromSchema/Examples/$Example"
        $spec    = Import-TableSpec -Path $path
        $columns = @(Invoke-SchemaEditor -Column (Resolve-TableSchema -Column @($spec.Columns)).Columns.ToArray())

        foreach ($column in @(ConvertTo-StreamColumn -Column $columns)) {
            $column.type | Should -BeIn $allowed
        }
    }
}
