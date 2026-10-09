#Requires -Version 7.2

<#
.SYNOPSIS
    Thin SharePoint (PnP.PowerShell) wrappers for the iSOC Blueprint site
    publisher.

.DESCRIPTION
    Each function does one SharePoint job (make sure the findings list
    exists, publish one page, rebuild the navigation, ...) and nothing
    else. Decisions about what to do live in Get-SacSyncPlan.ps1. Every
    function that changes the site supports -WhatIf / -Confirm and inherits
    the caller's preference, so Publish-SentinelDocsSite.ps1 -WhatIf reads
    the site but writes nothing.

    The functions assume an open PnP connection (Connect-PnPOnline) and are
    only dot-sourced by the publisher and the bootstrap. Tests dot-source
    the pure helpers here (Resolve-SacSiteUrl, Get-SacAppPackageInfo,
    ConvertTo-SacNavigationTree, Add-SacMaturityHistoryEntry) without PnP
    installed.

.NOTES
    File:         Tools/Documenter/SharePoint/Private/SacSharePoint.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.2.0
    Last Updated: 2026-10-09
    Requires:     PowerShell 7.2+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Names the generator owns on the site. Changing one strands what earlier
# runs created, so treat them as fixed.
$script:SacAssetsLibraryTitle = 'Documenter Assets'
$script:SacAssetsLibraryUrl   = 'DocumenterAssets'
$script:SacFindingsListTitle  = 'Sentinel Findings'
$script:SacFindingsListUrl    = 'Lists/SentinelFindings'
$script:SacStateFile          = 'publish-state.json'
$script:SacMaturityHistoryFile = 'maturity-history.json'
$script:SacWebPartComponentId = 'a2fd5aa3-01c5-431e-8c98-66f76c89803a'
$script:SacLinklessHeaderUrl  = 'http://linkless.header/'

# Findings list columns: internal name -> PnP field type.
$script:SacFindingFields = [ordered]@{
    FindingId    = 'Text'
    Severity     = 'Text'
    SeverityRank = 'Number'
    Category     = 'Text'
    Status       = 'Text'
    Evidence     = 'Note'
    Remediation  = 'Note'
    Learn        = 'URL'
    FirstSeen    = 'DateTime'
    LastSeen     = 'DateTime'
    ResolvedOn   = 'DateTime'
}

# ---------------------------------------------------------------------------
# Pure helpers (no SharePoint calls)
# ---------------------------------------------------------------------------

function Resolve-SacSiteUrl {
    <#
    .SYNOPSIS
        Replace the '~site/' prefix the build uses with the web's
        server-relative URL.

    .PARAMETER Text
        HTML or a URL that may contain '~site/' tokens.

    .PARAMETER WebServerRelativeUrl
        The web's server-relative URL, for example '/sites/isoc-prod'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [string] $WebServerRelativeUrl
    )
    $base = $WebServerRelativeUrl.TrimEnd('/')
    return $Text.Replace('~site/', "$base/")
}

function Get-SacAppPackageInfo {
    <#
    .SYNOPSIS
        Read the product id, version and title from an SPFx .sppkg.

    .DESCRIPTION
        An .sppkg is a zip with AppManifest.xml at its root. Its <App>
        element carries ProductID and Version, which is what the app
        catalog reports back, so the publisher can tell whether the
        deployed package is current without uploading it.

    .PARAMETER Path
        Path to the .sppkg file.

    .OUTPUTS
        [pscustomobject] ProductId (string, lower case), Version (string),
        Title (string).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'AppManifest.xml' } | Select-Object -First 1
        if (-not $entry) { throw "No AppManifest.xml in '$Path'; is it an SPFx .sppkg?" }
        $reader = [System.IO.StreamReader]::new($entry.Open())
        try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally { $zip.Dispose() }

    $app = $manifest.App
    $title = if ($app.Properties -and $app.Properties.Title) { [string]$app.Properties.Title } else { [string]$app.Name }
    return [pscustomobject]@{
        ProductId = ([string]$app.ProductID).Trim('{}').ToLowerInvariant()
        Version   = [string]$app.Version
        Title     = $title
    }
}

