#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-HNT-01: No hunting activity recorded

.DESCRIPTION
    Gap check for rule SAC-HNT-01 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Hunting/Test-HuntingActivityRecorded.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-HNT-01, No hunting activity recorded
# ------------------------------------------------------------
function Test-HuntingActivityRecorded {
    <#
    .SYNOPSIS
        Gap check SAC-HNT-01: No hunting activity recorded

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Both captures must have run: hunts.json is only written on success,
    # and an empty bookmarks list means nothing without it. When the
    # bookmarks list was too large to fetch, the collector keeps the count
    # the service reported in bookmarks-count.json instead.
    $haveBookmarks = ($Inventory.RawFiles -contains 'bookmarks.json') -or ($Inventory.RawFiles -contains 'bookmarks-count.json')
    if ($Inventory.RawFiles -notcontains 'hunts.json' -or -not $haveBookmarks) { return $null }
    $bookmarkCount = @($Inventory.Bookmarks).Count
    if ($Inventory.RawFiles -notcontains 'bookmarks.json' -and $null -ne $Inventory.BookmarksCount) {
        $bookmarkCount = ConvertTo-GapInt (Get-PropOrDefault $Inventory.BookmarksCount 'Count' 0)
    }
    if (@($Inventory.Hunts).Count -eq 0 -and $bookmarkCount -eq 0) {
        return New-Finding -Evidence 'No hunts and no bookmarks exist in the workspace, so there is no record of proactive hunting in Sentinel.' -Detail @{
            Hunts = 0
            Bookmarks = 0
        }
    }
    # Hunts or bookmarks exist: is any of them recent? A workspace can hold
    # hundreds of bookmarks nobody has touched in a year. Fires only when
    # both are known to have had no change in the window; unknown (undated,
    # or a HuntingBookmark table shorter than the window) stays quiet.
    $w = Get-PropOrDefault $Inventory 'Window' $null
    $days = (Get-GapWindow $Inventory).Days
    $asOf = if ($w -and (Get-PropOrDefault $w 'AsOfUtc' $null)) { [datetime]$w.AsOfUtc } else { [datetime]::UtcNow }
    # Assigned rather than returned from an if: an empty array returned from
    # a block becomes $null, which would read as "not captured".
    $fromLogs = $null
    if ($Inventory.RawFiles -contains 'bookmarks-from-logs.json') { $fromLogs = @(Get-PropOrDefault $Inventory 'BookmarksFromLogs' @()) }
    $bookmarkList = $null
    if ($Inventory.RawFiles -contains 'bookmarks.json') { $bookmarkList = @($Inventory.Bookmarks) }
    $activity = Get-HuntingActivity -Bookmarks $bookmarkList -BookmarksCount $Inventory.BookmarksCount -BookmarksFromLogs $fromLogs -Hunts @(
        $Inventory.Hunts
    ) -WorkspaceTables @(Get-PropOrDefault $Inventory 'WorkspaceTables' @()) -WindowDays $days -AsOf $asOf
    if ($activity.BookmarksRecent -ne 0 -or $activity.HuntsRecent -ne 0) { return $null }
    $hunts = @($Inventory.Hunts).Count
    return New-Finding -Evidence "$(Format-BlueprintPlural $bookmarkCount 'bookmark') and $(Format-BlueprintPlural $hunts 'hunt') exist, but none has been created or changed in the last $(Format-GapDays $days), so there is no record of recent proactive hunting in Sentinel." -Detail @{
        Hunts = $hunts
        Bookmarks = $bookmarkCount
        RecentHunts = 0
        RecentBookmarks = 0
        WindowDays = $days
    }
}
