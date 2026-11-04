#Requires -Version 7.2

<#
.SYNOPSIS
    Imports Microsoft Sentinel analytical rules from the David Alonso (Dalonso)
    Security community repository into the Sentinel-As-Code project.

.DESCRIPTION
    Clones the Dalonso Security Repo at a shallow depth, locates all analytical
    rule YAML files (and optionally ARM-based KQL folders), normalises each rule
    to project standards, and writes output YAML files under
    Content/AnalyticalRules/Community/Dalonso/.

    Processing applied to every rule:
    - Validates required fields: id, name, kind, severity, query
    - Sets enabled: false (all community rules deploy disabled by default)
    - Prepends a community attribution paragraph to the description
    - Merges tags: Community, Dalonso, ThreatHunting
    - Normalises triggerOperator short forms (gt/lt/eq/ne) to full names
    - Keeps the id a rule already has in the repository, and gives a rule
      whose upstream id another rule file uses a stable id of its own
      (RFC 4122 version 5, from the source repository and the rule's path),
      since the deployer names each rule in the workspace by its id

    When -IncludeKqlConversion is specified, the script also processes folders
    that use azuredeploy.json ARM templates, converting each alertRule resource
    into a YAML file using the same normalisation pipeline.

    A manifest file (import-manifest.json) is written to $OutputPath. The
    human-readable README is written to $DocsPath under the repository's
    Docs/ folder so all governance documentation lives in one place.

.PARAMETER OutputPath
    Destination directory for imported rule YAML files and the
    import-manifest.json artifact.
    Defaults to Content/AnalyticalRules/Community/Dalonso relative to the repository root.

.PARAMETER DocsPath
    Destination file for the auto-generated README markdown summary.
    Defaults to Docs/Content/Community/{ContributorName}.md where {ContributorName}
    is derived from the leaf folder name of $OutputPath. The parent directory
    is auto-created if missing.

.PARAMETER SourceRepo
    Git URL of the Dalonso Security repository.
    Defaults to https://github.com/davidalonsod/Dalonso-Security-Repo.git

.PARAMETER SourceBranch
    Branch to clone. Defaults to main.

.PARAMETER IncludeKqlConversion
    When specified, also processes ARM-template-based KQL folders
    (ADSecurityEvents, AzureActivity, M365OfficeActivity, NonHumanIdentities).

.PARAMETER DryRun
    Shows what would be written without creating or modifying any files.

.EXAMPLE
    .\Import-CommunityRules.ps1

    Imports all YAML-based rule folders into the default output path.

.EXAMPLE
    .\Import-CommunityRules.ps1 -IncludeKqlConversion -DryRun

    Previews all changes including ARM-converted rules without writing any files.

.EXAMPLE
    .\Import-CommunityRules.ps1 -OutputPath /custom/path -SourceBranch develop

    Imports from the develop branch into a custom output directory.

.EXAMPLE
    .\Import-CommunityRules.ps1 `
        -OutputPath /repo/Content/AnalyticalRules/Community/NewContributor `
        -DocsPath   /repo/Docs/Content/Community/NewContributor.md

    Onboards a new contributor - both paths can be set explicitly when the
    auto-derived defaults don't suit (e.g. for a one-off import into a
    sandbox folder).

.NOTES
    File:           Tools/Import-CommunityRules.ps1
    Repository:     Sentinel-As-Code
    Author:         noodlemctwoodle
    Website:        https://sentinel.blog
    Created:        2026-04-28
    Version:        1.2.1
    Last Updated:   2026-11-04
    Requires:       PowerShell 7.2+, powershell-yaml (auto-installed if missing); git 2.x or later in PATH
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path $PSScriptRoot '..' 'Content' 'AnalyticalRules' 'Community' 'Dalonso')
    ,
    [Parameter(Mandatory = $false)]
    [string]$DocsPath
    ,
    [Parameter(Mandatory = $false)]
    [string]$SourceRepo = "https://github.com/davidalonsod/Dalonso-Security-Repo.git"
    ,
    [Parameter(Mandatory = $false)]
    [string]$SourceBranch = "main"
    ,
    [Parameter(Mandatory = $false)]
    [switch]$IncludeKqlConversion
    ,
    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Derive the README destination from the output folder's leaf name when not
