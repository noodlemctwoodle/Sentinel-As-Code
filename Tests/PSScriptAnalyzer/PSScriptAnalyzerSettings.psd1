@{
    # Repository-wide PSScriptAnalyzer profile for PowerShell source (every
    # .ps1, .psm1 and .psd1 outside Tests/). Tests/Test-PSScriptAnalyzer.Tests.ps1
    # runs every file through it on every PR. Every built-in rule runs at every
    # severity, plus the opt-in rules the repository's coding standard needs:
    # OTBS braces, consistent whitespace and indentation, aligned hashtables,
    # lowercase keywords and operators, single-quoted constant strings, no
    # semicolon line terminators, named parameters and comment-based help on
    # every function.
    #
    # Companion profiles in this folder:
    #   PSScriptAnalyzerFormatting.psd1    formatting rules only, with command
    #                                      casing on (see PSUseCorrectCasing)
    #   PSScriptAnalyzerTestSettings.psd1  this profile with the exclusions
    #                                      test code needs (Tests/ only)
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning', 'Information', 'ParseError')
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
        # OTBS: the opening brace on the same line, and else, elseif, catch
        # and finally on the line of the closing brace (NewLineAfter off).
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
            # Command casing needs command metadata, which PSScriptAnalyzer 1.25
            # resolves on parallel threads and can crash on while a module
            # autoloads (PSScriptAnalyzer #1708). It is checked in a separate
            # pass with PSScriptAnalyzerFormatting.psd1 instead.
            CheckCommands = $false
            CheckKeyword  = $true
            CheckOperator = $true
        }
    }
}
