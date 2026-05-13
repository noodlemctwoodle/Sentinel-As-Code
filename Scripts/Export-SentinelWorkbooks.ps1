<#
.SYNOPSIS
    Exports Microsoft Sentinel workbooks from a workspace to disk in the
    same folder + file shape that Deploy-CustomContent.ps1 redeploys from.

.DESCRIPTION
    Reads every Sentinel-scoped workbook in the target resource group
    (filtered by `sourceId == <workspaceResourceId>`), then writes each
    one to:

        Workbooks/<FolderName>/workbook.json   # the gallery template
        Workbooks/<FolderName>/metadata.json   # displayName, description,
                                               # category, sourceId,
                                               # workbookId

    The output shape exactly matches what `Deploy-CustomContent.ps1`'s
    `Deploy-CustomWorkbooks` reads back, so a round-trip
    (export → commit → redeploy) is idempotent — the workbook resource
    GUID is preserved via metadata.json's `workbookId`, so updates land
    on the same Azure resource rather than spawning a duplicate.

    Three modes of operation, controlled by switches:

      Default        Export every Sentinel workbook in the workspace.
                     New folders created; existing folders overwritten
                     (with a backup of the prior workbook.json copy).

      -WhatIf        Read everything, write nothing. Reports per-workbook
                     what would change vs the on-disk content.

      -OnlyMissing   Write workbooks that have no matching folder in
                     Workbooks/ already. Existing folders are left alone.
                     Useful for incremental import after manual portal
                     authoring.

.PARAMETER SubscriptionId
    Azure Subscription ID. Defaults to the current Az context.

.PARAMETER ResourceGroup
    Resource group containing the Sentinel workspace.

.PARAMETER Workspace
    Log Analytics workspace name (used to derive workspace resource ID
    for the sourceId filter).

.PARAMETER Region
    Azure region. Required by Connect-AzureEnvironment but not used
    for export (workbooks are queried by RG, not region).

.PARAMETER BasePath
    Repository root path. Defaults to the parent of the Scripts folder.
    Output is written to `<BasePath>/Workbooks/`.

.PARAMETER Filter
    Optional regex applied to each workbook's displayName. Workbooks
    not matching are skipped. Default: '.' (match everything).

.PARAMETER OnlyMissing
    Skip workbooks that already have a folder under Workbooks/. Useful
    for one-off import without overwriting in-repo customisations.

.PARAMETER IncludeContentHub
    By default, workbooks installed via a Content Hub solution are
    excluded — they belong to the solution, not the customer, and
    putting them under repo governance conflicts with the Content
    Hub update flow. Pass this switch to include them anyway
    (advanced; almost always wrong).

.PARAMETER WhatIf
    Read everything, write nothing. Reports per-workbook what would
    change.

.PARAMETER IsGov
    Target Azure Government cloud.