# provided explicitly. Default lands at <repoRoot>/Docs/Content/Community/<Contributor>.md
# so the human-readable summary sits alongside the Content-authoring docs it
# describes.
if (-not $DocsPath) {
    $contributorName = Split-Path -Path $OutputPath -Leaf
    $repoRoot        = Split-Path -Path $PSScriptRoot -Parent
    $DocsPath        = Join-Path $repoRoot 'Docs' (Join-Path 'Content' (Join-Path 'Community' "$contributorName.md"))
}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:AttributionPrefix = @"
Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense.

"@

$script:RequiredTags   = @('Community', 'Dalonso', 'ThreatHunting')
$script:TriggerOpMap   = @{
    gt = 'GreaterThan'
    lt = 'LessThan'
    eq = 'Equal'
    ne = 'NotEqual'
}

# Source folder -> target category mappings (YAML-native folders)
$script:YamlFolderMap = [ordered]@{
    'Use Cases Threat Hunting/SigninLogs-ThreatHunting'                                 = @{ Target = 'SigninLogs';               YamlOnly = $true  }
    'Use Cases Threat Hunting/AadNonInteractiveUserSigninLogs/rules'                    = @{ Target = 'NonInteractiveSigninLogs'; YamlOnly = $false }
    'Use Cases Threat Hunting/ADFSSignInLogs/Sentinel-AnalyticRules-ADFS/rules'        = @{ Target = 'ADFSSignInLogs';           YamlOnly = $false }
    'Use Cases Threat Hunting/CommonSecurityLog-ThreatHunting'                          = @{ Target = 'CommonSecurityLog';        YamlOnly = $true  }
    'Use Cases Threat Hunting/DNSEvents/Analytic-Rules/rules'                           = @{ Target = 'DNSEvents';                YamlOnly = $false }
}

# Source folder -> target category mappings (ARM/KQL folders)
$script:ArmFolderMap = [ordered]@{
    'Use Cases Threat Hunting/ADSecurityEvents/AnalyticRules'                           = 'ADSecurityEvents'
    'Use Cases Threat Hunting/AzureCustomDetections/AnalyticRules'                      = 'AzureActivity'
    'Use Cases Threat Hunting/M365OfficeActivity/AnalyticRules'                         = 'M365OfficeActivity'
    'Use Cases Threat Hunting/Non-Human_Identities_Detections'                          = 'NonHumanIdentities'
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Section')]
        [string]$Level = 'Info'
    )
    switch ($Level) {
        'Section' { Write-Information "`n=== $Message ===" }
        'Success' { Write-Information "  [OK] $Message" }
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error $Message }
        default   { Write-Information "  $Message" }
    }
}

function Initialize-YamlModule {
    if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
        Write-Status "Installing powershell-yaml module (CurrentUser scope)..."
        Install-Module powershell-yaml -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module powershell-yaml -ErrorAction Stop
}

