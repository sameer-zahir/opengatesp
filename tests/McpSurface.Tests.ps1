#Requires -Version 7.4
# Guards the engine surface against drift: every exported cmdlet is reachable from the MCP engine
# host, the MCP server only calls commands the host implements, and the in-app AI catalog stays a
# subset of the MCP tool surface. Pure text checks — no build, no tenant. (Regression guard for
# Copy-SPTermGroup, which shipped exported but with no MCP surface at all.)

BeforeAll {
    $root      = Join-Path $PSScriptRoot '..'
    $psd1      = Import-PowerShellDataFile (Join-Path $root 'module\OpenGateSP\OpenGateSP.psd1')
    $hostText  = Get-Content -Raw (Join-Path $root 'mcp-server\engine-host.ps1')
    $indexText = Get-Content -Raw (Join-Path $root 'mcp-server\src\index.ts')
    . (Join-Path $root 'gui\ai\ToolCatalog.ps1')
}

Describe 'MCP surface parity' {
    It 'every exported cmdlet is used by the engine host' {
        $missing = @($psd1.FunctionsToExport | Where-Object { $hostText -notmatch [regex]::Escape($_) })
        $missing | Should -BeNullOrEmpty
    }
    It 'every command the MCP server calls exists in the engine host' {
        $called = [regex]::Matches($indexText, 'run\("([a-z.0-9]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $served = [regex]::Matches($hostText, "(?m)^\s*'([a-z.0-9]+)'\s*\{") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $called.Count | Should -BeGreaterThan 20
        @($called | Where-Object { $_ -notin $served }) | Should -BeNullOrEmpty
    }
    It 'every in-app AI tool also exists on the MCP server (matching surfaces)' {
        $mcpNames = [regex]::Matches($indexText, '"(sharepoint_[a-z_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        @((Get-SPAiToolCatalog -IncludeWrites).name | Where-Object { $_ -notin $mcpNames }) | Should -BeNullOrEmpty
    }
    It 'every MCP write tool is covered by the engine host preview gate' {
        # A tool whose handler tests an execute flag is a write; each one's engine command must be
        # in the host's $script:WriteCommands list so the session preview-first gate covers it.
        $writeCmds = @(foreach ($block in ($indexText -split 'server\.tool\(')) {
                if ($block -match '\bexecute\b\s*[!=]==' -and $block -match 'run\("([a-z.0-9]+)"') { $Matches[1] }
            }) | Sort-Object -Unique
        $writeCmds.Count | Should -Be 16
        ($hostText -match '\$script:WriteCommands\s*=\s*@\(([^)]*)\)') | Should -BeTrue
        $gated = [regex]::Matches($Matches[1], "'([a-z.0-9]+)'") | ForEach-Object { $_.Groups[1].Value }
        @($writeCmds | Where-Object { $_ -notin $gated }) | Should -BeNullOrEmpty
        $hostText | Should -Match 'Resolve-SPGatedWrite'   # the gate is actually wired into the loop
    }
}
