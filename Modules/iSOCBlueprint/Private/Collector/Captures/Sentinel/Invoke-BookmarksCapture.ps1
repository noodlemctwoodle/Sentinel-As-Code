#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'bookmarks': writes bookmarks.json, bookmarks-count.json, bookmarks-from-logs.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-BookmarksCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Invoke-BookmarksCapture {
    <#
    .SYNOPSIS
        Capture 'bookmarks': writes bookmarks.json, bookmarks-count.json, bookmarks-from-logs.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $rawOut = $Context.rawOut
    $sentinelScope = $Context.sentinelScope

    # The list API refuses a response over about 8 MB ("Bookmarks response
    # is too large (N bytes, M items)") and has no paging. The message does
    # carry the item count, which is kept in bookmarks-count.json: the
    # hunting rule, the maturity criterion and the dashboard count from it.
    # The list itself then comes from the HuntingBookmark table, where
    # Sentinel logs every bookmark and each change to it (Microsoft's own
    # route past the portal's 1,000-bookmark view): each bookmark's latest
    # entry, less the deleted ones, without the query text, result row and
    # entities that make the API's answer large. It is written to
    # bookmarks-from-logs.json rather than bookmarks.json because the table
    # keeps only its retention, so it can hold fewer than the service counts.
    try {
        $bm = Invoke-SentinelRest -Path "$sentinelScope/bookmarks" -ApiVersion $apiVersions.Sentinel
        Save-Json -FileName 'bookmarks.json' -Data $bm
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'too large[^)]*?(\d+)\s+items') {
            $count = [int]$Matches[1]
            $kql = @'
HuntingBookmark
| summarize arg_max(TimeGenerated, BookmarkName, CreatedTime, LastUpdatedTime, Tags, Notes, SoftDeleted) by BookmarkId
| where not(coalesce(SoftDeleted, false))
| project BookmarkId, BookmarkName, CreatedTime, LastUpdatedTime, Tags, Notes
'@
            $listed = $null
            $tableError = $null
            try {
                $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $script:WorkspaceObject.properties.customerId -Query (Add-BpWindow $kql) -ErrorAction Stop
                $listed = @($result.Results | ForEach-Object { ConvertFrom-HuntingBookmarkRow -Row $_ })
            } catch { $tableError = $_ }
            # The table's retention, from the tables capture, to say how far
            # back an empty table shows no change.
            $keeps = 0
            $tablesPath = Join-Path $rawOut 'workspace-tables.json'
            if (Test-Path -LiteralPath $tablesPath) {
                try {
                    $hb = @(Get-Content -LiteralPath $tablesPath -Raw | ConvertFrom-Json -Depth 16) | Where-Object { $_ -and $_.PSObject.Properties['name'] -and $_.name -eq 'HuntingBookmark' } | Select-Object -First 1
                    if ($hb -and $hb.PSObject.Properties['properties'] -and $hb.properties.PSObject.Properties['retentionInDays']) { $keeps = [int]$hb.properties.retentionInDays }
                } catch { $keeps = 0 }
            }
            $period = if ($keeps -gt 0) { "in the last $keeps days" } else { 'within the table''s retention' }
            # Why first, then the files it leads to.
            if ($tableError) {
                $tableMsg = Get-CaptureErrorText $tableError
                $tableKind = Get-CaptureIssueKind $tableMsg
                Write-CaptureNote -Kind $tableKind -Label 'bookmarks' -Text "$count bookmarks exist, too many for the API to list, and the HuntingBookmark table could not be read: $(Format-CaptureMessage $tableMsg) Kept the count."
                $script:CaptureErrors.Add([pscustomobject]@{ Label = 'bookmarks'; Kind = $tableKind; Message = "$count bookmarks exist, too many for the API to list, and the HuntingBookmark table could not be read, so only the count was kept: $tableMsg" })
            } elseif ($listed.Count -eq 0) {
                # Read, but empty: the table logs every bookmark change for its
                # retention, so none of them has changed in that time.
                Write-CaptureNote -Kind NotAvailable -Text "$count bookmarks exist, too many for the API to list, and none has been created or changed $period (the HuntingBookmark table, which logs every change, holds none). Kept the count."
                $script:CaptureErrors.Add([pscustomobject]@{ Label = 'bookmarks'; Kind = 'NotAvailable'; Message = "$count bookmarks exist, too many for the API to list, and none has been created or changed ${period}: the HuntingBookmark table, which logs every change, holds none. Only the count was kept." })
            } else {
                Write-Information "  ↳ $count bookmarks exist, too many for the API to list; listed the $($listed.Count) in the HuntingBookmark table instead."
            }
            Save-Json -FileName 'bookmarks-count.json' -Data ([pscustomobject]@{ Count = $count; Source = 'The bookmarks list was refused as too large; the count is the one the service reported.' })
            if (-not $tableError) { Save-Json -FileName 'bookmarks-from-logs.json' -Data $listed }
        } else {
            throw
        }
    }
}
