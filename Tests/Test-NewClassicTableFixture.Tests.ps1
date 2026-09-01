#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for the pure helpers in Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1.

.DESCRIPTION
    Covers the two functions whose correctness a live post depends on:

      New-DataCollectorSignature  HMAC-SHA256 SharedKey header. A wrong
                                  signature is a silent 403, and the
                                  content length must be UTF-8 bytes.
      New-FixtureRecord           Synthetic records whose field types drive
                                  the _s / _d / _b / _g classic columns.

    Deliberately not covered: the live POST, the shared-key fetch, and the
    table poll. Those need a real workspace and the retiring Data Collector
    API, so they cannot be unit tested.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-NewClassicTableFixture.Tests.ps1

    Runs the signature and record-shape tests. Needs no workspace.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-NewClassicTableFixture.Tests.ps1 -FullName '*New-DataCollectorSignature*'

    Runs only the HMAC-SHA256 signature assertions, the failure that would
    otherwise present as a silent 403.

.NOTES
    File:         Tests/Test-NewClassicTableFixture.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-07-28
    Version:      0.1.0
    Last Updated: 2026-09-01
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop

    $script:TablesApiVersion        = '2023-09-01'
    $script:DataCollectorApiVersion = '2016-04-01'

    Import-ScriptFunctions -Path $scriptPath
}

Describe 'New-ClassicTableFixture: script-level contract' {
    BeforeAll {
        $script:sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1'
        $script:sourceText = Get-Content -Path $script:sourcePath -Raw
    }

    It 'parses cleanly' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:sourcePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'signs with the UTF-8 byte length, not the character length' {
        # The content length fed to the signature must come from encoded
        # bytes. In the send helper the byte array is built and its .Length
        # passed straight to the signature call.
        $sendFn = [regex]::Match($script:sourceText,
            '(?s)function Send-DataCollectorBatch.*?\n\}').Value
        $sendFn | Should -Match '\$bodyBytes\s*=\s*\[System\.Text\.Encoding\]::UTF8\.GetBytes\(\$body\)'
        $sendFn | Should -Match '-ContentLength\s+\$bodyBytes\.Length'
    }

    It 'never writes the shared key to output' {
        # The key is used in memory only. It must not be echoed or logged.
        $script:sourceText | Should -Not -Match 'Write-.*\$sharedKey'
        $script:sourceText | Should -Not -Match 'Write-.*PrimarySharedKey'
    }

    It 'gates the delete behind ShouldProcess' {
        $script:sourceText | Should -Match 'SupportsShouldProcess'
        $script:sourceText | Should -Match "ShouldProcess\([^)]*'Delete fixture table'\)"
    }

    It 're-signs every batch in the send helper rather than reusing a signature' {
        # x-ms-date is part of the signed string, so a streaming loop that
        # reused one signature would 403 on the second batch. The send helper
        # must compute the date and signature on each call.
        $sendFn = [regex]::Match($script:sourceText,
            '(?s)function Send-DataCollectorBatch.*?\n\}').Value
        $sendFn | Should -Match "ToString\('r'\)"
        $sendFn | Should -Match 'New-DataCollectorSignature'
    }

    It 'streams via the re-signing helper, not an inline single signature' {
        # The streaming loop must call the helper (which re-signs) per batch.
        $script:sourceText | Should -Match 'if \(\$Stream\)'
        $script:sourceText | Should -Match 'Send-DataCollectorBatch'
    }

    It 'uses no em-dashes in prose' {
        $script:sourceText | Should -Not -Match ([char]0x2014)
    }

    It 'has the correct repo-relative header path' {
        $script:sourceText | Should -Match 'File:\s+Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture\.ps1'
        $script:sourceText | Should -Match 'Repository:\s+Sentinel-As-Code'
    }

    It 'is standalone: does not import the Sentinel.Common module' {
        $script:sourceText | Should -Not -Match 'Import-Module[^\r\n]*Sentinel\.Common'
        $script:sourceText | Should -Not -Match 'Sentinel\.Common\.psd1'
        $script:sourceText | Should -Match 'function Write-PipelineMessage'
    }
}

