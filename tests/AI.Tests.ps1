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
    It 'returns only read-only tools by default (writes off)' {
        $cat = Get-SPAiToolCatalog
        $cat.Count | Should -BeGreaterThan 4
        foreach ($t in $cat) {
            $t.name     | Should -Not -BeNullOrEmpty
            $t.cmdlet   | Should -Not -BeNullOrEmpty
            $t.readOnly | Should -BeTrue
            $t.schema.type | Should -Be 'object'
        }
    }
    It '-IncludeWrites adds write tools, each with an optional execute arg' {
        $cat = Get-SPAiToolCatalog -IncludeWrites
        $writes = @($cat | Where-Object { -not $_.readOnly })
        $writes.Count | Should -BeGreaterThan 5
        foreach ($t in $writes) {
            $t.schema.properties.Keys | Should -Contain 'execute'
            $t.schema.required        | Should -Not -Contain 'execute'
        }
        # The read-only set is unchanged by the switch.
        @($cat | Where-Object readOnly).name | Should -Be (Get-SPAiToolCatalog).name
    }
    It 'has unique tool names (including writes)' {
        $names = (Get-SPAiToolCatalog -IncludeWrites).name
        ($names | Select-Object -Unique).Count | Should -Be $names.Count
    }
}

Describe 'ConvertTo-SPCmdletParams' {
    It 'maps camelCase args to PascalCase cmdlet params' {
        $tool = @{ cmdlet = 'Get-SPSharingReport'; schema = @{ properties = [ordered]@{ siteUrl = @{}; includeLinks = @{} } } }
        $p = ConvertTo-SPCmdletParams -Tool $tool -Arguments @{ siteUrl = 'https://x'; includeLinks = $true }
        $p['SiteUrl']      | Should -Be 'https://x'
        $p['IncludeLinks'] | Should -BeTrue
    }
    It 'applies fixed params and skips empty values' {
        $tool = @{ fixedParams = @{ IncludeStorage = $true }; schema = @{ properties = [ordered]@{ siteUrl = @{} } } }
        $p = ConvertTo-SPCmdletParams -Tool $tool -Arguments @{ siteUrl = '' }
        $p['IncludeStorage'] | Should -BeTrue
        $p.ContainsKey('SiteUrl') | Should -BeFalse
    }
    It 'reads args from a PSCustomObject too' {
        $tool = @{ schema = @{ properties = [ordered]@{ minSizeMB = @{} } } }
        $p = ConvertTo-SPCmdletParams -Tool $tool -Arguments ([pscustomobject]@{ minSizeMB = 200 })
        $p['MinSizeMB'] | Should -Be 200
    }
    It 'drops arguments the schema does not declare (no smuggled safety switches)' {
        $tool = @{ schema = @{ properties = [ordered]@{ siteUrl = @{} } } }
        $p = ConvertTo-SPCmdletParams -Tool $tool -Arguments @{ siteUrl = 'https://x'; force = $true; confirm = $false; whatIf = $false; connection = 'evil' }
        @($p.Keys) | Should -Be @('SiteUrl')
    }
    It 'forwards nothing when the tool has no schema (secure default)' {
        (ConvertTo-SPCmdletParams -Tool @{} -Arguments @{ force = $true }).Count | Should -Be 0
    }
    It 'keeps undeclared fixed params non-overridable' {
        $tool = (Get-SPAiToolCatalog -IncludeWrites) | Where-Object name -eq 'sharepoint_migrate_files'
        $p = ConvertTo-SPCmdletParams -Tool $tool -Arguments @{ source = 'C:\s'; siteUrl = 'https://x'; preserveTimestamps = $false }
        $p['PreserveTimestamps'] | Should -BeTrue   # fixed param wins; arg not in schema is dropped
    }
}

