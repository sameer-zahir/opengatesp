#Requires -Version 7.4
# Fixture tests for Start-SPFileMigration's source enumeration: hidden files must migrate,
# reparse points (junctions) must be reported and NOT followed, and nothing PnP is touched —
# the run stays in -WhatIf with the connection/library lookups stubbed. CI-friendly.

BeforeAll {
    $mod = Join-Path $PSScriptRoot '..\module\OpenGateSP'
    . (Join-Path $mod 'Private\Write-SPLog.ps1')
    . (Join-Path $mod 'Private\ConvertTo-SPOutput.ps1')
    . (Join-Path $mod 'Private\Get-SPHttpStatusCode.ps1')
    . (Join-Path $mod 'Private\Get-SPRetryDelay.ps1')
    . (Join-Path $mod 'Private\Invoke-SPRetry.ps1')
    . (Join-Path $mod 'Public\Start-SPFileMigration.ps1')

    # Stubs standing in for PnP.PowerShell / the connection helper (never hit past -WhatIf).
    function Resolve-SPSiteConnection { [CmdletBinding()] param([string]$SiteUrl) $true }
    function Get-PnPList { [CmdletBinding()] param($Identity) [pscustomobject]@{ Title = "$Identity" } }
    function Get-PnPProperty { [CmdletBinding()] param($ClientObject, $Property) [pscustomobject]@{ ServerRelativeUrl = '/sites/x/Shared Documents' } }
    function Get-PnPWeb { [CmdletBinding()] param() [pscustomobject]@{ ServerRelativeUrl = '/sites/x' } }
    function Get-PnPFile { [CmdletBinding()] param() }
    function Resolve-PnPFolder { [CmdletBinding()] param() }
    function Add-PnPFile { [CmdletBinding()] param() }
}

Describe 'Start-SPFileMigration source enumeration' {
    BeforeEach {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('ogsp-filemig-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $fixture 'sub') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fixture 'visible.txt') -Value 'v'
        Set-Content -LiteralPath (Join-Path $fixture 'sub\inner.txt') -Value 'i'
        $hiddenPath = Join-Path $fixture 'hidden.txt'
        Set-Content -LiteralPath $hiddenPath -Value 'h'
        (Get-Item -LiteralPath $hiddenPath).Attributes = [System.IO.FileAttributes]::Hidden
        New-Item -ItemType Junction -Path (Join-Path $fixture 'jct') -Target (Join-Path $fixture 'sub') | Out-Null
    }
    AfterEach {
        # Remove the junction FIRST (by path, non-recursive) so cleanup can't chase it.
        $j = Join-Path $fixture 'jct'
        if (Test-Path -LiteralPath $j) { [System.IO.Directory]::Delete($j) }
        Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'includes hidden files in the migration set' {
        $rows = @(Start-SPFileMigration -Source $fixture -SiteUrl 'https://contoso.sharepoint.com/sites/x' -LogPath (Join-Path $fixture 'run.log') -WhatIf)
        @($rows | Where-Object { $_.File -like '*hidden.txt' -and $_.Status -eq 'WouldUpload' }).Count | Should -Be 1
    }
    It 'reports junctions as skipped instead of silently omitting them' {
        $rows = @(Start-SPFileMigration -Source $fixture -SiteUrl 'https://contoso.sharepoint.com/sites/x' -LogPath (Join-Path $fixture 'run.log') -WhatIf)
        @($rows | Where-Object { $_.File -like '*jct' -and $_.Status -like 'Skipped (reparse point*' }).Count | Should -Be 1
    }
    It 'does not follow junction contents (no double-copy)' {
        $rows = @(Start-SPFileMigration -Source $fixture -SiteUrl 'https://contoso.sharepoint.com/sites/x' -LogPath (Join-Path $fixture 'run.log') -WhatIf)
        @($rows | Where-Object { $_.File -like '*jct\*' }).Count | Should -Be 0
        # ...while the real path of the same content migrates exactly once.
        @($rows | Where-Object { $_.File -like '*sub\inner.txt' -and $_.Status -eq 'WouldUpload' }).Count | Should -Be 1
    }
}
