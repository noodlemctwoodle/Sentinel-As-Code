#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for the pure helpers in Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1.

.DESCRIPTION
    Invoke-TableMigrationReview is the read-only assess-and-plan stage of the
    ClassicToDcr toolkit: it discovers classic custom-log tables, scores their
    dependency impact, and maps each to a Content Hub solution. Most of the
    script talks to Azure and cannot be unit tested, so this suite covers the
    two decisions its report hinges on:

      Test-KqlReferencesTable   Whether a KQL body references a table by name.
                                A substring match here would over-report impact
                                (MyApp_CL matching MyApp_CL_v2), so the
                                word-boundary behaviour is pinned down.
      Resolve-ConnectorKind     Classifying a connector as CCF / AzureFunctions
                                / AMA / Platform / Agent / Legacy from its ID.
                                This drives the "no CCF equivalent" warning that
                                tells an operator a connector needs rebuilding.
      Get-ParserAliasIndex      Building the parser-alias graph, and deciding
      Resolve-IndirectTableImpact
                                which content reaches a classic table only
                                through a parser function. That is the case an
                                operator cannot see by searching for the table
                                name, so a miss here breaks rules silently.

    Deliberately not covered: the ARM calls, the Content Hub package fetch, and
    the HTML/CSV/JSON writers. Those need a live workspace.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-InvokeTableMigrationReview.Tests.ps1

    Runs the impact-scoring and connector-classification tests, plus the
    report.html.template contract checks.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-InvokeTableMigrationReview.Tests.ps1 -FullName '*Resolve-IndirectTableImpact*'

    Runs only the parser-chain resolution assertions, the case where a
    miss would break rules silently.

.NOTES
    File:         Tests/Test-InvokeTableMigrationReview.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Created:      2026-07-28
    Version:      0.1.0
    Last Updated: 2026-09-01
    Requires:     PowerShell 7.2+, Pester 5+

    One assertion couples the script's .NOTES Version to the version badge
    in Tools/ClassicToDcr/Templates/report.html.template. Bump both
    together or this suite fails.
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath
}

Describe 'Invoke-TableMigrationReview: script-level contract' {
    BeforeAll {
        $script:sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1'
        $script:sourceText = Get-Content -Path $script:sourcePath -Raw
    }

    It 'parses cleanly' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:sourcePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'has the correct repo-relative header path' {
        $script:sourceText | Should -Match 'File:\s+Tools/ClassicToDcr/Invoke-TableMigrationReview\.ps1'
        $script:sourceText | Should -Match 'Repository:\s+Sentinel-As-Code'
    }

    It 'records its origin as the folded-in CLv1 analyzer' {
        # The provenance note keeps the MIT->Apache-2.0 relicensing auditable.
        $script:sourceText | Should -Match 'Sentinel-CLv1-Analyzer'
    }

    It 'reads solution-mapping.json with -AsHashtable' {
        # The bundled mapping contains an empty-string property name, which
        # ConvertFrom-Json only tolerates in hashtable mode. Losing this switch
        # turns every lookup into a silent miss.
        $script:sourceText | Should -Match 'ConvertFrom-Json[^\r\n]*-AsHashtable'
    }

    It 'is read-only: issues no PUT/PATCH/DELETE ARM calls' {
        # The tool is documented as assessment-only. Guard against a mutating
        # verb slipping into the REST helper. Invoke-ArmRequest hard-codes Get.
        $script:sourceText | Should -Not -Match "-Method\s+'?(Put|Patch|Delete)'?"
    }

    It 'uses no em-dashes in prose' {
        $script:sourceText | Should -Not -Match ([char]0x2014)
    }

    It 'is standalone: does not import the Sentinel.Common module' {
        $script:sourceText | Should -Not -Match 'Import-Module[^\r\n]*Sentinel\.Common'
        $script:sourceText | Should -Not -Match 'Sentinel\.Common\.psd1'
    }

    It 'never calls into System.Web for HTML/JS encoding' {
        # System.Web is not loaded on PowerShell 7, so a call to
        # [System.Web.HttpUtility]::JavaScriptStringEncode throws outright
        # rather than falling back. Assert on executable code only: strip block
        # comments and line comments first, since the helper's own doc comment
        # legitimately names the API it avoids.
        $code = [regex]::Replace($script:sourceText, '(?s)<#.*?#>', '')
        $code = ($code -split "`n" | ForEach-Object { $_ -replace '#.*$', '' }) -join "`n"
        $code | Should -Not -Match 'HttpUtility'
        $code | Should -Not -Match 'JavaScriptStringEncode'
        $code | Should -Not -Match 'Add-Type\s+-AssemblyName\s+System\.Web'
    }
}

Describe 'ConvertTo-JsStringLiteral' {
    # The HTML template embeds the payload as JSON.parse("{{DATA_JSON}}"), so
    # this must produce a valid double-quoted JS string literal on PS7 without
    # System.Web.

    It 'round-trips text unchanged through a JSON string decode' {
        $original = 'plain text'
        $literal  = ConvertTo-JsStringLiteral -Value $original
        # Re-wrapping in quotes and decoding as JSON is what JS parsing does.
        ('"' + $literal + '"' | ConvertFrom-Json) | Should -BeExactly $original
    }

    It 'escapes double quotes and backslashes so the literal cannot terminate early' {
        $original = 'he said "hi" C:\temp\new'
        $literal  = ConvertTo-JsStringLiteral -Value $original
        ('"' + $literal + '"' | ConvertFrom-Json) | Should -BeExactly $original
    }

    It 'neutralises a closing script tag so it cannot close the script element' {
        $payload = '</script><img onerror=alert(1)>'
        $literal = ConvertTo-JsStringLiteral -Value $payload
        $literal | Should -Not -Match ([regex]::Escape($payload))
        $literal | Should -Match 'u003c'
        # Still decodes back to the original text: escaped, not corrupted.
        ('"' + $literal + '"' | ConvertFrom-Json) | Should -BeExactly $payload
    }

    It 'escapes the U+2028 / U+2029 JavaScript line terminators' {
        $original = "a$([char]0x2028)b$([char]0x2029)c"
        $literal  = ConvertTo-JsStringLiteral -Value $original
        $literal | Should -Match 'u2028'
        $literal | Should -Match 'u2029'
        ('"' + $literal + '"' | ConvertFrom-Json) | Should -BeExactly $original
    }

    It 'escapes newlines and tabs rather than emitting raw control characters' {
        $original = "line1`nline2`tend"
        $literal  = ConvertTo-JsStringLiteral -Value $original
        $literal | Should -Not -Match "`n"
        ('"' + $literal + '"' | ConvertFrom-Json) | Should -BeExactly $original
    }

    It 'round-trips a full compressed JSON payload' {
        $json    = ([ordered]@{ a = 'x"y'; b = 'C:\p'; c = '</script>' } | ConvertTo-Json -Compress)
        $literal = ConvertTo-JsStringLiteral -Value $json
        $decoded = ('"' + $literal + '"' | ConvertFrom-Json)
        $decoded | Should -BeExactly $json
        # And the decoded text is still parseable JSON, as JSON.parse expects.
        ($decoded | ConvertFrom-Json).c | Should -BeExactly '</script>'
    }
}

Describe 'Test-KqlReferencesTable' {
    It 'matches a whole-word table reference' {
        Test-KqlReferencesTable -Query 'MyApp_CL | where Level > 1' -TableName 'MyApp_CL' | Should -BeTrue
    }

    It 'is case-insensitive' {
        Test-KqlReferencesTable -Query 'myapp_cl | count' -TableName 'MyApp_CL' | Should -BeTrue
    }

    It 'does not match a longer table that merely starts with the name' {
        # The over-reporting trap: MyApp_CL must not match MyApp_CL_v2.
        Test-KqlReferencesTable -Query 'MyApp_CL_v2 | count' -TableName 'MyApp_CL' | Should -BeFalse
    }

    It 'does not match the name embedded inside another identifier' {
        Test-KqlReferencesTable -Query 'let x_MyApp_CL_y = 1;' -TableName 'MyApp_CL' | Should -BeFalse
    }

    It 'returns false for an empty query' {
        Test-KqlReferencesTable -Query '' -TableName 'MyApp_CL' | Should -BeFalse
    }
}