Describe 'New-DataCollectorSignature' {
    BeforeAll {
        # A fixed, syntactically valid base64 key so the HMAC is deterministic.
        $script:key  = [Convert]::ToBase64String([byte[]](1..32))
        $script:wsid = '00000000-0000-0000-0000-000000000000'
        $script:date = 'Mon, 20 Jul 2026 00:00:00 GMT'
    }

    It 'returns a SharedKey header naming the workspace' {
        $sig = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key `
                                          -ContentLength 42 -Rfc1123Date $script:date
        $sig | Should -Match "^SharedKey $($script:wsid):"
    }

    It 'is deterministic for identical inputs' {
        $a = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key -ContentLength 42 -Rfc1123Date $script:date
        $b = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key -ContentLength 42 -Rfc1123Date $script:date
        $a | Should -Be $b
    }

    It 'changes when the content length changes' {
        # Proves the length is actually part of the signed string. If it were
        # ignored, a wrong length would still validate.
        $a = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key -ContentLength 42 -Rfc1123Date $script:date
        $b = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key -ContentLength 43 -Rfc1123Date $script:date
        $a | Should -Not -Be $b
    }

    It 'changes when the date changes' {
        $a = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key -ContentLength 42 -Rfc1123Date $script:date
        $b = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key -ContentLength 42 -Rfc1123Date 'Tue, 21 Jul 2026 00:00:00 GMT'
        $a | Should -Not -Be $b
    }

    It 'produces a hash matching an independent computation of the documented string-to-hash' {
        # Recompute the reference the same way the Data Collector docs
        # specify, and confirm the function agrees byte for byte.
        $len  = 128
        $xh   = "x-ms-date:$($script:date)"
        $sth  = "POST`n$len`napplication/json`n$xh`n/api/logs"
        $hmac = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($script:key))
        try {
            $expected = 'SharedKey {0}:{1}' -f $script:wsid,
                        [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($sth)))
        }
        finally { $hmac.Dispose() }

        $actual = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key `
                                             -ContentLength $len -Rfc1123Date $script:date
        $actual | Should -Be $expected
    }
}

Describe 'New-FixtureRecord' {
    BeforeAll {
        $script:refTime = [datetime]::new(2026, 7, 20, 12, 0, 0, [System.DateTimeKind]::Utc)
        $script:recs    = @(New-FixtureRecord -Count 10 -ReferenceTime $script:refTime -SeedGuid '11111111-1111-1111-1111-111111111111')
    }

    It 'generates the requested number of records' {
        $script:recs.Count | Should -Be 10
    }

    It 'includes a nominated time field, a string, a double, a boolean and a GUID' {
        $r = $script:recs[0]
        $r.Keys | Should -Contain 'Timestamp'   # -> TimeGenerated via header
        $r.Keys | Should -Contain 'SourceHost'  # string -> _s
        $r.Keys | Should -Contain 'DurationMs'  # double -> _d
        $r.Keys | Should -Contain 'Success'     # bool   -> _b
        $r.Keys | Should -Contain 'EventId'     # guid   -> _g
    }

    It 'types the fields so the Data Collector API infers the classic suffixes' {
        $r = $script:recs[0]
        $r.DurationMs | Should -BeOfType [double]
        $r.Success    | Should -BeOfType [bool]
        $r.SourceHost | Should -BeOfType [string]
    }

    It 'emits round-trippable ISO 8601 timestamps' {
        { [datetime]::Parse($script:recs[0].Timestamp) } | Should -Not -Throw
    }

    It 'is deterministic when given a reference time and seed GUID' {
        $again = @(New-FixtureRecord -Count 10 -ReferenceTime $script:refTime -SeedGuid '11111111-1111-1111-1111-111111111111')
        ($again[0] | ConvertTo-Json) | Should -Be ($script:recs[0] | ConvertTo-Json)
    }

    It 'serialises to a JSON array, the shape the Data Collector API expects' {
        $json   = ConvertTo-Json -InputObject @($script:recs) -Depth 5
        $parsed = $json | ConvertFrom-Json
        @($parsed).Count | Should -Be 10
    }
}