function ConvertTo-SacNavigationTree {
    <#
    .SYNOPSIS
        Turn navigation nodes read from SharePoint into the planner's
        @{ title; url; children } shape, with URLs in '~site/' form.

    .PARAMETER Nodes
        Objects with Title, Url and Children (as Get-PnPNavigationNode
        -Tree returns them).

    .PARAMETER WebServerRelativeUrl
        The web's server-relative URL, used to rewrite URLs back to the
        '~site/' prefix so they compare with the plan.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Nodes,
        [Parameter(Mandatory)] [string] $WebServerRelativeUrl
    )

    $base = $WebServerRelativeUrl.TrimEnd('/')
    $out = foreach ($n in $Nodes) {
        $url = [string]$n.Url
        if ($url -eq $script:SacLinklessHeaderUrl -or $url -eq $script:SacLinklessHeaderUrl.TrimEnd('/')) { $url = $null }
        elseif ($url) {
            # Absolute URLs come back for some nodes; reduce to server-relative.
            if ($url -match '^https?://[^/]+(?<path>/.*)$') { $url = $Matches['path'] }
            if ($url.StartsWith("$base/", [StringComparison]::OrdinalIgnoreCase)) { $url = '~site/' + $url.Substring($base.Length + 1) }
        }
        $kids = @()
        # No @() around the call: the function returns its array as a single
        # object, and wrapping it would nest the array one level deeper.
        if ($n.Children) { $kids = ConvertTo-SacNavigationTree -Nodes @($n.Children) -WebServerRelativeUrl $WebServerRelativeUrl }
        [ordered]@{ title = [string]$n.Title; url = $url; children = $kids }
    }
    return , @($out)
}

# ---------------------------------------------------------------------------
# SharePoint functions (need an open PnP connection)
# ---------------------------------------------------------------------------

function Initialize-SacSiteStructure {
    <#
    .SYNOPSIS
        Make sure the assets library, its folders and the findings list
        (with its columns) exist. Idempotent.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not (Get-PnPList -Identity $script:SacAssetsLibraryUrl -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($script:SacAssetsLibraryUrl, 'Create assets library')) {
            New-PnPList -Title $script:SacAssetsLibraryTitle -Template DocumentLibrary -Url $script:SacAssetsLibraryUrl -EnableVersioning | Out-Null
        }
    }
    foreach ($folder in 'dashboard', 'diagrams', '_state') {
        if ($PSCmdlet.ShouldProcess("$script:SacAssetsLibraryUrl/$folder", 'Ensure folder')) {
            Resolve-PnPFolder -SiteRelativePath "$script:SacAssetsLibraryUrl/$folder" | Out-Null
        }
    }

    $list = Get-PnPList -Identity $script:SacFindingsListUrl -ErrorAction SilentlyContinue
    if (-not $list) {
        if ($PSCmdlet.ShouldProcess($script:SacFindingsListUrl, 'Create findings list')) {
            $list = New-PnPList -Title $script:SacFindingsListTitle -Template GenericList -Url $script:SacFindingsListUrl -EnableVersioning
        }
    }
    if (-not $list) { return }

    foreach ($name in $script:SacFindingFields.Keys) {
        if (Get-PnPField -List $script:SacFindingsListUrl -Identity $name -ErrorAction SilentlyContinue) { continue }
        if ($PSCmdlet.ShouldProcess("$script:SacFindingsListUrl/$name", 'Add column')) {
            Add-PnPField -List $script:SacFindingsListUrl -DisplayName $name -InternalName $name -Type $script:SacFindingFields[$name] -AddToDefaultView | Out-Null
            if ($name -eq 'FindingId') {
                Set-PnPField -List $script:SacFindingsListUrl -Identity $name -Values @{ Indexed = $true } | Out-Null
            }
        }
    }
}

function Publish-SacAppPackage {
    <#
    .SYNOPSIS
        Deploy the dashboard web part's .sppkg to the site collection app
        catalog when the deployed version differs.

    .DESCRIPTION
        The package is built with skipFeatureDeployment, so publishing it
        to the site's own app catalog makes the web part available on this
        site immediately; no per-site install step is needed.

    .PARAMETER Path
        Path to the .sppkg.

    .OUTPUTS
        [string] The package version now deployed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Path)

    $info = Get-SacAppPackageInfo -Path $Path
    $deployed = Get-PnPApp -Scope Site -ErrorAction SilentlyContinue |
        Where-Object { ([string]$_.Id).Trim('{}').ToLowerInvariant() -eq $info.ProductId } |
        Select-Object -First 1
    $deployedVersion = if ($deployed -and $deployed.AppCatalogVersion) { [string]$deployed.AppCatalogVersion } else { '' }

    if ($deployedVersion -eq $info.Version -and -not $deployed.CanUpgrade) {
        Write-Host "  App package $($info.Version) already deployed."
        return $info.Version
    }
    if ($PSCmdlet.ShouldProcess("$($info.Title) $($info.Version) (deployed: $(if ($deployedVersion) { $deployedVersion } else { 'none' }))", 'Deploy to site collection app catalog')) {
        Add-PnPApp -Path $Path -Scope Site -Overwrite -Publish -SkipFeatureDeployment | Out-Null
        Write-Host "  Deployed app package $($info.Version)."
    }
    return $info.Version
}