Describe 'Get-MatchedTable' {
    It 'returns only the tables the query references' {
        $result = Get-MatchedTable -Query 'union MyApp_CL, Other_CL | count' -TableNames @('MyApp_CL', 'Unused_CL', 'Other_CL')
        $result | Should -Contain 'MyApp_CL'
        $result | Should -Contain 'Other_CL'
        $result | Should -Not -Contain 'Unused_CL'
    }

    It 'returns nothing for an empty query' {
        Get-MatchedTable -Query '' -TableNames @('MyApp_CL') | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-ConnectorKind' {
    It 'classifies "<Id>" as <Expected>' -ForEach @(
        @{ Id = 'MyConnectorCCPDefinition'; Expected = 'CCF' }
        @{ Id = 'AwsS3Serverless';          Expected = 'AzureFunctions' }
        @{ Id = 'SomethingPolling';         Expected = 'AzureFunctions' }
        @{ Id = 'SyslogAma';                Expected = 'AMA' }
        @{ Id = 'AzureActiveDirectory';     Expected = 'Platform' }
        @{ Id = 'Office365';                Expected = 'Platform' }
        @{ Id = 'Syslog';                   Expected = 'Agent' }
        @{ Id = 'CEF';                      Expected = 'Agent' }
        @{ Id = 'SomeVendorCustomLog';      Expected = 'Legacy' }
    ) {
        Resolve-ConnectorKind -ConnectorId $Id | Should -Be $Expected
    }

    It 'returns Unknown for an empty connector id' {
        Resolve-ConnectorKind -ConnectorId '' | Should -Be 'Unknown'
    }
}

Describe 'Get-FunctionAliasSafety' {
    # A functionAlias is resolved transitively by treating it as if it were a
    # table name, so an alias that is a common word would drag in unrelated
    # content. These are the gates that stop that.

    It 'accepts a distinctive alias' {
        $v = Get-FunctionAliasSafety -Alias 'OfficeActivityParser'
        $v.IsSafe | Should -BeTrue
        $v.Alias  | Should -BeExactly 'OfficeActivityParser'
    }

    It 'accepts an ASIM-style alias that starts with an underscore' {
        (Get-FunctionAliasSafety -Alias '_Im_Dns').IsSafe | Should -BeTrue
    }

    It 'trims surrounding whitespace before judging the alias' {
        (Get-FunctionAliasSafety -Alias '  MyParser  ').Alias | Should -BeExactly 'MyParser'
    }

    It 'rejects "<Alias>" because it is <Why>' -ForEach @(
        @{ Alias = '';            Why = 'empty' }
        @{ Alias = '   ';         Why = 'whitespace only' }
        @{ Alias = 'Ofc';         Why = 'shorter than the four-character floor' }
        @{ Alias = 'My Parser';   Why = 'not a plain identifier' }
        @{ Alias = 'parser-v2';   Why = 'not a plain identifier' }
        @{ Alias = '2Fast';       Why = 'not a plain identifier' }
        @{ Alias = 'summarize';   Why = 'a KQL keyword' }
        @{ Alias = 'WHERE';       Why = 'a KQL keyword regardless of case' }
        @{ Alias = 'cluster';     Why = 'a scoping function, so it names something outside the workspace' }
        @{ Alias = 'TimeGenerated'; Why = 'a column Log Analytics puts on every table' }
    ) {
        $v = Get-FunctionAliasSafety -Alias $Alias
        $v.IsSafe | Should -BeFalse
        $v.Reason | Should -Not -BeNullOrEmpty
    }

    It 'admits a name that is only a common word, now that the table guard exists' {
        # The deny list used to carry a second block of "ubiquitous identifiers"
        # (alert, body, data, name, status, user...) standing in for two
        # problems now fixed properly: table-name collisions, and Logic App
        # JSON keys. Suppressing those names severed real chains - the finding
        # that motivated this change was rule -> InboxRuleAudit -> Alerts ->
        # MyApp_CL reporting nothing at all. What remains on the list is only
        # what KQL itself resolves to something other than a stored function.
        (Get-FunctionAliasSafety -Alias 'Alerts').IsSafe | Should -BeTrue
        (Get-FunctionAliasSafety -Alias 'Users').IsSafe  | Should -BeTrue
    }

    Context 'workspace table-name collision guard' {
        # The single largest source of false chains: a parser aliased over a
        # real table name makes every query against the genuine BUILT-IN table
        # an indirect dependent of whatever classic table that parser reads.

        It 'rejects an alias that collides with a real workspace table' {
            $v = Get-FunctionAliasSafety -Alias 'Update' -WorkspaceTableName @('Update', 'SecurityEvent')
            $v.IsSafe | Should -BeFalse
            $v.Reason | Should -Match 'collides with the workspace table'
        }

        It 'compares case-insensitively, because a near-miss is ambiguous too' {
            (Get-FunctionAliasSafety -Alias 'SECURITYEVENT' -WorkspaceTableName @('SecurityEvent')).IsSafe |
                Should -BeFalse
        }

        It 'names the colliding table in the reason, so the skip is actionable' {
            (Get-FunctionAliasSafety -Alias 'Heartbeat' -WorkspaceTableName @('Heartbeat')).Reason |
                Should -Match "'Heartbeat'"
        }

        It 'leaves a distinctive alias alone even when the table list is supplied' {
            (Get-FunctionAliasSafety -Alias 'OfficeActivityParser' `
                -WorkspaceTableName @('Update', 'SecurityEvent', 'OfficeActivity')).IsSafe | Should -BeTrue
        }

        It 'is a no-op when no table list is available' {
            (Get-FunctionAliasSafety -Alias 'Update').IsSafe | Should -BeTrue
        }
    }

    It 'agrees with the Test-SafeFunctionAlias predicate' {
        Test-SafeFunctionAlias -Alias 'OfficeActivityParser' | Should -BeTrue
        Test-SafeFunctionAlias -Alias 'summarize'            | Should -BeFalse
        Test-SafeFunctionAlias -Alias 'Update' -WorkspaceTableName @('Update') | Should -BeFalse
    }
}

Describe 'Get-WorkspaceTableInventory' {
    # The inventory exists so the collision guard has data. Its ClassicTables
    # output is what Get-ClassicCustomLogTable has always returned and must
    # keep returning byte for byte.

    BeforeAll {
        function New-TmrArmTable {
            param([string]$Name, [string]$Type = 'CustomLog', [string]$SubType = 'Classic')
            [PSCustomObject]@{
                id   = "/subscriptions/s/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/w/tables/$Name"
                name = $Name
                properties = [PSCustomObject]@{
                    plan = 'Analytics'; retentionInDays = 90; totalRetentionInDays = 90
                    schema = [PSCustomObject]@{
                        tableType = $Type; tableSubType = $SubType
                        columns = @([PSCustomObject]@{ name = 'TimeGenerated' })
                    }
                }
            }
        }

        # Invoke-ArmRequest is the only Azure call either function makes.
        Mock -CommandName Invoke-ArmRequest -MockWith {
            @(
                New-TmrArmTable -Name 'MyApp_CL'
                New-TmrArmTable -Name 'Other_CL'
                New-TmrArmTable -Name 'AzureDiagnostics'
                New-TmrArmTable -Name 'SecurityEvent' -Type 'Microsoft' -SubType 'Any'
                New-TmrArmTable -Name 'Update'        -Type 'Microsoft' -SubType 'Any'
            )
        }
    }

    It 'returns every table name in the workspace, built-ins included' {
        $inv = Get-WorkspaceTableInventory -SubscriptionId 's' -ResourceGroupName 'rg' -WorkspaceName 'w'
        @($inv.AllTableNames) | Should -Contain 'SecurityEvent'
        @($inv.AllTableNames) | Should -Contain 'Update'
        @($inv.AllTableNames) | Should -Contain 'MyApp_CL'
        # AzureDiagnostics is not a migration candidate but it IS a real table,
        # so an alias colliding with it must still be caught.
        @($inv.AllTableNames) | Should -Contain 'AzureDiagnostics'
    }

    It 'keeps the classic filter exactly as it was' {
        $inv = Get-WorkspaceTableInventory -SubscriptionId 's' -ResourceGroupName 'rg' -WorkspaceName 'w'
        @($inv.ClassicTables | ForEach-Object { $_.Name }) | Should -Be @('MyApp_CL', 'Other_CL')
    }

    It 'leaves Get-ClassicCustomLogTable returning what it always returned' {
        $viaWrapper = @(Get-ClassicCustomLogTable -SubscriptionId 's' -ResourceGroupName 'rg' -WorkspaceName 'w')
        $viaWrapper.Count | Should -Be 2
        $viaWrapper[0].Name         | Should -BeExactly 'MyApp_CL'
        $viaWrapper[0].TableSubType | Should -BeExactly 'Classic'
        $viaWrapper[0].ColumnCount  | Should -Be 1
        $viaWrapper[0].ResourceId   | Should -Match '/tables/MyApp_CL$'
    }

    It 'makes exactly one ARM call for both answers' {
        # The whole point of the sibling function: the table list was already
        # fetched and thrown away, so the guard has to cost nothing extra.
        $null = Get-WorkspaceTableInventory -SubscriptionId 's' -ResourceGroupName 'rg' -WorkspaceName 'w'
        Should -Invoke -CommandName Invoke-ArmRequest -Times 1 -Exactly -Scope It
    }
}

Describe 'Get-KqlIdentifierSet' {
    # The transitive pass asks one body of text about many names at once, so it
    # tokenises instead of running a regex per name. That is only sound if the
    # token set answers exactly what Test-KqlReferencesTable would answer.

    It 'splits on everything outside [A-Za-z0-9_]' {
        $set = Get-KqlIdentifierSet -Text @('OfficeActivity_CL | extend x = tostring(A.b)')
        $set.Contains('OfficeActivity_CL') | Should -BeTrue
        $set.Contains('tostring')          | Should -BeTrue
        $set.Contains('b')                 | Should -BeTrue
    }

    It 'is case-insensitive, matching the regex matcher' {
        (Get-KqlIdentifierSet -Text @('myapp_cl | count')).Contains('MyApp_CL') | Should -BeTrue
    }

    It 'returns a set, not an unrolled collection' {
        $set = Get-KqlIdentifierSet -Text @('a b c')
        $set.GetType().Name | Should -BeLike 'HashSet*'
    }

    It 'gives the same verdict as Test-KqlReferencesTable for every name in a corpus' {
        $bodies = @(
            'MyApp_CL | where Level > 1',
            'MyApp_CL_v2 | count',
            'let x_MyApp_CL_y = 1; print x_MyApp_CL_y',
            'union OfficeActivityParser, Other_CL',
            'OfficeActivityParser(1d) | project Op',
            '',
            'search "MyApp_CL"'
        )
        $names = @('MyApp_CL', 'MyApp_CL_v2', 'Other_CL', 'OfficeActivityParser', 'Absent_CL')
        foreach ($body in $bodies) {
            $set = Get-KqlIdentifierSet -Text @($body)
            foreach ($name in $names) {
                $viaRegex = [bool](Test-KqlReferencesTable -Query $body -TableName $name)
                $viaSet   = $set.Contains($name)
                $viaSet | Should -Be $viaRegex -Because "'$name' in '$body'"
            }
        }
    }
}

Describe 'Get-KqlCodeText' {
    # Splitting raw query text on [^A-Za-z0-9_] finds an identifier wherever it
    # appears, including two places KQL never resolves a name: inside a comment
    # and inside a string literal. Both produced false chained dependencies,
    # and a false dependency on a PARSER multiplies across every later hop.
    #
    # The forms below are exactly the ones the Kusto string data type reference
    # defines. KQL has no block comment syntax, so none is invented here.

    It 'strips a line comment' {
        Get-KqlCodeText -Text 'SigninLogs // TODO: replace OfficeParser later' |
            Should -Not -Match 'OfficeParser'
    }

    It 'strips only to the end of the line, leaving later code intact' {
        $out = Get-KqlCodeText -Text "SigninLogs // drop OfficeParser`nRealParser | count"
        $out | Should -Not -Match 'OfficeParser'
        $out | Should -Match 'RealParser'
    }

    It 'strips a double-quoted string' {
        Get-KqlCodeText -Text 'SigninLogs | extend N = "see OfficeParser docs"' |
            Should -Not -Match 'OfficeParser'
    }

    It 'strips a single-quoted string' {
        Get-KqlCodeText -Text "SigninLogs | where X == 'OfficeParser'" |
            Should -Not -Match 'OfficeParser'
    }

    It 'keeps a backslash-escaped quote inside the string, not ending it early' {
        # If the escape were ignored the string would close at the inner quote
        # and RealParser would be treated as prose rather than code... or worse,
        # the rest of the query would be swallowed as a string.
        $out = Get-KqlCodeText -Text 'print p = "a \" OfficeParser b" | RealParser'
        $out | Should -Not -Match 'OfficeParser'
        $out | Should -Match 'RealParser'
    }

    It 'treats a doubled quote as the escape inside a verbatim string' {
        $out = Get-KqlCodeText -Text 'print p = @"a ""OfficeParser"" b" | RealParser'
        $out | Should -Not -Match 'OfficeParser'
        $out | Should -Match 'RealParser'
    }

    It 'does not treat a backslash as an escape inside a verbatim string' {
        # @'C:\path\' ends at that final quote because the backslash is literal.
        $out = Get-KqlCodeText -Text "print p = @'C:\OfficeParser\' | RealParser"
        $out | Should -Not -Match 'OfficeParser'
        $out | Should -Match 'RealParser'
    }

    It 'strips a multi-line triple-backtick literal' {
        $tick = [char]0x60
        $fence = "$tick$tick$tick"
        $out = Get-KqlCodeText -Text "print p = ${fence}line one OfficeParser`nline two${fence} | RealParser"
        $out | Should -Not -Match 'OfficeParser'
        $out | Should -Match 'RealParser'
    }

    It 'strips the body of an obfuscated h-prefixed literal' {
        Get-KqlCodeText -Text "print s = h'OfficeParser'" | Should -Not -Match 'OfficeParser'
    }

    It 'does not let a // inside a string open a comment' {
        # If it did, everything after the URL would vanish and RealParser would
        # be a false NEGATIVE, which is the failure this feature exists to stop.
        $out = Get-KqlCodeText -Text 'print u = "https://contoso.example" | RealParser | count'
        $out | Should -Match 'RealParser'
    }

    It 'does not let an apostrophe inside a comment open a string' {
        # A comment is recognised first, so the apostrophe in "doesn't" cannot
        # swallow the following line as a string literal.
        $out = Get-KqlCodeText -Text "SigninLogs // this doesn't use a parser`nRealParser | count"
        $out | Should -Match 'RealParser'
    }

    It 'bounds an unterminated string to its own line' {
        $out = Get-KqlCodeText -Text "print p = `"unterminated`nRealParser | count"
        $out | Should -Match 'RealParser'
    }

    It 'leaves a query with no comments or strings untouched apart from spacing' {
        $q = 'OfficeActivity_CL | where Op == 1 | project A, B'
        (Get-KqlCodeText -Text $q) | Should -BeExactly $q
    }

    It 'handles null and empty input' {
        Get-KqlCodeText -Text $null | Should -BeExactly ''
        Get-KqlCodeText -Text ''    | Should -BeExactly ''
    }
}

Describe 'Get-KqlReferenceIdentifierSet' {
    # The identifiers a KQL body could actually resolve to a workspace entity.
    # Every rule here removes a position KQL provably does not resolve a stored
    # function in, so a genuine reference is never lost.

    It 'excludes a name that only appears in a comment' {
        $set = Get-KqlReferenceIdentifierSet -Text @("SigninLogs`n// replace OfficeParser later")
        $set.Contains('OfficeParser') | Should -BeFalse
        $set.Contains('SigninLogs')   | Should -BeTrue
    }

    It 'excludes a name that only appears in a string literal' {
        (Get-KqlReferenceIdentifierSet -Text @('SigninLogs | extend N = "OfficeParser"')).Contains('OfficeParser') |
            Should -BeFalse
    }

    It 'excludes a cross-cluster reference, which names another cluster entirely' {
        $set = Get-KqlReferenceIdentifierSet -Text @('cluster("x").database("y").MyParser | take 1')
        $set.Contains('MyParser') | Should -BeFalse
    }

    It 'excludes a cross-workspace reference' {
        (Get-KqlReferenceIdentifierSet -Text @('workspace("other").MyParser | count')).Contains('MyParser') |
            Should -BeFalse
    }

    It 'still sees a local reference in a query that also reaches another cluster' {
        $set = Get-KqlReferenceIdentifierSet -Text @('union cluster("x").database("y").Remote, LocalParser')
        $set.Contains('LocalParser') | Should -BeTrue
        $set.Contains('Remote')      | Should -BeFalse
    }

    It 'excludes an assignment target, which names a new column' {
        $set = Get-KqlReferenceIdentifierSet -Text @('SigninLogs | extend MyParser = 1 | project MyParser')
        # The binding site goes; the bare use on the right of the pipe does not,
        # because a column reference is the one position that cannot be ruled
        # out without a full KQL parser. Documented as residual over-reporting.
        $set.Contains('MyParser') | Should -BeTrue
    }

    It 'keeps an equality comparison, which is not an assignment' {
        (Get-KqlReferenceIdentifierSet -Text @('union MyParser | where X == 1')).Contains('MyParser') |
            Should -BeTrue
    }

    It 'excludes a dotted member access on a dynamic value' {
        (Get-KqlReferenceIdentifierSet -Text @('SigninLogs | extend V = Properties.MyParser')).Contains('MyParser') |
            Should -BeFalse
    }

    It 'excludes a let-bound local, which shadows a stored function of that name' {
        $set = Get-KqlReferenceIdentifierSet -Text @('let MyParser = SigninLogs; MyParser | take 5')
        $set.Contains('MyParser')   | Should -BeFalse
        $set.Contains('SigninLogs') | Should -BeTrue
    }

    It 'keeps a bracket-quoted entity name, which is a real reference' {
        (Get-KqlReferenceIdentifierSet -Text @("['MyParser'] | count")).Contains('MyParser') | Should -BeTrue
    }

    It 'excludes a dynamic index key, which is not an entity name' {
        $set = Get-KqlReferenceIdentifierSet -Text @('SigninLogs | extend V = parse_json(Props)["MyParser"]')
        $set.Contains('MyParser') | Should -BeFalse
    }

    It 'is case-sensitive, because KQL entity names are' {
        # Microsoft Learn, Entity names: "Identifiers are case-sensitive. For
        # example, you can't refer to a table called ThisTable as thisTABLE."
        $set = Get-KqlReferenceIdentifierSet -Text @('officeparser | count')
        $set.Contains('officeparser') | Should -BeTrue
        $set.Contains('OfficeParser') | Should -BeFalse
    }

    It 'still finds the ordinary case' {
        (Get-KqlReferenceIdentifierSet -Text @('MyParser | where X > 1')).Contains('MyParser') | Should -BeTrue
    }

    It 'keeps the source table of a column_ifexists parser and nothing else' {
        # The shape every Content Hub parser is built from, and the single
        # biggest source of vocabulary pollution: each line is an assignment
        # target on the left and a string literal on the right, so neither
        # side can be an entity reference. Measured against the live corpus
        # one such parser contributed 413 spurious identifiers.
        $q = @'
SalesforceServiceCloud_CL
| extend
    RequestSize=column_ifexists('request_size_s',''),
    PlatformType=column_ifexists('platform_type_s',''),
    UserAgent=column_ifexists('user_agent_s','')
| project-away *_s
'@
        $set = Get-KqlReferenceIdentifierSet -Text @($q)
        $set.Contains('SalesforceServiceCloud_CL') | Should -BeTrue
        foreach ($noise in 'RequestSize', 'PlatformType', 'UserAgent', 'request_size_s', 'user_agent_s') {
            $set.Contains($noise) | Should -BeFalse -Because "'$noise' is a new column name or a string, not an entity"
        }
    }

    It 'never invents an identifier the raw text does not contain' {
        # The preparation only ever removes. If it could add, a chain could be
        # reported for a name that appears nowhere in the query at all.
        $bodies = @(
            'MyApp_CL | where Level > 1 // OfficeParser',
            'let x = 1; print x, @"C:\a\b", ''q'' | RealParser',
            'cluster("c").database("d").T | union LocalOne',
            'SigninLogs | extend A = B.C | project-away D'
        )
        foreach ($b in $bodies) {
            $raw = Get-KqlIdentifierSet -Text @($b) -CaseSensitive
            foreach ($t in (Get-KqlReferenceIdentifierSet -Text @($b))) {
                $raw.Contains($t) | Should -BeTrue -Because "'$t' must come from the original text of '$b'"
            }
        }
    }
}

Describe 'Get-PlaybookKqlText' {
    # Scanning a whole Logic App definition for an alias makes a JSON key or a
    # word in an action name into a dependency. The indirect pass reads string
    # VALUES only, and only those shaped like a query.

    It 'finds the body of a run-query action' {
        $def = [PSCustomObject]@{ actions = [PSCustomObject]@{
            RunQuery = [PSCustomObject]@{ inputs = [PSCustomObject]@{ body = 'MyParser | project X' } } } }
        @(Get-PlaybookKqlText -Definition $def) | Should -Contain 'MyParser | project X'
    }

    It 'ignores object keys, so an action named after a parser is not a reference' {
        $def = [PSCustomObject]@{ actions = [PSCustomObject]@{
            MyParser = [PSCustomObject]@{ inputs = [PSCustomObject]@{ body = 'SigninLogs | count' } } } }
        @(Get-PlaybookKqlText -Definition $def) -join ' ' | Should -Not -Match 'MyParser'
    }

    It 'ignores prose that merely mentions a parser' {
        $def = [PSCustomObject]@{ actions = [PSCustomObject]@{
            Notify = [PSCustomObject]@{ inputs = [PSCustomObject]@{
                body = 'This incident was enriched by MyParser during triage.' } } } }
        @(Get-PlaybookKqlText -Definition $def).Count | Should -Be 0
    }

    It 'handles a null definition' {
        @(Get-PlaybookKqlText -Definition $null).Count | Should -Be 0
    }

    It 'walks arrays as well as objects' {
        $def = [PSCustomObject]@{ actions = @(
            [PSCustomObject]@{ body = 'not a query' }
            [PSCustomObject]@{ body = 'MyParser | summarize count()' }) }
        @(Get-PlaybookKqlText -Definition $def) | Should -Contain 'MyParser | summarize count()'
    }
}

Describe 'Transitive parser dependency resolution' {
    BeforeAll {
        function New-TmrSavedSearch {
            param([string]$Name, [string]$Query, [string]$Alias, [string]$Category = 'General')
            [PSCustomObject]@{
                id   = "/subscriptions/s/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/w/savedSearches/$Name"
                name = $Name
                properties = [PSCustomObject]@{
                    displayName   = $Name
                    query         = $Query
                    category      = $Category
                    functionAlias = $Alias
                }
            }
        }

        function New-TmrRule {
            param([string]$Name, [string]$Query, [string]$Severity = 'Medium', [bool]$Enabled = $true)
            [PSCustomObject]@{
                id   = "/subscriptions/s/resourceGroups/rg/providers/Microsoft.SecurityInsights/alertRules/$Name"
                name = $Name
                properties = [PSCustomObject]@{
                    displayName = $Name; query = $Query; severity = $Severity; enabled = $Enabled
                }
            }
        }

        function New-TmrWorkbook {
            param([string]$Name, [string[]]$Queries)
            $items = foreach ($q in $Queries) { @{ type = 3; content = @{ query = $q } } }
            [PSCustomObject]@{
                id   = "/subscriptions/s/providers/Microsoft.Insights/workbooks/$Name"
                name = $Name
                properties = [PSCustomObject]@{
                    displayName    = $Name
                    serializedData = (@{ items = @($items) } | ConvertTo-Json -Depth 10)
                }
            }
        }

        function New-TmrPlaybook {
            param([string]$Name, [string]$Query)
            [PSCustomObject]@{
                id   = "/subscriptions/s/providers/Microsoft.Logic/workflows/$Name"
                name = $Name
                properties = [PSCustomObject]@{
                    state      = 'Enabled'
                    definition = [PSCustomObject]@{
                        actions = [PSCustomObject]@{
                            RunQuery = [PSCustomObject]@{ inputs = [PSCustomObject]@{ body = $Query } }
                        }
                    }
                }
            }
        }

        function New-TmrDcr {
            param([string]$Name, [string]$TransformKql)
            [PSCustomObject]@{
                id   = "/subscriptions/s/providers/Microsoft.Insights/dataCollectionRules/$Name"
                name = $Name
                properties = [PSCustomObject]@{
                    dataFlows = @([PSCustomObject]@{ transformKql = $TransformKql })
                }
            }
        }

        function New-TmrContent {
            param($AlertRules = @(), $SavedSearches = @(), $Workbooks = @(), $Playbooks = @(), $Dcrs = @())
            # Mirrors the shape Get-WorkspaceContent returns, including the way
            # it derives HuntingQueries and Parsers from the saved searches.
            [PSCustomObject]@{
                AlertRules     = @($AlertRules)
                SavedSearches  = @($SavedSearches)
                HuntingQueries = @(@($SavedSearches) | Where-Object { $_.properties.category -eq 'Hunting Queries' })
                Parsers        = @(@($SavedSearches) | Where-Object { $_.properties.functionAlias })
                Workbooks      = @($Workbooks)
                Playbooks      = @($Playbooks)
                Dcrs           = @($Dcrs)
            }
        }

        function Get-TmrImpact {
            param(
                $Content,
                [string]$TableName = 'OfficeActivity_CL',
                [int]$MaxDepth = 10,
                [string[]]$WorkspaceTableName
            )
            $index = Get-ParserAliasIndex -Content $Content -WorkspaceTableName $WorkspaceTableName
            Get-TableImpactAnalysis -TableName $TableName -Content $Content -AliasIndex $index -MaxDepth $MaxDepth
        }
    }

    Context 'a rule that only ever names the parser' {
        BeforeAll {
            $script:oneHop = Get-TmrImpact -Content (New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'OfficeActivityParser' `
                    -Query 'OfficeActivity_CL | extend Op = OperationName_s') `
                -AlertRules @(New-TmrRule -Name 'Malicious Inbox Rule' `
                    -Query 'OfficeActivityParser | where Op == "New-InboxRule"'))
        }

        It 'reports the rule, which a direct scan cannot see' {
            @($script:oneHop.IndirectAnalyticsRules).Count | Should -Be 1
            $script:oneHop.IndirectAnalyticsRules[0].Name | Should -BeExactly 'Malicious Inbox Rule'
        }

        It 'carries the chain that explains the finding' {
            $item = $script:oneHop.IndirectAnalyticsRules[0]
            $item.DependencyKind | Should -BeExactly 'Indirect'
            $item.Via            | Should -BeExactly 'OfficeActivityParser'
            @($item.ViaChain)    | Should -Be @('OfficeActivityParser')
            $item.Depth          | Should -Be 1
        }

        It 'keeps the rule out of the direct list' {
            @($script:oneHop.AnalyticsRules).Count | Should -Be 0
        }

        It 'leaves TotalImpacted meaning direct hits only, and adds the honest total alongside' {
            $script:oneHop.TotalImpacted | Should -Be 1   # the parser itself
            $script:oneHop.TotalIndirect | Should -Be 1
            $script:oneHop.TotalAffected | Should -Be 2
        }

        It 'still reports the parser itself as a direct dependent' {
            @($script:oneHop.Parsers).Count | Should -Be 1
            $script:oneHop.Parsers[0].FunctionAlias | Should -BeExactly 'OfficeActivityParser'
            $script:oneHop.Parsers[0].DependencyKind | Should -BeExactly 'Direct'
        }

        It 'does not list the parser as an indirect dependent of its own alias' {
            @($script:oneHop.IndirectParsers).Count | Should -Be 0
        }

        It 'reports nothing indirect when no index is supplied' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'OfficeActivityParser' `
                    -Query 'OfficeActivity_CL | extend Op = 1') `
                -AlertRules @(New-TmrRule -Name 'r' -Query 'OfficeActivityParser | count')
            $plain = Get-TableImpactAnalysis -TableName 'OfficeActivity_CL' -Content $content
            $plain.TotalImpacted | Should -Be 1
            $plain.TotalIndirect | Should -Be 0
            @($plain.IndirectAnalyticsRules).Count | Should -Be 0
            $plain.ChainTruncated | Should -BeFalse
        }
    }

    Context 'two chained parsers' {
        BeforeAll {
            $script:twoHop = Get-TmrImpact -Content (New-TmrContent `
                -SavedSearches @(
                    New-TmrSavedSearch -Name 'a' -Alias 'OfficeActivityParser' -Query 'OfficeActivity_CL | extend Op = 1'
                    New-TmrSavedSearch -Name 'b' -Alias 'SecurityAlertParser'  -Query 'OfficeActivityParser | where Op == 1'
                ) `
                -AlertRules @(New-TmrRule -Name 'Chained Rule' -Query 'SecurityAlertParser | take 10'))
        }

        It 'walks both hops out to the rule' {
            @($script:twoHop.IndirectAnalyticsRules).Count | Should -Be 1
            $script:twoHop.IndirectAnalyticsRules[0].Depth | Should -Be 2
        }

        It 'orders the chain from the item outward to the table' {
            @($script:twoHop.IndirectAnalyticsRules[0].ViaChain) |
                Should -Be @('SecurityAlertParser', 'OfficeActivityParser')
        }

        It 'names the alias the rule literally types as Via' {
            $script:twoHop.IndirectAnalyticsRules[0].Via | Should -BeExactly 'SecurityAlertParser'
        }

        It 'reports the intermediate parser as an indirect dependent at depth 1' {
            @($script:twoHop.IndirectParsers).Count | Should -Be 1
            $script:twoHop.IndirectParsers[0].FunctionAlias | Should -BeExactly 'SecurityAlertParser'
            $script:twoHop.IndirectParsers[0].Depth | Should -Be 1
        }

        It 'counts three affected items in total' {
            $script:twoHop.TotalAffected | Should -Be 3
        }

        It 'does not flag the chain as truncated' {
            $script:twoHop.ChainTruncated | Should -BeFalse
        }
    }

    Context 'alias cycles' {
        It 'terminates when two parsers reference each other' {
            $content = New-TmrContent -SavedSearches @(
                New-TmrSavedSearch -Name 'a' -Alias 'AlphaParser' -Query 'OfficeActivity_CL | union BetaParser'
                New-TmrSavedSearch -Name 'b' -Alias 'BetaParser'  -Query 'AlphaParser | project X'
            )
            $impact = Get-TmrImpact -Content $content
            # AlphaParser is direct; BetaParser is one hop out. Expanding
            # BetaParser finds AlphaParser again, which is already claimed.
            $impact.TotalImpacted | Should -Be 1
            $impact.TotalIndirect | Should -Be 1
            $impact.IndirectParsers[0].FunctionAlias | Should -BeExactly 'BetaParser'
            $impact.ChainTruncated | Should -BeFalse
        }

        It 'terminates on a cycle between two parsers that are both indirect' {
            $content = New-TmrContent -SavedSearches @(
                New-TmrSavedSearch -Name 'a' -Alias 'AlphaParser' -Query 'OfficeActivity_CL | count'
                New-TmrSavedSearch -Name 'b' -Alias 'BetaParser'  -Query 'AlphaParser | union GammaParser'
                New-TmrSavedSearch -Name 'c' -Alias 'GammaParser' -Query 'BetaParser | project X'
            )
            $impact = Get-TmrImpact -Content $content
            @($impact.IndirectParsers).Count | Should -Be 2
            @($impact.IndirectParsers | ForEach-Object { $_.FunctionAlias }) |
                Should -Be @('BetaParser', 'GammaParser')
            $impact.ChainTruncated | Should -BeFalse
        }

        It 'reports each item once even when two chains reach it' {
            $content = New-TmrContent `
                -SavedSearches @(
                    New-TmrSavedSearch -Name 'a' -Alias 'AlphaParser' -Query 'OfficeActivity_CL | count'
                    New-TmrSavedSearch -Name 'b' -Alias 'BetaParser'  -Query 'OfficeActivity_CL | count'
                ) `
                -AlertRules @(New-TmrRule -Name 'Two Ways In' -Query 'union AlphaParser, BetaParser')
            $impact = Get-TmrImpact -Content $content
            @($impact.IndirectAnalyticsRules).Count | Should -Be 1
            # Frontier terms are expanded in ordinal order, so the ordinally
            # first alias supplies the chain no matter how ARM ordered them.
            $impact.IndirectAnalyticsRules[0].Via | Should -BeExactly 'AlphaParser'
        }
    }

    Context 'a parser that references its own alias' {
        BeforeAll {
            $script:selfRef = Get-TmrImpact -Content (New-TmrContent -SavedSearches @(
                New-TmrSavedSearch -Name 'a' -Alias 'SelfParser' `
                    -Query 'OfficeActivity_CL | extend Note = "see SelfParser for details"'
            ))
        }

        It 'reports the parser exactly once, as a direct dependent' {
            @($script:selfRef.Parsers).Count | Should -Be 1
            @($script:selfRef.IndirectParsers).Count | Should -Be 0
            $script:selfRef.TotalAffected | Should -Be 1
        }
    }

    Context 'an item that is both a direct and an indirect dependent' {
        BeforeAll {
            $script:both = Get-TmrImpact -Content (New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'OfficeActivityParser' `
                    -Query 'OfficeActivity_CL | count') `
                -AlertRules @(New-TmrRule -Name 'Belt And Braces' `
                    -Query 'union OfficeActivity_CL, OfficeActivityParser'))
        }

        It 'reports it once, in the direct list, and never in the indirect list' {
            @($script:both.AnalyticsRules).Count | Should -Be 1
            @($script:both.IndirectAnalyticsRules).Count | Should -Be 0
        }

        It 'does not inflate any of the counters' {
            $script:both.TotalImpacted | Should -Be 2
            $script:both.TotalIndirect | Should -Be 0
            $script:both.TotalAffected | Should -Be 2
        }
    }

    Context 'false-positive mitigation' {
        It 'does not resolve a reserved alias, so unrelated content stays out' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'summarize' -Query 'OfficeActivity_CL | count') `
                -AlertRules @(
                    New-TmrRule -Name 'Unrelated Signin Rule' -Query 'SigninLogs | summarize by Account'
                    New-TmrRule -Name 'Another Unrelated'     -Query 'AuditLogs | summarize c = count()'
                )
            $impact = Get-TmrImpact -Content $content
            @($impact.IndirectAnalyticsRules).Count | Should -Be 0
            $impact.TotalIndirect | Should -Be 0
            # The parser itself is still reported: direct matching is untouched.
            @($impact.Parsers).Count | Should -Be 1
        }

        It 'does not resolve an alias that collides with a real workspace table' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'Update' -Query 'OfficeActivity_CL | count') `
                -AlertRules @(
                    New-TmrRule -Name 'Patch Compliance' -Query 'Update | where Classification == "Security Updates"'
                    New-TmrRule -Name 'Missing Updates'  -Query 'Update | summarize by Computer'
                )
            $impact = Get-TmrImpact -Content $content -WorkspaceTableName @('Update', 'OfficeActivity_CL')
            @($impact.IndirectAnalyticsRules).Count | Should -Be 0
            $impact.TotalIndirect | Should -Be 0
        }

        It 'records why each unresolved alias was skipped, rather than dropping it silently' {
            $content = New-TmrContent -SavedSearches @(
                New-TmrSavedSearch -Name 'a' -Alias 'summarize'  -Query 'OfficeActivity_CL | count'
                New-TmrSavedSearch -Name 'b' -Alias 'Ofc'        -Query 'OfficeActivity_CL | count'
                New-TmrSavedSearch -Name 'c' -Alias 'My Parser'  -Query 'OfficeActivity_CL | count'
                New-TmrSavedSearch -Name 'd' -Alias 'GoodParser' -Query 'OfficeActivity_CL | count'
            )
            $index = Get-ParserAliasIndex -Content $content
            @($index.Aliases) | Should -Be @('GoodParser')
            @($index.SkippedAliases).Count | Should -Be 3
            foreach ($s in $index.SkippedAliases) { $s.Reason | Should -Not -BeNullOrEmpty }
            @($index.SkippedAliases | ForEach-Object { $_.Alias }) | Should -Contain 'summarize'
            @($index.SkippedAliases | ForEach-Object { $_.Alias }) | Should -Contain 'Ofc'
            @($index.SkippedAliases | ForEach-Object { $_.Alias }) | Should -Contain 'My Parser'
        }

        It 'never resolves an alias through a DCR transform, which cannot call a workspace function' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'OfficeActivityParser' `
                    -Query 'OfficeActivity_CL | count') `
                -Dcrs @(New-TmrDcr -Name 'dcr-1' -TransformKql 'source | extend Tag = "OfficeActivityParser"')
            $impact = Get-TmrImpact -Content $content
            @($impact.IndirectDcrs).Count | Should -Be 0
            $impact.TotalIndirect | Should -Be 0
        }

        It 'still reports a DCR that names the classic table directly' {
            $content = New-TmrContent -Dcrs @(
                New-TmrDcr -Name 'dcr-1' -TransformKql 'source | where Table == "OfficeActivity_CL"')
            $impact = Get-TmrImpact -Content $content
            @($impact.Dcrs).Count | Should -Be 1
        }

        It 'warns when an alias is referenced by an implausible share of the workspace' {
            # 60 of 61 content items. Both bounds are cleared with room to spare.
            $rules = 1..60 | ForEach-Object { New-TmrRule -Name "r$_" -Query 'Widget | count' }
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'Widget' -Query 'OfficeActivity_CL | count') `
                -AlertRules $rules
            $index = Get-ParserAliasIndex -Content $content
            @($index.Warnings).Count | Should -BeGreaterThan 0
            $index.Warnings[0] | Should -Match 'Widget'
        }

        It 'warns rather than suppresses, so the dependency is still reported' {
            $rules = 1..60 | ForEach-Object { New-TmrRule -Name "r$_" -Query 'Widget | count' }
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'Widget' -Query 'OfficeActivity_CL | count') `
                -AlertRules $rules
            (Get-TmrImpact -Content $content).TotalIndirect | Should -Be 60
        }

        Context 'fan-out thresholds' {
            # The old test was hitCount >= 5 AND hitCount/nodes > 0.25. That is
            # arithmetically unreachable at real scale (a 1000-item workspace
            # needed 251 references before it could fire) and it cried wolf on a
            # legitimate parser in a small one (5 of 18 items is 28%).

            It 'stays quiet for a legitimately shared parser in a small workspace' {
                # 5 of 6 items - 83% - but only five references. An operator can
                # read a five-item chain list without being told to distrust it.
                $rules = 1..5 | ForEach-Object { New-TmrRule -Name "r$_" -Query 'LegitParser | count' }
                $content = New-TmrContent `
                    -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'LegitParser' -Query 'OfficeActivity_CL | count') `
                    -AlertRules $rules
                @((Get-ParserAliasIndex -Content $content).Warnings).Count | Should -Be 0
            }

            It 'stays quiet for a popular parser in a large workspace' {
                # 40 of 201 items. Real ASIM-style parsers look exactly like this.
                $rules = 1..200 | ForEach-Object {
                    if ($_ -le 40) { New-TmrRule -Name "r$_" -Query 'HubParser | count' }
                    else { New-TmrRule -Name "r$_" -Query 'Heartbeat | count' }
                }
                $content = New-TmrContent `
                    -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'HubParser' -Query 'OfficeActivity_CL | count') `
                    -AlertRules $rules
                @((Get-ParserAliasIndex -Content $content).Warnings).Count | Should -Be 0
            }

            It 'fires at real scale, which the old ratio-only rule could not' {
                # 100 of 201 items. Under the old rule this needed 51 more hits.
                $rules = 1..200 | ForEach-Object {
                    if ($_ -le 100) { New-TmrRule -Name "r$_" -Query 'NoisyParser | count' }
                    else { New-TmrRule -Name "r$_" -Query 'Heartbeat | count' }
                }
                $content = New-TmrContent `
                    -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'NoisyParser' -Query 'OfficeActivity_CL | count') `
                    -AlertRules $rules
                @((Get-ParserAliasIndex -Content $content).Warnings).Count | Should -BeGreaterThan 0
            }

            It 'exposes both bounds so a workspace can tune them' {
                $rules = 1..5 | ForEach-Object { New-TmrRule -Name "r$_" -Query 'LegitParser | count' }
                $content = New-TmrContent `
                    -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'LegitParser' -Query 'OfficeActivity_CL | count') `
                    -AlertRules $rules
                $index = Get-ParserAliasIndex -Content $content `
                    -FanoutMinimumHits 3 -FanoutMinimumScale 1 -FanoutWarnRatio 0.1
                @($index.Warnings).Count | Should -BeGreaterThan 0
            }
        }
    }

    Context 'every content type can be reached indirectly' {
        BeforeAll {
            $script:allTypes = Get-TmrImpact -Content (New-TmrContent `
                -SavedSearches @(
                    New-TmrSavedSearch -Name 'p'  -Alias 'OfficeActivityParser' -Query 'OfficeActivity_CL | count'
                    New-TmrSavedSearch -Name 'hq' -Query 'OfficeActivityParser | take 5' -Category 'Hunting Queries'
                    New-TmrSavedSearch -Name 'ss' -Query 'OfficeActivityParser | count'  -Category 'General'
                ) `
                -AlertRules @(New-TmrRule -Name 'rule' -Query 'OfficeActivityParser | count' -Severity 'High') `
                -Workbooks @(New-TmrWorkbook -Name 'wb' -Queries @(
                    'OfficeActivityParser | count', 'OfficeActivityParser | take 1', 'Heartbeat | count')) `
                -Playbooks @(New-TmrPlaybook -Name 'pb' -Query 'OfficeActivityParser | project X'))
        }

        It 'reaches analytics rules, hunting queries, saved searches, workbooks and playbooks' {
            @($script:allTypes.IndirectAnalyticsRules).Count | Should -Be 1
            @($script:allTypes.IndirectHuntingQueries).Count | Should -Be 1
            @($script:allTypes.IndirectSavedSearches).Count  | Should -Be 1
            @($script:allTypes.IndirectWorkbooks).Count      | Should -Be 1
            @($script:allTypes.IndirectPlaybooks).Count      | Should -Be 1
        }

        It 'keeps the type-specific fields each direct item already carries' {
            $script:allTypes.IndirectAnalyticsRules[0].Severity | Should -BeExactly 'High'
            $script:allTypes.IndirectAnalyticsRules[0].Enabled  | Should -BeTrue
            $script:allTypes.IndirectHuntingQueries[0].Category | Should -BeExactly 'Hunting Queries'
            $script:allTypes.IndirectPlaybooks[0].State         | Should -BeExactly 'Enabled'
        }

        It 'counts the workbook queries that matched the alias, not the whole workbook' {
            $script:allTypes.IndirectWorkbooks[0].QueryCount | Should -Be 2
        }

        It 'always emits an IndirectDcrs key so consumers never hit an undefined field' {
            $script:allTypes.PSObject.Properties.Name | Should -Contain 'IndirectDcrs'
        }
    }

    Context 'depth bounding' {
        BeforeAll {
            $script:deepContent = New-TmrContent `
                -SavedSearches @(
                    New-TmrSavedSearch -Name 'l1' -Alias 'LevelOneParser'   -Query 'OfficeActivity_CL | count'
                    New-TmrSavedSearch -Name 'l2' -Alias 'LevelTwoParser'   -Query 'LevelOneParser | count'
                    New-TmrSavedSearch -Name 'l3' -Alias 'LevelThreeParser' -Query 'LevelTwoParser | count'
                    New-TmrSavedSearch -Name 'l4' -Alias 'LevelFourParser'  -Query 'LevelThreeParser | count'
                ) `
                -AlertRules @(New-TmrRule -Name 'Deep Rule' -Query 'LevelFourParser | count')
        }

        It 'resolves the whole chain at the default depth' {
            $impact = Get-TmrImpact -Content $script:deepContent
            $impact.ChainTruncated | Should -BeFalse
            @($impact.IndirectAnalyticsRules).Count | Should -Be 1
            $impact.IndirectAnalyticsRules[0].Depth | Should -Be 4
            @($impact.IndirectAnalyticsRules[0].ViaChain) | Should -Be @(
                'LevelFourParser', 'LevelThreeParser', 'LevelTwoParser', 'LevelOneParser')
        }

        It 'stops at the cap and says so, rather than reporting a partial answer silently' {
            $impact = Get-TmrImpact -Content $script:deepContent -MaxDepth 2
            $impact.ChainTruncated | Should -BeTrue
            @($impact.IndirectAnalyticsRules).Count | Should -Be 0
            @($impact.IndirectParsers).Count | Should -Be 2
        }
    }

    Context 'determinism and ordering' {
        It 'sorts indirect items by depth first' {
            $content = New-TmrContent `
                -SavedSearches @(
                    New-TmrSavedSearch -Name 'a' -Alias 'AlphaParser' -Query 'OfficeActivity_CL | count'
                    New-TmrSavedSearch -Name 'b' -Alias 'BetaParser'  -Query 'AlphaParser | count'
                ) `
                -AlertRules @(
                    New-TmrRule -Name 'zzz deep rule'    -Query 'BetaParser | count'
                    New-TmrRule -Name 'aaa shallow rule' -Query 'AlphaParser | count'
                )
            $impact = Get-TmrImpact -Content $content
            @($impact.IndirectAnalyticsRules | ForEach-Object { $_.Depth }) | Should -Be @(1, 2)
            $impact.IndirectAnalyticsRules[0].Name | Should -BeExactly 'aaa shallow rule'
        }

        It 'produces the same result on repeated runs over the same content' {
            $content = New-TmrContent `
                -SavedSearches @(
                    New-TmrSavedSearch -Name 'a' -Alias 'AlphaParser' -Query 'OfficeActivity_CL | count'
                    New-TmrSavedSearch -Name 'b' -Alias 'BetaParser'  -Query 'AlphaParser | count'
                ) `
                -AlertRules @(
                    New-TmrRule -Name 'r1' -Query 'BetaParser | count'
                    New-TmrRule -Name 'r2' -Query 'AlphaParser | count'
                    New-TmrRule -Name 'r3' -Query 'union AlphaParser, BetaParser'
                )
            $first  = (Get-TmrImpact -Content $content).IndirectAnalyticsRules | ConvertTo-Json -Depth 6
            $second = (Get-TmrImpact -Content $content).IndirectAnalyticsRules | ConvertTo-Json -Depth 6
            $second | Should -BeExactly $first
        }
    }

    Context 'textual mentions that are not references' {
        # Each of these was a reported CRITICAL false positive, reproduced
        # against the real functions before the fix.

        It 'does not count an alias that appears only in a comment' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'OfficeParser' `
                    -Query 'OfficeActivity_CL | count') `
                -AlertRules @(New-TmrRule -Name 'Comment Only' `
                    -Query "SigninLogs`n// TODO: replace OfficeParser later`n| count")
            (Get-TmrImpact -Content $content).TotalIndirect | Should -Be 0
        }

        It 'does not count an alias that appears only in a string literal' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'OfficeParser' `
                    -Query 'OfficeActivity_CL | count') `
                -AlertRules @(New-TmrRule -Name 'String Only' `
                    -Query 'SigninLogs | extend Note = "see OfficeParser docs"')
            (Get-TmrImpact -Content $content).TotalIndirect | Should -Be 0
        }

        It 'does not count a same-named function in another cluster' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'MyParser' `
                    -Query 'OfficeActivity_CL | count') `
                -AlertRules @(New-TmrRule -Name 'Cross Cluster' `
                    -Query 'cluster("x").database("y").MyParser | take 1')
            (Get-TmrImpact -Content $content).TotalIndirect | Should -Be 0
        }

        It 'does not count an alias appearing as a Logic App object key' {
            $pb = [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Logic/workflows/pb1'; name = 'pb1'
                properties = [PSCustomObject]@{ state = 'Enabled'; definition = [PSCustomObject]@{
                    actions = [PSCustomObject]@{ OfficeParser = [PSCustomObject]@{
                        inputs = [PSCustomObject]@{ body = 'SigninLogs | count' } } } } } }
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'OfficeParser' `
                    -Query 'OfficeActivity_CL | count') `
                -Playbooks @($pb)
            @((Get-TmrImpact -Content $content).IndirectPlaybooks).Count | Should -Be 0
        }

        It 'does not let one stray mention taint every genuine user of a parser' {
            # The compounding case. BaseParser genuinely reads MyApp_CL.
            # MidTierParser only MENTIONS BaseParser in a comment and actually
            # reads SigninLogs. Five rules genuinely use MidTierParser. Before
            # the fix this reported TotalAffected = 7; the truth is 1.
            $content = New-TmrContent `
                -SavedSearches @(
                    New-TmrSavedSearch -Name 'base' -Alias 'BaseParser'    -Query 'MyApp_CL | extend X = 1'
                    New-TmrSavedSearch -Name 'mid'  -Alias 'MidTierParser' `
                        -Query "SigninLogs`n// migrated off BaseParser in 2024`n| count"
                ) `
                -AlertRules @(1..5 | ForEach-Object { New-TmrRule -Name "r$_" -Query 'MidTierParser | count' })
            $impact = Get-TmrImpact -Content $content -TableName 'MyApp_CL'
            $impact.TotalImpacted | Should -Be 1
            $impact.TotalIndirect | Should -Be 0
            $impact.TotalAffected | Should -Be 1
        }
    }

    Context 'case sensitivity' {
        # KQL entity names are case-sensitive, so a case variant of an alias
        # does not resolve to it and must not be reported as a dependent.

        It 'does not match a case variant of the alias' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'OfficeParser' `
                    -Query 'OfficeActivity_CL | count') `
                -AlertRules @(
                    New-TmrRule -Name 'lower' -Query 'officeparser | count'
                    New-TmrRule -Name 'upper' -Query 'OFFICEPARSER | count')
            (Get-TmrImpact -Content $content).TotalIndirect | Should -Be 0
        }

        It 'keeps two aliases that differ only in case, instead of dropping one' {
            $content = New-TmrContent -SavedSearches @(
                New-TmrSavedSearch -Name 'a' -Alias 'MyParser' -Query 'OfficeActivity_CL | count'
                New-TmrSavedSearch -Name 'b' -Alias 'myparser' -Query 'Heartbeat | count')
            $index = Get-ParserAliasIndex -Content $content
            @($index.Aliases) | Should -Be @('MyParser', 'myparser')
            @($index.SkippedAliases).Count | Should -Be 0
        }

        It 'resolves each case variant to its own callers only' {
            $content = New-TmrContent `
                -SavedSearches @(
                    New-TmrSavedSearch -Name 'a' -Alias 'MyParser' -Query 'OfficeActivity_CL | count'
                    New-TmrSavedSearch -Name 'b' -Alias 'myparser' -Query 'Heartbeat | count') `
                -AlertRules @(
                    New-TmrRule -Name 'calls upper' -Query 'MyParser | count'
                    New-TmrRule -Name 'calls lower' -Query 'myparser | count')
            $impact = Get-TmrImpact -Content $content
            @($impact.IndirectAnalyticsRules).Count | Should -Be 1
            $impact.IndirectAnalyticsRules[0].Name | Should -BeExactly 'calls upper'
        }

        It 'leaves the inherited direct matcher case-insensitive' {
            # Deliberate asymmetry, explained in Get-KqlReferenceIdentifierSet:
            # a case variant of a TABLE name is nearly always a typo aimed at
            # the real table, and reporting it errs safe. Indirect resolution
            # chains off its own matches, so it errs precise instead.
            Test-KqlReferencesTable -Query 'officeactivity_cl | count' -TableName 'OfficeActivity_CL' |
                Should -BeTrue
        }
    }

    Context 'severed chains are reported, not swallowed' {
        # Silently dropping an alias reproduces the exact silent breakage this
        # feature exists to prevent, so a skip has to name what it cost.

        It 'reports the parser whose alias could not be resolved' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'Update' -Query 'MyApp_CL | count') `
                -AlertRules @(1..4 | ForEach-Object {
                    New-TmrRule -Name "r$_" -Query 'Update | where Classification == "Security Updates"' })
            $impact = Get-TmrImpact -Content $content -TableName 'MyApp_CL' -WorkspaceTableName @('Update')
            @($impact.UnresolvedBridges).Count | Should -Be 1
            $impact.UnresolvedBridges[0].Alias  | Should -BeExactly 'Update'
            $impact.UnresolvedBridges[0].Reason | Should -Match 'collides with the workspace table'
        }

        It 'names the dependents that were therefore not resolved' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'Update' -Query 'MyApp_CL | count') `
                -AlertRules @(1..4 | ForEach-Object { New-TmrRule -Name "r$_" -Query 'Update | count' })
            $impact = Get-TmrImpact -Content $content -TableName 'MyApp_CL' -WorkspaceTableName @('Update')
            $impact.UnresolvedBridges[0].ReferenceCount | Should -Be 4
            @($impact.UnresolvedBridges[0].Dependents | ForEach-Object { $_.Name }) | Should -Contain 'r1'
        }

        It 'reports a bridge severed part way down a chain, with the route to it' {
            # OuterParser is reached through InnerParser, but its own alias is a
            # reserved word, so anything calling OuterParser is unreported.
            $content = New-TmrContent `
                -SavedSearches @(
                    New-TmrSavedSearch -Name 'i' -Alias 'InnerParser' -Query 'MyApp_CL | count'
                    New-TmrSavedSearch -Name 'o' -Alias 'summarize'   -Query 'InnerParser | count')
            $impact = Get-TmrImpact -Content $content -TableName 'MyApp_CL'
            @($impact.UnresolvedBridges).Count | Should -Be 1
            $impact.UnresolvedBridges[0].Alias      | Should -BeExactly 'summarize'
            @($impact.UnresolvedBridges[0].ViaChain) | Should -Be @('InnerParser')
        }

        It 'no longer severs the chain the deny list used to cut' {
            # rule -> InboxRuleAudit -> Alerts -> MyApp_CL used to report
            # nothing at all, because 'Alerts' was on the deny list.
            $content = New-TmrContent `
                -SavedSearches @(
                    New-TmrSavedSearch -Name 'a' -Alias 'Alerts'         -Query 'MyApp_CL | count'
                    New-TmrSavedSearch -Name 'b' -Alias 'InboxRuleAudit' -Query 'Alerts | count') `
                -AlertRules @(New-TmrRule -Name 'Severed Rule' -Query 'InboxRuleAudit | count')
            $impact = Get-TmrImpact -Content $content -TableName 'MyApp_CL'
            @($impact.IndirectAnalyticsRules).Count | Should -Be 1
            @($impact.IndirectParsers).Count        | Should -Be 1
            @($impact.UnresolvedBridges).Count      | Should -Be 0
        }

        It 'attaches the lost dependents to the skipped alias in the index too' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'summarize' -Query 'MyApp_CL | count') `
                -AlertRules @(New-TmrRule -Name 'r1' -Query 'SigninLogs | summarize count()')
            $index = Get-ParserAliasIndex -Content $content
            $skip = @($index.SkippedAliases | Where-Object { $_.Alias -eq 'summarize' })[0]
            $skip.ReferenceCount | Should -Be 1
            @($skip.Dependents | ForEach-Object { $_.Name }) | Should -Contain 'r1'
        }

        It 'leaves UnresolvedBridges empty when every alias resolves' {
            $content = New-TmrContent `
                -SavedSearches @(New-TmrSavedSearch -Name 'p' -Alias 'GoodParser' -Query 'MyApp_CL | count') `
                -AlertRules @(New-TmrRule -Name 'r1' -Query 'GoodParser | count')
            @((Get-TmrImpact -Content $content -TableName 'MyApp_CL').UnresolvedBridges).Count | Should -Be 0
        }

        It 'always emits the key, so a consumer never hits an undefined field' {
            $content = New-TmrContent -AlertRules @(New-TmrRule -Name 'r1' -Query 'MyApp_CL | count')
            $direct = Get-TableImpactAnalysis -TableName 'MyApp_CL' -Content $content
            $direct.PSObject.Properties.Name | Should -Contain 'UnresolvedBridges'
            @($direct.UnresolvedBridges).Count | Should -Be 0
        }
    }

    Context 'a workspace with no parsers at all' {
        It 'behaves exactly as the direct-only scan did' {
            $content = New-TmrContent -AlertRules @(
                New-TmrRule -Name 'r1' -Query 'OfficeActivity_CL | count'
                New-TmrRule -Name 'r2' -Query 'Heartbeat | count'
            )
            $impact = Get-TmrImpact -Content $content
            @($impact.AnalyticsRules).Count | Should -Be 1
            $impact.TotalImpacted | Should -Be 1
            $impact.TotalIndirect | Should -Be 0
            $impact.TotalAffected | Should -Be 1
        }
    }
}

Describe 'report.html.template: migration-command contract' {
    # The report renders a per-table, copyable migration command. That logic is
    # client-side JavaScript, so the Pester suite cannot execute it. What it CAN
    # do is pin the invariants that make a shareable HTML file safe to hand
    # around, so none of them regress unnoticed.

    BeforeAll {
        $script:tplPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/ClassicToDcr/Templates/report.html.template'
        $script:tplText = Get-Content -Path $script:tplPath -Raw
    }

    It 'exists' {
        Test-Path -Path $script:tplPath | Should -BeTrue
    }

    It 'emits the current migration script name' {
        # A rename that misses the template would ship a report whose copy
        # button hands the operator a command that cannot run.
        $script:tplText | Should -Match ([regex]::Escape('./Invoke-ClassicTableMigration.ps1'))
        $script:tplText | Should -Not -Match 'New-DcrFromClassicTable'
    }

    It 'escapes every character that closes a PowerShell single-quoted string' {
        # PowerShell ends a '-quoted string on U+0027 and the curved quotes
        # U+2018, U+2019, U+201A and U+201B. Escaping only the ASCII apostrophe
        # lets a resource group name close the string early and append its own
        # statements to the command the operator pastes.
        $script:tplText | Should -Match 'CMD_PS_QUOTES'
        foreach ($cp in '2018', '2019', '201a', '201b') {
            $script:tplText | Should -Match ('\\u' + $cp)
        }
    }

    It 'never emits -Force in a generated command' {
        # -Force skips the confirmation prompt, which is the last human check
        # before an irreversible migration. It must not appear in copyable text.
        $script:tplText | Should -Not -Match '-Force'
    }

    It 'gates command generation on the table-name pattern the migrate script accepts' {
        $script:tplText | Should -Match 'CMD_TABLE_NAME'
        $script:tplText | Should -Match '\^\[A-Za-z0-9_\]\+\$'
        $script:tplText | Should -Match '_CL'
    }

    It 'pins the subscription only when it is a GUID' {
        $script:tplText | Should -Match 'CMD_GUID'
    }

    It 'wires the copy button by delegation, not an inline handler' {
        # Table cards are injected via innerHTML, so an inline onclick carrying
        # an interpolated table name or command would be an injection vector.
        # (The About modal's three static onclick handlers predate this and
        # interpolate nothing, so the assertion is scoped to the copy button.)
        $copyMarkup = [regex]::Match($script:tplText, '<button[^>]*cmd-copy[^>]*>').Value
        $copyMarkup | Should -Not -BeNullOrEmpty
        $copyMarkup | Should -Not -Match 'onclick'
        $script:tplText | Should -Match 'closest'
        $script:tplText | Should -Match 'addEventListener'
    }

    It 'reads the command from the rendered text, not a data attribute' {
        # Holding the command in a data-* attribute would add a second escaping
        # context to get right. The handler reads textContent instead.
        $script:tplText | Should -Not -Match 'data-command'
        $script:tplText | Should -Match 'textContent'
    }

    It 'stays self-contained: no external scripts, styles or fetches' {
        $script:tplText | Should -Not -Match '<script[^>]+src='
        $script:tplText | Should -Not -Match '<link[^>]+href="https?:'
        $script:tplText | Should -Not -Match 'fetch\('
        $script:tplText | Should -Not -Match 'XMLHttpRequest'
    }

    It 'keeps a clipboard fallback for pages opened from disk' {
        # navigator.clipboard is not guaranteed on a file:// page, which is the
        # primary way this report is opened.
        $script:tplText | Should -Match 'navigator\.clipboard'
        $script:tplText | Should -Match 'execCommand'
    }

    It 'uses no em-dashes in prose' {
        # The suite enforces this on the toolkit's .ps1 files; the template ships
        # to readers too, so hold it to the same rule.
        $script:tplText | Should -Not -Match ([char]0x2014)
    }

    It 'shows a version badge matching the script version' {
        # The badge is the only version an operator reading report.html ever
        # sees. If it drifts from the script's own .NOTES version, a report can
        # no longer be tied back to the tool that produced it.
        $scriptText = Get-Content -Path (Join-Path (Split-Path -Parent $PSScriptRoot) `
                        'Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1') -Raw
        $scriptVersion = [regex]::Match($scriptText, 'Version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Groups[1].Value
        $badgeVersion  = [regex]::Match($script:tplText, 'v([0-9]+\.[0-9]+\.[0-9]+)').Groups[1].Value

        $scriptVersion | Should -Not -BeNullOrEmpty
        $badgeVersion  | Should -Not -BeNullOrEmpty
        $badgeVersion  | Should -BeExactly $scriptVersion
    }
}

