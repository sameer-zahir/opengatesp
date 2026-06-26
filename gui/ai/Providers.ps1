#Requires -Version 7.4
# Pure provider adapters for the BYOK AI bar. Two wire formats:
#   - 'anthropic' : Anthropic Messages API (/v1/messages, tool_use / tool_result blocks)
#   - 'openai'    : OpenAI Chat Completions (/chat/completions) — also covers Azure OpenAI, Ollama,
#                   and LM Studio; only the endpoint + auth header differ.
# No HTTP happens here (that's the agent loop's Invoke-RestMethod) so all of this is unit-testable.

# Catalog -> provider-shaped tool definitions.
function ConvertTo-SPProviderTools {
    param([ValidateSet('anthropic', 'openai')][string]$Provider, [object[]]$Catalog)
    if ($Provider -eq 'anthropic') {
        foreach ($t in $Catalog) { @{ name = $t.name; description = $t.description; input_schema = $t.schema } }
    }
    else {
        foreach ($t in $Catalog) { @{ type = 'function'; function = @{ name = $t.name; description = $t.description; parameters = $t.schema } } }
    }
}

# Build the request body (a hashtable; the loop ConvertTo-Json's it).
function New-SPAiRequestBody {
    param(
        [ValidateSet('anthropic', 'openai')][string]$Provider,
        [string]$Model, [string]$System, [object[]]$Messages, [object[]]$Tools, [int]$MaxTokens = 2048
    )
    if ($Provider -eq 'anthropic') {
        $body = @{ model = $Model; max_tokens = $MaxTokens; messages = @($Messages) }
        if ($System) { $body.system = $System }
        if ($Tools) { $body.tools = @($Tools) }
        $body
    }
    else {
        $msgs = @($Messages)
        if ($System) { $msgs = @(@{ role = 'system'; content = $System }) + $msgs }
        $body = @{ model = $Model; messages = $msgs }
        if ($Tools) { $body.tools = @($Tools); $body.tool_choice = 'auto' }
        $body
    }
}

# Parse a provider response into a normalized shape: @{ Text; ToolCalls=@(@{ id; name; input }); StopReason }.
function Read-SPAiResponse {
    param([ValidateSet('anthropic', 'openai')][string]$Provider, $Response)
    $text = ''; $toolCalls = @(); $stop = $null
    if ($Provider -eq 'anthropic') {
        $stop = $Response.stop_reason
        if ($Response.content) {
            foreach ($block in @($Response.content)) {
                if ($block.type -eq 'text') { $text += [string]$block.text }
                elseif ($block.type -eq 'tool_use') { $toolCalls += @{ id = $block.id; name = $block.name; input = $block.input } }
            }
        }
    }
    else {
        $choice = @($Response.choices)[0]
        $stop = $choice.finish_reason
        if ($choice.message.content) { $text = [string]$choice.message.content }
        if ($choice.message.tool_calls) {
            foreach ($tc in @($choice.message.tool_calls)) {
                $argObj = @{}
                try { if ($tc.function.arguments) { $argObj = $tc.function.arguments | ConvertFrom-Json } } catch { $argObj = @{} }
                $toolCalls += @{ id = $tc.id; name = $tc.function.name; input = $argObj }
            }
        }
    }
    @{ Text = $text; ToolCalls = @($toolCalls); StopReason = $stop }
}

# Append the assistant's turn (echoing its content / tool calls) to the running messages list.
function Add-SPAiAssistantTurn {
    param([ValidateSet('anthropic', 'openai')][string]$Provider, [System.Collections.Generic.List[object]]$Messages, $Response)
    if ($Provider -eq 'anthropic') { $Messages.Add(@{ role = 'assistant'; content = $Response.content }) }
    else { $Messages.Add((@($Response.choices)[0].message) ) }
}

# Append a tool result so the model can continue.
function Add-SPAiToolResult {
    param([ValidateSet('anthropic', 'openai')][string]$Provider, [System.Collections.Generic.List[object]]$Messages, [string]$ToolCallId, [string]$ResultText)
    if ($Provider -eq 'anthropic') {
        $Messages.Add(@{ role = 'user'; content = @(@{ type = 'tool_result'; tool_use_id = $ToolCallId; content = $ResultText }) })
    }
    else {
        $Messages.Add(@{ role = 'tool'; tool_call_id = $ToolCallId; content = $ResultText })
    }
}

# Endpoint + headers for the loop's HTTP call. Endpoint override supports Azure/Ollama/LM Studio.
function Get-SPAiEndpoint {
    param([string]$Provider, [string]$Endpoint)
    if ($Provider -eq 'anthropic') { if ($Endpoint) { $Endpoint } else { 'https://api.anthropic.com/v1/messages' } }
    else { $base = if ($Endpoint) { $Endpoint.TrimEnd('/') } else { 'https://api.openai.com/v1' }; "$base/chat/completions" }
}
function Get-SPAiHeaders {
    param([string]$Provider, [string]$ApiKey)
    if ($Provider -eq 'anthropic') {
        @{ 'x-api-key' = $ApiKey; 'anthropic-version' = '2023-06-01' }
    }
    else {
        $h = @{}
        if ($ApiKey) { $h['Authorization'] = "Bearer $ApiKey" }
        $h
    }
}

# System prompt that frames the assistant for SharePoint admins (non-technical GUI audience).
function Get-SPAiSystemPrompt {
    @'
You are the OpenGateSP assistant, embedded in a Windows app that helps SharePoint Online admins
migrate and govern their tenant. Use the provided tools to answer questions about the user's
SharePoint (external sharing, permissions, orphaned users, migration readiness, inventory, etc.).
Prefer calling a tool over guessing. When a site URL is needed and the user gave a site name, ask
for or construct the full URL (https://<tenant>.sharepoint.com/sites/<name>). Keep answers short and
plain-language; the audience is not technical. After a tool runs, summarize the key findings in 1-3
sentences. Never claim to have changed anything — these tools are read-only.
'@
}