function Send-SacFile {
    <#
    .SYNOPSIS
        Upload one local file into a folder of the assets library.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Folder
    )
    $target = "$script:SacAssetsLibraryUrl/$Folder"
    if ($PSCmdlet.ShouldProcess("$target/$(Split-Path $Path -Leaf)", 'Upload')) {
        Add-PnPFile -Path $Path -Folder $target | Out-Null
    }
}

function Get-SacFolderFileNames {
    <#
    .SYNOPSIS
        Names of the files in one folder of the assets library, or an empty
        array when the folder does not exist yet.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string] $Folder)
    $items = Get-PnPFolderItem -FolderSiteRelativeUrl "$script:SacAssetsLibraryUrl/$Folder" -ItemType File -ErrorAction SilentlyContinue
    return , @($items | ForEach-Object { [string]$_.Name })
}

function Read-SacPublishState {
    <#
    .SYNOPSIS
        Read the state the last successful publish left behind (page hashes,
        navigation signature, app version), or an empty state.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $state = @{ pages = @{}; navSignature = ''; appVersion = '' }
    try {
        $text = Get-PnPFile -Url "$script:SacAssetsLibraryUrl/_state/$script:SacStateFile" -AsString -ErrorAction Stop
        if ($text) {
            $parsed = $text | ConvertFrom-Json -AsHashtable
            if ($parsed.pages) { $state.pages = $parsed.pages }
            if ($parsed.navSignature) { $state.navSignature = [string]$parsed.navSignature }
            if ($parsed.appVersion) { $state.appVersion = [string]$parsed.appVersion }
        }
    }
    catch {
        Write-Verbose "No publish state yet: $($_.Exception.Message)"
    }
    return $state
}

function Save-SacPublishState {
    <#
    .SYNOPSIS
        Write the publish state file into the assets library.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [hashtable] $State)
    $json = $State | ConvertTo-Json -Depth 8
    if ($PSCmdlet.ShouldProcess("$script:SacAssetsLibraryUrl/_state/$script:SacStateFile", 'Save publish state')) {
        Add-PnPFile -Folder "$script:SacAssetsLibraryUrl/_state" -FileName $script:SacStateFile -Content $json | Out-Null
    }
}

function Read-SacMaturityHistory {
    <#
    .SYNOPSIS
        Read the maturity score history the earlier publishes left behind,
        or an empty history.

    .OUTPUTS
        [hashtable] @{ entries = @(...) }, oldest first.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $history = @{ entries = @() }
    try {
        $text = Get-PnPFile -Url "$script:SacAssetsLibraryUrl/_state/$script:SacMaturityHistoryFile" -AsString -ErrorAction Stop
        if ($text) {
            $parsed = $text | ConvertFrom-Json -AsHashtable
            if ($parsed.entries) { $history.entries = @($parsed.entries) }
        }
    }
    catch {
        Write-Verbose "No maturity history yet: $($_.Exception.Message)"
    }
    return $history
}

function Add-SacMaturityHistoryEntry {
    <#
    .SYNOPSIS
        Return a new history with one entry appended: the same bundle
        published twice replaces its earlier entry, and the oldest entries
        are dropped past -MaxEntries. Pure; the input is not changed.

    .PARAMETER History
        @{ entries = @(...) } as Read-SacMaturityHistory returns it.

    .PARAMETER Entry
        A hashtable with at least bundleBuiltUtc, publishedUtc and overall.

    .PARAMETER MaxEntries
        How many entries to keep. Defaults to 180 (half a year of daily runs).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [hashtable] $History,
        [Parameter(Mandatory)] [hashtable] $Entry,
        [Parameter()] [ValidateRange(1, 10000)] [int] $MaxEntries = 180
    )
    $key = [string]$Entry.bundleBuiltUtc
    $kept = @($History.entries | Where-Object { $_ -and ([string]$_.bundleBuiltUtc) -ne $key })
    $entries = @($kept) + @($Entry)
    if ($entries.Count -gt $MaxEntries) { $entries = @($entries | Select-Object -Last $MaxEntries) }
    return @{ entries = $entries }
}

