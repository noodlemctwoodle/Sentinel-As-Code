@{
    RootModule        = 'iSOCDeployments.psm1'
    ModuleVersion     = '26.11.0'
    GUID              = 'ef4950cc-5176-443e-b28d-889b7e1cc85a'
    Author            = 'noodlemctwoodle'
    CompanyName       = 'Sentinel-As-Code'
    Copyright         = '(c) noodlemctwoodle. Released under the Apache License 2.0.'
    Description       = 'iSOC Deployments: deploy, export, compare and sync security operations content kept in a Sentinel-As-Code repository. One command per verb, each taking -ContentType, over a registry of content types. Today it works with Microsoft Sentinel workspaces and Defender XDR custom detections.'
    PowerShellVersion = '7.2'
    # No RequiredModules: each command checks what it needs when it runs
    # (Test-iSOCDeploymentPrerequisite), so reading repository content offline
    # never needs Az.Accounts.
    FunctionsToExport = @(
        'Connect-iSOCWorkspace'
        'Get-iSOCContentDependency'
        'Get-iSOCContentType'
        'Get-iSOCContext'
        'Test-iSOCDependencyManifest'
        'Test-iSOCDeploymentPrerequisite'
        'Update-iSOCDependencyManifest'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('iSOC', 'Deployments', 'SecurityOperations', 'Sentinel', 'DefenderXDR', 'Azure', 'DevOps')
            ProjectUri   = 'https://github.com/noodlemctwoodle/Sentinel-As-Code'
            LicenseUri   = 'https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/LICENSE'
            ReleaseNotes = '26.11.0 (in development) - first release as a module. Built beside the scripts under Deploy/ and Tools/ it replaces; MIGRATION.md records where each script, function and parameter goes. The version follows the repository release it ships in.'
        }
    }
}
