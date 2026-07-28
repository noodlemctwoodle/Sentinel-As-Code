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

    Deliberately not covered: the ARM calls, the Content Hub package fetch, and
    the HTML/CSV/JSON writers. Those need a live workspace.
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
        $script:sourceText | Should -Match 'Sentinel-As-Code/Tools/ClassicToDcr/Invoke-TableMigrationReview\.ps1'
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
}
