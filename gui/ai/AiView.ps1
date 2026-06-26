#Requires -Version 7.4
# Wires the Assistant view (ViewAI): the "Connect your AI" panel (BYOK config), and the chat loop that
# runs Invoke-SPAiConversation in the GUI's worker runspace, streaming step-cards back to the UI via a
# ConcurrentQueue drained on the dispatcher. Dot-sourced by Start-OpenGateSPGui.ps1 (shares its script
# scope: $script:Worker, $script:Busy, controls, Show-Toast, Set-Status, Invoke-FadeIn). Pure AI logic
# is in the sibling ai\*.ps1 files (unit-tested); this is GUI glue, verified by render + live run.

# Display name -> provider kind + defaults. Anthropic = Claude; everything else speaks the OpenAI format.
function Initialize-AiView {
    $script:AiProviders = [ordered]@{
        'Claude (Anthropic)' = @{ kind = 'anthropic'; endpoint = ''; model = 'claude-sonnet-4-6'; needsEndpoint = $false }
        'OpenAI'             = @{ kind = 'openai'; endpoint = ''; model = 'gpt-4o'; needsEndpoint = $false }
        'Ollama (local)'     = @{ kind = 'openai'; endpoint = 'http://localhost:11434/v1'; model = 'llama3.1'; needsEndpoint = $true }
        'LM Studio (local)'  = @{ kind = 'openai'; endpoint = 'http://localhost:1234/v1'; model = 'local-model'; needsEndpoint = $true }
    }
    $script:AiProvider.ItemsSource = [string[]]@($script:AiProviders.Keys)
    $script:AiProvider.Add_SelectionChanged({
            $p = $script:AiProviders[[string]$script:AiProvider.SelectedItem]
            if (-not $p) { return }
            if (-not $script:AiModel.Text.Trim()) { $script:AiModel.Text = $p.model }
            $vis = if ($p.needsEndpoint) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
            $script:AiEndpoint.Visibility = $vis; $script:AiEndpointLabel.Visibility = $vis
            if ($p.needsEndpoint -and -not $script:AiEndpoint.Text.Trim()) { $script:AiEndpoint.Text = $p.endpoint }
        })

    $cfg = Get-SPAiConfig
    if ($cfg -and $cfg.Provider) {
        $script:AiCfg = @{ Provider = $cfg.Provider; Model = $cfg.Model; Endpoint = $cfg.Endpoint; KeyEnc = $cfg.KeyEnc }
        $script:AiProvider.SelectedItem = (Resolve-AiProviderDisplay $cfg.Provider $cfg.Endpoint)
        $script:AiModel.Text = $cfg.Model
        if ($cfg.Endpoint) { $script:AiEndpoint.Text = $cfg.Endpoint }
        if ($cfg.AllowWrites) { $script:AiAllowWrites.IsChecked = $true }
        $script:AiCfgStatus.Text = "Connected ($($cfg.Model))."
    }
    else { $script:AiProvider.SelectedIndex = 0 }

    $script:AiSave.Add_Click({ Save-AiPanelConfig })
    $script:AiTest.Add_Click({ Test-AiPanelConnection })
    $script:AiAddClaude.Add_Click({ Add-ClaudeDesktopEntry })
    $script:AiHelpKey.Add_Click({ Start-Process 'https://github.com/sameer-zahir/opengatesp/blob/main/docs/13-ai-assistant.md' })
    $script:AiSend.Add_Click({ Start-SPAiTurn $script:AiInput.Text })
    $script:AiInput.Add_KeyDown({ if ($args[1].Key -eq 'Return') { $args[1].Handled = $true; Start-SPAiTurn $script:AiInput.Text } })
}

function Resolve-AiProviderDisplay([string]$kind, [string]$endpoint) {
    foreach ($k in $script:AiProviders.Keys) {
        $p = $script:AiProviders[$k]
        if ($p.kind -ne $kind) { continue }
        if (-not $p.needsEndpoint) { return $k }
        if ($endpoint -and $p.endpoint -and $endpoint.TrimEnd('/') -eq $p.endpoint.TrimEnd('/')) { return $k }
    }
    foreach ($k in $script:AiProviders.Keys) { if ($script:AiProviders[$k].kind -eq $kind) { return $k } }
    [string]$script:AiProvider.SelectedItem
}

