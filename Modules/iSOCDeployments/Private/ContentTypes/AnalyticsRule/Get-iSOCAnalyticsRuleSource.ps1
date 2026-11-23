#Requires -Version 7.6

<#
.SYNOPSIS
    Classify handler for analytics rules: where a workspace rule's source
    of truth is.

.DESCRIPTION
    Replaces Resolve-RuleSource and the filters at the top of the rule loop
    in Invoke-Main (Tools/Test-SentinelRuleDrift.ps1). The repository's
    rules, the Content Hub templates and the solution names are read once
    per run, whatever is excluded: the script did not read the rule files
    under -SkipCustom, nor the templates under -SkipContentHub, so those
    rules were classed as orphans and exported again as new files. Here an
    excluded source is skipped (MIGRATION.md edit E23).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Get-iSOCAnalyticsRuleSource.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCAnalyticsRuleSource {
    <#
    .SYNOPSIS
        Say whether a workspace rule is Microsoft-managed, filtered out,
        governed by a repository file, from Content Hub, or portal-only.

    .DESCRIPTION
        In order:
        - Fusion, MicrosoftSecurityIncidentCreation, MLBehaviorAnalytics and
          ThreatIntelligence rules are Microsoft-managed and not compared;
        - a rule of a severity not asked for, or one marked [Deprecated], is
          skipped;
        - a rule whose name (its id) is a repository rule's id is governed
          by that file (Custom), even when it is also linked to a template:
          that is how a rule absorbed from the portal stays governed. The
          file is compared as deploy would send it; one that does not
          validate is skipped;
        - a rule linked to a template the workspace has is from Content Hub,
          compared with the template's rule; -Solution limits these to the
          solutions named;
        - anything else exists only in the workspace (Orphan).

    .PARAMETER Run
        The drift run, for its options and its cache.

    .PARAMETER ContentType
        The analytics rule content type.

    .PARAMETER WorkspaceItem
        A rule as Read-iSOCAnalyticsRuleWorkspace returns it.

    .OUTPUTS
        [hashtable] Source (Managed, Custom, ContentHub, Orphan or nothing
        when filtered out first), State (Managed, Skipped or PortalOnly when
        no compare is needed; nothing otherwise), Reason, Expected (the
        body to compare with), SourceRef, SourcePath and Solution.

    .EXAMPLE
        $source = Get-iSOCAnalyticsRuleSource -Run $run -ContentType $rules -WorkspaceItem $rule
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [Parameter(Mandatory)]
        [psobject] $WorkspaceItem
    )

    $cache = $Run.Cache
    $key = $ContentType.Name
    if (-not $cache.ContainsKey("$key.Repo")) {
        $byId = @{}
        $items = @(Invoke-iSOCContentTypeHandler -ContentType $ContentType -Handler ReadRepo -Parameters @{ RepoPath = $Run.RepoPath; ContentType = $ContentType })
        foreach ($item in $items) {
            if ($item.ParseError) { Write-iSOCLog "Failed to parse YAML '$($item.RelativePath)': $($item.ParseError)" -Level Warning; continue }
            if ($item.Identity) { $byId[$item.Identity] = $item }
        }
        Write-iSOCLog "Indexed $($byId.Count) repo YAML rule(s); skipped $($items.Count - $byId.Count)."
        $cache["$key.Repo"] = $byId

        Write-iSOCLog 'Fetching Content Hub Analytics Rule templates...'
        $templates = @{}
        foreach ($template in Get-iSOCContentHubTemplate -Context $Run.Context -Kind AnalyticsRule -ExpandMainTemplate) {
            $contentId = Get-iSOCPropertyValue -InputObject $template -Path 'properties.contentId'
            if (-not $contentId) { $contentId = $template.name }
            if ($contentId) { $templates[[string]$contentId] = $template }
        }
        Write-iSOCLog "Found $($templates.Count) Content Hub Analytics Rule templates."
        $cache["$key.Templates"] = $templates

        $names = Get-iSOCContentHubSolutionName -Context $Run.Context
        $cache["$key.Solutions"] = $names
        $allowed = $null
        if (@($Run.Options.Solution).Count -gt 0) {
            $wanted = @($Run.Options.Solution | ForEach-Object { $_.ToLowerInvariant() })
            $allowed = @{}
            foreach ($packageId in $names.Keys) {
                if ($wanted -contains $names[$packageId].ToLowerInvariant()) { $allowed[$packageId] = $true }
            }
            Write-iSOCLog "Solution filter active: $($Run.Options.Solution -join ', ') -> $($allowed.Keys.Count) packageId(s) matched."
        }
        $cache["$key.AllowedPackages"] = $allowed
    }

    $result = @{ Source = $null; State = $null; Reason = ''; Expected = $null; SourceRef = $null; SourcePath = $null; Solution = $null }
    $actual = ConvertTo-iSOCAnalyticsRuleComparable -WorkspaceItem $WorkspaceItem
    $properties = $actual.properties

    if ($actual.kind -in 'Fusion', 'MicrosoftSecurityIncidentCreation', 'MLBehaviorAnalytics', 'ThreatIntelligence') {
        $result.Source = 'Managed'
        $result.State = 'Managed'
        $result.Reason = 'Microsoft-managed rule kind'
        return $result
    }

    $severity = ConvertTo-iSOCRuleSeverity (Get-iSOCPropertyValue -InputObject $properties -Path 'severity')
    if (@($Run.Options.Severity).Count -gt 0 -and $severity -and $Run.Options.Severity -notcontains $severity) {
        $result.State = 'Skipped'
        $result.Reason = "severity $severity is not included"
        return $result
    }
    $displayName = [string](Get-iSOCPropertyValue -InputObject $properties -Path 'displayName')
    if ($displayName -and $displayName -match '\[Deprecated\]') {
        $result.State = 'Skipped'
        $result.Reason = 'the rule is deprecated'
        return $result
    }

    $excluded = @($Run.Options.ExcludeSource)
    $ruleId = ([string]$WorkspaceItem.name).ToLowerInvariant()
    $repo = $cache["$key.Repo"]
    if ($ruleId -and $repo.ContainsKey($ruleId)) {
        $item = $repo[$ruleId]
        $result.Source = 'Custom'
        $result.SourceRef = $item.RelativePath
        $result.SourcePath = $item.Path
        if ($excluded -contains 'Custom') {
            $result.State = 'Skipped'
            $result.Reason = 'Custom rules are excluded'
            return $result
        }
        $issues = @(Invoke-iSOCContentTypeHandler -ContentType $ContentType -Handler Validate -Parameters @{ Item = $item })
        if ($issues.Count -gt 0) {
            $result.State = 'Skipped'
            $result.Reason = "the rule file does not validate: $($issues[0])"
            return $result
        }
        $result.Expected = (Invoke-iSOCContentTypeHandler -ContentType $ContentType -Handler ToRequest -Parameters @{ Item = $item }).Body
        return $result
    }

    $templateName = Get-iSOCPropertyValue -InputObject $properties -Path 'alertRuleTemplateName'
    $templates = $cache["$key.Templates"]
    if (-not [string]::IsNullOrWhiteSpace([string]$templateName) -and $templates.ContainsKey([string]$templateName)) {
        $template = $templates[[string]$templateName]
        $packageId = Get-iSOCPropertyValue -InputObject $template -Path 'properties.packageId'
        $names = $cache["$key.Solutions"]
        $result.Source = 'ContentHub'
        $result.SourceRef = [string]$templateName
        $result.Solution = if ($packageId -and $names.ContainsKey([string]$packageId)) { $names[[string]$packageId] } else { $null }
        if ($excluded -contains 'ContentHub') {
            $result.State = 'Skipped'
            $result.Reason = 'Content Hub rules are excluded'
            return $result
        }
        $allowed = $cache["$key.AllowedPackages"]
        if ($null -ne $allowed -and (-not $packageId -or -not $allowed.ContainsKey([string]$packageId))) {
            $result.State = 'Skipped'
            $result.Reason = 'its solution is not included'
            return $result
        }
        $result.Expected = Get-iSOCAnalyticsRuleTemplateBody -Template $template
        if ($null -eq $result.Expected) {
            Write-iSOCLog "  Could not extract template properties for '$displayName'; skipping." -Level Debug
            $result.State = 'Skipped'
            $result.Reason = 'the template has no rule'
        }
        return $result
    }

    $result.Source = 'Orphan'
    if ($excluded -contains 'Orphan') {
        $result.State = 'Skipped'
        $result.Reason = 'orphan rules are excluded'
        return $result
    }
    $result.State = 'PortalOnly'
    $result.Reason = 'no repository file or Content Hub template'
    $result
}
