#Requires -Version 7.4
# Unit tests for the BYOK AI core (gui/ai/*.ps1) — all pure, no HTTP / tenant / WPF.

BeforeAll {
    $ai = Join-Path $PSScriptRoot '..\gui\ai'
    . (Join-Path $ai 'ToolCatalog.ps1')
    . (Join-Path $ai 'Providers.ps1')
    . (Join-Path $ai 'Secrets.ps1')
    . (Join-Path $ai 'AiClient.ps1')
}

Describe 'Tool catalog' {
    It 'returns read-only tools with the required fields' {
        $cat = Get-SPAiToolCatalog
        $cat.Count | Should -BeGreaterThan 4
        foreach ($t in $cat) {
            $t.name     | Should -Not -BeNullOrEmpty
            $t.cmdlet   | Should -Not -BeNullOrEmpty
            $t.readOnly | Should -BeTrue
            $t.schema.type | Should -Be 'object'
        }
    }
    It 'has unique tool names' {
        $names = (Get-SPAiToolCatalog).name
        ($names | Select-Object -Unique).Count | Should -Be $names.Count
    }
}

Describe 'ConvertTo-SPCmdletParams' {
    It 'maps camelCase args to PascalCase cmdlet params' {
        $tool = @{ cmdlet = 'Get-SPSharingReport' }
        $p = ConvertTo-SPCmdletParams -Tool $tool -Arguments @{ siteUrl = 'https://x'; includeLinks = $true }
        $p['SiteUrl']      | Should -Be 'https://x'
        $p['IncludeLinks'] | Should -BeTrue
    }
    It 'applies fixed params and skips empty values' {
        $tool = @{ fixedParams = @{ IncludeStorage = $true } }
        $p = ConvertTo-SPCmdletParams -Tool $tool -Arguments @{ siteUrl = '' }
        $p['IncludeStorage'] | Should -BeTrue
        $p.ContainsKey('SiteUrl') | Should -BeFalse
    }
    It 'reads args from a PSCustomObject too' {
        $p = ConvertTo-SPCmdletParams -Tool @{} -Arguments ([pscustomobject]@{ minSizeMB = 200 })
        $p['MinSizeMB'] | Should -Be 200
    }
}

Describe 'Get-SPCommandLine' {
    It 'renders switches, strings and numbers, sorted' {
        $line = Get-SPCommandLine -Cmdlet 'Get-SPSharingReport' -Params @{ SiteUrl = 'https://x'; IncludeLinks = $true }
        $line | Should -Be "Get-SPSharingReport -IncludeLinks -SiteUrl 'https://x'"
    }
    It 'omits false switches and escapes quotes' {
        $line = Get-SPCommandLine -Cmdlet 'Get-SPLargeFiles' -Params @{ SiteUrl = "o'brien"; IncludeLinks = $false; MinSizeMB = 100 }
        $line | Should -Be "Get-SPLargeFiles -MinSizeMB 100 -SiteUrl 'o''brien'"
    }
}

Describe 'Provider tool definitions' {
    It 'shapes Anthropic tools with input_schema' {
        $t = @(ConvertTo-SPProviderTools -Provider anthropic -Catalog (Get-SPAiToolCatalog))[0]
        $t.name | Should -Not -BeNullOrEmpty
        $t.input_schema.type | Should -Be 'object'
    }
    It 'shapes OpenAI tools with function.parameters' {
        $t = @(ConvertTo-SPProviderTools -Provider openai -Catalog (Get-SPAiToolCatalog))[0]
        $t.type | Should -Be 'function'
        $t.function.parameters.type | Should -Be 'object'
    }
}

Describe 'Request body' {
    It 'Anthropic body carries system, max_tokens, tools' {
        $b = New-SPAiRequestBody -Provider anthropic -Model 'claude-x' -System 'sys' -Messages @(@{ role = 'user'; content = 'hi' }) -Tools @(@{ name = 't' })
        $b.model      | Should -Be 'claude-x'
        $b.system     | Should -Be 'sys'
        $b.max_tokens | Should -BeGreaterThan 0
        $b.tools.Count | Should -Be 1
    }
    It 'OpenAI body prepends the system message and sets tool_choice' {
        $b = New-SPAiRequestBody -Provider openai -Model 'gpt' -System 'sys' -Messages @(@{ role = 'user'; content = 'hi' }) -Tools @(@{ type = 'function' })
        @($b.messages)[0].role | Should -Be 'system'
        $b.tool_choice | Should -Be 'auto'
    }
}