function Get-AiPanelConfig {
    $p = $script:AiProviders[[string]$script:AiProvider.SelectedItem]
    if (-not $p) { Set-Status 'Pick an AI provider first.'; return $null }
    $model = $script:AiModel.Text.Trim(); if (-not $model) { $model = $p.model }
    $endpoint = if ($p.needsEndpoint) { $script:AiEndpoint.Text.Trim() } else { '' }
    @{ Kind = $p.kind; Model = $model; Endpoint = $endpoint; ApiKey = $script:AiKey.Password; AllowWrites = [bool]$script:AiAllowWrites.IsChecked }
}

# If the key box is blank but we already have one saved, keep the saved key (don't wipe it).
function Get-AiEffectiveKey($PanelKey) {
    if ($PanelKey) { return $PanelKey }
    if ($script:AiCfg -and $script:AiCfg.KeyEnc) { return (Unprotect-SPSecret $script:AiCfg.KeyEnc) }
    ''
}

function Save-AiPanelConfig {
    $c = Get-AiPanelConfig; if (-not $c) { return }
    $key = Get-AiEffectiveKey $c.ApiKey
    Save-SPAiConfig -Provider $c.Kind -Model $c.Model -Endpoint $c.Endpoint -ApiKey $key -AllowWrites $c.AllowWrites
    $script:AiCfg = @{ Provider = $c.Kind; Model = $c.Model; Endpoint = $c.Endpoint; KeyEnc = (Protect-SPSecret $key) }
    $script:AiCfgStatus.Text = "Connected ($($c.Model))."
    $script:AiKey.Clear()
    Show-Toast 'success' 'AI connected' "Ready to chat with $($c.Model)."
}

function Test-AiPanelConnection {
    if ($script:Busy) { Set-Status 'Busy — wait for the current operation.'; return }
    $c = Get-AiPanelConfig; if (-not $c) { return }
    $cfg = @{ Provider = $c.Kind; Model = $c.Model; Endpoint = $c.Endpoint; ApiKey = (Get-AiEffectiveKey $c.ApiKey) }
    $script:AiCfgStatus.Text = 'Testing...'; $script:Busy = $true
    $ps = [powershell]::Create(); $ps.Runspace = $script:Worker
    $ps.Runspace.SessionStateProxy.SetVariable('TestCfg', $cfg)
    $null = $ps.AddScript({
            try {
                $body = New-SPAiRequestBody -Provider $TestCfg.Provider -Model $TestCfg.Model -System 'Connectivity test.' -Messages @(@{ role = 'user'; content = 'Reply with: OK' }) -Tools @()
                $ep = Get-SPAiEndpoint -Provider $TestCfg.Provider -Endpoint $TestCfg.Endpoint
                $hd = Get-SPAiHeaders -Provider $TestCfg.Provider -ApiKey $TestCfg.ApiKey
                $resp = Invoke-SPAiHttp -Endpoint $ep -Headers $hd -Body $body -TimeoutSec 30
                @{ ok = $true; text = (Read-SPAiResponse -Provider $TestCfg.Provider -Response $resp).Text }
            }
            catch { @{ ok = $false; error = $_.Exception.Message } }
        })
    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Tag = @{ Ps = $ps; Handle = $handle }
    $timer.Add_Tick({
            $st = $args[0].Tag
            if (-not $st.Handle.IsCompleted) { return }
            $args[0].Stop()
            $r = $null; try { $r = $st.Ps.EndInvoke($st.Handle) } catch { }
            $st.Ps.Dispose(); $script:Busy = $false
            $res = @($r)[0]
            if ($res -and $res.ok) { $script:AiCfgStatus.Text = 'Reachable — looks good.'; Show-Toast 'success' 'AI reachable' '' }
            else { $script:AiCfgStatus.Text = "Failed: $($res.error)" }
        })
    $timer.Start()
}

