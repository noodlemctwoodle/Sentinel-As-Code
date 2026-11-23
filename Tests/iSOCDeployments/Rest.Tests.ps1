#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for Invoke-iSOCRestRequest, the module's one REST client,
    and the helpers it uses for retry delays and error text.

.DESCRIPTION
    Invoke-AzRestMethod is mocked with scripted responses, so every path
    runs offline: ARM and Graph addressing, the api-version, paging through
    nextLink and @odata.nextLink, retries with and without Retry-After,
    connection failures, 404 handling, error text, body serialisation and
    the -WhatIf guard. Start-Sleep is mocked, so retries cost no time.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Rest.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Rest.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force

    $script:sub = '00000000-0000-0000-0000-0000000000aa'
    $script:rules = "/subscriptions/$($script:sub)/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws/providers/Microsoft.SecurityInsights/alertRules"

    # Queue the responses the mocked Invoke-AzRestMethod returns, in order,
    # and record every call it receives.
    function Set-Response {
        <#
        .SYNOPSIS
            Queues the responses the stubbed request command returns, and clears the recorded calls.
        .PARAMETER Response
            The responses, returned one per call in order.
        #>
        param([object[]] $Response)
        $script:queue = [System.Collections.Generic.Queue[object]]::new()
        foreach ($r in $Response) { $script:queue.Enqueue($r) }
        $script:calls = [System.Collections.Generic.List[hashtable]]::new()
    }
    function New-Response {
        <#
        .SYNOPSIS
            Returns a response object with a status code, a content string and headers.
        .PARAMETER Status
            The HTTP status code.
        .PARAMETER Body
            The body: a string is used as it is, any other value is converted to JSON.
        .PARAMETER Headers
            The response headers.
        #>
        param([int] $Status = 200, [AllowNull()] [object] $Body, [hashtable] $Headers = @{})
        $content = if ($null -eq $Body) { '' } elseif ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 20 -Compress }
        [pscustomobject]@{ StatusCode = $Status; Content = $content; Headers = $Headers }
    }

    $script:context = InModuleScope iSOCDeployments {
        New-iSOCContext -Value @{
            TenantId = 't'; SubscriptionId = 's'; ResourceGroup = 'rg'; WorkspaceName = 'ws'; WorkspaceResourceId = '/w'
            WorkspaceId = 'c'; Region = 'uksouth'; PlaybookResourceGroup = 'rg'; Environment = 'AzureCloud'; IsGov = $false
            ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
        }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Invoke-iSOCRestRequest' {
    BeforeEach {
        Mock -ModuleName iSOCDeployments Start-Sleep { }
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Invoke-AzRestMethod {
            $script:calls.Add(@{ Path = $Path; Uri = $Uri; ResourceId = $ResourceId; Method = $Method; Payload = $Payload })
            $next = $script:queue.Dequeue()
            if ($next -is [System.Exception]) { throw $next }
            $next
        }
    }

    Context 'Addressing' {
        It 'adds the api-version to an ARM path once' {
            Set-Response (New-Response -Body @{ id = 'x' })
            InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)/abc" } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion '2025-07-01-preview' } | Out-Null
            $script:calls[0].Path | Should -BeExactly "$($script:rules)/abc?api-version=2025-07-01-preview"
        }

        It 'keeps an api-version the path already has, and joins with & after a query' {
            Set-Response (New-Response -Body @{}), (New-Response -Body @{})
            InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)?api-version=2020-01-01" } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion '2025-07-01-preview' } | Out-Null
            InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)?`$filter=x" } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion '2025-07-01-preview' } | Out-Null
            $script:calls[0].Path | Should -BeExactly "$($script:rules)?api-version=2020-01-01"
            $script:calls[1].Path | Should -BeExactly "$($script:rules)?`$filter=x&api-version=2025-07-01-preview"
        }

        It 'sends an absolute ARM URL as a path, so the sign-in picks the host' {
            Set-Response (New-Response -Body @{})
            InModuleScope iSOCDeployments -Parameters @{ P = "https://management.usgovcloudapi.net$($script:rules)?api-version=1" } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P } | Out-Null
            $script:calls[0].Path | Should -BeExactly "$($script:rules)?api-version=1"
            $script:calls[0].Uri | Should -BeNullOrEmpty
        }

        It 'refuses an ARM path that does not start with /' {
            { InModuleScope iSOCDeployments { Invoke-iSOCRestRequest -Method GET -Path 'subscriptions/x' } } | Should -Throw -ExpectedMessage "*starts with '/'*"
        }

        It 'sends a Graph request to the context''s Graph host with the Graph audience' {
            Set-Response (New-Response -Body @{ id = 'rule' })
            InModuleScope iSOCDeployments -Parameters @{ Ctx = $script:context } { param($Ctx) Invoke-iSOCRestRequest -Method GET -Api Graph -Path '/security/rules/detectionRules/1' -ApiVersion beta -Context $Ctx } | Out-Null
            $script:calls[0].Uri | Should -BeExactly 'https://graph.microsoft.com/beta/security/rules/detectionRules/1'
            $script:calls[0].ResourceId | Should -BeExactly 'https://graph.microsoft.com/'
            $script:calls[0].Path | Should -BeNullOrEmpty
        }

        It 'needs the Graph version segment' {
            { InModuleScope iSOCDeployments -Parameters @{ Ctx = $script:context } { param($Ctx) Invoke-iSOCRestRequest -Method GET -Api Graph -Path '/security' -Context $Ctx } } |
                Should -Throw -ExpectedMessage '*-ApiVersion*'
        }

    }

    Context 'Responses and paging' {
        It 'returns a single resource as an object' {
            Set-Response (New-Response -Body @{ id = 'abc'; properties = @{ displayName = 'Rule' } })
            $r = InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)/abc" } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v }
            $r.properties.displayName | Should -Be 'Rule'
        }

        It 'follows nextLink through every page of an ARM collection' {
            Set-Response (New-Response -Body @{ value = @(@{ id = 1 }, @{ id = 2 }); nextLink = "https://management.azure.com$($script:rules)?api-version=v&`$skipToken=2" }),
            (New-Response -Body @{ value = @(@{ id = 3 }) })
            $items = @(InModuleScope iSOCDeployments -Parameters @{ P = $script:rules } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v })
            $items.id | Should -Be @(1, 2, 3)
            $script:calls[1].Path | Should -BeExactly "$($script:rules)?api-version=v&`$skipToken=2"
        }

        It 'follows @odata.nextLink through a Graph collection' {
            Set-Response (New-Response -Body @{ value = @(@{ id = 'a' }); '@odata.nextLink' = 'https://graph.microsoft.com/beta/security/rules/detectionRules?$skiptoken=x' }),
            (New-Response -Body @{ value = @(@{ id = 'b' }) })
            $items = @(InModuleScope iSOCDeployments -Parameters @{ Ctx = $script:context } { param($Ctx) Invoke-iSOCRestRequest -Method GET -Api Graph -Path '/security/rules/detectionRules' -ApiVersion beta -Context $Ctx })
            $items.id | Should -Be @('a', 'b')
            $script:calls[1].Uri | Should -BeExactly 'https://graph.microsoft.com/beta/security/rules/detectionRules?$skiptoken=x'
        }

        It 'returns nothing for an empty collection or an empty body' {
            Set-Response (New-Response -Body @{ value = @() }), (New-Response -Status 204 -Body $null)
            @(InModuleScope iSOCDeployments -Parameters @{ P = $script:rules } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v }).Count | Should -Be 0
            InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)/x" } { param($P) Invoke-iSOCRestRequest -Method DELETE -Path $P -ApiVersion v } | Should -BeNullOrEmpty
        }

        It 'returns status, headers and body with -Raw, without paging' {
            Set-Response (New-Response -Status 201 -Body @{ value = @(1); nextLink = 'https://management.azure.com/next' } -Headers @{ 'Azure-AsyncOperation' = 'https://op' })
            $r = InModuleScope iSOCDeployments -Parameters @{ P = $script:rules } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v -Raw }
            $r.StatusCode | Should -Be 201
            $r.Headers['Azure-AsyncOperation'] | Should -Be 'https://op'
            $r.Content.value | Should -Be @(1)
            $script:calls.Count | Should -Be 1
        }

        It 'does not page the response of a write' {
            Set-Response (New-Response -Body @{ value = @(1, 2) })
            $r = InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)/x" } { param($P) Invoke-iSOCRestRequest -Method PUT -Path $P -ApiVersion v -Body @{} }
            $r.value | Should -Be @(1, 2)
        }
    }

    Context 'Bodies' {
        It 'serialises an object body once, as compressed JSON' {
            Set-Response (New-Response -Body @{})
            InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)/x" } { param($P) Invoke-iSOCRestRequest -Method PUT -Path $P -ApiVersion v -Body @{ kind = 'Scheduled'; properties = @{ tactics = @('Execution') } } } | Out-Null
            $sent = $script:calls[0].Payload | ConvertFrom-Json
            $sent.kind | Should -Be 'Scheduled'
            , $sent.properties.tactics | Should -BeOfType [object[]]
            $script:calls[0].Payload | Should -Not -Match "`n"
        }

        It 'sends a string body as it is' {
            Set-Response (New-Response -Body @{})
            InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)/x" } { param($P) Invoke-iSOCRestRequest -Method PUT -Path $P -ApiVersion v -Body '{"already":"json"}' } | Out-Null
            $script:calls[0].Payload | Should -BeExactly '{"already":"json"}'
        }

        It 'sends no payload without a body' {
            Set-Response (New-Response -Body @{})
            InModuleScope iSOCDeployments -Parameters @{ P = $script:rules } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v } | Out-Null
            $script:calls[0].Payload | Should -BeNullOrEmpty
        }
    }

    Context 'Failures and retries' {
        It 'returns nothing on 404 with -AllowNotFound' {
            Set-Response (New-Response -Status 404 -Body @{ error = @{ code = 'NotFound'; message = 'gone' } })
            InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)/x" } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v -AllowNotFound } | Should -BeNullOrEmpty
        }

        It 'throws on 404 otherwise, with the status on the exception' {
            Set-Response (New-Response -Status 404 -Body @{ error = @{ code = 'NotFound'; message = 'gone' } })
            $caught = $null
            try { InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)/x" } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v } }
            catch { $caught = $_ }
            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
        }

        It 'names the status, method, item and the service''s reason, but not the subscription' {
            Set-Response (New-Response -Status 400 -Body @{ error = @{ code = 'BadRequest'; message = 'Failed to run the analytics rule query.'; details = @(@{ message = 'FailedToResolveColumn X' }) } })
            $caught = $null
            try { InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)/rule-1" } { param($P) Invoke-iSOCRestRequest -Method PUT -Path $P -ApiVersion v -Body @{} } }
            catch { $caught = $_ }
            $caught.Exception.Message | Should -BeExactly 'HTTP 400 from PUT alertRules/rule-1: BadRequest: Failed to run the analytics rule query.: FailedToResolveColumn X'
            $caught.Exception.Message | Should -Not -Match $script:sub
            $script:calls.Count | Should -Be 1 -Because 'a 400 is not retried'
        }

        It 'retries 429 for as long as Retry-After says' {
            Set-Response (New-Response -Status 429 -Body '' -Headers @{ 'Retry-After' = '7' }), (New-Response -Body @{ ok = $true })
            $r = InModuleScope iSOCDeployments -Parameters @{ P = $script:rules } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v }
            $r.ok | Should -BeTrue
            Should -Invoke -ModuleName iSOCDeployments Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
            Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' -and $Message -match 'HTTP 429.*retrying in 7s \(attempt 1 of 5\)' }
        }

        It 'retries <Status> and gives up after -MaxAttempts' -ForEach @(@{ Status = 500 }, @{ Status = 502 }, @{ Status = 503 }, @{ Status = 504 }, @{ Status = 408 }) {
            Set-Response (1..3 | ForEach-Object { New-Response -Status $Status -Body @{ error = @{ code = 'Busy'; message = 'try later' } } })
            { InModuleScope iSOCDeployments -Parameters @{ P = $script:rules } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v -MaxAttempts 3 } } |
                Should -Throw -ExpectedMessage "HTTP $Status from GET *"
            $script:calls.Count | Should -Be 3
            Should -Invoke -ModuleName iSOCDeployments Start-Sleep -Times 2 -Exactly
        }

        It 'retries a dropped connection' {
            Set-Response ([System.Net.Http.HttpRequestException]::new('connection reset')), (New-Response -Body @{ ok = 1 })
            (InModuleScope iSOCDeployments -Parameters @{ P = $script:rules } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v }).ok | Should -Be 1
            $script:calls.Count | Should -Be 2
        }

        It 'does not retry a failure that is not about the connection, such as no sign-in' {
            Set-Response ([System.InvalidOperationException]::new('Run Connect-AzAccount to login.')), (New-Response -Body @{})
            { InModuleScope iSOCDeployments -Parameters @{ P = $script:rules } { param($P) Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v } } |
                Should -Throw -ExpectedMessage '*Run Connect-AzAccount*'
            $script:calls.Count | Should -Be 1
        }
    }

    Context 'Under -WhatIf' {
        It 'refuses a <Method> that skipped ShouldProcess' -ForEach @(@{ Method = 'PUT' }, @{ Method = 'PATCH' }, @{ Method = 'POST' }, @{ Method = 'DELETE' }) {
            Set-Response (New-Response -Body @{})
            {
                InModuleScope iSOCDeployments -Parameters @{ P = "$($script:rules)/x"; M = $Method } {
                    param($P, $M)
                    $WhatIfPreference = $true
                    Invoke-iSOCRestRequest -Method $M -Path $P -ApiVersion v -Body @{}
                }
            } | Should -Throw -ExpectedMessage '*under -WhatIf*ShouldProcess*'
            $script:calls.Count | Should -Be 0
        }

        It 'still runs reads, and POSTs marked -ReadOnly' {
            Set-Response (New-Response -Body @{ a = 1 }), (New-Response -Body @{ b = 2 })
            InModuleScope iSOCDeployments -Parameters @{ P = $script:rules } {
                param($P)
                $WhatIfPreference = $true
                (Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v).a | Should -Be 1
                (Invoke-iSOCRestRequest -Method POST -Path "$P/query" -ApiVersion v -ReadOnly -Body @{}).b | Should -Be 2
            }
            $script:calls.Count | Should -Be 2
        }
    }
}

