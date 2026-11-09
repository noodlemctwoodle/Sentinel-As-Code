#Requires -Version 7.6

<#
.SYNOPSIS
    The limits, reserved names and type maps a custom table schema is checked against.

.DESCRIPTION
    Taken from the Azure Monitor documentation, as New-DcrFromSchema.ps1
    takes them, so the command refuses what Azure refuses and nothing more.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Get-iSOCTableSchemaSetting.ps1
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

function Get-iSOCTableSchemaSetting {
    <#
    .SYNOPSIS
        The limits, reserved names and type maps a custom table schema is
        checked against.

    .DESCRIPTION
        The values Tools/DcrFromSchema/New-DcrFromSchema.ps1 uses, from the
        Azure Monitor documentation (the tables template reference, the
        create-custom-table page, the service limits and the data collection
        rule template reference):

          MinColumnNameLength,   column names are 2 to 45 characters
          MaxColumnNameLength
          MinTableNameLength,    the table resource name is 4 to 63
          MaxTableNameLength     characters
          MaxColumnCount         500 columns a table
          MaxTransformLength     15,360 characters a transformation
          MaxDescriptionLength   256: a rule's description, undocumented and
                                 seen only as a preflight rejection; the
                                 table's description is held to it too, as
                                 both are fed from one text
          ReservedColumns        the documented system and reserved names,
                                 then the platform-populated ones the list
                                 leaves out (matched without case)
          TableColumnTypes       the Tables API's eight column types
          DataTypeHints          the documented dataTypeHint values
          TableTypeMap           every accepted spelling of a column type,
                                 keyed in lower case, to its Tables API type
                                 (dateTime in camel case)
          CastByType             the KQL cast to each table type, for the
                                 transform
          ClassicTypeSuffixes    the classic Custom Log Wizard's type
                                 suffixes, flagged and never blocked

    .OUTPUTS
        [hashtable]

    .EXAMPLE
        (Get-iSOCTableSchemaSetting).MaxColumnCount
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        MinColumnNameLength  = 2
        MaxColumnNameLength  = 45
        MinTableNameLength   = 4
        MaxTableNameLength   = 63
        MaxColumnCount       = 500
        MaxTransformLength   = 15360
        MaxDescriptionLength = 256
        ReservedColumns      = @(
            'id'
            'BilledSize'
            'IsBillable'
            'InvalidTimeGenerated'
            'TenantId'
            'Title'
            'Type'
            'UniqueId'
            '_ItemId'
            '_ResourceGroup'
            '_ResourceId'
            '_SubscriptionId'
            '_TimeReceived'
            'MG'
            'ManagementGroupName'
            'SourceSystem'
        )
        TableColumnTypes     = @('boolean', 'dateTime', 'dynamic', 'guid', 'int', 'long', 'real', 'string')
        DataTypeHints        = @('armPath', 'guid', 'ip', 'uri')
        TableTypeMap         = @{
            'string'    = 'string'
            'int'       = 'int'
            'integer'   = 'int'
            'int32'     = 'int'
            'long'      = 'long'
            'int64'     = 'long'
            'real'      = 'real'
            'double'    = 'real'
            'float'     = 'real'
            'decimal'   = 'real'
            'boolean'   = 'boolean'
            'bool'      = 'boolean'
            'datetime'  = 'dateTime'
            'date'      = 'dateTime'
            'timestamp' = 'dateTime'
            'guid'      = 'guid'
            'uuid'      = 'guid'
            'dynamic'   = 'dynamic'
            'object'    = 'dynamic'
            'array'     = 'dynamic'
        }
        CastByType           = @{
            'string'   = 'tostring'
            'int'      = 'toint'
            'long'     = 'tolong'
            'real'     = 'toreal'
            'boolean'  = 'tobool'
            'datetime' = 'todatetime'
            'guid'     = 'toguid'
            'dynamic'  = 'todynamic'
        }
        ClassicTypeSuffixes  = @('_s', '_d', '_b', '_g', '_t')
    }
}