Describe 'Write helpers (preview-first contract)' {
    It 'previews with -WhatIf and never leaks the execute arg to the cmdlet' {
        $tool = @{ name = 'sharepoint_bulk_metadata' }
        $p = Resolve-SPWriteParams -Tool $tool -Params @{ SiteUrl = 'https://x'; Execute = $true } -Apply $false
        $p['WhatIf'] | Should -BeTrue
        $p.ContainsKey('Execute') | Should -BeFalse
        $p.ContainsKey('Force')   | Should -BeFalse
    }
    It 'applies with -Force (and no -WhatIf)' {
        $p = Resolve-SPWriteParams -Tool @{ name = 't' } -Params @{ SiteUrl = 'https://x'; Execute = $true } -Apply $true
        $p['Force'] | Should -BeTrue
        $p.ContainsKey('WhatIf') | Should -BeFalse
    }
    It 'strips smuggled safety switches in both modes' {
        $dirty = @{ SiteUrl = 'https://x'; Execute = $true; Force = $true; WhatIf = $false; Confirm = $false }
        $preview = Resolve-SPWriteParams -Tool @{ name = 't' } -Params $dirty -Apply $false
        @($preview.Keys | Sort-Object) | Should -Be @('SiteUrl', 'WhatIf')
        $preview['WhatIf'] | Should -BeTrue
        $apply = Resolve-SPWriteParams -Tool @{ name = 't' } -Params $dirty -Apply $true
        @($apply.Keys | Sort-Object) | Should -Be @('Force', 'SiteUrl')
        $apply['Force'] | Should -BeTrue
    }
    It 'omits -Force for noForce cmdlets (New-SPSiteFromTemplate)' {
        $tool = (Get-SPAiToolCatalog -IncludeWrites) | Where-Object name -eq 'sharepoint_provision_site'
        $tool.noForce | Should -BeTrue
        $p = Resolve-SPWriteParams -Tool $tool -Params @{ Title = 'HR'; Execute = $true } -Apply $true
        $p.ContainsKey('Force')  | Should -BeFalse
        $p.ContainsKey('WhatIf') | Should -BeFalse
    }
    It 'write keys ignore safety flags and argument order' {
        $tool = @{ name = 'sharepoint_remove_orphaned_users' }
        $k1 = Get-SPWriteKey -Tool $tool -Params @{ SiteUrl = 'https://x'; Execute = $true }
        $k2 = Get-SPWriteKey -Tool $tool -Params @{ WhatIf = $true; SiteUrl = 'https://x' }
        $k1 | Should -Be $k2
        $k3 = Get-SPWriteKey -Tool $tool -Params @{ SiteUrl = 'https://OTHER' }
        $k3 | Should -Not -Be $k1
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

Describe 'System prompt' {
    It 'frames the assistant as read-only when writes are off' {
        $p = Get-SPAiSystemPrompt
        $p | Should -Match 'read-only'
        $p | Should -Match 'Allow write actions'
        $p | Should -Not -Match 'execute=true'
    }
    It 'states the preview-then-execute contract when writes are on' {
        $p = Get-SPAiSystemPrompt -WritesEnabled
        $p | Should -Match 'PREVIEW'
        $p | Should -Match 'execute=true'
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

    It 'never applies in the preview turn — execute=true only works in a later turn' {
        # Turn 1: the model tries to apply immediately, twice with identical args. Both calls must
        # run as -WhatIf previews — a preview arms only when the turn ends, so a prompt-injected
        # model cannot preview + apply within one user message.
        $mkModel = {
            param($tries)
            $state = @{ n = 0 }
            {
                param($body, $endpoint, $headers)
                $state.n++
                if ($state.n -gt $tries) {
                    [pscustomobject]@{ stop_reason = 'end_turn'; content = @([pscustomobject]@{ type = 'text'; text = 'Done.' }) }
                }
                else {
                    [pscustomobject]@{ stop_reason = 'tool_use'; content = @(
                            [pscustomobject]@{ type = 'tool_use'; id = "toolu_$($state.n)"; name = 'sharepoint_remove_orphaned_users'; input = [pscustomobject]@{ siteUrl = 'https://x'; execute = $true } }
                        ) }
                }
            }.GetNewClosure()
        }
        $steps = [System.Collections.Generic.List[object]]::new()
        $msgs = [System.Collections.Generic.List[object]]::new()
        $msgs.Add(@{ role = 'user'; content = 'remove the orphaned users on /sites/x' })
        $calls = [System.Collections.Generic.List[hashtable]]::new()
        $previewed = [System.Collections.Generic.HashSet[string]]::new()
        $cfg = @{ Provider = 'anthropic'; Model = 'claude'; ApiKey = 'k' }
        $invoke = { param($c, $p) [void]$calls.Add($p); @([pscustomobject]@{ Principal = 'ghost@x.com'; Status = 'WouldRemove' }) }

        Invoke-SPAiConversation -Config $cfg -Messages $msgs -Catalog (Get-SPAiToolCatalog -IncludeWrites) `
            -PreviewedWrites $previewed -CallModel (& $mkModel 2) -Emit { param($s) [void]$steps.Add($s) } -InvokeTool $invoke

        $calls.Count | Should -Be 2
        foreach ($c in $calls) {                       # BOTH same-turn calls stay previews
            $c['WhatIf'] | Should -BeTrue
            $c.ContainsKey('Force')   | Should -BeFalse
            $c.ContainsKey('Execute') | Should -BeFalse
        }
        @($steps | Where-Object { $_.kind -eq 'toolresult' -and $_.applied }).Count | Should -Be 0
        ($msgs | ConvertTo-Json -Depth 8) | Should -Match 'PREVIEW ONLY'

        # Turn 2: the user replied; the previewed call is now armed, so execute=true applies.
        $msgs.Add(@{ role = 'user'; content = 'yes, go ahead' })
        Invoke-SPAiConversation -Config $cfg -Messages $msgs -Catalog (Get-SPAiToolCatalog -IncludeWrites) `
            -PreviewedWrites $previewed -CallModel (& $mkModel 1) -Emit { param($s) [void]$steps.Add($s) } -InvokeTool $invoke

        $calls.Count | Should -Be 3
        $calls[2]['Force'] | Should -BeTrue
        $calls[2].ContainsKey('WhatIf') | Should -BeFalse
        (@($steps | Where-Object { $_.kind -eq 'toolresult' })[-1]).applied | Should -BeTrue
    }

    It 'previews again when the arguments change after a preview' {
        $state = @{ n = 0 }
        $callModel = {
            param($body, $endpoint, $headers)
            $state.n++
            switch ($state.n) {
                1 { [pscustomobject]@{ stop_reason = 'tool_use'; content = @([pscustomobject]@{ type = 'tool_use'; id = 't1'; name = 'sharepoint_check_in_files'; input = [pscustomobject]@{ siteUrl = 'https://x' } }) } }
                2 { [pscustomobject]@{ stop_reason = 'tool_use'; content = @([pscustomobject]@{ type = 'tool_use'; id = 't2'; name = 'sharepoint_check_in_files'; input = [pscustomobject]@{ siteUrl = 'https://OTHER'; execute = $true } }) } }
                default { [pscustomobject]@{ stop_reason = 'end_turn'; content = @([pscustomobject]@{ type = 'text'; text = 'Done.' }) } }
            }
        }
        $calls = [System.Collections.Generic.List[hashtable]]::new()
        $msgs = [System.Collections.Generic.List[object]]::new()
        $msgs.Add(@{ role = 'user'; content = 'check in files' })

        Invoke-SPAiConversation -Config @{ Provider = 'anthropic'; Model = 'claude'; ApiKey = 'k' } -Messages $msgs `
            -Catalog (Get-SPAiToolCatalog -IncludeWrites) `
            -CallModel $callModel `
            -Emit { param($s) } `
            -InvokeTool { param($c, $p) [void]$calls.Add($p); @() }

        $calls.Count | Should -Be 2
        $calls[1]['WhatIf'] | Should -BeTrue          # different site ⇒ back to preview
        $calls[1].ContainsKey('Force') | Should -BeFalse
    }

    It 'write tools are unknown to the loop when the catalog is read-only' {
        $state = @{ n = 0 }
        $callModel = {
            param($body, $endpoint, $headers)
            $state.n++
            if ($state.n -ge 2) { [pscustomobject]@{ stop_reason = 'end_turn'; content = @([pscustomobject]@{ type = 'text'; text = 'Writes are off.' }) } }
            else {
                [pscustomobject]@{ stop_reason = 'tool_use'; content = @([pscustomobject]@{ type = 'tool_use'; id = 't1'; name = 'sharepoint_remove_orphaned_users'; input = [pscustomobject]@{ siteUrl = 'https://x'; execute = $true } }) }
            }
        }
        $steps = [System.Collections.Generic.List[object]]::new()
        $msgs = [System.Collections.Generic.List[object]]::new()
        $msgs.Add(@{ role = 'user'; content = 'remove orphaned users' })
        $ran = @{ hit = $false }

        Invoke-SPAiConversation -Config @{ Provider = 'anthropic'; Model = 'claude'; ApiKey = 'k' } -Messages $msgs `
            -Catalog (Get-SPAiToolCatalog) `
            -CallModel $callModel `
            -Emit { param($s) [void]$steps.Add($s) } `
            -InvokeTool { param($c, $p) $ran.hit = $true; @() }

        $ran.hit | Should -BeFalse
        @($steps | Where-Object { $_.kind -eq 'toolerror' }).Count | Should -Be 1
    }
}
