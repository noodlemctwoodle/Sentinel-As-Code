#Requires -Version 7.2

<#
.SYNOPSIS
    Run an engine script and resolve the paths the public commands take.

.DESCRIPTION
    The public commands are thin: they turn their parameters into the
    engine script's, call it through Invoke-iSOCBlueprintEngine and return
    an object describing what was written. The path helpers give every
    command the same defaults (./SecurityDocs under the current directory)
    and accept either a workspace folder or its _raw folder where a command
    reads an inventory.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Invoke-iSOCBlueprintEngine.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.2.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCBlueprintEngine {
    <#
    .SYNOPSIS
        Run one script under Engine/ with the given parameters.

    .DESCRIPTION
        Parameters whose value is $null are left out, so the script's own
        default applies. Common parameters the caller was given (-Verbose,
        -WhatIf, -InformationAction and the rest) are passed on when the
        script accepts them.

        Strict mode is turned off for the call. The module runs strict, but
        a script invoked from here inherits the caller's strict mode, and
        the engine scripts have always run without it unless they set it
        themselves (the collector does). Leaving it on would change how the
        renderer and the SharePoint steps behave.

    .PARAMETER Script
        Path of the script relative to Engine/, for example
        'SharePoint/Build-SentinelDocsSite.ps1'.

    .PARAMETER Parameters
        Parameters for the script, by the script's own names.

    .PARAMETER BoundParameters
        The calling command's $PSBoundParameters, for the common
        parameters.

    .OUTPUTS
        Whatever the script writes to the pipeline.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Script,
        [Parameter(Mandatory)] [hashtable] $Parameters,
        [System.Collections.IDictionary] $BoundParameters = @{}
    )

    $path = Join-Path $script:iSOCBlueprintEngineRoot $Script
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "iSOCBlueprint engine script not found: $path" }
    $command = Get-Command -Name $path -CommandType ExternalScript

    $splat = @{}
    foreach ($key in $Parameters.Keys) {
        if ($null -ne $Parameters[$key]) { $splat[$key] = $Parameters[$key] }
    }
    foreach ($key in 'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'WhatIf', 'Confirm') {
        if (($BoundParameters.Keys -contains $key) -and $command.Parameters.ContainsKey($key)) { $splat[$key] = $BoundParameters[$key] }
    }

    Set-StrictMode -Off
    & $path @splat
}

function Resolve-iSOCBlueprintPath {
    <#
    .SYNOPSIS
        An absolute file-system path for a path a user gave, or a default.

    .PARAMETER Path
        The path given, relative or absolute. May be empty.

    .PARAMETER Default
        Used when Path is empty, relative to the current directory.

    .OUTPUTS
        [string] The absolute path, or $null when both are empty. The path
        need not exist.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyString()] [string] $Path,
        [AllowNull()] [AllowEmptyString()] [string] $Default
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = $Default }
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Get-iSOCBlueprintRunFolderName {
    <#
    .SYNOPSIS
        The folder a run writes to under its workspace's folder: today's
        date, yyyy-MM-dd, in UTC. One folder a day, so a run does not
        overwrite the last and the dashboard can look back day by day.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Resolve-iSOCBlueprintRunPath {
    <#
    .SYNOPSIS
        A run's folder, given it or its workspace's folder. A workspace
        folder that holds day folders (yyyy-MM-dd) resolves to the newest
        day with an inventory; any other folder is returned as it is.

    .PARAMETER Path
        A run's folder, or a workspace folder holding day folders.

    .OUTPUTS
        [string] The absolute path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Path)

    $full = Resolve-iSOCBlueprintPath -Path $Path
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return $full }
    foreach ($marker in '_raw', 'sections', 'run-context.json') {
        if (Test-Path -LiteralPath (Join-Path $full $marker)) { return $full }
    }
    $days = @(Get-ChildItem -LiteralPath $full -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and ((Test-Path -LiteralPath (Join-Path $_.FullName '_raw')) -or (Test-Path -LiteralPath (Join-Path $_.FullName 'sections'))) } |
        Sort-Object Name -Descending)
    if ($days.Count) { return $days[0].FullName }
    return $full
}

function Resolve-iSOCBlueprintRawPath {
    <#
    .SYNOPSIS
        The _raw folder of an inventory, given the workspace folder or the
        _raw folder itself.

    .PARAMETER Path
        A run's folder (holding _raw/), a workspace folder holding day
        folders (the newest day is used), or a _raw folder.

    .OUTPUTS
        [string] The absolute path of the _raw folder. Throws when neither
        shape is found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Path)

    $full = Resolve-iSOCBlueprintRunPath -Path $Path
    $raw = Join-Path $full '_raw'
    if (Test-Path -LiteralPath $raw -PathType Container) { return $raw }
    if (Test-Path -LiteralPath (Join-Path $full 'run-context.json') -PathType Leaf) { return $full }
    throw "No Blueprint inventory at '$Path'. Give the workspace folder that holds _raw/, or the _raw folder itself (it contains run-context.json)."
}

function Copy-iSOCBlueprintParameter {
    <#
    .SYNOPSIS
        Copy the parameters a caller was actually given into an engine
        parameter table, renaming where the engine uses another name.

    .DESCRIPTION
        Only bound parameters are copied, so anything the caller left out
        keeps the engine script's own default.

    .PARAMETER BoundParameters
        The calling command's $PSBoundParameters.

    .PARAMETER Into
        The engine parameter table to add to.

    .PARAMETER Name
        Parameters to copy under the same name.

    .PARAMETER Rename
        Parameters to copy under another name: public name to engine name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $BoundParameters,
        [Parameter(Mandatory)] [hashtable] $Into,
        [string[]] $Name = @(),
        [hashtable] $Rename = @{}
    )

    foreach ($key in $Name) {
        if ($BoundParameters.Keys -contains $key) { $Into[$key] = $BoundParameters[$key] }
    }
    foreach ($key in $Rename.Keys) {
        if ($BoundParameters.Keys -contains $key) { $Into[$Rename[$key]] = $BoundParameters[$key] }
    }
}