Describe 'Invoke-iSOCRestRequest against a cmdlet that honours -WhatIf' {
    BeforeEach {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
    }

    It 'keeps reads running under -WhatIf, where Invoke-AzRestMethod would skip them' {
        # A stand-in that honours ShouldProcess the way the real cmdlet does,
        # defined in the module's scope so the client calls it.
        InModuleScope iSOCDeployments {
            function script:Invoke-AzRestMethod {
                <#
                .SYNOPSIS
                    Stand-in for Invoke-AzRestMethod that returns a fixed success response when the call is confirmed.
                .PARAMETER Path
                    The request path.
                .PARAMETER Uri
                    The request URI.
                .PARAMETER ResourceId
                    The resource ID of the request.
                .PARAMETER Method
                    The HTTP method.
                .PARAMETER Payload
                    The request body.
                #>
                [CmdletBinding(SupportsShouldProcess)]
                param($Path, $Uri, $ResourceId, $Method, $Payload)
                if ($PSCmdlet.ShouldProcess($Path, $Method)) { [pscustomobject]@{ StatusCode = 200; Content = '{"ran":true}'; Headers = @{} } }
            }
        }
        try {
            $result = InModuleScope iSOCDeployments -Parameters @{ P = $script:rules } {
                param($P)
                $WhatIfPreference = $true
                Invoke-iSOCRestRequest -Method GET -Path $P -ApiVersion v
            }
            $result.ran | Should -BeTrue
        } finally {
            InModuleScope iSOCDeployments { Remove-Item -Path function:script:Invoke-AzRestMethod }
        }
    }
}