Describe 'Response parsing' {
    It 'parses an Anthropic tool_use response' {
        $resp = [pscustomobject]@{ stop_reason = 'tool_use'; content = @(
                [pscustomobject]@{ type = 'text'; text = 'Checking.' }
                [pscustomobject]@{ type = 'tool_use'; id = 'toolu_1'; name = 'sharepoint_explore'; input = [pscustomobject]@{ siteUrl = 'https://x' } }
            ) }
        $r = Read-SPAiResponse -Provider anthropic -Response $resp
        $r.Text | Should -Be 'Checking.'
        $r.StopReason | Should -Be 'tool_use'
        $r.ToolCalls.Count | Should -Be 1
        $r.ToolCalls[0].id | Should -Be 'toolu_1'
        $r.ToolCalls[0].name | Should -Be 'sharepoint_explore'
        $r.ToolCalls[0].input.siteUrl | Should -Be 'https://x'
    }
    It 'parses an OpenAI tool_calls response (arguments are a JSON string)' {
        $resp = [pscustomobject]@{ choices = @([pscustomobject]@{ finish_reason = 'tool_calls'; message = [pscustomobject]@{
                        role = 'assistant'; content = $null; tool_calls = @([pscustomobject]@{ id = 'call_1'; type = 'function'; function = [pscustomobject]@{ name = 'sharepoint_large_files'; arguments = '{"siteUrl":"https://y","minSizeMB":200}' } })
                    }
                }) }
        $r = Read-SPAiResponse -Provider openai -Response $resp
        $r.StopReason | Should -Be 'tool_calls'
        $r.ToolCalls.Count | Should -Be 1
        $r.ToolCalls[0].id | Should -Be 'call_1'
        $r.ToolCalls[0].input.siteUrl | Should -Be 'https://y'
        $r.ToolCalls[0].input.minSizeMB | Should -Be 200
    }
}

Describe 'Tool-result messages' {
    It 'Anthropic appends a tool_result user turn' {
        $msgs = [System.Collections.Generic.List[object]]::new()
        Add-SPAiToolResult -Provider anthropic -Messages $msgs -ToolCallId 'toolu_1' -ResultText 'data'
        $msgs[0].role | Should -Be 'user'
        $msgs[0].content[0].type | Should -Be 'tool_result'
        $msgs[0].content[0].tool_use_id | Should -Be 'toolu_1'
    }
    It 'OpenAI appends a tool-role message' {
        $msgs = [System.Collections.Generic.List[object]]::new()
        Add-SPAiToolResult -Provider openai -Messages $msgs -ToolCallId 'call_1' -ResultText 'data'
        $msgs[0].role | Should -Be 'tool'
        $msgs[0].tool_call_id | Should -Be 'call_1'
    }
}

Describe 'Endpoints + headers' {
    It 'defaults Anthropic and OpenAI endpoints, honors overrides (Ollama)' {
        Get-SPAiEndpoint -Provider anthropic | Should -Be 'https://api.anthropic.com/v1/messages'
        Get-SPAiEndpoint -Provider openai | Should -Be 'https://api.openai.com/v1/chat/completions'
        Get-SPAiEndpoint -Provider openai -Endpoint 'http://localhost:11434/v1' | Should -Be 'http://localhost:11434/v1/chat/completions'
    }
    It 'uses x-api-key for Anthropic and Bearer for OpenAI' {
        (Get-SPAiHeaders -Provider anthropic -ApiKey 'k')['x-api-key'] | Should -Be 'k'
        (Get-SPAiHeaders -Provider openai -ApiKey 'k')['Authorization'] | Should -Be 'Bearer k'
    }
}

Describe 'Secret DPAPI round-trip' {
    It 'protects then unprotects to the original' {
        $secret = 'sk-test-12345-abcde'
        $enc = Protect-SPSecret $secret
        $enc | Should -Not -Be $secret
        (Unprotect-SPSecret $enc) | Should -Be $secret
    }
    It 'handles empty input' {
        Protect-SPSecret '' | Should -Be ''
        Unprotect-SPSecret '' | Should -Be ''
    }
}

