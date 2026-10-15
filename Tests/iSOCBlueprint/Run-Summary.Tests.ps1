#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for what a Blueprint run prints when it ends.

.DESCRIPTION
    A run under an identity without every role loses some captures. The
    collector sorts each failure into a refusal for want of permission or
    another error, says so in one short line as it goes (one line for a
    capture that could not read some of its items, not one an item), and
    lists them apart in the capture summary. The renderer and the site build
    each end in one line, and New-iSOCBlueprint closes the run with a short
    summary. These tests hold each of those.

.NOTES
    File:         Tests/iSOCBlueprint/Run-Summary.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $engine = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine'
    . (Join-Path $engine 'Private/Write-CaptureSummary.ps1')
    $script:collector = Get-Content (Join-Path $engine 'Export-SentinelInventory.ps1') -Raw
    $script:renderer = Get-Content (Join-Path $engine 'Convert-SentinelInventoryToMarkdown.ps1') -Raw
    $script:siteBuild = Get-Content (Join-Path $engine 'SharePoint/Build-SentinelDocsSite.ps1') -Raw
    $script:fixtureRaw = Join-Path $script:repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
    $script:graph403 = "Microsoft Graph refused Defender custom detections to the Graph SDK session (Forbidden). To include them, Connect-MgGraph -Scopes 'CustomDetection.Read.All' with an account allowed to read custom detections, or grant CustomDetection.Read.All (application) to the pipeline identity."
    $script:http401 = 'Response status code does not indicate success: 401 (Unauthorized).'
}

Describe 'Sorting a failed capture' {
    It 'calls a refusal for want of permission a permission issue' {
        Get-CaptureIssueKind $script:graph403 | Should -Be 'Permission'
        Get-CaptureIssueKind $script:http401 | Should -Be 'Permission'
        Get-CaptureIssueKind "The client 'x' with object id 'y' does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/read' (AuthorizationFailed)" | Should -Be 'Permission'
    }

    It 'calls anything else an error' {
        Get-CaptureIssueKind 'Response status code does not indicate success: 404 (Not Found).' | Should -Be 'Error'
        Get-CaptureIssueKind 'The operation has timed out.' | Should -Be 'Error'
    }

    It 'names the status the error carries' {
        Get-CaptureStatusText $script:http401 | Should -Be '401 Unauthorized'
        Get-CaptureStatusText 'Response status code does not indicate success: Forbidden (Forbidden).' | Should -Be 'Forbidden'
        Get-CaptureStatusText $script:graph403 | Should -Be 'Forbidden'
        Get-CaptureStatusText 'The operation has timed out.' | Should -BeNullOrEmpty
    }

    It 'drops the HTTP client wording and doubled full stops' {
        Format-CaptureMessage 'Graph refused it: Response status code does not indicate success: Forbidden (Forbidden).. Sign in again.' | Should -Be 'Graph refused it: Forbidden. Sign in again.'
    }

    It 'wraps a message under a hanging indent within the width' {
        $lines = @(Format-WrappedText -Text ('word ' * 40) -Indent 8 -Width 60)
        $lines.Count | Should -BeGreaterThan 3
        foreach ($l in $lines) { $l.Length | Should -BeLessOrEqual 60; $l | Should -Match '^ {8}\S' }
    }
}

Describe 'A capture that could not read some of its items' {
    BeforeAll {
        $fails = @('Add-IncidentTasks', 'Get-DeviceHealthStatus') | ForEach-Object { [pscustomobject]@{ Name = $_; Message = $script:http401 } }
        $script:partial = @(Write-PartialCaptureIssue -Label 'playbook-runs' -What 'the run history of' -Noun 'playbook', 'playbooks' -Total 12 -Failures $fails -WarningVariable partialWarn -WarningAction SilentlyContinue)
        $script:partialWarn = @($partialWarn)
    }

    It 'warns once, naming the items, the count and the status' {
        @($script:partialWarn).Count | Should -Be 1
        [string]$script:partialWarn[0] | Should -Be '[playbook-runs] No permission to read the run history of 2 of 12 playbooks (401 Unauthorized): Add-IncidentTasks, Get-DeviceHealthStatus.'
    }

    It 'returns one permission issue for the summary' {
        $script:partial.Count | Should -Be 1
        $script:partial[0].Kind | Should -Be 'Permission'
        $script:partial[0].Label | Should -Be 'playbook-runs'
    }

    It 'keeps other errors apart, with the first of their messages' {
        $mixed = @(
            [pscustomobject]@{ Name = 'A'; Message = $script:http401 }
            [pscustomobject]@{ Name = 'B'; Message = 'The operation has timed out.' }
        )
        $issues = @(Write-PartialCaptureIssue -Label 'playbook-runs' -What 'the run history of' -Noun 'playbook', 'playbooks' -Total 1 -Failures $mixed -WarningAction SilentlyContinue)
        $issues.Count | Should -Be 2
        ($issues | Where-Object Kind -eq 'Error').Message | Should -Match 'Could not read the run history of 1 of 1 playbook: B\. First error: The operation has timed out\.'
    }

    It 'says nothing when every item was read' {
        @(Write-PartialCaptureIssue -Label 'playbook-runs' -What 'the run history of' -Noun 'playbook', 'playbooks' -Total 4 -Failures @() -WarningVariable none -WarningAction SilentlyContinue).Count | Should -Be 0
        @($none).Count | Should -Be 0
    }
}

