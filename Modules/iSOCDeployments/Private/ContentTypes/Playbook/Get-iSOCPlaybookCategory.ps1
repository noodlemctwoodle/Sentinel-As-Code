#Requires -Version 7.6

<#
.SYNOPSIS
    The Content/Playbooks/ folder a workflow's trigger puts it in.

.DESCRIPTION
    Copied from Get-TriggerCategory (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookCategory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCPlaybookCategory {
    <#
    .SYNOPSIS
        Return Incident, Entity, Alert, Module, Watchlist or Other for a
        workflow definition.

    .DESCRIPTION
        By the first trigger that tells: a Sentinel webhook on
        /incident-creation is Incident, on /entity/ Entity, on /subscribe
        Alert; an HTTP request trigger is Module; a connector trigger on a
        watchlist path is Watchlist. Failing those, a definition whose
        actions mention watchlists is Watchlist, and anything else Other.

    .PARAMETER Definition
        The workflow definition.

    .OUTPUTS
        [string] The category.

    .EXAMPLE
        Get-iSOCPlaybookCategory -Definition $app.properties.definition
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Definition
    )

    $triggers = Get-iSOCPropertyValue -InputObject $Definition -Path 'triggers'
    foreach ($entry in @(Get-iSOCPropertyEntry -InputObject $triggers)) {
        $trigger = $entry.Value
        $triggerType = Get-iSOCPropertyValue -InputObject $trigger -Path 'type'
        $triggerKind = Get-iSOCPropertyValue -InputObject $trigger -Path 'kind'
        $path = Get-iSOCPropertyValue -InputObject $trigger -Path 'inputs.path'

        if ($triggerType -eq 'ApiConnectionWebhook') {
            if ($path -match '/incident-creation') { return 'Incident' }
            if ($path -match '/entity/') { return 'Entity' }
            if ($path -match '/subscribe') { return 'Alert' }
        }
        if ($triggerType -eq 'Request' -and $triggerKind -eq 'Http') { return 'Module' }
        if ($triggerType -eq 'ApiConnection' -and $path -match '/watchlist') { return 'Watchlist' }
    }

    $actions = Get-iSOCPropertyValue -InputObject $Definition -Path 'actions'
    if ($actions) {
        $actionsJson = $actions | ConvertTo-Json -Depth 100 -Compress
        if ($actionsJson -match 'watchlist') { return 'Watchlist' }
    }
    'Other'
}
