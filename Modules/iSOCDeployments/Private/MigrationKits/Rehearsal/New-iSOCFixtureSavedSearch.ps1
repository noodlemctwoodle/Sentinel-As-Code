#Requires -Version 7.6

<#
.SYNOPSIS
    Write the dependency fixture's parsers and hunting query.

.DESCRIPTION
    In dependency order, the cycle closed by a third write; saved searches are
    not validated on write.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCFixtureSavedSearch.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCFixtureSavedSearch {
    <#
    .SYNOPSIS
        Write the dependency fixture's parsers and hunting query.

    .DESCRIPTION
        Saved searches are not validated on write, so these save whatever the
        tables' state; they still go in dependency order, so a partial
        failure leaves a sane state, the cycle closed by a last write of
        parser A. The parsers are in the '<prefix> Fixture' category; the
        hunting query is in Hunting Queries with no alias, so the review
        counts it as a hunting query. Each write asks ShouldProcess; a write
        that fails is a warning and counted.

    .PARAMETER Fixture
        From Get-iSOCDependencyFixturePlan.

    .PARAMETER RunId
        The run.

    .OUTPUTS
        [pscustomobject] Created and Failed.

    .EXAMPLE
        New-iSOCFixtureSavedSearch -Fixture $fixture -RunId $runId
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Fixture,

        [Parameter(Mandatory)]
        [string] $RunId
    )

    $marker = (Get-iSOCDependencyFixtureSetting).FixtureMarker
    $created = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $put = {
        param($Id, $Body)
        Invoke-iSOCRestRequest -Method PUT -Path "$($Fixture.WorkspaceBase)/savedSearches/$Id" -ApiVersion (Get-iSOCApiVersion SavedSearches) -Body $Body | Out-Null
    }

    Write-iSOCLog 'Creating parsers' -Level Section
    Write-iSOCLog 'Saved searches are not validated server side, so these save whether or not the tables have finished materialising. They are still created in dependency order so a partial failure leaves a sane state.'
    foreach ($parser in $Fixture.Plan.Parser) {
        $resource = "$($Fixture.WorkspaceBase)/savedSearches/$($parser.SavedSearchId)"
        $action = if ($parser.IsCycleClosure) { 'Update fixture parser to close the reference cycle' } else { "Create fixture parser (alias $($parser.Alias))" }
        if (-not $PSCmdlet.ShouldProcess($resource, $action)) {
            Write-iSOCLog "Skipped $($parser.SavedSearchId)." -Level Warning
            continue
        }
        try {
            $body = New-iSOCFixtureSavedSearchBody -Category "$($Fixture.Plan.NamePrefix) Fixture" -DisplayName $parser.DisplayName -Query $parser.Query -FunctionAlias $parser.Alias -FixtureMarker $marker -RunId $RunId -ScenarioName $parser.ScenarioName
            & $put $parser.SavedSearchId $body
            $verb = if ($parser.IsCycleClosure) { 'Closed the cycle on' } else { 'Created' }
            Write-iSOCLog "$verb parser $($parser.SavedSearchId) (alias $($parser.Alias))." -Level Success
            if (-not $parser.IsCycleClosure) { $created.Add($resource) }
        }
        catch {
            Write-iSOCLog "Failed to write $($parser.SavedSearchId): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
            $failed.Add($resource)
        }
    }

    foreach ($hunt in $Fixture.Plan.HuntingQuery) {
        $resource = "$($Fixture.WorkspaceBase)/savedSearches/$($hunt.SavedSearchId)"
        if (-not $PSCmdlet.ShouldProcess($resource, 'Create fixture hunting query')) {
            Write-iSOCLog "Skipped $($hunt.SavedSearchId)." -Level Warning
            continue
        }
        try {
            $body = New-iSOCFixtureSavedSearchBody -Category 'Hunting Queries' -DisplayName $hunt.DisplayName -Query $hunt.Query -FixtureMarker $marker -RunId $RunId -ScenarioName $hunt.ScenarioName
            & $put $hunt.SavedSearchId $body
            Write-iSOCLog "Created hunting query $($hunt.SavedSearchId)." -Level Success
            $created.Add($resource)
        }
        catch {
            Write-iSOCLog "Failed to write $($hunt.SavedSearchId): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
            $failed.Add($resource)
        }
    }
    [pscustomobject]@{ Created = $created.ToArray(); Failed = $failed.ToArray() }
}
