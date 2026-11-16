@{
    RootModule           = 'SdlMigrationExport.psm1'
    ModuleVersion        = '0.2.0'
    GUID                 = '52c5121c-e76f-4e38-a69d-7c9372d28fc8'
    Author               = 'noodlemctwoodle'
    CompanyName          = 'Sentinel-As-Code'
    Copyright            = '(c) noodlemctwoodle. Released under the Apache License 2.0.'
    Description          = 'DEPRECATED. Exports every dataset behind the Sentinel Data Lake Migration workbook to one multi-sheet Excel file. To be replaced by the iSOCDeployments module.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')

    # Az.Accounts, Az.OperationalInsights and ImportExcel are needed only at run
    # time and are listed under ExternalModuleDependencies below rather than in
    # RequiredModules: Assert-SdlPrerequisite checks them when the command runs,
    # so the module can be imported (and tested) where they are not installed,
    # and ImportExcel is loaded without the libgdiplus warning it prints on load.
    RequiredModules      = @()

    # Only the one command is public; every helper under Private stays internal.
    FunctionsToExport    = @('Export-SdlMigrationWorkbook')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags                       = @('Sentinel', 'DataLake', 'Cost', 'Excel')
            ProjectUri                 = 'https://github.com/noodlemctwoodle/Sentinel-As-Code'
            ExternalModuleDependencies = @('Az.Accounts', 'Az.OperationalInsights', 'ImportExcel')
            ReleaseNotes               = 'Deprecated. 0.2.0: query and pricing fixes, retention-aware costs, module layout. See Docs/Tools/SDL-Migration-Workbook-Export.md.'
        }
    }
}
