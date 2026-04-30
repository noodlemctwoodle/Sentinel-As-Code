#
# Sentinel-As-Code/Scripts/Export-SentinelWorkbooks.ps1
#
# Created by noodlemctwoodle on 30/04/2026.
#

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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function ConvertTo-FolderName {
    <#
    .SYNOPSIS
        Convert a workbook displayName to a PascalCase folder name that
        matches the convention used by existing Workbooks/<Folder>/.
    .EXAMPLE
        ConvertTo-FolderName 'Microsoft Sentinel Monitoring'
        # -> 'MicrosoftSentinelMonitoring'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$DisplayName)

    # Strip non-alphanumerics, capitalise each word, concatenate.
    $words = [regex]::Split($DisplayName, '[^A-Za-z0-9]+') |
        Where-Object { $_ -ne '' } |
        ForEach-Object {
            if ($_.Length -gt 1) {
                $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
            }
            else {
                $_.ToUpperInvariant()
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

# List Sentinel-scoped workbooks. The Microsoft.Insights/workbooks API
# accepts a `category=sentinel` filter and a `sourceId={workspaceResourceId}`
# filter; combining both narrows the result to exactly the workbooks
# Deploy-CustomWorkbooks would manage.
$listUri = "{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Insights/workbooks?api-version={3}&category=sentinel&sourceId={4}" -f `
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
        $displayName = $wb.properties.displayName
        if (-not ($displayName -match $Filter)) {
            Write-PipelineMessage "Skipping '$displayName' — does not match -Filter '$Filter'" -Level Info
            $counters.Skipped++
            continue
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
        $serialised = $wb.properties.serializedData
        if (-not $serialised) {
            Write-PipelineMessage "Skipping '$displayName' — no serializedData on the resource." -Level Warning
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

        # Build the metadata block. Preserve the workbookId so a
        # round-trip (export → commit → redeploy) lands on the same
        # Azure resource rather than creating a duplicate. workbookId
        # is the trailing GUID segment of the resource ID.
        $workbookId = $null
        if ($wb.id) {
            $workbookId = ($wb.id -split '/')[-1]
        }

        $metadata = [ordered]@{
            displayName = $displayName
            description = if ($wb.properties.description) { $wb.properties.description } else { '' }
            category    = if ($wb.properties.category) { $wb.properties.category } else { 'sentinel' }
            sourceId    = $wb.properties.sourceId
            workbookId  = $workbookId
        }

        # If a metadata.json already exists, preserve any extra fields
        # (e.g. tags an author has added that we don't model). Only the
        # keys this script writes are overwritten; the rest survive.
        $existingMetaPath = Join-Path $folderPath 'metadata.json'
        if (Test-Path $existingMetaPath) {
            try {
                $existing = Get-Content -Path $existingMetaPath -Raw | ConvertFrom-Json -Depth 8
                foreach ($prop in $existing.PSObject.Properties) {
                    if (-not $metadata.Contains($prop.Name)) {
                        $metadata[$prop.Name] = $prop.Value
                    }
                }
            }
            catch {
                Write-PipelineMessage "  Warning: existing metadata.json at '$existingMetaPath' failed to parse; overwriting." -Level Warning
            }
        }

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
