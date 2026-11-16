#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 tests for the (deprecated) SdlMigrationExport module in
    Content/Workbooks/SentinelDataLake/SdlMigrationExport.

.DESCRIPTION
    Guards the repository's PowerShell coding standard and the module's
    behaviour.

    Standard. PSScriptAnalyzer itself runs over these files, like every
    PowerShell file in the repository, in Tests/Test-PSScriptAnalyzer.Tests.ps1
    with the profiles in Tests/PSScriptAnalyzer. The rules the standard names
    that PSScriptAnalyzer has no built-in rule for are checked here through the
    AST and the tokenizer, one test per rule (one function per file named
    after it, no backtick line continuation, comment casing and so on).

    Module. The manifest is valid, exports exactly one command by name, and
    its version matches the code; a README sits beside it.

    Behaviour. KQL text helpers, nested function resolution, rule
    references, pricing rates and lets, number formatting, Azure sign-in,
    and error scenarios that deliberately trigger each error path.

    Private helpers are dot-sourced into the test scope; the public command
    never runs against Azure.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-ExportSdlMigrationWorkbook.Tests.ps1

    Runs the standard, module and behaviour tests.

.NOTES
    File:         Tests/Test-ExportSdlMigrationWorkbook.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $moduleRoot = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Content/Workbooks/SentinelDataLake/SdlMigrationExport'
    $script:files = @(Get-ChildItem -Path $moduleRoot -Recurse -Include '*.ps1', '*.psm1', '*.psd1' | ForEach-Object -Process {
            @{ Name = $_.FullName.Substring($moduleRoot.Length + 1); Path = $_.FullName }
        })
    $script:codeFiles = @($script:files | Where-Object -FilterScript { $_.Name -like '*.ps1' -or $_.Name -like '*.psm1' })
    $script:functionFiles = @($script:files | Where-Object -FilterScript { $_.Name -like 'Private*.ps1' -or $_.Name -like 'Public*.ps1' })
}