function Save-SacMaturityHistory {
    <#
    .SYNOPSIS
        Write the maturity history to _state/ (the record) and to dashboard/
        (what the dashboard fetches from beside its own page).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [hashtable] $History)
    $json = $History | ConvertTo-Json -Depth 8
    foreach ($folder in '_state', 'dashboard') {
        if ($PSCmdlet.ShouldProcess("$script:SacAssetsLibraryUrl/$folder/$script:SacMaturityHistoryFile", 'Save maturity history')) {
            Add-PnPFile -Folder "$script:SacAssetsLibraryUrl/$folder" -FileName $script:SacMaturityHistoryFile -Content $json | Out-Null
        }
    }
}

function Get-SacGeneratedPageNames {
    <#
    .SYNOPSIS
        Names (without .aspx) of the generated section pages in Site Pages:
        every page whose file name starts with 'sac-'.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $items = Get-PnPListItem -List 'SitePages' -PageSize 500 -Fields 'FileLeafRef'
    return , @($items |
        ForEach-Object { [string]$_.FieldValues['FileLeafRef'] } |
        Where-Object { $_ -match '^sac-.+\.aspx$' } |
        ForEach-Object { $_ -replace '\.aspx$', '' })
}

function Publish-SacSectionPage {
    <#
    .SYNOPSIS
        Create or rebuild one generated section page and publish it.

    .DESCRIPTION
        The page canvas is cleared and rebuilt through the PnP Core page
        object, so the whole page is saved and published once rather than
        once per web part. Rebuilding in place (rather than deleting and
        recreating) keeps the page URL and its version history, and a
        failed publish leaves the last published version live.

    .PARAMETER PageDoc
        One page document from the bundle's pages/ folder.

    .PARAMETER Create
        Create the page first (it does not exist yet).

    .PARAMETER WebServerRelativeUrl
        The web's server-relative URL, for links and image paths.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $PageDoc,
        [switch] $Create,
        [Parameter(Mandatory)] [string] $WebServerRelativeUrl
    )

    $name = [string]$PageDoc.name
    if (-not $PSCmdlet.ShouldProcess("SitePages/$name.aspx", $(if ($Create) { 'Create and publish page' } else { 'Rebuild and publish page' }))) { return }

    $page = if ($Create) {
        Add-PnPPage -Name $name -LayoutType Article -Title ([string]$PageDoc.title)
    }
    else {
        Get-PnPPage -Identity $name
    }

    $page.PageTitle = [string]$PageDoc.title
    $page.ClearPage()
    $page.AddSection('OneColumn', 1, $null)
    $column = $page.Sections[0].Columns[0]

    $optionsType = $page.GetType().Assembly.GetType('PnP.Core.Model.SharePoint.PageImageOptions')
    $order = 1
    foreach ($seg in @($PageDoc.segments)) {
        if ($seg.type -eq 'image') {
            $options = $null
            if ($optionsType) {
                $options = [Activator]::CreateInstance($optionsType)
                $options.AlternativeText = [string]$seg.alt
            }
            $url = "$($WebServerRelativeUrl.TrimEnd('/'))/$script:SacAssetsLibraryUrl/diagrams/$($seg.file)"
            $control = $page.GetImageWebPart($url, $options)
        }
        else {
            $control = $page.NewTextPart((Resolve-SacSiteUrl -Text ([string]$seg.html) -WebServerRelativeUrl $WebServerRelativeUrl))
        }
        $page.AddControl($control, $column, $order, $null)
        $order++
    }

    [void]$page.Save($name)
    $page.Publish('Generated by the Sentinel Documenter')
}

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

    $properties = @{ fileRelativeUrl = $FileRelativeUrl }
    $page = Get-PnPPage -Identity $PageName -ErrorAction SilentlyContinue
    $existing = $null
    if ($page) {
        $existing = Get-PnPPageComponent -Page $PageName -ErrorAction SilentlyContinue |
            Where-Object { ([string]$_.WebPartId).Trim('{}') -eq $script:SacWebPartComponentId } |
            Select-Object -First 1
    }
    else {
        Add-PnPPage -Name $PageName -LayoutType Article -Title $Title | Out-Null
        Set-PnPPage -Identity $PageName -HeaderType None | Out-Null
    }

    if ($existing) {
        Set-PnPPageWebPart -Page $PageName -Identity $existing.InstanceId -PropertiesJson ($properties | ConvertTo-Json -Compress) | Out-Null
    }
    else {
        Add-PnPPageSection -Page $PageName -SectionTemplate OneColumnFullWidth -Order 1 | Out-Null
        # A web part deployed moments ago can take a few minutes to show up
        # in the site's toolbox.
        $deadline = (Get-Date).AddSeconds($WebPartWaitSeconds)
        while ($true) {
            try {
                Add-PnPPageWebPart -Page $PageName -Component $script:SacWebPartComponentId -WebPartProperties $properties -Section 1 -Column 1 -ErrorAction Stop | Out-Null
                break
            }
            catch {
                if ((Get-Date) -ge $deadline) { throw "Dashboard web part $script:SacWebPartComponentId is not available on the site: $($_.Exception.Message)" }
                Write-Host '  Dashboard web part not available yet; retrying in 20 seconds...'
                Start-Sleep -Seconds 20
            }
        }
    }

    Set-PnPPage -Identity $PageName -Title $Title -Publish | Out-Null
    Set-PnPHomePage -RootFolderRelativeUrl "SitePages/$PageName.aspx" | Out-Null
}