.EXAMPLE
    ./Scripts/Export-SentinelWorkbooks.ps1 `
        -ResourceGroup 'rg-sentinel-prod' `
        -Workspace     'law-sentinel-prod' `
        -Region        'uksouth'

    Exports every Sentinel workbook in the workspace to Workbooks/
    under the repo root.

.EXAMPLE
    ./Scripts/Export-SentinelWorkbooks.ps1 `
        -ResourceGroup 'rg-sentinel-prod' `
        -Workspace     'law-sentinel-prod' `
        -Region        'uksouth' `
        -Filter        '^Identity'

    Exports only workbooks whose displayName starts with 'Identity'.

.EXAMPLE
    ./Scripts/Export-SentinelWorkbooks.ps1 `
        -ResourceGroup 'rg-sentinel-prod' `
        -Workspace     'law-sentinel-prod' `
        -Region        'uksouth' `
        -OnlyMissing

    Exports any workbook that doesn't already have a folder. Doesn't
    touch existing folders.

.EXAMPLE
    ./Scripts/Export-SentinelWorkbooks.ps1 `
        -ResourceGroup 'rg-sentinel-prod' `
        -Workspace     'law-sentinel-prod' `
        -Region        'uksouth' `
        -WhatIf

    Reports what would change without writing.

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-04-30
    Repository:     Sentinel-As-Code
    Requires:       PowerShell 7.2+, Az.Accounts, Sentinel.Common module

    Symmetry contract:

      - Same JSON file shape as Deploy-CustomWorkbooks reads
        (workbook.json = gallery template, metadata.json = display
        metadata + workbookId).
      - Same API version as the deploy script (2022-04-01).
      - Folder name derived from displayName via PascalCase
        compaction (matches how the existing Workbooks/* folders
        are named).
      - workbookId preserved via metadata.json so redeploy lands
        on the same Azure resource.

    Content Hub filtering:

      - Default behaviour skips workbooks installed via a Content
        Hub solution (identified via the Microsoft.SecurityInsights/
        metadata resource where source.kind == 'Solution').
      - Content Hub workbooks belong to their solution; bringing
        them under repo governance conflicts with Content Hub's
        update flow. The matching deploy
        (Deploy-CustomContent.ps1's Deploy-CustomWorkbooks)
        intentionally only handles repo-authored workbooks.
      - Pass -IncludeContentHub to override (advanced).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$Workspace,

    [Parameter(Mandatory = $true)]
    [string]$Region,

    [Parameter(Mandatory = $false)]
    [string]$BasePath,

    [Parameter(Mandatory = $false)]
    [string]$Filter = '.',

    [Parameter(Mandatory = $false)]
    [switch]$OnlyMissing,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeContentHub,

    [Parameter(Mandatory = $false)]
    [switch]$IsGov
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Module imports
# ---------------------------------------------------------------------------
Import-Module (Join-Path $PSScriptRoot '../Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop

if (-not $BasePath) {
    $BasePath = Split-Path -Path $PSScriptRoot -Parent
}

$script:WorkbookApiVersion = '2022-04-01'
$script:SentinelApiVersion = '2025-09-01'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Remove-WorkspaceArmId {
    <#
    .SYNOPSIS
        Replace literal workspace ARM resource IDs in a workbook
        gallery template with a portable placeholder.

    .DESCRIPTION
        Sentinel saves workbooks with `fallbackResourceIds` and
        sometimes inline resource references that bake the source
        workspace's ARM resource ID directly into the gallery
        template:

            "/subscriptions/<sub-guid>/resourcegroups/<rg>/providers/microsoft.operationalinsights/workspaces/<workspace>"

        Committing that value to a repo would lock the workbook to
        one specific workspace. The existing in-repo workbooks use
        the convention of a generic placeholder:

            "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/your-resource-group/providers/microsoft.operationalinsights/workspaces/your-workspace"

        This helper does a case-insensitive substitution of the
        source workspace's ARM ID with that placeholder, applied to
        the serialised JSON string (so all fields that reference
        the workspace get rewritten, not just `fallbackResourceIds`).

        `fallbackResourceIds` is only consulted by the standalone
        Workbooks-portal view — when a deployed workbook is opened
        from within its parent Sentinel workspace, the placeholder
        is irrelevant. So the substitution is safe at deploy time.

    .PARAMETER Json
        The serialised workbook gallery template (a JSON string).

    .PARAMETER WorkspaceResourceId
        The full ARM resource ID of the source workspace, e.g.
        '/subscriptions/.../workspaces/<name>'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Json,
        [Parameter(Mandatory)] [string] $WorkspaceResourceId
    )

    $placeholder = '/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/your-resource-group/providers/microsoft.operationalinsights/workspaces/your-workspace'

    return [regex]::Replace(
        $Json,
        [regex]::Escape($WorkspaceResourceId),
        $placeholder,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
}

function Remove-WorkspaceSuffix {
    <#
    .SYNOPSIS
        Strip a trailing workspace-name annotation from a workbook
        displayName.

    .DESCRIPTION
        Microsoft-published workbook templates that get instantiated
        per-workspace pick up a ` - <workspace-name>` suffix on their
        displayName (e.g. "Data Collection Rule Toolkit -
        stl-eus-siem-law"). The suffix is noise from a repo-storage
        perspective — the workbook would be redeployed under a
        clean name and Sentinel attaches the workspace suffix at
        display time anyway. Strip it for a cleaner folder structure
        and metadata.json.

        Match pattern: ` - <workspace-name>` at the very end of the
        string. The workspace name is interpreted as a literal
        (regex-escaped) so workspace names containing regex
        metacharacters work correctly.

        If the displayName doesn't end with the suffix, the input is
        returned unchanged.

    .EXAMPLE
        Remove-WorkspaceSuffix `
            -DisplayName  'Data Collection Rule Toolkit - stl-eus-siem-law' `
            -WorkspaceName 'stl-eus-siem-law'
        # -> 'Data Collection Rule Toolkit'

    .EXAMPLE
        Remove-WorkspaceSuffix `
            -DisplayName  'Microsoft Sentinel Cost (GBP) v2' `
            -WorkspaceName 'stl-eus-siem-law'
        # -> 'Microsoft Sentinel Cost (GBP) v2'    (unchanged — no suffix)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $DisplayName,
        [Parameter(Mandatory)] [string] $WorkspaceName
    )

    $pattern = ' - ' + [regex]::Escape($WorkspaceName) + '$'
    return [regex]::Replace($DisplayName, $pattern, '')
}

function ConvertTo-FolderName {
    <#
    .SYNOPSIS
        Convert a workbook displayName to a PascalCase folder name.

    .DESCRIPTION
        Folder names are PascalCase (no spaces, no punctuation) so
        they're shell-friendly and match the existing convention in
        this repo's Workbooks/ tree.

        Algorithm:
          1. Split on any run of non-alphanumeric characters
             (spaces, parens, hyphens, slashes — all become word
             boundaries).
          2. For each word:
             - If the word contains internal camelCase
               (lowercase-then-uppercase pattern, e.g. "pfSense",
               "ApacheTomcat", "MicrosoftSentinel"), preserve the
               case as authored — only the leading char is forced
               to uppercase. This keeps user-curated camelCase
               brands (pfSense -> PfSense) intact.
             - Otherwise the word is a single-case form
               (all-lower, all-upper, or all-digit) — apply
               TitleCase: first char upper, rest lower. So "GBP"
               becomes "Gbp" and "machines" becomes "Machines",
               matching the existing repo convention (e.g.
               "MicrosoftSentinelCostGbp", not
               "MicrosoftSentinelCostGBP").
          3. Concatenate words.

    .EXAMPLE
        ConvertTo-FolderName 'Microsoft Sentinel Monitoring'
        # -> 'MicrosoftSentinelMonitoring'

    .EXAMPLE
        ConvertTo-FolderName 'Microsoft Sentinel Cost (GBP) v2'
        # -> 'MicrosoftSentinelCostGbpV2'

    .EXAMPLE
        ConvertTo-FolderName 'pfSense Firewall'
        # -> 'PfSenseFirewall'    (camelCase brand preserved)

    .EXAMPLE
        ConvertTo-FolderName 'Bad/Name:With*Illegal?Chars'
        # -> 'BadNameWithIllegalChars'    (illegal chars become word boundaries)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$DisplayName)

    $words = [regex]::Split($DisplayName, '[^A-Za-z0-9]+') |
        Where-Object { $_ -ne '' } |
        ForEach-Object {
            if ($_.Length -lt 2) {
                $_.ToUpperInvariant()
            }
            elseif ($_ -cmatch '[a-z][A-Z]') {
                # Internal camelCase — preserve, just force the
                # leading character to uppercase. This keeps
                # user-curated brand spellings like 'pfSense' or
                # 'MicrosoftSentinelMonitoring' intact when the
                # input arrives already in compact form.
                $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
            }
            else {
                # Single-case word (all-upper, all-lower, or
                # all-digit) — apply TitleCase. 'GBP' -> 'Gbp',
                # 'machines' -> 'Machines'.
                $_.Substring(0, 1).ToUpperInvariant() +
                $_.Substring(1).ToLowerInvariant()
            }
        }
    return ($words -join '')
}

function Format-WorkbookJson {
    <#
    .SYNOPSIS
        Pretty-print a workbook gallery template (parsed JSON) for
        on-disk readability. Matches the formatting used by existing
        Workbooks/*/workbook.json files.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $JsonObject)

    return ($JsonObject | ConvertTo-Json -Depth 32)
}

function Merge-WorkbookMetadata {
    <#
    .SYNOPSIS
        Build the metadata.json hashtable for a single workbook,
        preferring author-curated values from any pre-existing
        metadata.json over the API's defaults.

    .DESCRIPTION
        The Sentinel REST API returns sparse workbook metadata —
        most workbooks come back with `description = ''` and
        `category = 'sentinel'`. Hand-authored repo metadata.json
        files often carry richer values:

            description : 'Multi-site management workbook for ...'
            category    : 'Network'

        A naive overwrite-on-export strategy destroys this curation.
        This helper merges, with the following preference rules:

          - displayName  : prefer the API value, EXCEPT when the
                           existing value matches case-insensitively
                           (the author has likely tweaked
                           capitalisation, e.g. 'UniFi' vs 'Unifi').
          - description  : prefer the API value when non-empty;
                           else preserve any existing curated value.
          - category     : prefer the existing value when set
                           (the API default 'sentinel' is too
                           generic); fall back to the API value.
          - sourceId     : always the folder name (an in-repo
                           identifier; existing values may be
                           inconsistent and should be normalised).
          - workbookId   : always the API-supplied resource GUID
                           (the canonical stable binding to Azure).

        Plus: any extra keys present in the existing metadata.json
        that this helper doesn't write (custom annotations, tags,
        deploy-pipeline hints) are preserved verbatim.

    .PARAMETER ApiDisplayName
        The cleaned displayName from the workbook resource (after
        workspace-suffix strip). Drives the canonical UI name.

    .PARAMETER ApiDescription
        The description property from the workbook resource. May be
        empty.

    .PARAMETER ApiCategory
        The category property from the workbook resource. Typically
        'sentinel' as the default.

    .PARAMETER FolderName
        The on-disk folder name (PascalCase compaction of the
        cleaned displayName). Used as the sourceId.

    .PARAMETER WorkbookId
        The trailing GUID segment of the workbook's ARM resource ID.

    .PARAMETER ExistingMetadata
        The deserialised existing metadata.json hashtable (or
        $null if no metadata.json exists yet).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $ApiDisplayName,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $ApiDescription,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $ApiCategory,
        [Parameter(Mandatory)]                       [string] $FolderName,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $WorkbookId,
        [Parameter()]                                         $ExistingMetadata
    )

    $existing = $ExistingMetadata

    # displayName: prefer API; preserve existing case if names match
    # case-insensitively (author-curated capitalisation).
    $resolvedDisplayName = $ApiDisplayName
    if ($existing -and (Get-MetaValue -Object $existing -Key 'displayName')) {
        $existingDn = [string](Get-MetaValue -Object $existing -Key 'displayName')
        if ($existingDn -ieq $ApiDisplayName -and $existingDn -cne $ApiDisplayName) {
            $resolvedDisplayName = $existingDn
        }
    }

    # description: prefer existing curated value when API returns empty.
    $resolvedDescription = $ApiDescription
    if ([string]::IsNullOrWhiteSpace($resolvedDescription) -and $existing) {
        $existingDesc = [string](Get-MetaValue -Object $existing -Key 'description')
        if (-not [string]::IsNullOrWhiteSpace($existingDesc)) {
            $resolvedDescription = $existingDesc
        }
    }

    # category: prefer existing curated value over the generic API
    # default. The API's 'sentinel' is what every workbook gets by
    # default; an author-supplied value is almost always more
    # specific.
    $apiCategoryEffective = if ([string]::IsNullOrWhiteSpace($ApiCategory)) { 'sentinel' } else { $ApiCategory }
    $resolvedCategory = $apiCategoryEffective
    if ($existing) {
        $existingCat = [string](Get-MetaValue -Object $existing -Key 'category')
        if (-not [string]::IsNullOrWhiteSpace($existingCat)) {
            $resolvedCategory = $existingCat
        }
    }

    $metadata = [ordered]@{
        displayName = $resolvedDisplayName
        description = $resolvedDescription
        category    = $resolvedCategory
        sourceId    = $FolderName
        workbookId  = $WorkbookId
    }

    # Preserve extra keys (tags, custom annotations) that the
    # author added but this helper doesn't write.
    if ($existing) {
        $existingKeys = if ($existing.PSObject -and $existing.PSObject.Properties) {
            @($existing.PSObject.Properties | ForEach-Object { $_.Name })
        }
        elseif ($existing -is [System.Collections.IDictionary]) {
            @($existing.Keys)
        }
        else {
            @()
        }
        foreach ($key in $existingKeys) {
            if (-not $metadata.Contains($key)) {
                $metadata[$key] = Get-MetaValue -Object $existing -Key $key
            }
        }
    }

    return $metadata
}

function Get-MetaValue {
    <#
    .SYNOPSIS
        Read a property from an arbitrary deserialised JSON object,
        whether it was parsed as PSCustomObject (default for
        ConvertFrom-Json) or hashtable (-AsHashtable). Returns $null
        if the key is missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string] $Key
    )

    if ($null -eq $Object) { return $null }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Key)) { return $Object[$Key] }
        return $null
    }
    if ($Object.PSObject -and $Object.PSObject.Properties[$Key]) {
        return $Object.PSObject.Properties[$Key].Value
    }
    return $null
}

function Write-WorkbookFolder {
    <#
    .SYNOPSIS
        Write a single workbook to disk in the canonical folder shape.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]   $FolderPath,
        [Parameter(Mandatory)] [string]   $WorkbookJson,
        [Parameter(Mandatory)] [hashtable]$Metadata
    )

    $workbookFile = Join-Path $FolderPath 'workbook.json'
    $metadataFile = Join-Path $FolderPath 'metadata.json'

    if (-not (Test-Path $FolderPath)) {
        if ($PSCmdlet.ShouldProcess($FolderPath, 'Create folder')) {
            [void](New-Item -Path $FolderPath -ItemType Directory -Force)
        }
    }

    if ($PSCmdlet.ShouldProcess($workbookFile, 'Write workbook.json')) {
        Set-Content -Path $workbookFile -Value $WorkbookJson -Encoding UTF8
    }

    $metadataJson = $Metadata | ConvertTo-Json -Depth 8
    if ($PSCmdlet.ShouldProcess($metadataFile, 'Write metadata.json')) {
        Set-Content -Path $metadataFile -Value $metadataJson -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-PipelineMessage "Sentinel Workbook Export" -Level Section
Write-PipelineMessage "  Resource Group: $ResourceGroup" -Level Info
Write-PipelineMessage "  Workspace:      $Workspace"     -Level Info
Write-PipelineMessage "  Region:         $Region"        -Level Info
Write-PipelineMessage "  Base path:      $BasePath"      -Level Info
Write-PipelineMessage "  Filter:         $Filter"        -Level Info
Write-PipelineMessage "  WhatIf:         $($PSCmdlet.ShouldProcess('test', 'preview') -eq $false)" -Level Info
Write-PipelineMessage "  Only missing:   $OnlyMissing"   -Level Info

# Connect to Azure and resolve workspace resource ID
$ctx = Connect-AzureEnvironment `
    -ResourceGroup  $ResourceGroup `
    -Workspace      $Workspace `
    -Region         $Region `
    -SubscriptionId $SubscriptionId `
    -IsGov:$IsGov