Describe 'The capture summary' {
    BeforeAll {
        $script:sumRaw = Join-Path ([System.IO.Path]::GetTempPath()) "bp-summary-$(New-Guid)"
        Copy-Item -Path $script:fixtureRaw -Destination $script:sumRaw -Recurse
        '[]' | Set-Content (Join-Path $script:sumRaw 'watchlists.json')
        $issues = @(
            [pscustomobject]@{ Label = 'defender-custom-detections'; Kind = 'Permission'; Message = $script:graph403 }
            [pscustomobject]@{ Label = 'dcrs'; Kind = 'Error'; Message = 'The operation has timed out.' }
        )
        $saved = $env:TF_BUILD
        $env:TF_BUILD = $null
        $script:summary = (Write-CaptureSummary -RawRoot $script:sumRaw -Issues $issues -ExpectNonEmpty 'workspace.json' -ExpectIfActive 'watchlists.json', 'playbook-runs.json' 6>&1 | Out-String)
        $env:TF_BUILD = 'True'
        $script:summaryAdo = (Write-CaptureSummary -RawRoot $script:sumRaw -Issues $issues -ExpectNonEmpty 'workspace.json' 6>&1 | Out-String)
        $env:TF_BUILD = $saved
    }

    AfterAll {
        if ($script:sumRaw -and (Test-Path $script:sumRaw)) { Remove-Item $script:sumRaw -Recurse -Force }
    }

    It 'lists the permission refusals as expected, apart from failures' {
        $script:summary | Should -Match 'No access\s+1 capture\(s\) not read in full for want of a role or permission\.'
        $script:summary | Should -Match 'Expected where the signed-in account or pipeline identity was not'
        $script:summary | Should -Match '(?s)No access.*defender-custom-detections.*Failed\s+1 capture\(s\) raised an error.*dcrs'
    }

    It 'wraps each message under its capture' {
        $script:summary | Should -Match '\n {4}defender-custom-detections\r?\n {8}Microsoft Graph refused'
    }

    It 'lists only the key captures that hold no data' {
        $script:summary | Should -Match 'Key data\s+1 of 3 key captures hold no data:'
        $script:summary | Should -Match 'watchlists\.json\s+empty'
        $script:summary | Should -Not -Match 'playbook-runs\.json\s+empty'
    }

    It 'annotates the headlines only on a pipeline agent' {
        $script:summary | Should -Not -Match '##\[warning\]'
        $script:summaryAdo | Should -Match '##\[section\]Capture summary'
        $script:summaryAdo | Should -Match '##\[warning\]  No access'
    }
}

Describe 'The collector as it runs' {
    It 'sorts each failed capture and keeps the line short for a permission refusal' {
        $script:collector | Should -Match '\$kind = Get-CaptureIssueKind \$msg'
        $script:collector | Should -Match 'Skipped, no permission\$\(if \(\$status\)'
        $script:collector | Should -Match 'Kind\s+= \$kind'
    }

    It 'warns once for the playbooks it could not read, not once each' {
        $script:collector | Should -Not -Match 'Write-Warning "Run history for playbook'
        $script:collector | Should -Not -Match 'Write-Warning "RBAC enumeration for playbook'
        $script:collector | Should -Match 'Write-PartialCaptureIssue -Label ''playbook-runs'' -What ''the run history of'''
        $script:collector | Should -Match 'Write-PartialCaptureIssue -Label ''playbooks'' -What ''the role assignments of'''
    }

    It 'records the issues in run-context.json and ends with the summary' {
        $script:collector | Should -Match 'Add-Member -MemberType NoteProperty -Name CaptureIssues -Value @\(\$script:CaptureErrors\)'
        $script:collector | Should -Match 'Write-CaptureSummary -RawRoot \$rawOut -Issues @\(\$script:CaptureErrors\)'
        $script:collector.IndexOf('Name CaptureIssues') | Should -BeLessThan $script:collector.IndexOf('Write-CaptureSummary -RawRoot')
    }
}