function Get-SacFindingItems {
    <#
    .SYNOPSIS
        Read the findings list into the planner's shape (ItemId, FindingId,
        Status).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    $items = Get-PnPListItem -List $script:SacFindingsListUrl -PageSize 500 -Fields 'FindingId', 'Status' -ErrorAction SilentlyContinue
    return , @($items | ForEach-Object {
            [pscustomobject]@{
                ItemId    = $_.Id
                FindingId = [string]$_.FieldValues['FindingId']
                Status    = [string]$_.FieldValues['Status']
            }
        })
}

function Invoke-SacFindingPlan {
    <#
    .SYNOPSIS
        Apply a findings plan to the list in one batch.

    .PARAMETER Plan
        Output of Get-FindingSyncPlan.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan)

    if ($Plan.Count -eq 0) { return }
    $summary = ($Plan | Group-Object Action | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '
    if (-not $PSCmdlet.ShouldProcess($script:SacFindingsListUrl, "Apply findings plan ($summary)")) { return }

    $batch = New-PnPBatch
    foreach ($step in $Plan) {
        if ($step.Action -eq 'Add') {
            Add-PnPListItem -List $script:SacFindingsListUrl -Values $step.Values -Batch $batch
        }
        else {
            Set-PnPListItem -List $script:SacFindingsListUrl -Identity $step.ItemId -Values $step.Values -Batch $batch
        }
    }
    Invoke-PnPBatch -Batch $batch -StopOnException
}

function Get-SacNavigation {
    <#
    .SYNOPSIS
        Read the site's top navigation as a planner-shaped tree.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)] [string] $WebServerRelativeUrl)
    $nodes = Get-PnPNavigationNode -Location TopNavigationBar -Tree -ErrorAction SilentlyContinue
    if (-not $nodes) { return , @() }
    $tree = ConvertTo-SacNavigationTree -Nodes @($nodes) -WebServerRelativeUrl $WebServerRelativeUrl
    return , $tree
}

function Set-SacNavigation {
    <#
    .SYNOPSIS
        Replace the site's whole top navigation with the planned tree. The
        generator owns the top navigation.

    .PARAMETER Nodes
        Planned nodes from Get-NavigationPlan.

    .PARAMETER WebServerRelativeUrl
        The web's server-relative URL, to resolve '~site/' links.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [object[]] $Nodes,
        [Parameter(Mandatory)] [string] $WebServerRelativeUrl
    )
    if (-not $PSCmdlet.ShouldProcess('TopNavigationBar', "Replace with $($Nodes.Count) top-level nodes")) { return }

    Remove-PnPNavigationNode -Location TopNavigationBar -All -Force | Out-Null
    foreach ($n in $Nodes) {
        $url = if ($n.url) { Resolve-SacSiteUrl -Text $n.url -WebServerRelativeUrl $WebServerRelativeUrl } else { $script:SacLinklessHeaderUrl }
        $parent = Add-PnPNavigationNode -Location TopNavigationBar -Title $n.title -Url $url
        foreach ($c in @($n.children)) {
            if (-not $c) { continue }
            $childUrl = Resolve-SacSiteUrl -Text $c.url -WebServerRelativeUrl $WebServerRelativeUrl
            Add-PnPNavigationNode -Location TopNavigationBar -Title $c.title -Url $childUrl -Parent $parent.Id | Out-Null
        }
    }
}