Describe 'Invoke-SPAiConversation (agent loop)' {
    It 'calls a tool, feeds the result back, and summarizes (Anthropic)' {
        $state = @{ n = 0 }
        $callModel = {
            param($body, $endpoint, $headers)
            $state.n++
            if ($state.n -ge 2) {
                [pscustomobject]@{ stop_reason = 'end_turn'; content = @([pscustomobject]@{ type = 'text'; text = 'Found 2 external users.' }) }
            }
            else {
                [pscustomobject]@{ stop_reason = 'tool_use'; content = @(
                        [pscustomobject]@{ type = 'text'; text = 'Let me check.' },
                        [pscustomobject]@{ type = 'tool_use'; id = 'toolu_1'; name = 'sharepoint_external_sharing_report'; input = [pscustomobject]@{ siteUrl = 'https://x' } }
                    ) }
            }
        }
        $steps = [System.Collections.Generic.List[object]]::new()
        $msgs = [System.Collections.Generic.List[object]]::new()
        $msgs.Add(@{ role = 'user'; content = 'who has external access?' })
        $toolRan = @{ cmdlet = $null }

        Invoke-SPAiConversation -Config @{ Provider = 'anthropic'; Model = 'claude'; ApiKey = 'k' } -Messages $msgs -Catalog (Get-SPAiToolCatalog) `
            -CallModel $callModel `
            -Emit { param($s) [void]$steps.Add($s) } `
            -InvokeTool { param($c, $p) $toolRan.cmdlet = $c; @([pscustomobject]@{ Principal = 'a@x.com' }, [pscustomobject]@{ Principal = 'b@x.com' }) }

        $state.n | Should -Be 2   # one tool round, then the answer
        $toolRan.cmdlet | Should -Be 'Get-SPSharingReport'
        @($steps | Where-Object { $_.kind -eq 'toolcall' }).Count | Should -Be 1
        @($steps | Where-Object { $_.kind -eq 'toolresult' }).Count | Should -Be 1
        (@($steps | Where-Object { $_.kind -eq 'toolresult' })[0]).count | Should -Be 2
        (@($steps | Where-Object { $_.kind -eq 'assistant' })[-1]).text | Should -Match 'external users'
        $msgs.Count | Should -BeGreaterThan 3   # user + assistant(tool_use) + tool_result + assistant
    }

    It 'surfaces a tool error without crashing the loop (OpenAI)' {
        $state = @{ n = 0 }
        $callModel = {
            param($body, $endpoint, $headers)
            $state.n++
            if ($state.n -ge 2) {
                [pscustomobject]@{ choices = @([pscustomobject]@{ finish_reason = 'stop'; message = [pscustomobject]@{ role = 'assistant'; content = 'I could not reach that site.' } }) }
            }
            else {
                [pscustomobject]@{ choices = @([pscustomobject]@{ finish_reason = 'tool_calls'; message = [pscustomobject]@{
                                role = 'assistant'; content = $null; tool_calls = @([pscustomobject]@{ id = 'call_1'; type = 'function'; function = [pscustomobject]@{ name = 'sharepoint_explore'; arguments = '{"siteUrl":"https://x"}' } })
                            }
                        }) }
            }
        }
        $steps = [System.Collections.Generic.List[object]]::new()
        $msgs = [System.Collections.Generic.List[object]]::new()
        $msgs.Add(@{ role = 'user'; content = 'explore marketing' })

        Invoke-SPAiConversation -Config @{ Provider = 'openai'; Model = 'gpt'; ApiKey = 'k' } -Messages $msgs -Catalog (Get-SPAiToolCatalog) `
            -CallModel $callModel `
            -Emit { param($s) [void]$steps.Add($s) } `
            -InvokeTool { param($c, $p) throw 'Not connected' }

        $state.n | Should -Be 2
        @($steps | Where-Object { $_.kind -eq 'toolerror' }).Count | Should -Be 1
        (@($steps | Where-Object { $_.kind -eq 'assistant' })[-1]).text | Should -Match 'could not'
    }
}