Describe 'report.html.template: chained-dependency contract' {
    # An indirect dependent is the finding an operator cannot reach any other
    # way, so the report must not be able to render it as absent or as clean.

    BeforeAll {
        $script:tplPath2 = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/ClassicToDcr/Templates/report.html.template'
        $script:tplText2 = Get-Content -Path $script:tplPath2 -Raw
    }

    It 'normalises every Indirect* array the writer emits' {
        # ConvertTo-Json unwraps a single-element array to a bare object, so
        # every list has to go through ensureArray or .length throws.
        $script:tplText2 | Should -Match "ensureArray\(i\['Indirect' \+ k\]\)"
    }

    It 'counts direct and via-parser dependents together in the card badge' {
        # The regression this guards: a card reading "2 dependencies" while four
        # more rules break through a parser.
        $script:tplText2 | Should -Match 'var affectedCount = directCount \+ indirectCount'
        $script:tplText2 | Should -Match 'affectedCount > 0'
    }

    It 'only calls a table clean when neither kind of dependent exists' {
        $cleanBadge = [regex]::Match($script:tplText2,
            'if \(affectedCount > 0\)[\s\S]{0,600}?badge clean">No dependencies')
        $cleanBadge.Success | Should -BeTrue
    }

    It 'sums both kinds in the Total Dependencies tile' {
        $script:tplText2 | Should -Match '\(DATA\.TotalImpacted \|\| 0\) \+ \(DATA\.TotalIndirect \|\| 0\)'
    }

    It 'does not count a table with chained dependents as clean in the header' {
        $script:tplText2 | Should -Match 'i\.TotalImpacted \|\| 0\) \+ \(i\.TotalIndirect \|\| 0\)'
    }

    It 'renders indirect rows inside the content type they belong to' {
        # A separate "indirect" section would let the Analytics Rules count keep
        # lying, so the two lists are concatenated under one heading.
        $script:tplText2 | Should -Match "impact\['Indirect' \+ it\.key\]"
        $script:tplText2 | Should -Match 'directItems\.concat\(indirectItems\)'
    }

    It 'marks every indirect row with the chain it travels' {
        $script:tplText2 | Should -Match "item\.DependencyKind === 'Indirect'"
        $script:tplText2 | Should -Match 'badge via'
        $script:tplText2 | Should -Match 'ensureArray\(item\.ViaChain\)'
    }

    It 'defines the via badge style so the chip is visible' {
        $script:tplText2 | Should -Match '\.badge\.via\s*\{'
    }

    It 'escapes each chain hop separately, keeping the arrow as an entity' {
        # Escaping the joined string would turn the arrow entity into literal
        # text; escaping only the hops keeps both correct.
        $script:tplText2 | Should -Match "hops\.map\(function\(h\) \{ return escapeHtml\(h\); \}\)\.join\(' &#8594; '\)"
    }

    It 'exposes a via-parser filter wired to a data attribute' {
        $script:tplText2 | Should -Match 'data-filter="indirect"'
        $script:tplText2 | Should -Match 'data-indirect="'
        $script:tplText2 | Should -Match "f === 'indirect'"
    }

    It 'keeps the With Impact filter honest by putting the combined total in data-impact' {
        $script:tplText2 | Should -Match 'data-impact="\x27 \+ affectedCount'
    }

    It 'still renders the migration command section after the impact sections' {
        $script:tplText2 | Should -Match 'renderMigrationSection'
        $script:tplText2 | Should -Match ([regex]::Escape('./Invoke-ClassicTableMigration.ps1'))
    }

    It 'surfaces a truncated chain rather than silently under-reporting' {
        $script:tplText2 | Should -Match 'impact\.ChainTruncated'
    }
}