function Get-FileHash256 {
    param([string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

function Get-ContentHash256 {
    param([string]$Content)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $hash  = $sha.ComputeHash($bytes)
    return [System.BitConverter]::ToString($hash).Replace('-', '')
}

function Format-TriggerOperator {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    $mapped = $script:TriggerOpMap[$Value.ToLower()]
    return $mapped ?? $Value
}

function Merge-Tags {
    param($Existing)
    $set = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    if ($Existing -is [System.Collections.IEnumerable] -and $Existing -isnot [string]) {
        foreach ($t in $Existing) { [void]$set.Add($t.ToString()) }
    }
    elseif ($Existing -is [string] -and $Existing -ne '') {
        [void]$set.Add($Existing)
    }
    foreach ($t in $script:RequiredTags) { [void]$set.Add($t) }
    return @($set | Sort-Object)
}

function ConvertTo-Iso8601Duration {
    param([string]$Value)
    if ($Value -match '^\d+(m|h|d)$') {
        $num = [int]($Value -replace '[^\d]')
        switch -Regex ($Value) {
            'd$' { return "P${num}D" }
            'h$' { return "PT${num}H" }
            'm$' { return "PT${num}M" }
        }
    }
    return $Value
}

function Build-RuleYaml {
    <#
    .SYNOPSIS
        Applies all normalisation steps to a parsed rule hashtable and returns
        the final YAML string ready to write to disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Rule,
        [Parameter(Mandatory)] [string]$SourceFile
    )

    # Validate required fields. The rule may be a hashtable or an ordered
    # dictionary; a [hashtable] parameter would convert an ordered rule and
    # lose its key order. The result is wrapped in @() because under
    # Set-StrictMode -Version Latest .Count throws on $null and on a single
    # string, which made every rule with none or one field missing fail.
    $missing = @(@('id', 'name', 'kind', 'severity', 'query') | Where-Object {
        -not $Rule.Contains($_) -or [string]::IsNullOrWhiteSpace($Rule[$_])
    })
    if ($missing.Count -gt 0) {
        throw "Rule in '$SourceFile' is missing required fields: $($missing -join ', ')"
    }

    # Disable by default
    $Rule['enabled'] = $false

    # Prepend attribution to description
    $existing = if ($Rule.Contains('description')) { $Rule['description'] } else { '' }
    $Rule['description'] = $script:AttributionPrefix + $existing

    # Merge tags
    $Rule['tags'] = Merge-Tags -Existing ($Rule.Contains('tags') ? $Rule['tags'] : @())

    # Normalise triggerOperator
    if ($Rule.Contains('triggerOperator') -and $Rule['triggerOperator']) {
        $Rule['triggerOperator'] = Format-TriggerOperator -Value $Rule['triggerOperator']
    }

    return ConvertTo-Yaml $Rule
}

function Import-YamlFile {
    <#
    .SYNOPSIS
        Reads, normalises, and returns the YAML content for a single source rule file.
        Returns $null if the file should be skipped (validation failure).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    try {
        $raw  = Get-Content -Path $Path -Raw -Encoding utf8
        # -Ordered returns an OrderedDictionary, which is not a [hashtable];
        # checking for [hashtable] here skipped every YAML source rule.
        $rule = ConvertFrom-Yaml $raw -Ordered
        if ($null -eq $rule -or $rule -isnot [System.Collections.IDictionary]) {
            Write-Status "Skipping '$Path': the YAML is not a mapping" -Level Warning
            return $null
        }
        return Build-RuleYaml -Rule $rule -SourceFile $Path
    }
    catch {
        Write-Status "Skipping '$Path': $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function ConvertFrom-ArmAlertRule {
    <#
    .SYNOPSIS
        Converts a single ARM alertRule resource object into a normalised rule hashtable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Resource,
        [Parameter(Mandatory)] [string]$SourceFile
    )

    # Under Set-StrictMode -Version Latest reading a property the resource
    # does not have throws, so every optional property is read through $get.
    $get = {
        param($Object, [string]$Name)
        if ($null -eq $Object) { return $null }
        $prop = $Object.PSObject.Properties[$Name]
        if ($prop) { , $prop.Value } else { $null }
    }
    $p = & $get $Resource 'properties'

    # Build hashtable from ARM properties
    $rule = [ordered]@{}

    # id - use the rule name property or generate from displayName
    $displayName = (& $get $p 'displayName') ?? (& $get $p 'alertRuleTemplateName') ?? 'UnknownRule'
    $ruleId      = (& $get $p 'alertRuleTemplateName') ?? [guid]::NewGuid().ToString()

    $rule['id']          = $ruleId
    $rule['name']        = $displayName
    $rule['kind']        = (& $get $Resource 'kind') ?? 'Scheduled'
    $rule['description'] = (& $get $p 'description') ?? ''
    $rule['severity']    = (& $get $p 'severity') ?? 'Medium'
    $rule['query']       = (& $get $p 'query') ?? ''

    if (& $get $p 'queryFrequency')  { $rule['queryFrequency']   = ConvertTo-Iso8601Duration (& $get $p 'queryFrequency') }
    if (& $get $p 'queryPeriod')     { $rule['queryPeriod']      = ConvertTo-Iso8601Duration (& $get $p 'queryPeriod') }
    if (& $get $p 'triggerOperator') { $rule['triggerOperator']  = & $get $p 'triggerOperator' }
    if ($null -ne (& $get $p 'triggerThreshold')) { $rule['triggerThreshold'] = & $get $p 'triggerThreshold' }

    $tactics = & $get $p 'tactics'
    if ($tactics -and @($tactics).Count -gt 0) {
        $rule['tactics'] = @($tactics)
    }
    $techniques = & $get $p 'techniques'
    if ($techniques -and @($techniques).Count -gt 0) {
        $rule['techniques'] = @($techniques)
    }
    foreach ($name in 'entityMappings', 'customDetails', 'alertDetailsOverride', 'incidentConfiguration') {
        $value = & $get $p $name
        if ($value) { $rule[$name] = $value }
    }

    return Build-RuleYaml -Rule $rule -SourceFile $SourceFile
}

function Get-ArmRulesFromFolder {
    <#
    .SYNOPSIS
        Scans a folder for azuredeploy.json files, parses the ARM template, and
        returns a list of @{ Name; YamlContent } objects for each alertRule resource.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FolderPath
    )

    $results = [System.Collections.ArrayList]::new()

    # Search recursively for azuredeploy.json
    $armFiles = Get-ChildItem -Path $FolderPath -Recurse -Filter 'azuredeploy.json' -File -ErrorAction SilentlyContinue
    if (-not $armFiles) {
        Write-Status "No azuredeploy.json found under '$FolderPath'" -Level Warning
        return $results
    }

    foreach ($armFile in $armFiles) {
        try {
            $template = Get-Content -Path $armFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop

            $resources = if ($template.PSObject.Properties['resources']) { $template.resources } else { @() }
            $alertRules = @($resources | Where-Object {
                $_.PSObject.Properties['type'] -and $_.type -in @(
                    'Microsoft.SecurityInsights/alertRules',
                    'Microsoft.OperationalInsights/workspaces/providers/alertRules'
                )
            })

            if ($alertRules.Count -eq 0) {
                Write-Status "No alertRule resources found in '$($armFile.FullName)'" -Level Warning
                continue
            }

            foreach ($resource in $alertRules) {
                try {
                    $yamlContent = ConvertFrom-ArmAlertRule -Resource $resource -SourceFile $armFile.FullName
                    if ($null -eq $yamlContent) { continue }

                    # Derive a safe file name from the displayName
                    $displayName = if ($resource.properties.PSObject.Properties['displayName']) { $resource.properties.displayName } else { 'UnknownRule' }
                    $safeName    = ($displayName -replace '[^\w\-]', '-') -replace '-{2,}', '-'
                    $safeName    = $safeName.Trim('-')

                    [void]$results.Add(@{
                        Name        = "${safeName}.yaml"
                        YamlContent = $yamlContent
                        SourceFile  = $armFile.FullName
                    })
                }
                catch {
                    Write-Status "Skipping ARM rule in '$($armFile.FullName)': $($_.Exception.Message)" -Level Warning
                }
            }
        }
        catch {
            Write-Status "Failed to parse ARM template '$($armFile.FullName)': $($_.Exception.Message)" -Level Warning
        }
    }

    return $results
}

function Write-OutputFile {
    param(
        [string]$FilePath,
        [string]$Content
    )

    $dir = Split-Path $FilePath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    Set-Content -Path $FilePath -Value $Content -Encoding utf8NoBOM
}

function Get-RuleFileId {
    <#
    .SYNOPSIS
        Returns the top-level id a rule YAML file declares, or $null when the
        file does not exist or has no id line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ([string]::IsNullOrEmpty($text)) { return $null }
    $match = [regex]::Match($text, '(?m)^id:[ \t]*[''"]?([^''"\r\n]+?)[''"]?[ \t]*$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Get-ReservedRuleId {
    <#
    .SYNOPSIS
        Returns the ids used by rule files under a rules folder, outside the
        folder being imported into, as a hashtable of id -> relative path.
    .DESCRIPTION
        These are the ids an import must not hand to a community rule: the
        in-house rules and any other contributor's. Keys compare without
        regard to case, as the workspace does.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$RulesRoot,
        [Parameter(Mandatory)] [string]$ExcludePath
    )

    $ids = @{}
    if (-not (Test-Path -LiteralPath $RulesRoot -PathType Container)) { return $ids }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $exclude   = [System.IO.Path]::GetFullPath($ExcludePath).TrimEnd('/', '\') + $separator
    foreach ($file in Get-ChildItem -LiteralPath $RulesRoot -Recurse -File -Include '*.yaml', '*.yml') {
        if ($file.FullName.StartsWith($exclude, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $id = Get-RuleFileId -Path $file.FullName
        if ($id -and -not $ids.ContainsKey($id)) {
            $ids[$id] = [System.IO.Path]::GetRelativePath($RulesRoot, $file.FullName).Replace('\', '/')
        }
    }
    return $ids
}

function New-CommunityRuleId {
    <#
    .SYNOPSIS
        Returns a name-based (RFC 4122 version 5, SHA-1) GUID for a rule, so
        the same name gives the same id on every run.
    .DESCRIPTION
        Uses the RFC 4122 URL namespace. The caller passes the source
        repository and the rule's relative path, which together name one
        upstream rule.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Computes a GUID from a name; nothing changes.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name
    )

    $namespace = [byte[]](0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8)
    $data      = [byte[]]($namespace + [System.Text.Encoding]::UTF8.GetBytes($Name))
    $sha1      = [System.Security.Cryptography.SHA1]::Create()
    try { $hash = $sha1.ComputeHash($data) }
    finally { $sha1.Dispose() }

    $hash[6] = ($hash[6] -band 0x0f) -bor 0x50
    $hash[8] = ($hash[8] -band 0x3f) -bor 0x80
    $hex = -join ($hash[0..15] | ForEach-Object { $_.ToString('x2') })
    return '{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0, 8), $hex.Substring(8, 4), $hex.Substring(12, 4), $hex.Substring(16, 4), $hex.Substring(20, 12)
}

function Resolve-CommunityRuleId {
    <#
    .SYNOPSIS
        Gives every pending rule an id no other rule file uses, keeping the
        id a rule already has in the repository.
    .DESCRIPTION
        The deployer names each rule in the workspace by its id, so two files
        with one id are one rule and every deploy overwrites one with the
        other. Upstream repositories can reuse ids across their categories,
        and a file in the repository may have been given a new id after an
        earlier import. In ordinal order of relative path:

        1. A rule whose destination file already exists keeps that file's
           id, so a re-import never changes a deployed rule's identity.
        2. Any other rule keeps its upstream id unless another rule (pending,
           or under -ReservedIds) already has it; then it gets
           New-CommunityRuleId for the source repository and its relative
           path, the same on every run.

        Ids compare without regard to case. Only the top-level id line of a
        rule's YamlContent is changed, in place.
    .PARAMETER PendingRules
        The rules collected for this import, each a hashtable with
        RelativePath and YamlContent.
    .PARAMETER OutputPath
        The folder the rules are written to.
    .PARAMETER SourceRepo
        The source repository URL. A trailing .git or slash is ignored.
    .PARAMETER ReservedIds
        Ids used by rule files outside the import, as id -> path.
    .OUTPUTS
        One object per rule whose id is not its upstream id: RelativePath,
        UpstreamId, Id and Reason.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IList]$PendingRules,
        [Parameter(Mandatory)] [string]$OutputPath,
        [Parameter(Mandatory)] [string]$SourceRepo,
        [hashtable]$ReservedIds = @{}
    )

    $idLine = '(?m)^id:[ \t]*[''"]?([^''"\r\n]+?)[''"]?[ \t]*$'
    $source = ($SourceRepo.TrimEnd('/') -replace '\.git$', '').TrimEnd('/')
    $used   = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $ReservedIds.Keys) { $used[[string]$key] = [string]$ReservedIds[$key] }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in $PendingRules) {
        $relative = ([string]$rule.RelativePath).Replace('\', '/')
        $match    = [regex]::Match([string]$rule.YamlContent, $idLine)
        if (-not $match.Success) { throw "Rule '$relative' has no top-level id line." }
        $entries.Add([pscustomobject]@{
            Rule     = $rule
            Relative = $relative
            Upstream = $match.Groups[1].Value.Trim()
            Existing = Get-RuleFileId -Path (Join-Path $OutputPath $rule.RelativePath)
        })
    }
    $entries.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Relative, $b.Relative) })

    $changes = [System.Collections.Generic.List[object]]::new()
    $assign = {
        param($Entry, [string]$Id, [string]$Reason)
        if ($Id -cne $Entry.Upstream) {
            $Entry.Rule.YamlContent = [regex]::new('(?m)^id:[^\r\n]*').Replace([string]$Entry.Rule.YamlContent, "id: $Id", 1)
            $changes.Add([pscustomobject]@{
                RelativePath = $Entry.Relative
                UpstreamId   = $Entry.Upstream
                Id           = $Id
                Reason       = $Reason
            })
        }
        $used[$Id] = $Entry.Relative
    }

    # Ids the repository already gave a file are claimed first.
    $fresh = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $entries) {
        if ($entry.Existing -and -not $used.ContainsKey($entry.Existing)) {
            & $assign $entry $entry.Existing 'kept the id the repository file has'
            continue
        }
        $fresh.Add($entry)
    }

    foreach ($entry in $fresh) {
        if (-not $used.ContainsKey($entry.Upstream)) {
            & $assign $entry $entry.Upstream ''
            continue
        }
        $derived = New-CommunityRuleId -Name "$source#$($entry.Relative)"
        if ($used.ContainsKey($derived)) {
            throw "Rule '$($entry.Relative)': the derived id $derived is already used by '$($used[$derived])'."
        }
        & $assign $entry $derived "upstream id $($entry.Upstream) is already used by $($used[$entry.Upstream])"
    }

    return $changes.ToArray()
}