function Add-ClaudeDesktopEntry {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $serverJs = Join-Path $repoRoot 'mcp-server\dist\index.js'
    $cfgPath = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
    try {
        $cfg = if (Test-Path -LiteralPath $cfgPath) { Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
        if (-not $cfg) { $cfg = @{} }
        if (-not $cfg.mcpServers) { $cfg.mcpServers = @{} }
        $cfg.mcpServers.opengatesp = @{ command = 'node'; args = @($serverJs) }
        $dir = Split-Path $cfgPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $cfg | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $cfgPath -Encoding utf8
        Show-Toast 'success' 'Added to Claude Desktop' 'Restart Claude Desktop to use OpenGateSP there.'
    }
    catch {
        try { [System.Windows.Clipboard]::SetText("`"opengatesp`": { `"command`": `"node`", `"args`": [`"$serverJs`"] }") } catch { }
        Show-Toast 'warn' 'Copied the config' 'Paste it into your Claude Desktop config (mcpServers).'
    }
}

# ---- chat loop --------------------------------------------------------------------------
$script:AiLoopScript = {
    try {
        $cat = Get-SPAiToolCatalog
        Invoke-SPAiConversation -Config $AiCfg -Messages $AiMessages -Catalog $cat `
            -Emit { param($s) $AiQueue.Enqueue($s) } `
            -InvokeTool { param($c, $p) & $c @p 3>$null 4>$null 5>$null 6>$null }
        $AiQueue.Enqueue(@{ kind = 'done' })
    }
    catch { $AiQueue.Enqueue(@{ kind = 'fatal'; error = $_.Exception.Message }) }
}

function Start-SPAiTurn([string]$UserText) {
    $UserText = "$UserText".Trim()
    if (-not $UserText) { return }
    if (-not $script:AiCfg -or -not $script:AiCfg.Provider) {
        Set-Status 'Connect your AI first (provider + model, then Save).'; Show-View 'AI'; return
    }
    if ($script:Busy) { Set-Status 'Busy — wait for the current operation to finish.'; return }

    Add-AiBubble 'user' $UserText
    $script:AiInput.Text = ''
    if (-not $script:AiMessages) { $script:AiMessages = [System.Collections.Generic.List[object]]::new() }
    $script:AiMessages.Add(@{ role = 'user'; content = $UserText })

    $script:Busy = $true
    if ($script:BusyBar) { $script:BusyBar.Visibility = [System.Windows.Visibility]::Visible }
    $script:AiSend.IsEnabled = $false
    Set-Status 'Thinking...'

    $queue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $cfg = @{ Provider = $script:AiCfg.Provider; Model = $script:AiCfg.Model; Endpoint = $script:AiCfg.Endpoint; ApiKey = (Unprotect-SPSecret $script:AiCfg.KeyEnc) }

    $ps = [powershell]::Create(); $ps.Runspace = $script:Worker
    $ps.Runspace.SessionStateProxy.SetVariable('AiCfg', $cfg)
    $ps.Runspace.SessionStateProxy.SetVariable('AiMessages', $script:AiMessages)
    $ps.Runspace.SessionStateProxy.SetVariable('AiQueue', $queue)
    $null = $ps.AddScript($script:AiLoopScript)
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Tag = @{ Ps = $ps; Handle = $handle; Queue = $queue }
    $timer.Add_Tick({
            $st = $args[0].Tag; $step = $null
            while ($st.Queue.TryDequeue([ref]$step)) { Show-AiStep $step }
            if ($st.Handle.IsCompleted) {
                $args[0].Stop()
                try { $st.Ps.EndInvoke($st.Handle) } catch { }
                $st.Ps.Dispose()
                $s2 = $null; while ($st.Queue.TryDequeue([ref]$s2)) { Show-AiStep $s2 }
                $script:Busy = $false
                if ($script:BusyBar) { $script:BusyBar.Visibility = [System.Windows.Visibility]::Collapsed }
                $script:AiSend.IsEnabled = $true
                Set-Status 'Ready.'
            }
        })
    $timer.Start()
}

# ---- step rendering ---------------------------------------------------------------------
function Get-FriendlyToolName([string]$name) { (($name -replace '^sharepoint_', '') -replace '_', ' ').Trim() }

function Add-AiNode($node) {
    [void]$script:AiTranscript.Children.Add($node)
    if ($script:AiEmpty) { $script:AiEmpty.Visibility = [System.Windows.Visibility]::Collapsed }
    Invoke-FadeIn $node
    $script:AiScroll.ScrollToEnd()
}

function Add-AiBubble([string]$role, [string]$text) {
    $align = if ($role -eq 'user') { 'Right' } else { 'Left' }
    $bg = if ($role -eq 'user') { 'Accent' } else { 'BgElev' }
    $fg = if ($role -eq 'user') { 'AccentFg' } else { 'Fg' }
    $xaml = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        CornerRadius="12" Padding="12,9" Margin="0,0,0,8" MaxWidth="640" HorizontalAlignment="$align" Background="{DynamicResource $bg}">
  <TextBlock x:Name="T" TextWrapping="Wrap" Foreground="{DynamicResource $fg}"/>
</Border>
"@
    $n = [Windows.Markup.XamlReader]::Parse($xaml)
    $n.FindName('T').Text = $text
    Add-AiNode $n
}

function Show-AiStep($step) {
    switch ([string]$step.kind) {
        'assistant' { if ($step.text) { Add-AiBubble 'assistant' $step.text } }
        'toolcall' { Add-AiToolCard $step }
        'toolresult' { Add-AiNote ("Ran {0} — {1} result(s)" -f (Get-FriendlyToolName $step.name), $step.count) 'Good' }
        'toolerror' { Add-AiNote ("{0} couldn't run: {1}" -f (Get-FriendlyToolName $step.name), $step.error) 'Danger' }
        'fatal' { Add-AiNote ("Assistant error: {0}" -f $step.error) 'Danger' }
        default { }
    }
}

function Add-AiNote([string]$text, [string]$color) {
    $xaml = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Margin="2,0,0,8" HorizontalAlignment="Left">
  <TextBlock x:Name="T" FontSize="12" TextWrapping="Wrap" Foreground="{DynamicResource $color}"/>
</Border>
"@
    $n = [Windows.Markup.XamlReader]::Parse($xaml); $n.FindName('T').Text = $text; Add-AiNode $n
}

function Add-AiToolCard($step) {
    $xaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        CornerRadius="10" Padding="12,10" Margin="0,0,0,8" HorizontalAlignment="Left" MaxWidth="660"
        Background="{DynamicResource BgElev2}" BorderBrush="{DynamicResource Border}" BorderThickness="1">
  <StackPanel>
    <TextBlock x:Name="Title" FontWeight="SemiBold" Foreground="{DynamicResource Fg}"/>
    <TextBox x:Name="Cmd" IsReadOnly="True" BorderThickness="0" Background="Transparent" FontFamily="Consolas" FontSize="12"
             Foreground="{DynamicResource FgMute}" TextWrapping="Wrap" Margin="0,6,0,0"/>
    <Button x:Name="Copy" Content="Copy script" Style="{DynamicResource GhostButton}" HorizontalAlignment="Left" Margin="0,8,0,0"/>
  </StackPanel>
</Border>
'@
    $n = [Windows.Markup.XamlReader]::Parse($xaml)
    $n.FindName('Title').Text = "Running: $(Get-FriendlyToolName $step.name)"
    $n.FindName('Cmd').Text = $step.cmdline
    $cmd = $step.cmdline
    $n.FindName('Copy').Add_Click({ try { [System.Windows.Clipboard]::SetText($cmd) } catch { } }.GetNewClosure())
    Add-AiNode $n
}

Initialize-AiView
