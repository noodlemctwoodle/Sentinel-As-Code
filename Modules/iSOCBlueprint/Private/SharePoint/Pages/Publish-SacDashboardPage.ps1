#Requires -Version 7.6

<#
.SYNOPSIS
    Create or update the dashboard page.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Pages/Publish-SacDashboardPage.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Publish-SacDashboardPage {
    <#
    .SYNOPSIS
        Make sure the dashboard page exists with the web part pointing at
        the uploaded dashboard, publish it and make it the home page.

    .PARAMETER PageName
        Page name without .aspx.

    .PARAMETER Title
        Page title.

    .PARAMETER FileRelativeUrl
        Site-relative path of the dashboard HTML, as the web part expects.

    .PARAMETER WebPartWaitSeconds
        How long to keep retrying when a freshly deployed web part is not
        available on the site yet.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $PageName,
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] [string] $FileRelativeUrl,
        [int] $WebPartWaitSeconds = 300
    )

    if (-not $PSCmdlet.ShouldProcess("SitePages/$PageName.aspx", 'Publish dashboard page and set as home')) { return }

    # isFullWidth: when PnP loads a saved page it decides whether a custom web
    # part may sit in a full-width section from this property alone (it reads
    # supportsFullBleed from the manifest only when the web part is first
    # added). Without it every later save of the page, even setting its title,
    # fails with "You cannot host text controls inside a one column full
    # width section". The web part itself ignores the property.
    $properties = @{ fileRelativeUrl = $FileRelativeUrl; isFullWidth = $true }
    $page = Get-PnPPage -Identity $PageName -ErrorAction SilentlyContinue
    $existing = $null
    if ($page) {
        $existing = Get-PnPPageComponent -Page $PageName -ErrorAction SilentlyContinue |
            Where-Object { ([string]$_.WebPartId).Trim('{}').ToLowerInvariant() -eq $script:SacWebPartComponentId } |
            Select-Object -First 1
        if ($existing -and -not (Test-SacFullWidthProperty -PropertiesJson ([string]$existing.PropertiesJson))) {
            # Placed without isFullWidth, so PnP can no longer save this page.
            # It holds only the dashboard web part, so rebuild it.
            Write-Host "  Rebuilding $PageName.aspx: its dashboard web part predates the full-width property."
            Remove-PnPPage -Identity $PageName -Recycle -Force | Out-Null
            $page = $null
            $existing = $null
        }
    }
    if (-not $page) {
        Add-PnPPage -Name $PageName -LayoutType Article -Title $Title | Out-Null
        Set-PnPPage -Identity $PageName -HeaderType None | Out-Null
    }

    if ($existing) {
        Set-PnPPageWebPart -Page $PageName -Identity $existing.InstanceId -PropertiesJson ($properties | ConvertTo-Json -Compress) | Out-Null
    }
    else {
        # Reuse a full-width section an earlier, failed run left on the page,
        # so a re-run does not stack a second one.
        $sectionIndex = 0
        if ($page) {
            $sections = @($page.Sections)
            for ($i = 0; $i -lt $sections.Count; $i++) {
                if ([string]$sections[$i].Type -eq 'OneColumnFullWidth') { $sectionIndex = $i + 1; break }
            }
        }
        if ($sectionIndex -eq 0) {
            Add-PnPPageSection -Page $PageName -SectionTemplate OneColumnFullWidth -Order 1 | Out-Null
            $sectionIndex = 1
        }

        # Pass the component object, not its id. Add-PnPPageWebPart matches an
        # id string exactly, SharePoint can return the id in braces or another
        # case, and a miss becomes an empty web part that PnP refuses in a
        # full-width section ("You cannot host text controls inside a one
        # column full width section"). A web part deployed moments ago can take
        # a few minutes to show up in the site's component list.
        $deadline = (Get-Date).AddSeconds($WebPartWaitSeconds)
        while ($true) {
            $component = Get-PnPAvailablePageComponents -Page $PageName -ErrorAction SilentlyContinue |
                Where-Object { ([string]$_.Id).Trim('{}').ToLowerInvariant() -eq $script:SacWebPartComponentId } |
                Select-Object -First 1
            if ($component) {
                Add-PnPPageWebPart -Page $PageName -Component $component -WebPartProperties $properties -Section $sectionIndex -Column 1 -ErrorAction Stop |
                    Out-Null
                break
            }
            if ((Get-Date) -ge $deadline) {
                throw "Dashboard web part $script:SacWebPartComponentId is not in the site's component list after $WebPartWaitSeconds seconds. Check that the app package is deployed to this site's app catalog."
            }
            Write-Host '  Dashboard web part not available yet; retrying in 20 seconds...'
            Start-Sleep -Seconds 20
        }
    }

    Set-PnPPage -Identity $PageName -Title $Title -Publish | Out-Null
    Set-PnPHomePage -RootFolderRelativeUrl "SitePages/$PageName.aspx" | Out-Null
}
