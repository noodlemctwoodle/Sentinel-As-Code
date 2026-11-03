#Requires -Version 7.2

<#
.SYNOPSIS
    ToRepoFile handler for analytics rules: a workspace rule as a rule
    file in the repository's style.

.DESCRIPTION
    Copied from New-AbsorbedRuleYaml (Tools/Test-SentinelRuleDrift.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCAnalyticsRuleYaml.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCAnalyticsRuleYaml {
    <#
    .SYNOPSIS
        Return the YAML text for a rule absorbed from the workspace.

    .DESCRIPTION
        In the order the repository's rules use: id (the rule's name, which
        keeps the workspace rule governed by the file), name, description (a
        stub naming where it came from when the rule has none), severity,
        the schedule and trigger for a Scheduled rule (the operator in its
        short form), enabled, tactics, relevantTechniques (the API's
        techniques and subTechniques in one sorted list, each sub-technique
        after its parent), query, entityMappings, eventGroupingSettings,
        incidentConfiguration, version 1.0.0, kind, and tags naming where it
        was absorbed from, and its solution.

    .PARAMETER WorkspaceItem
        A rule as Read-iSOCAnalyticsRuleWorkspace returns it.

    .PARAMETER Provenance
        ContentHub or Orphan.

    .PARAMETER SolutionName
        The Content Hub solution, for its tag.

    .OUTPUTS
        [string] The file's text, ending in a newline.

    .EXAMPLE
        ConvertTo-iSOCAnalyticsRuleYaml -WorkspaceItem $rule -Provenance Orphan
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $WorkspaceItem,

        [Parameter(Mandatory)]
        [ValidateSet('ContentHub', 'Orphan')]
        [string] $Provenance,

        [string] $SolutionName
    )

    $props = $WorkspaceItem.properties
    $kind = if ($WorkspaceItem.PSObject.Properties.Name -contains 'kind') { [string]$WorkspaceItem.kind } else { 'Scheduled' }
    $has = { param([string] $Name) $props.PSObject.Properties.Name -contains $Name }
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("id: $(([string]$WorkspaceItem.name).ToLowerInvariant())")
    $displayName = if (& $has 'displayName') { [string]$props.displayName } else { [string]$WorkspaceItem.name }
    $lines.Add("name: $(ConvertTo-iSOCYamlScalar $displayName)")

    $description = if (& $has 'description') { [string]$props.description } else { '' }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = "Absorbed from $Provenance via Sentinel-Drift-Detect on $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))."
    }
    $lines.Add('description: |')
    foreach ($line in (($description.TrimEnd()) -split "`r?`n")) { $lines.Add("  $line") }

    $severity = if (& $has 'severity') { ConvertTo-iSOCRuleSeverity ([string]$props.severity) } else { 'Medium' }
    $lines.Add("severity: $severity")

    if ($kind -eq 'Scheduled') {
        if (& $has 'queryFrequency') { $lines.Add("queryFrequency: $([string]$props.queryFrequency)") }
        if (& $has 'queryPeriod') { $lines.Add("queryPeriod: $([string]$props.queryPeriod)") }
        if (& $has 'triggerOperator') { $lines.Add("triggerOperator: $(ConvertTo-iSOCShortTriggerOperator ([string]$props.triggerOperator))") }
        if (& $has 'triggerThreshold') { $lines.Add("triggerThreshold: $([int]$props.triggerThreshold)") }
    }

    $enabled = if (& $has 'enabled') { [bool]$props.enabled } else { $true }
    $lines.Add("enabled: $($enabled.ToString().ToLowerInvariant())")

    if ((& $has 'tactics') -and $props.tactics) {
        $tacticArray = @($props.tactics)
        if ($tacticArray.Count -gt 0) {
            $lines.Add('tactics:')
            foreach ($t in $tacticArray) { $lines.Add("- $t") }
        }
    }

    $techArray = @(foreach ($field in 'techniques', 'subTechniques') {
            if ((& $has $field) -and $props.$field) { @($props.$field) }
        }) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique
    if (@($techArray).Count -gt 0) {
        $lines.Add('relevantTechniques:')
        foreach ($t in $techArray) { $lines.Add("- $t") }
    }

    if (& $has 'query') {
        $lines.Add('query: |')
        foreach ($line in ((([string]$props.query).TrimEnd()) -split "`r?`n")) { $lines.Add("  $line") }
    }

    if ((& $has 'entityMappings') -and $props.entityMappings) {
        $em = @($props.entityMappings)
        if ($em.Count -gt 0) {
            $lines.Add('entityMappings:')
            foreach ($line in ((ConvertTo-iSOCYamlSubtree -Object $em -Indent 0) -split "`r?`n")) { if ($line.Length -gt 0) { $lines.Add($line) } }
        }
    }

    foreach ($section in 'eventGroupingSettings', 'incidentConfiguration') {
        if ((& $has $section) -and $props.$section) {
            $lines.Add("${section}:")
            foreach ($line in ((ConvertTo-iSOCYamlSubtree -Object $props.$section -Indent 2) -split "`r?`n")) { if ($line.Length -gt 0) { $lines.Add($line) } }
        }
    }

    $lines.Add('version: 1.0.0')
    $lines.Add("kind: $kind")
    $lines.Add('tags:')
    $lines.Add('- Sentinel-As-Code')
    $lines.Add('- Custom')
    $lines.Add("- AbsorbedFromPortal-$Provenance")
    if ($SolutionName) { $lines.Add("- $(ConvertTo-iSOCYamlScalar $SolutionName)") }

    ($lines -join "`n") + "`n"
}