Describe 'The renderer and the site build as they end' {
    It 'lists pages only under -Verbose and ends in one line' {
        $script:renderer | Should -Not -Match 'Write-Information "  ↳ rendered'
        $script:renderer | Should -Match 'Write-Verbose "rendered \$FileName"'
        $script:renderer | Should -Match 'Write-Information "Report: \$\(\$rendered -join'
    }

    It 'notes the long tables once, as a display limit' {
        $script:siteBuild | Should -Match 'Long tables: \$\(\$cappedTables\.Count\) table\(s\) longer than'
        $script:siteBuild | Should -Match 'the dashboard''s Sections tab has every row'
    }
}

Describe 'The run summary New-iSOCBlueprint prints' {
    BeforeAll {
        Import-Module (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/iSOCBlueprint.psd1') -Force
        $script:runDir = Join-Path ([System.IO.Path]::GetTempPath()) "bp-run-$(New-Guid)"
        New-Item -ItemType Directory -Path (Join-Path $script:runDir '_raw'), (Join-Path $script:runDir 'sections'), (Join-Path $script:runDir 'sharepoint') -Force | Out-Null
        @{ CaptureIssues = @(
            @{ Label = 'defender-custom-detections'; Kind = 'Permission'; Message = 'x' }
            @{ Label = 'playbook-runs'; Kind = 'Permission'; Message = 'y' }
            @{ Label = 'dcrs'; Kind = 'Error'; Message = 'z' }
        ) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:runDir '_raw/run-context.json')
        '{}' | Set-Content (Join-Path $script:runDir '_raw/workspace.json')
        foreach ($n in '00-overview', '10-data-connectors') {
            'x' | Set-Content (Join-Path $script:runDir "$n.md")
            '{}' | Set-Content (Join-Path $script:runDir "sections/$n.json")
        }
        'x' | Set-Content (Join-Path $script:runDir 'index.md')
        '{}' | Set-Content (Join-Path $script:runDir 'sections/index.json')
        @{ sections = @(1, 2); summary = @{ findings = 7 } } | ConvertTo-Json | Set-Content (Join-Path $script:runDir 'sharepoint/site.json')
        $script:runText = & (Get-Module iSOCBlueprint) {
            param($p) Write-iSOCBlueprintRunSummary -Path $p -Elapsed ([timespan]::FromSeconds(2475)) -Collected $true -SiteBundle (Join-Path $p 'sharepoint') 6>&1 | Out-String
        } $script:runDir
        $script:reusedText = & (Get-Module iSOCBlueprint) {
            param($p) Write-iSOCBlueprintRunSummary -Path $p -Elapsed ([timespan]::FromSeconds(12)) -Collected $false 6>&1 | Out-String
        } $script:runDir
    }

    AfterAll {
        if ($script:runDir -and (Test-Path $script:runDir)) { Remove-Item $script:runDir -Recurse -Force }
    }

    It 'says how long the run took and where it went' {
        $script:runText | Should -Match 'iSOC Blueprint finished in 41m 15s'
        $script:runText | Should -Match ('Folder\s+' + [regex]::Escape($script:runDir))
    }

    It 'lists the captures with no permission as expected, apart from failures' {
        $script:runText | Should -Match 'Captures\s+2 files written'
        $script:runText | Should -Match '2 not read in full, no permission \(expected without the role\): defender-custom-detections, playbook-runs'
        $script:runText | Should -Match '1 failed: dcrs'
    }

    It 'counts the pages without the contents page, and shows the bundle under the run folder' {
        $script:runText | Should -Match 'Report\s+2 Markdown pages, 2 JSON sections'
        $script:runText | Should -Match 'SharePoint\s+sharepoint \(2 pages, 7 findings\), not published \(no -SiteUrl\)'
    }

    It 'says the inventory was reused under -SkipCollection' {
        $script:reusedText | Should -Match 'finished in 12s'
        $script:reusedText | Should -Match 'Captures\s+2 files, reused \(-SkipCollection\)'
    }

    It 'shows only the workspace and folder of the returned object by default' {
        @((Get-TypeData 'iSOCBlueprint.Blueprint').DefaultDisplayPropertySet.ReferencedProperties) | Should -Be @('WorkspaceName', 'Path')
    }
}