BeforeAll {
    $script:moduleRoot = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Content/Workbooks/SentinelDataLake/SdlMigrationExport'
    foreach ($helper in Get-ChildItem -Path (Join-Path -Path $script:moduleRoot -ChildPath 'Private') -Filter '*.ps1' -Recurse) {
        . $helper.FullName
    }

    function Get-TestAst {
        <#
        .SYNOPSIS
            Parses a file and returns its syntax tree.
        #>
        param ([string]$Path)
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    }

    function Get-TestToken {
        <#
        .SYNOPSIS
            Parses a file and returns its tokens.
        #>
        param ([string]$Path)
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $tokens
    }

    function Get-TestFunction {
        <#
        .SYNOPSIS
            Returns the first function definition in a file.
        #>
        param ([string]$Path)
        (Get-TestAst -Path $Path).Find({ param ($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    }

    function Test-ParameterIsMandatory {
        <#
        .SYNOPSIS
            Tests whether a parameter's [Parameter()] attribute sets Mandatory.
        #>
        param ($Parameter)
        foreach ($attribute in $Parameter.Attributes) {
            if ($attribute.TypeName.Name -eq 'Parameter' -and ($attribute.NamedArguments.ArgumentName -contains 'Mandatory')) {
                return $true
            }
        }
        return $false
    }
}

Describe 'Coding standard: rules with no built-in PSScriptAnalyzer equivalent' {
    It 'is ASCII, so UTF-8 without a BOM: <Name>' -ForEach $script:files {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        @($bytes | Where-Object -FilterScript { $_ -gt 127 }).Count | Should -Be 0
    }

    It 'has no monolith: <Name> is at most 300 lines' -ForEach $script:files {
        @(Get-Content -LiteralPath $Path).Count | Should -BeLessOrEqual 300
    }

    It 'defines one function, named after the file: <Name>' -ForEach $script:functionFiles {
        $functions = @((Get-TestAst -Path $Path).FindAll({ param ($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        $functions.Count | Should -Be 1
        $functions[0].Name | Should -BeExactly ([System.IO.Path]::GetFileNameWithoutExtension($Path))
    }

    It 'advanced function with PositionalBinding off and comment help (PSProvideCommentHelp): <Name>' -ForEach $script:functionFiles {
        $function = Get-TestFunction -Path $Path
        $binding = @($function.Body.ParamBlock.Attributes | Where-Object -FilterScript { $_.TypeName.Name -eq 'CmdletBinding' })
        $binding.Count | Should -Be 1
        $positional = @($binding[0].NamedArguments | Where-Object -FilterScript { $_.ArgumentName -eq 'PositionalBinding' })
        $positional.Count | Should -Be 1
        $positional[0].Argument.Extent.Text | Should -Be '$false'
        $function.GetHelpContent().Synopsis | Should -Not -BeNullOrEmpty
    }

    It 'opens every function the same way, with param ( after the attributes: <Name>' -ForEach $script:functionFiles {
        # Every function opens the same way: help, [CmdletBinding()],
        # [OutputType()], then "param (", with a blank line after the block.
        $function = Get-TestFunction -Path $Path
        $paramBlock = $function.Body.ParamBlock
        @($paramBlock.Attributes.TypeName.Name) -join ',' | Should -Be 'CmdletBinding,OutputType'
        $paramBlock.Extent.Text | Should -Match '^param \('
        $paramBlock.Attributes[0].Extent.StartLineNumber | Should -BeLessThan $paramBlock.Extent.StartLineNumber
        $lines = Get-Content -LiteralPath $Path
        $lines[$paramBlock.Extent.EndLineNumber] | Should -BeNullOrEmpty
    }

    It 'separates parameters with a blank line: <Name>' -ForEach $script:functionFiles {
        $parameters = @((Get-TestFunction -Path $Path).Body.ParamBlock.Parameters)
        $lines = Get-Content -LiteralPath $Path
        for ($index = 1; $index -lt $parameters.Count; $index++) {
            $lines[$parameters[$index - 1].Extent.EndLineNumber] | Should -BeNullOrEmpty -Because "a blank line separates $($parameters[$index - 1].Name) from $($parameters[$index].Name)"
        }
    }

    It 'declares mandatory parameters before optional ones: <Name>' -ForEach $script:functionFiles {
        $seenOptional = $false
        foreach ($parameter in (Get-TestFunction -Path $Path).Body.ParamBlock.Parameters) {
            $mandatory = Test-ParameterIsMandatory -Parameter $parameter
            if ($mandatory) {
                $seenOptional | Should -BeFalse -Because "$($parameter.Name) is mandatory and follows an optional parameter"
            } else {
                $seenOptional = $true
            }
        }
    }

    It 'uses no backtick line continuation: <Name>' -ForEach $script:codeFiles {
        @(Get-TestToken -Path $Path | Where-Object -FilterScript { $_.Kind -eq 'LineContinuation' }).Count | Should -Be 0
    }

    It 'starts each comment with a capital: <Name>' -ForEach $script:codeFiles {
        # Only the first line of a comment block is checked; the lines that
        # follow it are continuations of the same sentence.
        $previousCommentLine = -1
        $bad = foreach ($token in (Get-TestToken -Path $Path)) {
            if ($token.Kind -ne 'Comment' -or $token.Text -notmatch '^#(?!Requires)') { continue }
            $line = $token.Extent.StartLineNumber
            $continues = $line -eq $previousCommentLine + 1
            $previousCommentLine = $line
            if (-not $continues -and $token.Text -cmatch '^#\s*[a-z]') {
                "line ${line}: $($token.Text)"
            }
        }
        @($bad) -join "`n" | Should -BeNullOrEmpty
    }

    It 'has no space just inside ( and ): <Name>' -ForEach $script:codeFiles {
        $tokens = @(Get-TestToken -Path $Path)
        $bad = for ($index = 0; $index -lt $tokens.Count - 1; $index++) {
            $current = $tokens[$index]
            $next = $tokens[$index + 1]
            $sameLine = $current.Extent.EndLineNumber -eq $next.Extent.StartLineNumber
            $gap = $next.Extent.StartOffset -gt $current.Extent.EndOffset
            $opens = $current.Kind -in @('LParen', 'AtParen', 'DollarParen')
            if ($sameLine -and $gap -and (($opens -and $next.Kind -notin @('NewLine', 'Comment')) -or ($next.Kind -eq 'RParen' -and $current.Kind -notin @('NewLine', 'Comment', 'LParen')))) {
                "line $($current.Extent.StartLineNumber): $($current.Text) $($next.Text)"
            }
        }
        @($bad) -join "`n" | Should -BeNullOrEmpty
    }

    It 'PSAvoidUsingPositionalParameters (any count): <Name> passes every argument by name' -ForEach $script:codeFiles {
        # The built-in rule only fires at three or more positional arguments.
        $positional = foreach ($command in (Get-TestAst -Path $Path).FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            if ($command.InvocationOperator -ne 'Unknown') { continue }
            $elements = @($command.CommandElements)
            for ($index = 1; $index -lt $elements.Count; $index++) {
                $element = $elements[$index]
                $previous = $elements[$index - 1]
                $isParameter = $element -is [System.Management.Automation.Language.CommandParameterAst] -or ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted)
                $takenByPrevious = $index -gt 1 -and $previous -is [System.Management.Automation.Language.CommandParameterAst] -and -not $previous.Argument
                if (-not $isParameter -and -not $takenByPrevious) {
                    "$($command.GetCommandName()) line $($element.Extent.StartLineNumber): $($element.Extent.Text)"
                }
            }
        }
        @($positional) -join "`n" | Should -BeNullOrEmpty
    }

    It 'uses no += assignment: <Name>' -ForEach $script:codeFiles {
        $plusEquals = @((Get-TestAst -Path $Path).FindAll({
                    param ($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Operator -eq 'PlusEquals'
                }, $true))
        $plusEquals.Count | Should -Be 0
    }
}

Describe 'Module' {
    BeforeAll {
        $script:manifestPath = Join-Path -Path $script:moduleRoot -ChildPath 'SdlMigrationExport.psd1'
        $script:manifest = Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop
        $script:module = Import-Module -Name $script:manifestPath -Force -PassThru -ErrorAction Stop
    }

    AfterAll {
        Remove-Module -Name 'SdlMigrationExport' -Force -ErrorAction SilentlyContinue
    }

    It 'has a valid manifest that lists its exports by name' {
        $script:manifest.ExportedFunctions.Keys | Should -Be @('Export-SdlMigrationWorkbook')
        (Import-PowerShellDataFile -Path $script:manifestPath).FunctionsToExport | Should -Not -Contain '*'
    }

    It 'exports only Export-SdlMigrationWorkbook, never a wildcard' {
        @($script:module.ExportedCommands.Keys) | Should -Be @('Export-SdlMigrationWorkbook')
        Get-Content -LiteralPath (Join-Path -Path $script:moduleRoot -ChildPath 'SdlMigrationExport.psm1') -Raw | Should -Not -Match 'Export-ModuleMember[^\r\n]*\*'
    }

    It 'keeps the manifest, root module and public function versions in step' {
        $version = $script:manifest.Version.ToString()
        foreach ($file in @('SdlMigrationExport.psm1', 'Public/Export-SdlMigrationWorkbook.ps1')) {
            Get-Content -LiteralPath (Join-Path -Path $script:moduleRoot -ChildPath $file) -Raw | Should -Match ('(?m)^\s+Version:\s+' + [regex]::Escape($version) + '\s*$')
        }
    }

    It 'is marked deprecated in its help and description' {
        (Get-Help -Name 'Export-SdlMigrationWorkbook').Synopsis | Should -Match '^DEPRECATED\.'
        $script:manifest.Description | Should -Match '^DEPRECATED\.'
    }

    It 'has a README beside the manifest' {
        Join-Path -Path $script:moduleRoot -ChildPath 'README.md' | Should -Exist
    }
}

Describe 'KQL text helpers' {
    It 'ignores table names in comments and string literals' {
        $clean = Get-KqlCodeText -Text "SecurityEvent // Heartbeat`n| where Msg == 'Syslog' and Y == `"Event`""
        Test-KqlIdentifier -CleanText $clean -Name 'SecurityEvent' | Should -BeTrue
        Test-KqlIdentifier -CleanText $clean -Name 'Heartbeat' | Should -BeFalse
        Test-KqlIdentifier -CleanText $clean -Name 'Syslog' | Should -BeFalse
        Test-KqlIdentifier -CleanText $clean -Name 'Event' | Should -BeFalse
    }

    It 'keeps table(''X'') references, and skips members and longer words' {
        $clean = Get-KqlCodeText -Text "union table('Syslog'), x.Heartbeat | where EventID == 1"
        Test-KqlIdentifier -CleanText $clean -Name 'Syslog' | Should -BeTrue
        Test-KqlIdentifier -CleanText $clean -Name 'Heartbeat' | Should -BeFalse
        Test-KqlIdentifier -CleanText $clean -Name 'Event' | Should -BeFalse
    }

    It 'recognises a function call but not a bare word' {
        Test-KqlCall -CleanText 'MyParser() | take 1' -Alias 'MyParser' | Should -BeTrue
        Test-KqlCall -CleanText 'where MyParser == 1' -Alias 'MyParser' | Should -BeFalse
    }
}

Describe 'Rule references through workspace functions' {
    BeforeAll {
        $functions = @(
            [pscustomobject]@{ FunctionAlias = 'Outer'; DisplayName = 'o'; QueryBody = 'Inner() | project a' },
            [pscustomobject]@{ FunctionAlias = 'Inner'; DisplayName = 'i'; QueryBody = 'DeviceProcessEvents | project a' }
        )
        $script:universe = @('DeviceProcessEvents', 'SecurityEvent')
        $script:reach = Get-SdlFunctionReach -Function $functions -TableUniverse $script:universe
        $rule = [pscustomobject]@{ RuleName = 'r'; Kind = 'Scheduled'; Severity = 'High'; QueryText = 'Outer() | where x == 1' }
        $bodies = @(Get-SdlRuleBody -Rule @($rule))
        $script:refs = @(Get-SdlRuleReference -FunctionReach $script:reach -RuleBody $bodies -TableUniverse $script:universe)
    }

    It 'resolves a table through a nested function' {
        $script:reach['Outer'].Tables | Should -Contain 'DeviceProcessEvents'
    }

    It 'counts the rule against the table underneath, via the function' {
        $script:refs.Table | Should -Contain 'DeviceProcessEvents'
        ($script:refs | Where-Object -FilterScript { $_.Table -eq 'DeviceProcessEvents' }).Via | Should -Be 'Function Outer'
    }
}

Describe 'Pricing inputs' {
    It 'derives tier <Model> from the East US daily commitment price' -ForEach @(
        @{ Model = 'PAYG'; Expected = 4.30 }
        @{ Model = 'CT50'; Expected = 161.25 / 50 }
        @{ Model = 'CT100'; Expected = 296 / 100 }
        @{ Model = 'CT200'; Expected = 548 / 200 }
        @{ Model = 'CT300'; Expected = 800 / 300 }
        @{ Model = 'CT400'; Expected = 1037.33 / 400 }
        @{ Model = 'CT500'; Expected = 1265 / 500 }
        @{ Model = 'CT1000'; Expected = 2480 / 1000 }
        @{ Model = 'CT2000'; Expected = 4800 / 2000 }
        @{ Model = 'CT5000'; Expected = 11550 / 5000 }
        @{ Model = 'CT10000'; Expected = 22240 / 10000 }
        @{ Model = 'CT25000'; Expected = 53450 / 25000 }
        @{ Model = 'CT50000'; Expected = 102600 / 50000 }
    ) {
        [Math]::Abs((Get-SdlPricingRate -Model $Model) - $Expected) | Should -BeLessThan 0.0001
    }

    It 'charges lake storage after analytics retention on the Analytics side and for the whole retention on the Lake side' {
        $settings = [pscustomobject]@{
            EffectiveAnalyticsRate            = 0
            PricingModel                      = 'PAYG'
            LakeIngestPricePerGB              = 0.05
            LakeProcessingPricePerGB          = 0.10
            LakeStoragePricePerGBMonth        = 0.026
            LakeQueryPricePerGB               = 0.005
            TargetLakeRetentionDays           = 730
            CompressionRatio                  = 6
            AnalyticsRetentionDays            = 90
            AnalyticsRetentionPricePerGBMonth = 0.10
        }
        $let = Get-SdlPricingLet -Settings $settings
        $let | Should -Match 'analyticsLakeStoragePerGB = max_of\(lakeRetentionDays - analyticsRetentionDays, 0\.0\)'
        $let | Should -Match 'lakeOnlyStoragePerGB = lakeRetentionDays / 30\.0 / compressionRatio \* priceLakeStore'
        $let | Should -Match 'analyticsRetentionPerGB = max_of\(analyticsRetentionDays - 90\.0, 0\.0\)'
    }

    It 'uses a decimal point whatever the thread culture' {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
            Format-KqlNumber -Value 1.5 | Should -Be '1.5'
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }
    }
}

Describe 'Azure sign-in handling' {
    BeforeAll {
        function Get-AzContext {
            <#
            .SYNOPSIS
                Stub that Pester mocks; keeps the real command's parameter names.
            #>
            param ($ErrorAction, $ErrorVariable)
        }
        function Set-AzContext {
            <#
            .SYNOPSIS
                Stub that Pester mocks; keeps the real command's parameter names.
            #>
            param ($SubscriptionId, $ErrorAction, $WarningAction)
        }
        function Get-AzAccessToken {
            <#
            .SYNOPSIS
                Stub that Pester mocks; keeps the real command's parameter names.
            #>
            param ($ResourceUrl, $ErrorAction, $WarningAction)
        }
        function Get-AzSubscription {
            <#
            .SYNOPSIS
                Stub that Pester mocks; keeps the real command's parameter names.
            #>
            param ($SubscriptionId, $ErrorAction, $WarningAction)
        }
        function Connect-AzAccount {
            <#
            .SYNOPSIS
                Stub that Pester mocks; keeps the real command's parameter names.
            #>
            param ($SubscriptionId, $Tenant, $ErrorAction)
        }
        $script:ctx = [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = 'sub-1' }; Account = [pscustomobject]@{ Id = 'a@b' } }
        Mock Get-Module { [pscustomobject]@{ Name = 'x' } }
        Mock Import-Module { }
    }

    It 'reuses a context whose token works, without signing in' {
        Mock Get-AzContext { $script:ctx }
        Mock Get-AzAccessToken { 'token' }
        Mock Connect-AzAccount { }
        Assert-SdlPrerequisite -SubscriptionId 'sub-1' | Should -Be $script:ctx
        Should -Invoke Connect-AzAccount -Times 0 -Exactly
    }

    It 'signs in to the subscription''s tenant when the token has expired' {
        $script:tokenCalls = 0
        Mock Get-AzContext { $script:ctx }
        Mock Get-AzSubscription { [pscustomobject]@{ TenantId = 'tenant-1' } }
        Mock Get-AzAccessToken { $script:tokenCalls++; if ($script:tokenCalls -le 1) { throw 'expired' } 'token' }
        Mock Connect-AzAccount { }
        Assert-SdlPrerequisite -SubscriptionId 'sub-1' | Should -Be $script:ctx
        Should -Invoke Connect-AzAccount -Times 1 -Exactly -ParameterFilter { $SubscriptionId -eq 'sub-1' -and $Tenant -eq 'tenant-1' }
    }

    It 'fails with an actionable message when sign-in still gives no token' {
        Mock Get-AzContext { $script:ctx }
        Mock Get-AzSubscription { throw 'no access' }
        Mock Get-AzAccessToken { throw 'expired' }
        Mock Connect-AzAccount { }
        { Assert-SdlPrerequisite -SubscriptionId 'sub-1' } | Should -Throw '*Connect-AzAccount*'
    }
}

Describe 'Error scenarios' {
    BeforeAll {
        function Invoke-AzRestMethod {
            <#
            .SYNOPSIS
                Stub that Pester mocks; keeps the real command's parameter names.
            #>
            param ($Method, $Path, $Uri, $ErrorAction)
        }
        function Invoke-AzOperationalInsightsQuery {
            <#
            .SYNOPSIS
                Stub that Pester mocks; keeps the real command's parameter names.
            #>
            param ($WorkspaceId, $Query, $ErrorAction)
        }
        $script:connection = [pscustomobject]@{
            SubscriptionId      = 's'
            ResourceGroupName   = 'r'
            WorkspaceName       = 'ws'
            ThrottleMs          = 0
            WorkspaceCustomerId = '00000000-0000-0000-0000-000000000000'
            WorkspaceApiVersion = '2023-09-01'
        }
        Mock Start-Sleep { }
        Mock Write-Warning { }
    }

    It 'fails at once on a non-transient HTTP error, without retrying' {
        Mock Invoke-AzRestMethod { [pscustomobject]@{ StatusCode = 403; Content = 'forbidden' } }
        { Invoke-SdlArmRequest -Connection $script:connection -Path '/x' } | Should -Throw '*HTTP 403*'
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly
    }

    It 'retries a throttled request and returns the later success' {
        $script:calls = 0
        Mock Invoke-AzRestMethod {
            $script:calls++
            if ($script:calls -eq 1) {
                return [pscustomobject]@{ StatusCode = 429; Content = '' }
            }
            [pscustomobject]@{ StatusCode = 200; Content = '{"ok":true}' }
        }
        (Invoke-SdlArmRequest -Connection $script:connection -Path '/x').ok | Should -BeTrue
        Should -Invoke Invoke-AzRestMethod -Times 2 -Exactly
    }

    It 'stops at once when the sign-in has expired, without retrying' {
        Mock Invoke-AzRestMethod { throw 'Your Azure credentials have not been set up or have expired, please run Connect-AzAccount' }
        { Invoke-SdlArmRequest -Connection $script:connection -Path '/x' } | Should -Throw '*sign-in expired*'
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly
    }

    It 'gives up after the retry budget on repeated transient failures' {
        Mock Invoke-AzRestMethod { [pscustomobject]@{ StatusCode = 503; Content = '' } }
        { Invoke-SdlArmRequest -Connection $script:connection -Path '/x' -Retries 2 } | Should -Throw '*failed after 2 attempts*'
    }

    It 'wraps a failed KQL query with the workspace and keeps the cause' {
        Mock Invoke-AzOperationalInsightsQuery { throw 'Failed to resolve table' }
        $caught = $null
        try {
            Invoke-SdlKqlQuery -Connection $script:connection -Query 'Nope | take 1'
        } catch {
            $caught = $_.Exception
        }
        $caught | Should -BeOfType ([System.InvalidOperationException])
        $caught.Message | Should -Match "workspace 'ws'"
        $caught.InnerException.Message | Should -Match 'Failed to resolve table'
    }

    It 'turns a failed optional query into a warning and no rows' {
        Mock Invoke-AzOperationalInsightsQuery { throw 'LAQueryLogs not found' }
        $settings = [pscustomobject]@{ TimeRangeDays = 30; QueryLookbackDays = 7; XdrLookbackDays = 7; AlertActivityDays = 30; Currency = 'USD' }
        @(Get-SdlAlertActivityReport -Connection $script:connection -Settings $settings).Count | Should -Be 0
        Should -Invoke Write-Warning -Times 1 -Exactly
    }

    It 'explains a locked output file instead of a raw IO error' {
        $path = Join-Path -Path $TestDrive -ChildPath 'locked.xlsx'
        Set-Content -LiteralPath $path -Value 'x'
        Mock Remove-Item { throw [System.IO.IOException]::new('The process cannot access the file') }
        { Write-SdlWorkbook -Path $path -Sheet ([ordered]@{}) } | Should -Throw '*file is in use*'
    }

    It 'rejects a Windows drive path on macOS and Linux' -Skip:($IsWindows) {
        { Resolve-SdlOutputPath -WorkspaceName 'ws' -Timestamp (Get-Date) -OutputPath 'C:\reports\x.xlsx' } | Should -Throw '*Windows drive path*'
    }

    It 'rejects a total retention shorter than the analytics retention' {
        { Assert-SdlSetting -Settings ([pscustomobject]@{ TargetLakeRetentionDays = 60; AnalyticsRetentionDays = 90 }) } | Should -Throw '*cannot be shorter*'
    }
}

Describe 'Regression cases' {
    It 'ignores table() calls inside comments and string literals' {
        $comment = Get-KqlCodeText -Text "SecurityEvent | take 1 // table('Syslog')"
        Test-KqlIdentifier -CleanText $comment -Name 'Syslog' | Should -BeFalse
        $string = Get-KqlCodeText -Text "SecurityEvent | where Note == `"table('Syslog')`""
        Test-KqlIdentifier -CleanText $string -Name 'Syslog' | Should -BeFalse
        $call = Get-KqlCodeText -Text "union table('Syslog'), SecurityEvent"
        Test-KqlIdentifier -CleanText $call -Name 'Syslog' | Should -BeTrue
    }

    It 'reaches a table through a chain of functions longer than ten' {
        # Outer functions are listed first, so a fixed number of passes would
        # stop before the table reaches the top of the chain.
        $chain = foreach ($index in 0..11) {
            $body = if ($index -eq 11) { 'DeviceProcessEvents | take 1' } else { "Fn$($index + 1)() | take 1" }
            [pscustomobject]@{ FunctionAlias = "Fn$index"; DisplayName = "Fn$index"; QueryBody = $body }
        }
        $reach = Get-SdlFunctionReach -Function $chain -TableUniverse @('DeviceProcessEvents')
        foreach ($index in 0..11) {
            $reach["Fn$index"].Tables | Should -Contain 'DeviceProcessEvents' -Because "Fn$index calls down the chain"
        }
    }

    It 'bases Query-Weighted hourly ingestion on every hour in the window' {
        Mock Invoke-SdlKqlQuery { $script:queryWeightedKql = $Query }
        $settings = [pscustomobject]@{
            TimeRangeDays                     = 30
            QueryLookbackDays                 = 7
            XdrLookbackDays                   = 7
            AlertActivityDays                 = 30
            Currency                          = 'USD'
            EffectiveAnalyticsRate            = 0
            PricingModel                      = 'PAYG'
            LakeIngestPricePerGB              = 0.05
            LakeProcessingPricePerGB          = 0.10
            LakeStoragePricePerGBMonth        = 0.026
            LakeQueryPricePerGB               = 0.005
            TargetLakeRetentionDays           = 730
            CompressionRatio                  = 6
            AnalyticsRetentionDays            = 90
            AnalyticsRetentionPricePerGBMonth = 0.10
        }
        $inventory = [pscustomobject]@{ ClassicV1 = @(); DcrCustom = @(); BasicPlan = @(); AuxiliaryPlan = @() }
        $null = Get-SdlQueryWeightedReport -Connection ([pscustomobject]@{ WorkspaceName = 'ws' }) -Settings $settings -Inventory $inventory
        $script:queryWeightedKql | Should -Match ([regex]::Escape('AvgHourlyIngestionGB = sum(Quantity) / 1000.0 / (toreal(30) * 24.0)'))
        $script:queryWeightedKql | Should -Not -Match 'avg\(Quantity\)'
    }

    It 'resolves a relative -OutputPath against the current PowerShell location' {
        Push-Location -LiteralPath $TestDrive
        try {
            $expected = [System.IO.Path]::Combine((Get-Location).ProviderPath, 'reports', 'export.xlsx')
            $resolved = Resolve-SdlOutputPath -WorkspaceName 'ws' -Timestamp (Get-Date) -OutputPath './reports/export.xlsx'
            [System.IO.Path]::IsPathRooted($resolved) | Should -BeTrue
            [System.IO.Path]::GetFullPath($resolved) | Should -Be ([System.IO.Path]::GetFullPath($expected))
        } finally {
            Pop-Location
        }
    }
}