Describe 'Get-iSOCRestRetryDelay' {
    It 'reads Retry-After seconds from a dictionary, any case' {
        InModuleScope iSOCDeployments { Get-iSOCRestRetryDelay -Headers @{ 'retry-after' = '12' } -Attempt 1 } | Should -Be 12
    }

    It 'reads Retry-After as a date' {
        $when = [DateTimeOffset]::UtcNow.AddSeconds(30).ToString('r')
        $delay = InModuleScope iSOCDeployments -Parameters @{ When = $when } { param($When) Get-iSOCRestRetryDelay -Headers @{ 'Retry-After' = $When } -Attempt 1 }
        $delay | Should -BeGreaterOrEqual 28
        $delay | Should -BeLessOrEqual 31
    }

    It 'reads the RetryAfter header Invoke-AzRestMethod returns' {
        $message = [System.Net.Http.HttpResponseMessage]::new()
        $message.Headers.RetryAfter = [System.Net.Http.Headers.RetryConditionHeaderValue]::new([TimeSpan]::FromSeconds(9))
        InModuleScope iSOCDeployments -Parameters @{ Headers = $message.Headers } { param($Headers) Get-iSOCRestRetryDelay -Headers $Headers -Attempt 1 } | Should -Be 9
    }

    It 'doubles from five seconds without Retry-After: attempt <Attempt> waits <Seconds>' -ForEach @(
        @{ Attempt = 1; Seconds = 5 }, @{ Attempt = 2; Seconds = 10 }, @{ Attempt = 3; Seconds = 20 }, @{ Attempt = 4; Seconds = 40 }, @{ Attempt = 6; Seconds = 120 }
    ) {
        InModuleScope iSOCDeployments -Parameters @{ A = $Attempt } { param($A) Get-iSOCRestRetryDelay -Headers @{} -Attempt $A } | Should -Be $Seconds
    }

    It 'waits at least one second and at most two minutes' {
        InModuleScope iSOCDeployments { Get-iSOCRestRetryDelay -Headers @{ 'Retry-After' = '0' } -Attempt 1 } | Should -Be 1
        InModuleScope iSOCDeployments { Get-iSOCRestRetryDelay -Headers @{ 'Retry-After' = '3600' } -Attempt 1 } | Should -Be 120
    }
}

Describe 'Get-iSOCRestErrorDetail' {
    It 'joins the code, message and detail messages of an ARM or Graph error' {
        InModuleScope iSOCDeployments { Get-iSOCRestErrorDetail -Content '{"error":{"code":"Conflict","message":"Exists","details":[{"code":"x","message":"Rule id taken"}]}}' } |
            Should -BeExactly 'Conflict: Exists: Rule id taken'
    }

    It 'returns other bodies trimmed, cut at 2000 characters' {
        InModuleScope iSOCDeployments { Get-iSOCRestErrorDetail -Content '  <html>Bad gateway</html>  ' } | Should -BeExactly '<html>Bad gateway</html>'
        (InModuleScope iSOCDeployments { Get-iSOCRestErrorDetail -Content ('x' * 2500) }).Length | Should -Be 2003
    }

    It 'says when there is no body' {
        InModuleScope iSOCDeployments { Get-iSOCRestErrorDetail -Content '' } | Should -Be 'no response body'
    }
}
