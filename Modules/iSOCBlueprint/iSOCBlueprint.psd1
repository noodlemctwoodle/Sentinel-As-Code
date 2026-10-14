@{
    RootModule        = 'iSOCBlueprint.psm1'
    ModuleVersion     = '26.10.0'
    GUID              = '9e071a50-715c-49fe-a1f2-ca8f4e16ff13'
    Author            = 'noodlemctwoodle'
    CompanyName       = 'Sentinel-As-Code'
    Copyright         = '(c) noodlemctwoodle. Released under the Apache License 2.0.'
    Description       = 'iSOC Blueprint: document a security operations workspace and assess it against best practice and a maturity model, as JSON, Markdown, a Word report or a SharePoint site. New-iSOCBlueprint produces any of them in one command; the other commands run each step on its own. Today it documents Microsoft Sentinel workspaces.'
    PowerShellVersion = '7.2'
    # No RequiredModules: each command checks what it needs when it runs
    # (Test-iSOCBlueprintPrerequisite), so a JSON-only user never needs
    # PnP.PowerShell, pandoc or LibreOffice installed.
    FunctionsToExport = @(
        'New-iSOCBlueprint'
        'Export-iSOCBlueprintInventory'
        'ConvertTo-iSOCBlueprint'
        'ConvertTo-iSOCBlueprintChartImage'
        'Export-iSOCBlueprintWord'
        'New-iSOCBlueprintSite'
        'Publish-iSOCBlueprintSite'
        'Initialize-iSOCBlueprintSite'
        'Get-iSOCBlueprintFinding'
        'Get-iSOCBlueprintMaturity'
        'Get-iSOCBlueprintWhatsNew'
        'Test-iSOCBlueprintPrerequisite'
        'Update-iSOCBlueprintConnectorCatalogue'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('iSOC', 'Blueprint', 'SecurityOperations', 'Sentinel', 'Documentation', 'Azure')
            ProjectUri   = 'https://github.com/noodlemctwoodle/Sentinel-As-Code'
            LicenseUri   = 'https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/LICENSE'
            ReleaseNotes = '26.10.0 - first release as a module. The Blueprint scripts that lived in Tools/Blueprint now run from Engine/ inside this module, unchanged apart from the edits listed in MIGRATION.md, behind twelve commands. The version follows the repository release it ships in.'
        }
    }
}