# ---------------------------------------------------------------------------
# Build the Content Hub workbook exclusion set
# ---------------------------------------------------------------------------
# Sentinel marks Content-Hub-installed content via a parallel
# `Microsoft.SecurityInsights/metadata` resource with `source.kind ==
# 'Solution'`. The workbook resource itself is identical in shape to
# a Custom workbook, so the only reliable filter is to enumerate the
# metadata records and build a set of workbook resource IDs that the
# Content Hub owns. Any workbook whose ID matches gets skipped (unless
# -IncludeContentHub overrides).
#
# Content Hub workbooks belong to their solution, not the customer.
# Re-deploying them via Deploy-CustomContent.ps1 doesn't help (the
# Content Hub solution will overwrite on update); putting them under
# repo governance is almost always the wrong call. The default of
# skipping them is the right behaviour.
$contentHubWorkbookIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)

if (-not $IncludeContentHub) {
    $metadataUri = "{0}{1}/providers/Microsoft.SecurityInsights/metadata?api-version={2}" -f `
        $ctx.ServerUrl,
        $ctx.WorkspaceResourceId,
        $script:SentinelApiVersion

    Write-PipelineMessage "Querying Sentinel metadata to identify Content Hub workbooks..." -Level Info
    try {
        $metaResp = Invoke-SentinelApi -Uri $metadataUri -Method Get -Headers $ctx.AuthHeader
        $metaRecords = @($metaResp.value)

        # Sentinel paginates large metadata responses. Follow nextLink
        # until exhausted so we don't miss Content Hub workbooks just
        # because they fall on a later page.
        $nextLink = $metaResp.nextLink
        while ($nextLink) {
            $page = Invoke-SentinelApi -Uri $nextLink -Method Get -Headers $ctx.AuthHeader
            if ($page.value) { $metaRecords += @($page.value) }
            $nextLink = $page.nextLink
        }

        foreach ($rec in $metaRecords) {
            if ($rec.properties.kind -ne 'Workbook') { continue }
            $sourceKind = $null
            if ($rec.properties.PSObject.Properties['source'] -and $rec.properties.source) {
                $sourceKind = $rec.properties.source.kind
            }
            if ($sourceKind -eq 'Solution' -and $rec.properties.parentId) {
                [void]$contentHubWorkbookIds.Add($rec.properties.parentId)
            }
        }

        Write-PipelineMessage "  Identified $($contentHubWorkbookIds.Count) Content Hub workbook(s) — these will be skipped." -Level Info
    }
    catch {
        Write-PipelineMessage "  Could not enumerate Sentinel metadata: $($_.Exception.Message)" -Level Warning
        Write-PipelineMessage "  Continuing without Content Hub filtering. Pass -IncludeContentHub to suppress this warning if intentional." -Level Warning
    }
}
else {
    Write-PipelineMessage "-IncludeContentHub specified — Content Hub workbooks WILL be exported alongside Custom." -Level Warning
}

# List Sentinel-scoped workbooks. The Microsoft.Insights/workbooks API
# accepts a `category=sentinel` filter and a `sourceId={workspaceResourceId}`
# filter; combining both narrows the result to exactly the workbooks
# Deploy-CustomWorkbooks would manage.
#
# `canFetchContent=true` is REQUIRED. Without it, the LIST response
# returns only resource metadata — the `serializedData` property
# (the gallery template content we actually need) is omitted to keep
# response sizes small. With the flag, the LIST returns full content
# for workbooks the caller has read access to. For any workbook where
# the LIST still doesn't return content (Microsoft-published Content
# Hub workbooks that the workspace inherits but doesn't own, certain
# permission edge cases), we fall back to a per-workbook GET below.
$listUri = "{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Insights/workbooks?api-version={3}&category=sentinel&sourceId={4}&canFetchContent=true" -f `
    $ctx.ServerUrl,
    $ctx.SubscriptionId,
    $ResourceGroup,
    $script:WorkbookApiVersion,
    [Uri]::EscapeDataString($ctx.WorkspaceResourceId)

Write-PipelineMessage "Listing workbooks via:" -Level Info
Write-PipelineMessage "  $listUri" -Level Info

try {
    $listResp = Invoke-SentinelApi -Uri $listUri -Method Get -Headers $ctx.AuthHeader
}
catch {
    Write-PipelineMessage "Failed to list workbooks: $($_.Exception.Message)" -Level Error
    throw
}

$workbooks = @($listResp.value)
Write-PipelineMessage "" -Level Info
Write-PipelineMessage "Found $($workbooks.Count) workbook(s) in the workspace." -Level Info

if ($workbooks.Count -eq 0) {
    Write-PipelineMessage "Nothing to export." -Level Info
    return
}

$workbooksRoot = Join-Path $BasePath 'Workbooks'
if (-not (Test-Path $workbooksRoot)) {
    if ($PSCmdlet.ShouldProcess($workbooksRoot, 'Create Workbooks/ folder')) {
        [void](New-Item -Path $workbooksRoot -ItemType Directory -Force)
    }
}

$counters = @{
    Exported = 0
    Skipped  = 0
    Failed   = 0
}

foreach ($wb in $workbooks) {
    try {
        $rawDisplayName = $wb.properties.displayName

        # Skip Content Hub workbooks — they belong to their installing
        # solution, not the customer. Bringing them under repo
        # governance would conflict with the Content Hub update flow.
        # Override with -IncludeContentHub for advanced cases.
        if (-not $IncludeContentHub -and $contentHubWorkbookIds.Contains($wb.id)) {
            Write-PipelineMessage "Skipping '$rawDisplayName' — Content Hub-managed workbook (use -IncludeContentHub to override)." -Level Info
            $counters.Skipped++
            continue
        }

        if (-not ($rawDisplayName -match $Filter)) {
            Write-PipelineMessage "Skipping '$rawDisplayName' — does not match -Filter '$Filter'" -Level Info
            $counters.Skipped++
            continue
        }

        # Strip the ` - <workspace-name>` suffix Microsoft attaches to
        # workspace-instantiated templates (e.g. "Data Collection Rule
        # Toolkit - stl-eus-siem-law"). The cleaned name drives both
        # the folder and the metadata.json displayName so on redeploy
        # Sentinel re-attaches the suffix at display time, keeping
        # the round-trip stable.
        $displayName = Remove-WorkspaceSuffix -DisplayName $rawDisplayName -WorkspaceName $Workspace

        if ($displayName -ne $rawDisplayName) {
            Write-PipelineMessage "  Stripped workspace suffix: '$rawDisplayName' -> '$displayName'" -Level Info
        }

        $folderName = ConvertTo-FolderName -DisplayName $displayName
        $folderPath = Join-Path $workbooksRoot $folderName

        if ($OnlyMissing -and (Test-Path $folderPath)) {
            Write-PipelineMessage "Skipping '$displayName' — folder exists and -OnlyMissing was specified." -Level Info
            $counters.Skipped++
            continue
        }

        # The serializedData property is a JSON string; reformat it via
        # parse + ConvertTo-Json so the on-disk file is pretty-printed
        # and matches the existing repo's formatting.
        #
        # If the LIST response (even with canFetchContent=true) didn't
        # return serializedData for this workbook, fall back to a
        # per-workbook GET. Microsoft-published Content Hub workbooks
        # that the workspace inherits but hasn't customised typically
        # need the per-resource fetch to surface their content.
        $serialised = $wb.properties.serializedData
        if (-not $serialised) {
            $detailUri = "{0}{1}?api-version={2}&canFetchContent=true" -f `
                $ctx.ServerUrl,
                $wb.id,
                $script:WorkbookApiVersion
            try {
                Write-PipelineMessage "  '$displayName' had no content in the list response; fetching detail..." -Level Info
                $detail = Invoke-SentinelApi -Uri $detailUri -Method Get -Headers $ctx.AuthHeader
                $serialised = $detail.properties.serializedData
            }
            catch {
                Write-PipelineMessage "Skipping '$displayName' — detail fetch failed: $($_.Exception.Message)" -Level Warning
                $counters.Skipped++
                continue
            }
        }

        if (-not $serialised) {
            Write-PipelineMessage "Skipping '$displayName' — still no serializedData after detail fetch (likely a Content Hub gallery template not customised in this workspace)." -Level Warning
            $counters.Skipped++
            continue
        }

        try {
            $workbookContent = $serialised | ConvertFrom-Json -Depth 64
        }
        catch {
            Write-PipelineMessage "Skipping '$displayName' — serializedData failed to parse as JSON: $($_.Exception.Message)" -Level Warning
            $counters.Skipped++
            continue
        }

        $workbookJson = Format-WorkbookJson -JsonObject $workbookContent

        # Strip the source workspace's ARM ID and replace with the
        # placeholder convention used by every existing repo
        # workbook. Otherwise the workbook would be locked to one
        # specific workspace.
        $beforeArmStrip = $workbookJson
        $workbookJson = Remove-WorkspaceArmId -Json $workbookJson -WorkspaceResourceId $ctx.WorkspaceResourceId
        if ($workbookJson -ne $beforeArmStrip) {
            Write-PipelineMessage "  Replaced workspace ARM ID with placeholder in workbook content." -Level Info
        }

        # Build the metadata block. Preserve the workbookId so a
        # round-trip (export → commit → redeploy) lands on the same
        # Azure resource rather than creating a duplicate. workbookId
        # is the trailing GUID segment of the resource ID.
        $workbookId = $null
        if ($wb.id) {
            $workbookId = ($wb.id -split '/')[-1]
        }

        # Read any existing metadata.json so the merge helper can
        # preserve author-curated values where the API returns
        # empty/default. See Merge-WorkbookMetadata for the merge
        # rules — short version: API wins for displayName /
        # workbookId; existing wins for description / category /
        # any extra keys.
        $existingMetadata  = $null
        $existingMetaPath  = Join-Path $folderPath 'metadata.json'
        if (Test-Path $existingMetaPath) {
            try {
                $existingMetadata = Get-Content -Path $existingMetaPath -Raw | ConvertFrom-Json -Depth 8
            }
            catch {
                Write-PipelineMessage "  Warning: existing metadata.json at '$existingMetaPath' failed to parse; treating as absent." -Level Warning
            }
        }

        $apiDescription = if ($wb.properties.description) { [string]$wb.properties.description } else { '' }
        $apiCategory    = if ($wb.properties.category)    { [string]$wb.properties.category    } else { '' }

        $metadata = Merge-WorkbookMetadata `
            -ApiDisplayName    $displayName `
            -ApiDescription    $apiDescription `
            -ApiCategory       $apiCategory `
            -FolderName        $folderName `
            -WorkbookId        ([string]$workbookId) `
            -ExistingMetadata  $existingMetadata

        Write-PipelineMessage "Exporting: $displayName -> Workbooks/$folderName/" -Level Info

        Write-WorkbookFolder -FolderPath $folderPath -WorkbookJson $workbookJson -Metadata $metadata

        $counters.Exported++
        Write-PipelineMessage "  Wrote: $folderPath" -Level Success
    }
    catch {
        Write-PipelineMessage "Failed to export '$($wb.properties.displayName)': $($_.Exception.Message)" -Level Error
        $counters.Failed++
    }
}

Write-PipelineMessage "" -Level Info
Write-PipelineMessage "Export summary" -Level Section
Write-PipelineMessage "  Exported: $($counters.Exported)" -Level Info
Write-PipelineMessage "  Skipped:  $($counters.Skipped)"  -Level Info
Write-PipelineMessage "  Failed:   $($counters.Failed)"   -Level Info

if ($counters.Failed -gt 0) {
    Write-PipelineMessage "One or more workbooks failed to export." -Level Error
    exit 1
}

Write-PipelineMessage "Done. Review the Workbooks/ tree, run Pester (Test-WorkbookJson.Tests.ps1) before committing." -Level Success
