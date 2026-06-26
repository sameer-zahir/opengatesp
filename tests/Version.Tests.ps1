#Requires -Version 7.4
# Guards the single source of truth for the app version (tools\Get-OpenGateSPVersion.ps1).
# Regression guard for the bug where tools\Build-Exe.ps1 hard-coded 0.6.0.0 while the module
# manifest (the real version) said 0.10.0 — so the shipped .exe reported the wrong version.

BeforeAll {
    $root            = Join-Path $PSScriptRoot '..'
    $versionPs1      = Join-Path $root 'tools\Get-OpenGateSPVersion.ps1'
    $psd1            = Join-Path $root 'module\OpenGateSP\OpenGateSP.psd1'
    $manifestVersion = [string](Import-PowerShellDataFile -LiteralPath $psd1).ModuleVersion
}

Describe 'Get-OpenGateSPVersion' {
    It 'returns the module manifest version (single source of truth)' {
        (& $versionPs1) | Should -Be $manifestVersion
    }
    It 'returns a three-part version string' {
        (& $versionPs1) | Should -Match '^\d+\.\d+\.\d+$'
    }
    It 'pads to a four-part Win32 version with -FourPart' {
        (& $versionPs1 -FourPart) | Should -Match '^\d+\.\d+\.\d+\.\d+$'
        (& $versionPs1 -FourPart) | Should -BeLike "$(& $versionPs1).*"
    }
}

Describe 'Build scripts use the single version source (no hard-coded drift)' {
    It 'Build-Exe.ps1 reads from Get-OpenGateSPVersion.ps1, not a literal' {
        $content = Get-Content -Raw (Join-Path $root 'tools\Build-Exe.ps1')
        $content | Should -Match 'Get-OpenGateSPVersion\.ps1'
        $content | Should -Not -Match '0\.6\.0\.0'
    }
    It 'Build-Installer.ps1 passes the version to ISCC' {
        $content = Get-Content -Raw (Join-Path $root 'installer\Build-Installer.ps1')
        $content | Should -Match '/DMyAppVersion='
    }
}
