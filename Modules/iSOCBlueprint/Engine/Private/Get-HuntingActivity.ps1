#Requires -Version 7.2

<#
.SYNOPSIS
    How much hunting the workspace shows: its hunts and bookmarks, and how
    many of each were created or changed within the run's window.

.DESCRIPTION
    A workspace can hold hundreds of bookmarks nobody has touched in a year,
    so "bookmarks exist" says little about whether anyone hunts. This counts
    the hunts and bookmarks created or changed within the window the run
    read (its lookback), dated as follows:

      Bookmarks  the API list's created and updated times; or, when the list
                 was refused as too large, the HuntingBookmark table's rows
                 (one a change, kept for the table's retention).
      Hunts      the resource's systemData createdAt and lastModifiedAt.

    A recent count is $null (unknown) when the evidence cannot cover the
    whole window: a hunt or bookmark with no date and none recent, or a
    HuntingBookmark table that keeps fewer days than the window and holds
    nothing recent. Unknown never reads as no activity.

    Rule SAC-HNT-01 and the maturity metric bookmarksRecent read it.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-HuntingActivity.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+

    This file defines functions rather than running.
#>

function Get-HuntingActivityTime {
    <#
    .SYNOPSIS
        The latest of the named date properties on an object (UTC), or
        $null when it has none that parse.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] $Object,
        [string[]] $Names
    )
    if ($null -eq $Object) { return $null }
    $latest = $null
    foreach ($n in $Names) {
        $p = $Object.PSObject.Properties[$n]
        if (-not $p -or -not $p.Value) { continue }
        $t = [datetime]::MinValue
        if ($p.Value -is [datetime]) { $t = $p.Value.ToUniversalTime() }
        elseif (-not [datetime]::TryParse([string]$p.Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$t)) { continue }
        if ($null -eq $latest -or $t -gt $latest) { $latest = $t }
    }
    $latest
}

function Get-HuntingActivity {
    <#
    .SYNOPSIS
        Hunts and bookmarks, in total and created or changed within the
        window.

    .PARAMETER Bookmarks
        The bookmarks API list (bookmarks.json), or $null when it was not
        captured.

    .PARAMETER BookmarksCount
        bookmarks-count.json: the count the service reported when it refused
        the list as too large.

    .PARAMETER BookmarksFromLogs
        bookmarks-from-logs.json: the HuntingBookmark table's bookmarks, or
        $null when the table was not read.

    .PARAMETER Hunts
        hunts.json, or $null when it was not captured.

    .PARAMETER WorkspaceTables
        workspace-tables.json, for the HuntingBookmark table's retention.

    .PARAMETER WindowDays
        The run's lookback.

    .PARAMETER AsOf
        When the run collected (UTC); the window ends here.

    .OUTPUTS
        [pscustomobject] WindowDays, Bookmarks and Hunts (totals, $null when
        not captured), BookmarksRecent and HuntsRecent (created or changed
        within the window, $null when unknown).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] [object[]] $Bookmarks,
        [AllowNull()] $BookmarksCount,
        [AllowNull()] [object[]] $BookmarksFromLogs,
        [AllowNull()] [object[]] $Hunts,
        [AllowNull()] [object[]] $WorkspaceTables,
        [int] $WindowDays = 30,
        [datetime] $AsOf = [datetime]::UtcNow
    )

    $since = $AsOf.ToUniversalTime().AddDays(-$WindowDays)
    # Recent items, or $null when none is recent and some carry no date.
    $recentOf = {
        param([object[]] $Items, [scriptblock] $When)
        $recent = 0; $undated = 0
        foreach ($i in @($Items | Where-Object { $_ })) {
            $t = & $When $i
            if ($null -eq $t) { $undated++ } elseif ($t -ge $since) { $recent++ }
        }
        if ($recent -eq 0 -and $undated -gt 0) { $null } else { $recent }
    }
    $bookmarkTime = { param($b) Get-HuntingActivityTime -Object $(if ($b.PSObject.Properties['properties']) { $b.properties } else { $b }) -Names 'created', 'updated' }

    $bookmarkTotal = $null
    $bookmarkRecent = $null
    if ($null -ne $Bookmarks) {
        $bookmarkTotal = @($Bookmarks | Where-Object { $_ }).Count
        $bookmarkRecent = & $recentOf $Bookmarks $bookmarkTime
    }
    elseif ($null -ne $BookmarksCount -and $BookmarksCount.PSObject.Properties['Count']) {
        $bookmarkTotal = [int]$BookmarksCount.Count
        if ($null -ne $BookmarksFromLogs) {
            $fromLogs = & $recentOf $BookmarksFromLogs $bookmarkTime
            # The table logs every change for its retention, so nothing
            # recent in it means nothing changed, if it keeps the window.
            $table = @($WorkspaceTables | Where-Object { $_ -and [string]$_.name -eq 'HuntingBookmark' }) | Select-Object -First 1
            $keeps = if ($table -and $table.PSObject.Properties['properties'] -and $table.properties.PSObject.Properties['retentionInDays']) { [int]$table.properties.retentionInDays } else { 0 }
            $bookmarkRecent = if ($fromLogs -gt 0) { $fromLogs } elseif ($fromLogs -eq 0 -and $keeps -ge $WindowDays) { 0 } else { $null }
        }
    }

    $huntTotal = $null
    $huntRecent = $null
    if ($null -ne $Hunts) {
        $huntTotal = @($Hunts | Where-Object { $_ }).Count
        $huntRecent = & $recentOf $Hunts { param($h) Get-HuntingActivityTime -Object $(if ($h.PSObject.Properties['systemData']) { $h.systemData } else { $null }) -Names 'createdAt', 'lastModifiedAt' }
    }

    [pscustomobject]@{
        WindowDays      = $WindowDays
        Bookmarks       = $bookmarkTotal
        BookmarksRecent = $bookmarkRecent
        Hunts           = $huntTotal
        HuntsRecent     = $huntRecent
    }
}
