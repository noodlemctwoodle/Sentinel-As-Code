@{
    # PSScriptAnalyzer profile for test code (every file under Tests/). It is
    # PSScriptAnalyzerSettings.psd1 with the exclusions test code needs; each
    # one says why.
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning', 'Information', 'ParseError')
    ExcludeRules        = @(
        # Azure stubs must be global functions so they shadow the Az cmdlets
        # while module code runs.
        'PSAvoidGlobalVars'
        # Stubs and mocks keep the parameter list of the command they replace,
        # and do not read every parameter.
        'PSReviewUnusedParameter'
        # Pester blocks share variables through dynamic scope, which the rule
        # cannot see.
        'PSUseDeclaredVarsMoreThanAssignments'
        # Test fixtures hold made-up credentials that the stubs accept.
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        # A stub that replaces a state-changing Az cmdlet changes nothing.
        'PSUseShouldProcessForStateChangingFunctions'
    )
    Rules               = @{
        PSAvoidSemicolonsAsLineTerminators        = @{
            Enable = $true
        }
        PSAvoidUsingDoubleQuotesForConstantString = @{
            Enable = $true
        }
        PSAvoidUsingPositionalParameters          = @{
            Enable           = $true
            CommandAllowList = @()
        }
        PSProvideCommentHelp                      = @{
            Enable                  = $true
            ExportedOnly            = $false
            BlockComment            = $true
            VSCodeSnippetCorrection = $false
            Placement               = 'begin'
        }
        PSUseSingularNouns                        = @{
            Enable = $true
        }
        PSPlaceOpenBrace                          = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace                         = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation                = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }
        PSUseConsistentWhitespace                 = @{
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
        PSAlignAssignmentStatement                = @{
            Enable         = $true
            CheckHashtable = $true
        }
        PSUseCorrectCasing                        = @{
            Enable        = $true
            # Checked by the formatting pass (PSScriptAnalyzer #1708).
            CheckCommands = $false
            CheckKeyword  = $true
            CheckOperator = $true
        }
    }
}
