@{
    RootModule        = 'Sentinel.Common.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = '8d0c8a73-2b16-4f5a-8e7f-1c5e6f1a8d4b'
    Author            = 'noodlemctwoodle'
    CompanyName       = 'Sentinel-As-Code'
    Copyright         = '(c) noodlemctwoodle. Released under MIT.'
    Description       = 'Shared helpers for the Sentinel-As-Code deployer scripts: Write-PipelineMessage (logging abstraction), Invoke-SentinelApi (REST wrapper with retry), Connect-AzureEnvironment (Az context bootstrap). Single source of truth removes inline duplication across Deploy-CustomContent, Deploy-SentinelContentHub, Deploy-DefenderDetections, and Test-SentinelRuleDrift.'
    PowerShellVersion = '7.2'
    RequiredModules   = @(
        @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0' }
    )
    FunctionsToExport = @(
        'Write-PipelineMessage'
        'Invoke-SentinelApi'
        'Connect-AzureEnvironment'
        'Remove-KqlComments'
        'Get-KqlWatchlistReferences'
        'Get-KqlExternalDataReferences'
        'Get-KqlBareIdentifiers'
        'Get-ContentKqlQuery'
        'Get-ContentDependencies'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('Sentinel', 'Azure', 'Internal')
            ProjectUri   = 'https://github.com/noodlemctwoodle/Sentinel-As-Code'
            LicenseUri   = 'https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/LICENSE'
            ReleaseNotes = '1.1.0 — added KQL dependency-discovery helpers (Remove-KqlComments, Get-KqlWatchlistReferences, Get-KqlExternalDataReferences, Get-KqlBareIdentifiers, Get-ContentKqlQuery, Get-ContentDependencies). Used by Scripts/Build-DependencyManifest.ps1 to derive dependencies.json from content rather than hand-maintaining it. 1.0.0 — initial release. Extracted from inline duplication across the four pre-Wave-4 consumer scripts. Connect-AzureEnvironment refactored to take explicit parameters and return a state hashtable.'
        }
    }
}