function Build-Readme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$CategoryStats,
        [Parameter(Mandatory)] [hashtable]$RuleDetails,
        [Parameter(Mandatory)] [string]$ImportDate
    )

    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("# Community Rules: David Alonso - Threat Hunting")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("## Attribution")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("These analytical rules were authored by **David Alonso** and sourced from the")
    [void]$sb.AppendLine("[Dalonso Security Repository](https://github.com/davidalonsod/Dalonso-Security-Repo).")
    [void]$sb.AppendLine("David maintains a comprehensive collection of Microsoft Sentinel threat-hunting")
    [void]$sb.AppendLine("detections across identity, endpoint, cloud, and network data sources.")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("## License")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("All rules in this directory are released under **The Unlicense** (public domain).")
    [void]$sb.AppendLine("You are free to use, modify, and distribute them without restriction.")
    [void]$sb.AppendLine("See [The Unlicense](https://unlicense.org) for full terms.")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("## Deployment Note")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("These rules deploy as **disabled** by default. Enable individual rules in the")
    [void]$sb.AppendLine("Microsoft Sentinel portal after reviewing them against your environment's data")
    [void]$sb.AppendLine("sources, retention, and noise tolerance.")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("## Categories")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("| Category | Rule Count |")
    [void]$sb.AppendLine("|---|---|")
    foreach ($cat in ($CategoryStats.Keys | Sort-Object)) {
        [void]$sb.AppendLine("| $cat | $($CategoryStats[$cat]) |")
    }
    [void]$sb.AppendLine()

    # Per-category rule listings
    foreach ($cat in ($RuleDetails.Keys | Sort-Object)) {
        [void]$sb.AppendLine("## $cat")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("| Name | Severity | Description |")
        [void]$sb.AppendLine("|---|---|---|")
        foreach ($entry in $RuleDetails[$cat]) {
            $descFirstLine = ($entry.Description -split "`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1) ?? ''
            # Escape pipe chars in table cells
            $safeName  = $entry.Name -replace '\|', '\|'
            $safeSev   = $entry.Severity -replace '\|', '\|'
            $safeDesc  = $descFirstLine -replace '\|', '\|'
            [void]$sb.AppendLine("| $safeName | $safeSev | $safeDesc |")
        }
        [void]$sb.AppendLine()
    }

    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("Last synced: $ImportDate")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("To re-import or update these rules, run:")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('```powershell')
    [void]$sb.AppendLine(".\Tools\Import-CommunityRules.ps1")
    [void]$sb.AppendLine('```')

    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
function Invoke-Main {
    Write-Status "Import Community Rules - Dalonso Security Repo" -Level Section

    if ($DryRun) {
        Write-Status "DRY RUN mode - no files will be written" -Level Warning
    }

    # Resolve output path to an absolute path
    $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    Write-Status "Output path: $OutputPath"

    # Ensure powershell-yaml is available
    Initialize-YamlModule

    # Create a temp directory for the clone
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "dalonso-import-$([System.IO.Path]::GetRandomFileName())"

    try {
        # Clone source repository (shallow, single branch)
        Write-Status "Cloning repository" -Level Section
        Write-Status "Source: $SourceRepo ($SourceBranch)"
        Write-Status "Destination: $tempDir"

        try {
            $cloneArgs = @(
                'clone',
                '--depth', '1',
                '--branch', $SourceBranch,
                '--single-branch',
                $SourceRepo,
                $tempDir
            )
            $gitOutput = & git @cloneArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git clone exited with code $LASTEXITCODE.`n$gitOutput"
            }
            Write-Status "Clone completed" -Level Success
        }
        catch {
            throw "Failed to clone repository: $($_.Exception.Message)"
        }

        # Capture source commit SHA
        $sourceCommitSha = ''
        try {
            $sourceCommitSha = (& git -C $tempDir rev-parse HEAD 2>&1).Trim()
            if ($LASTEXITCODE -ne 0) { $sourceCommitSha = 'unknown' }
        }
        catch { $sourceCommitSha = 'unknown' }
        Write-Status "Source commit: $sourceCommitSha"

        # ---------------------------------------------------------------------------
        # Collect rules
        # ---------------------------------------------------------------------------
        Write-Status "Collecting rules" -Level Section

        # Each entry: @{ RelativePath; YamlContent; Category }
        $pendingRules = [System.Collections.ArrayList]::new()
        $stats = @{ Imported = 0; Updated = 0; Skipped = 0; Errors = 0 }

        # --- YAML-native folders ---
        foreach ($srcFolder in $script:YamlFolderMap.Keys) {
            $folderInfo    = $script:YamlFolderMap[$srcFolder]
            $targetCategory = $folderInfo.Target
            $yamlOnly       = $folderInfo.YamlOnly

            $srcPath = Join-Path $tempDir $srcFolder
            if (-not (Test-Path $srcPath)) {
                Write-Status "Source folder not found, skipping: $srcFolder" -Level Warning
                continue
            }

            $filter = if ($yamlOnly) { '*.yaml' } else { '*.yaml' }
            $yamlFiles = Get-ChildItem -Path $srcPath -Filter $filter -File -ErrorAction SilentlyContinue

            foreach ($file in $yamlFiles) {
                # Skip .kql files (already filtered by glob, but be explicit)
                if ($file.Extension -eq '.kql') { continue }

                $yamlContent = Import-YamlFile -Path $file.FullName
                if ($null -eq $yamlContent) {
                    $stats.Errors++
                    continue
                }

                $relPath = Join-Path $targetCategory $file.Name
                [void]$pendingRules.Add(@{
                    RelativePath = $relPath
                    YamlContent  = $yamlContent
                    Category     = $targetCategory
                    SourceFile   = $file.FullName
                })
            }
        }

        # --- ARM/KQL folders (optional) ---
        if ($IncludeKqlConversion) {
            Write-Status "Processing ARM/KQL folders" -Level Section

            foreach ($srcFolder in $script:ArmFolderMap.Keys) {
                $targetCategory = $script:ArmFolderMap[$srcFolder]
                $srcPath = Join-Path $tempDir $srcFolder

                if (-not (Test-Path $srcPath)) {
                    Write-Status "ARM source folder not found, skipping: $srcFolder" -Level Warning
                    continue
                }

                $armRules = Get-ArmRulesFromFolder -FolderPath $srcPath
                foreach ($armRule in $armRules) {
                    $relPath = Join-Path $targetCategory $armRule.Name
                    [void]$pendingRules.Add(@{
                        RelativePath = $relPath
                        YamlContent  = $armRule.YamlContent
                        Category     = $targetCategory
                        SourceFile   = $armRule.SourceFile
                    })
                }
            }
        }

        Write-Status "Total rules collected: $($pendingRules.Count)"

        # ---------------------------------------------------------------------------
        # Resolve rule ids
        # ---------------------------------------------------------------------------
        # The deployer names a rule by its id, so no two rule files may share
        # one. Keep the ids the repository already has and give a stable new id
        # to any rule whose upstream id another file uses.
        $rulesRoot   = Join-Path (Split-Path -Path $PSScriptRoot -Parent) (Join-Path 'Content' 'AnalyticalRules')
        $reservedIds = Get-ReservedRuleId -RulesRoot $rulesRoot -ExcludePath $OutputPath
        $idChanges   = @(Resolve-CommunityRuleId -PendingRules $pendingRules -OutputPath $OutputPath -SourceRepo $SourceRepo -ReservedIds $reservedIds)
        foreach ($change in $idChanges) {
            Write-Status "  ID $($change.RelativePath): $($change.Id) instead of $($change.UpstreamId) ($($change.Reason))" -Level Warning
        }

        # ---------------------------------------------------------------------------
        # Write output files
        # ---------------------------------------------------------------------------
        Write-Status "Writing output files" -Level Section

        $manifestFiles     = [ordered]@{}
        $categoryStats     = @{}
        $readmeRuleDetails = @{}

        foreach ($pending in $pendingRules) {
            $destFile = Join-Path $OutputPath $pending.RelativePath

            # Track category stats
            $cat = $pending.Category
            if (-not $categoryStats.ContainsKey($cat))     { $categoryStats[$cat]     = 0 }
            if (-not $readmeRuleDetails.ContainsKey($cat)) { $readmeRuleDetails[$cat] = [System.Collections.ArrayList]::new() }

            # Parse YAML back to extract name/severity for README
            try {
                $parsedForReadme = ConvertFrom-Yaml $pending.YamlContent -Ordered
                $ruleName     = $parsedForReadme['name'] ?? (Split-Path $pending.RelativePath -Leaf)
                $ruleSeverity = $parsedForReadme['severity'] ?? 'Unknown'
                $ruleDesc     = $parsedForReadme['description'] ?? ''
                [void]$readmeRuleDetails[$cat].Add(@{
                    Name        = $ruleName
                    Severity    = $ruleSeverity
                    Description = $ruleDesc
                })
            }
            catch {
                # Non-fatal - README entry just won't be as rich
            }

            $contentHash = Get-ContentHash256 -Content $pending.YamlContent
            $manifestKey = $pending.RelativePath -replace '\\', '/'

            if ($DryRun) {
                $action = if (Test-Path $destFile) { 'UPDATE' } else { 'CREATE' }
                Write-Status "  [DRY RUN] $action $($pending.RelativePath)"
                $stats.Imported++
                $categoryStats[$cat]++
                $manifestFiles[$manifestKey] = $contentHash
                continue
            }

            # Determine if file changed
            if (Test-Path $destFile) {
                $existingContent = Get-Content -Path $destFile -Raw -Encoding utf8
                $existingHash    = Get-ContentHash256 -Content $existingContent
                if ($existingHash -eq $contentHash) {
                    Write-Status "  UNCHANGED $($pending.RelativePath)"
                    $stats.Skipped++
                    $categoryStats[$cat]++
                    $manifestFiles[$manifestKey] = $contentHash
                    continue
                }
                Write-Status "  UPDATE $($pending.RelativePath)" -Level Success
                $stats.Updated++
            }
            else {
                Write-Status "  CREATE $($pending.RelativePath)" -Level Success
                $stats.Imported++
            }

            Write-OutputFile -FilePath $destFile -Content $pending.YamlContent
            $categoryStats[$cat]++
            $manifestFiles[$manifestKey] = $contentHash
        }

        # ---------------------------------------------------------------------------
        # Write manifest
        # ---------------------------------------------------------------------------
        $importDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        $manifest = [ordered]@{
            sourceRepo      = $SourceRepo
            sourceBranch    = $SourceBranch
            sourceCommitSha = $sourceCommitSha
            importDate      = $importDate
            files           = $manifestFiles
        }

        $manifestJson = $manifest | ConvertTo-Json -Depth 10
        $manifestPath = Join-Path $OutputPath 'import-manifest.json'

        if ($DryRun) {
            Write-Status "[DRY RUN] Would write manifest: $manifestPath"
        }
        else {
            Write-OutputFile -FilePath $manifestPath -Content $manifestJson
            Write-Status "Manifest written: $manifestPath" -Level Success
        }

        # ---------------------------------------------------------------------------
        # Write README
        # ---------------------------------------------------------------------------
        # Convert ArrayList values to plain arrays for README builder
        $readmeDetailsClean = @{}
        foreach ($key in $readmeRuleDetails.Keys) {
            $readmeDetailsClean[$key] = @($readmeRuleDetails[$key])
        }

        $readmeContent = Build-Readme `
            -CategoryStats $categoryStats `
            -RuleDetails $readmeDetailsClean `
            -ImportDate $importDate

        # README is written to $DocsPath (under Docs/Community/) so all
        # governance documentation lives in a single tree. The manifest stays
        # next to the rules under $OutputPath because it's an operational
        # artifact (content hashes for upstream-drift detection), not a doc.
        if ($DryRun) {
            Write-Status "[DRY RUN] Would write README: $DocsPath"
        }
        else {
            Write-OutputFile -FilePath $DocsPath -Content $readmeContent
            Write-Status "README written: $DocsPath" -Level Success
        }

        # ---------------------------------------------------------------------------
        # Summary
        # ---------------------------------------------------------------------------
        Write-Status "Import Complete" -Level Section
        Write-Status "  Imported (new):    $($stats.Imported)"
        Write-Status "  Updated:           $($stats.Updated)"
        Write-Status "  Skipped (no diff): $($stats.Skipped)"
        if ($stats.Errors -gt 0) {
            Write-Status "  Errors:            $($stats.Errors)" -Level Warning
        }
    }
    finally {
        # Clean up temp directory
        if (Test-Path $tempDir) {
            try {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Status "Cleaned up temp directory: $tempDir"
            }
            catch {
                Write-Status "Could not remove temp directory '$tempDir': $($_.Exception.Message)" -Level Warning
            }
        }
    }
}

Invoke-Main