Describe 'report.html.template: resolver-coverage contract' {
    # The chained-dependency list is only as complete as the parser-alias
    # resolver, and the resolver deliberately refuses to follow some aliases.
    # That refusal used to reach the console and nothing else, so the HTML -
    # the artefact that actually gets shared - implied a completeness it did
    # not have. These pin the disclosure.

    BeforeAll {
        $script:tplText3 = Get-Content -Raw -Path (Join-Path (Split-Path -Parent $PSScriptRoot) `
            'Tools/ClassicToDcr/Templates/report.html.template')
    }

    It 'has a mount point for the resolver-coverage section' {
        $script:tplText3 | Should -Match 'id="resolver-coverage"'
        $script:tplText3 | Should -Match 'renderResolverCoverage'
    }

    It 'actually calls the renderer, rather than only defining it' {
        $script:tplText3 | Should -Match '(?m)^renderResolverCoverage\(\);'
    }

    It 'reads the skipped aliases and fan-out warnings the writer emits' {
        $script:tplText3 | Should -Match 'DATA\.AliasResolution'
        $script:tplText3 | Should -Match 'skippedAliases'
        $script:tplText3 | Should -Match 'warnings'
    }

    It 'names the reason a chain was not followed' {
        $script:tplText3 | Should -Match 'escapeHtml\(s\.Reason\)'
    }

    It 'lists the dependents that were therefore not resolved' {
        # A skip without its lost dependents is not actionable: the operator
        # cannot tell whether it cost them nothing or thirty rules.
        $script:tplText3 | Should -Match 's\.Dependents'
        $script:tplText3 | Should -Match 'ReferenceCount'
    }

    It 'normalises UnresolvedBridges so a single-item array does not throw' {
        $script:tplText3 | Should -Match 'i\.UnresolvedBridges = ensureArray\(i\.UnresolvedBridges\)'
    }

    It 'renders a per-table callout for a chain that could not be followed' {
        $script:tplText3 | Should -Match 'could not be followed'
        $script:tplText3 | Should -Match 'impact\.UnresolvedBridges'
    }

    It 'puts the gap ahead of the dependency lists it qualifies' {
        # unshift, not push: reading a dependency list without knowing where it
        # stops is worse than reading no list at all.
        $script:tplText3 | Should -Match 'sections\.unshift[\s\S]{0,400}could not be followed'
    }

    It 'escapes every value it interpolates into the callouts' {
        foreach ($expr in 'escapeHtml\(b\.Alias\)', 'escapeHtml\(b\.Reason\)', 'escapeHtml\(d\.Name\)', 'escapeHtml\(w\)') {
            $script:tplText3 | Should -Match $expr
        }
    }

    It 'says the fan-out warning does not suppress the chain' {
        $script:tplText3 | Should -Match 'still reported in full'
    }

    It 'uses no em-dashes in the new prose' {
        $script:tplText3 | Should -Not -Match ([char]0x2014)
    }
}
