@{
    # The only differences allowed between a file under Tools/Blueprint and its
    # copy under Modules/iSOCBlueprint/Engine. Each change is an exact text
    # replacement that must match once in the source; the copy-drift test
    # applies them to the source and requires the result to equal the copy
    # byte for byte. Anything else that differs fails the test.
    #
    # Paths are relative to Tools/Blueprint and to Modules/iSOCBlueprint/Engine.
    # See Modules/iSOCBlueprint/MIGRATION.md for the file-by-file map.

    # Applied to every copied .ps1 file: the File: key in the help block names
    # the file's new home.
    HeaderPath = @{
        Id      = 'G1'
        Include = '*.ps1'
        Pattern = '(?m)^(\s*File:\s+)Tools/Blueprint/'
        Replace = '${1}Modules/iSOCBlueprint/Engine/'
    }

    Edits = @(
        @{
            Id      = 'E1'
            File    = 'Export-SentinelInventory.ps1'
            Why     = 'Load the vendored KQL helpers instead of importing Modules/Sentinel.Common from the repository.'
            Changes = @(
                @{
                    Find    = @'
# Sentinel.Common supplies the KQL identifier extractor behind the
# table-reference captures. It needs Az.Accounts, which this script already
# requires; the consumers of the captured files do not.
Import-Module (Join-Path $PSScriptRoot '../../Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop
'@
                    Replace = @'
# Sentinel.Common's KQL identifier extractor sits behind the table-reference
# captures. The module carries its own copy of the two functions used
# (Private/Vendor), so it needs nothing from the repository around it.
. (Join-Path $PSScriptRoot 'Private/Vendor/SentinelCommon.Kql.ps1')
'@
                }
            )
        }
        @{
            Id      = 'E2'
            File    = 'Export-SentinelInventory.ps1'
            Why     = 'Default the output root to ./SecurityDocs under the current directory, not two folders above the script.'
            Changes = @(
                @{
                    Find    = @'
    [string]$OutputRoot = (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'SecurityDocs'),
'@
                    Replace = @'
    [string]$OutputRoot = (Join-Path -Path (Get-Location).ProviderPath -ChildPath 'SecurityDocs'),
'@
                }
            )
        }
        @{
            Id      = 'E3'
            File    = 'Export-SentinelInventory.ps1'
            Why     = 'Record the module version as the Blueprint version, and the commit only when git is present.'
            Changes = @(
                @{
                    Find    = @'
$blueprintVersion = '0.2.0'
'@
                    Replace = @'
$blueprintVersion = [string](Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '../iSOCBlueprint.psd1')).ModuleVersion
'@
                }
                @{
                    Find    = @'
    ScriptCommit      = (& git -C (Split-Path -Parent $PSScriptRoot) rev-parse HEAD 2>$null) -as [string]
'@
                    Replace = @'
    ScriptCommit      = $(if (Get-Command git -ErrorAction SilentlyContinue) { (& git -C $PSScriptRoot rev-parse HEAD 2>$null) -as [string] } else { $null })
'@
                }
            )
        }
        @{
            Id      = 'E4'
            File    = 'Convert-SentinelInventoryToMarkdown.ps1'
            Why     = 'Default the input root to ./SecurityDocs/<workspace> under the current directory.'
            Changes = @(
                @{
                    Find    = @'
    $InputRoot = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath "SecurityDocs/$WorkspaceName"
'@
                    Replace = @'
    $InputRoot = Join-Path -Path (Get-Location).ProviderPath -ChildPath "SecurityDocs/$WorkspaceName"
'@
                }
            )
        }
        @{
            Id      = 'E5'
            File    = 'Convert-SentinelInventoryToMarkdown.ps1'
            Why     = 'Read page 99 from the copy the module ships, not from the repository docs.'
            Changes = @(
                @{
                    Find    = @'
$refSrc = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Docs/Tools/Blueprint/Blueprint-References.md'
'@
                    Replace = @'
$refSrc = Join-Path $PSScriptRoot 'Private/Resources/Blueprint-References.md'
'@
                }
            )
        }
        @{
            Id      = 'E6'
            File    = 'Convert-SentinelInventoryToMarkdown.ps1'
            Why     = 'Point the four links into the repository at GitHub, so they work in Word, on SharePoint and outside the repository.'
            Changes = @(
                @{
                    Find    = '](../../Tools/Blueprint/Private/Resources/best-practices.json)'
                    Replace = '](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Modules/iSOCBlueprint/Engine/Private/Resources/best-practices.json)'
                }
                @{
                    Find    = '](../../Tools/Blueprint/Private/GapChecks.ps1)'
                    Replace = '](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1)'
                }
                @{
                    Find    = '](../../Docs/Tools/Blueprint/Sentinel-Maturity-Model.md)'
                    Replace = '](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Docs/iSOCBlueprint/Sentinel-Maturity-Model.md)'
                }
                @{
                    Find    = '](../../Tools/Test-SentinelRuleDrift.ps1)'
                    Replace = '](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Tools/Test-SentinelRuleDrift.ps1)'
                }
            )
        }
        @{
            Id      = 'E7'
            File    = 'Blueprint.psd1'
            Why     = 'The module manifest is the only version; drop the stale one here.'
            Changes = @(
                @{
                    Find    = @'
    Component  = 'Sentinel Blueprint'
    Version    = '0.1.0'
'@
                    Replace = @'
    Component  = 'Sentinel Blueprint'
'@
                }
            )
        }
    )
}
