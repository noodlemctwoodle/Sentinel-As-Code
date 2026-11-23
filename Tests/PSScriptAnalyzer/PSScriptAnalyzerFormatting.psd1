@{
    # Formatting-only PSScriptAnalyzer profile. Runs as a second pass over
    # every file, with PSUseCorrectCasing's command check on: the main profiles
    # turn it off because, mixed with every other rule, its command lookup can
    # crash PSScriptAnalyzer 1.25 (PSScriptAnalyzer #1708). The other rules
    # repeat the main profile's settings so this pass agrees with it.
    IncludeRules = @(
        'PSPlaceOpenBrace',
        'PSPlaceCloseBrace',
        'PSUseConsistentWhitespace',
        'PSUseConsistentIndentation',
        'PSAlignAssignmentStatement',
        'PSUseCorrectCasing',
        'PSAvoidTrailingWhitespace',
        'PSAvoidSemicolonsAsLineTerminators'
    )
    Rules        = @{
        PSAvoidSemicolonsAsLineTerminators = @{
            Enable = $true
        }
        PSPlaceOpenBrace                   = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace                  = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation         = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }
        PSUseConsistentWhitespace          = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckPipe                               = $true
            CheckPipeForRedundantWhitespace         = $true
            CheckSeparator                          = $true
            CheckParameter                          = $true
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        PSAlignAssignmentStatement         = @{
            Enable         = $true
            CheckHashtable = $true
        }
        PSUseCorrectCasing                 = @{
            Enable        = $true
            CheckCommands = $true
            CheckKeyword  = $true
            CheckOperator = $true
        }
    }
}
