#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the one-time SharePoint site set-up.

.DESCRIPTION
    Runs Invoke-iSOCBlueprintSiteInitialize with the PnP cmdlets replaced
    by recorders, so no tenant is touched. Checks the order and content of
    the calls, that -WhatIf makes none that change anything, the admin URL
    it works out from the site URL and the module check it makes first.

.NOTES
    File:         Tests/iSOCBlueprint/Site-Initialize.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $script:moduleRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/iSOCBlueprint'
    Import-Module (Join-Path $script:moduleRoot 'iSOCBlueprint.psd1') -Force
    $script:module = Get-Module iSOCBlueprint

    $script:siteArgs = @{
        SiteUrl = 'https://contoso.sharepoint.com/sites/isoc/'; Owner = 'o@contoso.com'; PublisherAppId = 'pub-id'
        ClientId = 'client-id'; Tenant = 'contoso.onmicrosoft.com'
    }
}

Describe 'Invoke-iSOCBlueprintSiteInitialize' {
    BeforeEach {
        $global:SiteInitCalls = [System.Collections.Generic.List[string]]::new()
        foreach ($name in 'Connect-PnPOnline', 'Get-PnPTenantSite', 'New-PnPSite', 'Add-PnPSiteCollectionAppCatalog', 'Get-PnPSiteCollectionAppCatalog',
            'Get-PnPEntraIDAppSitePermission', 'Set-PnPEntraIDAppSitePermission', 'Grant-PnPEntraIDAppSitePermission', 'Set-PnPSite', 'Set-PnPWeb') {
            Set-Item "function:global:$name" ([scriptblock]::Create("`$global:SiteInitCalls.Add('$name'); `$null"))
        }
        Set-Item 'function:global:Get-PnPTenantAppCatalogUrl' { $global:SiteInitCalls.Add('Get-PnPTenantAppCatalogUrl'); 'https://contoso.sharepoint.com/sites/apps' }
        Mock -ModuleName iSOCBlueprint Assert-iSOCBlueprintPrerequisite { }
        Mock -ModuleName iSOCBlueprint Publish-SacAppPackage { $global:SiteInitCalls.Add("Publish-SacAppPackage $Path") }
    }

    AfterEach {
        Remove-Variable -Name SiteInitCalls -Scope Global -ErrorAction SilentlyContinue
        foreach ($name in 'Connect-PnPOnline', 'Get-PnPTenantSite', 'New-PnPSite', 'Add-PnPSiteCollectionAppCatalog', 'Get-PnPSiteCollectionAppCatalog',
            'Get-PnPEntraIDAppSitePermission', 'Set-PnPEntraIDAppSitePermission', 'Grant-PnPEntraIDAppSitePermission', 'Set-PnPSite', 'Set-PnPWeb', 'Get-PnPTenantAppCatalogUrl') {
            Remove-Item "function:global:$name" -ErrorAction SilentlyContinue
        }
    }

    It 'creates the site, adds the site app catalog, grants the publisher and sets the site up, in that order' {
        $a = $script:siteArgs
        & $script:module { param($a) Invoke-iSOCBlueprintSiteInitialize @a 6> $null } $a
        $order = @($global:SiteInitCalls | Where-Object { $_ -in 'New-PnPSite', 'Add-PnPSiteCollectionAppCatalog', 'Grant-PnPEntraIDAppSitePermission', 'Set-PnPSite', 'Set-PnPWeb' })
        $order | Should -Be @('New-PnPSite', 'Add-PnPSiteCollectionAppCatalog', 'Grant-PnPEntraIDAppSitePermission', 'Set-PnPSite', 'Set-PnPWeb')
    }

    It 'makes no change under -WhatIf' {
        $a = $script:siteArgs
        & $script:module { param($a) Invoke-iSOCBlueprintSiteInitialize @a -WhatIf 6> $null } $a
        @($global:SiteInitCalls | Where-Object { $_ -match '^(New|Add|Grant|Set)-' }).Count | Should -Be 0
    }

    It 'works out the admin centre from the site URL' {
        $a = $script:siteArgs
        $log = & $script:module { param($a) Invoke-iSOCBlueprintSiteInitialize @a -WhatIf 6>&1 | ForEach-Object { "$_" } } $a
        ($log -join "`n") | Should -Match 'Admin\s+: https://contoso-admin\.sharepoint\.com'
        ($log -join "`n") | Should -Match 'Site\s+: https://contoso\.sharepoint\.com/sites/isoc\r?\n'
    }

    It 'asks for -TenantAdminUrl when the site is not a sharepoint.com address' {
        $a = $script:siteArgs.Clone()
        $a.SiteUrl = 'https://intranet.example/sites/isoc'
        { & $script:module { param($a) Invoke-iSOCBlueprintSiteInitialize @a 6> $null } $a } | Should -Throw '*pass -TenantAdminUrl*'
    }

    It 'stops when there is no tenant app catalog' {
        Set-Item 'function:global:Get-PnPTenantAppCatalogUrl' { $null }
        $a = $script:siteArgs
        { & $script:module { param($a) Invoke-iSOCBlueprintSiteInitialize @a 6> $null } $a } | Should -Throw '*no app catalog*'
    }

    It 'checks the PnP module before it does anything' {
        Mock -ModuleName iSOCBlueprint Assert-iSOCBlueprintPrerequisite { throw 'This command needs: PnP.PowerShell' }
        $a = $script:siteArgs
        { & $script:module { param($a) Invoke-iSOCBlueprintSiteInitialize @a 6> $null } $a } | Should -Throw '*needs*'
        $global:SiteInitCalls.Count | Should -Be 0
    }

    It 'stops before connecting when the app package is missing' {
        $a = $script:siteArgs + @{ AppPackagePath = (Join-Path $TestDrive 'missing.sppkg') }
        { & $script:module { param($a) Invoke-iSOCBlueprintSiteInitialize @a 6> $null } $a } | Should -Throw '*App package not found*'
        $global:SiteInitCalls.Count | Should -Be 0
    }
}
