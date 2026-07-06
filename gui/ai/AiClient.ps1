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
# tool and returns its data (the GUI runs this in its worker; tests pass canned data). $PreviewedWrites
# is the set of ARMED write calls (owned by the caller so it survives across turns): execute=true is
# downgraded to a preview unless its exact call was previewed in an EARLIER turn. Previews from this
# turn arm only when the function returns — so a write can never preview and apply within one turn,
# which forces a user reply between plan and change (prompt injection in tool results can't skip it).
function Invoke-SPAiConversation {
    param(
        [hashtable]$Config,
        [System.Collections.Generic.List[object]]$Messages,
        [object[]]$Catalog,
        [scriptblock]$Emit,
        [scriptblock]$InvokeTool,
        [scriptblock]$CallModel,   # injectable for tests; defaults to the real HTTP call
        [System.Collections.Generic.HashSet[string]]$PreviewedWrites,
        [int]$MaxIterations = 8
    )
    if ($null -eq $PreviewedWrites) { $PreviewedWrites = [System.Collections.Generic.HashSet[string]]::new() }
    $newPreviews = [System.Collections.Generic.List[string]]::new()   # armed only after this turn ends
    $provider = $Config.Provider
    $tools    = @(ConvertTo-SPProviderTools -Provider $provider -Catalog $Catalog)
    $writesOn = @($Catalog | Where-Object { -not $_.readOnly }).Count -gt 0
    $system   = Get-SPAiSystemPrompt -WritesEnabled:$writesOn
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
            $params = ConvertTo-SPCmdletParams -Tool $tool -Arguments $tc.input
            # Write tools: strict preview-first. execute=true only takes effect once this exact call
            # (tool + args) has already run as a preview — otherwise it is downgraded to a preview.
            $isWrite = -not $tool.readOnly
            $apply = $false; $downgraded = $false; $writeKey = $null
            if ($isWrite) {
                $apply    = [bool]$params['Execute']
                $writeKey = Get-SPWriteKey -Tool $tool -Params $params
                if ($apply -and -not $PreviewedWrites.Contains($writeKey)) { $apply = $false; $downgraded = $true }
                $params = Resolve-SPWriteParams -Tool $tool -Params $params -Apply $apply
            }
            $cmdline = Get-SPCommandLine -Cmdlet $tool.cmdlet -Params $params
            & $Emit @{ kind = 'toolcall'; name = $tc.name; cmdline = $cmdline; write = $isWrite; applied = ($isWrite -and $apply) }
            try {
                $data = & $InvokeTool $tool.cmdlet $params
                $rows = @($data)
                if ($isWrite -and -not $apply) { $newPreviews.Add($writeKey) }
                & $Emit @{ kind = 'toolresult'; name = $tc.name; rows = $rows; count = $rows.Count; cmdline = $cmdline; write = $isWrite; applied = ($isWrite -and $apply) }
                $resultText = if ($rows.Count) { ($rows | ConvertTo-Json -Depth 6 -Compress) } else { '[] (no rows)' }
                if ($isWrite) {
                    $prefix = if ($apply) { 'APPLIED — the change was made.' }
                    elseif ($downgraded) { 'PREVIEW ONLY — nothing was changed. Writes always preview first, and the apply call is only honored after the user replies: show them this plan, end your turn, and call the tool again with execute=true only if their next message confirms.' }
                    else { 'PREVIEW ONLY — nothing was changed. Show the user this plan and end your turn; if their next message confirms, call the same tool again with execute=true to apply.' }
                    $resultText = "$prefix`n$resultText"
                }
            }
            catch {
                $err = $_.Exception.Message
                & $Emit @{ kind = 'toolerror'; name = $tc.name; error = $err; cmdline = $cmdline }
                $resultText = "Error: $err"
            }
            Add-SPAiToolResult -Provider $provider -Messages $Messages -ToolCallId $tc.id -ResultText $resultText
        }
    }
    # Arm this turn's previews only now — the next user turn may execute them, this one never could.
    foreach ($k in $newPreviews) { [void]$PreviewedWrites.Add($k) }
}
