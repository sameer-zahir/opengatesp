#Requires -Version 7.4
# The BYOK agent loop: drives the user's chosen model through tool calls until it answers. Runs in the
# GUI's worker runspace (where the module + PnP connection live). The HTTP call and the tool execution
# are injected (Invoke-SPAiHttp / the -InvokeTool scriptblock) so the orchestration is unit-testable
# without a network or a tenant — see tests/AI.Tests.ps1. Streams progress via the -Emit callback.

# The one impure bit: the actual model HTTP request. Mocked in tests.
function Invoke-SPAiHttp {
    param([string]$Endpoint, [hashtable]$Headers, [hashtable]$Body, [int]$TimeoutSec = 90)
    $json = $Body | ConvertTo-Json -Depth 12
    Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $Headers -Body $json -ContentType 'application/json' -TimeoutSec $TimeoutSec
}

# Run one user turn end-to-end. $Config = @{ Provider; Model; Endpoint; ApiKey }. $Messages is the
# provider-native running history (mutated in place). $Emit { param($step) } streams step hashtables
# (kind = assistant|toolcall|toolresult|toolerror). $InvokeTool { param($cmdlet,$paramHash) } executes a
# tool and returns its data (the GUI runs this in its worker; tests pass canned data).
function Invoke-SPAiConversation {
    param(
        [hashtable]$Config,
        [System.Collections.Generic.List[object]]$Messages,
        [object[]]$Catalog,
        [scriptblock]$Emit,
        [scriptblock]$InvokeTool,
        [scriptblock]$CallModel,   # injectable for tests; defaults to the real HTTP call
        [int]$MaxIterations = 8
    )
    $provider = $Config.Provider
    $tools    = @(ConvertTo-SPProviderTools -Provider $provider -Catalog $Catalog)
    $system   = Get-SPAiSystemPrompt
    $endpoint = Get-SPAiEndpoint -Provider $provider -Endpoint $Config.Endpoint
    $headers  = Get-SPAiHeaders -Provider $provider -ApiKey $Config.ApiKey

    for ($i = 0; $i -lt $MaxIterations; $i++) {
        $body = New-SPAiRequestBody -Provider $provider -Model $Config.Model -System $system -Messages $Messages -Tools $tools
        $resp = if ($CallModel) { & $CallModel $body $endpoint $headers } else { Invoke-SPAiHttp -Endpoint $endpoint -Headers $headers -Body $body }
        $parsed = Read-SPAiResponse -Provider $provider -Response $resp

        if ($parsed.Text) { & $Emit @{ kind = 'assistant'; text = $parsed.Text } }
        Add-SPAiAssistantTurn -Provider $provider -Messages $Messages -Response $resp

        if (@($parsed.ToolCalls).Count -eq 0) { break }

        foreach ($tc in $parsed.ToolCalls) {
            $tool = $Catalog | Where-Object { $_.name -eq $tc.name } | Select-Object -First 1
            if (-not $tool) {
                & $Emit @{ kind = 'toolerror'; name = $tc.name; error = 'Unknown tool' }
                Add-SPAiToolResult -Provider $provider -Messages $Messages -ToolCallId $tc.id -ResultText "Error: unknown tool '$($tc.name)'"
                continue
            }
            $params  = ConvertTo-SPCmdletParams -Tool $tool -Arguments $tc.input
            $cmdline = Get-SPCommandLine -Cmdlet $tool.cmdlet -Params $params
            & $Emit @{ kind = 'toolcall'; name = $tc.name; cmdline = $cmdline }
            try {
                $data = & $InvokeTool $tool.cmdlet $params
                $rows = @($data)
                & $Emit @{ kind = 'toolresult'; name = $tc.name; rows = $rows; count = $rows.Count; cmdline = $cmdline }
                $resultText = if ($rows.Count) { ($rows | ConvertTo-Json -Depth 6 -Compress) } else { '[] (no rows)' }
            }
            catch {
                $err = $_.Exception.Message
                & $Emit @{ kind = 'toolerror'; name = $tc.name; error = $err; cmdline = $cmdline }
                $resultText = "Error: $err"
            }
            Add-SPAiToolResult -Provider $provider -Messages $Messages -ToolCallId $tc.id -ResultText $resultText
        }
    }
}
