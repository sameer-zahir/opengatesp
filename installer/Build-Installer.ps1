#Requires -Version 7.4
<#
.SYNOPSIS
    Build dist/OpenGateSP-Setup.exe: (re)build the launcher exe, then compile the
    Inno Setup script. Requires Inno Setup 6 (winget install JRSoftware.InnoSetup).
.PARAMETER SkipExe
    Skip rebuilding OpenGateSP.exe (use the existing dist/OpenGateSP.exe).
#>
[CmdletBinding()]
param([switch]$SkipExe)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

if (-not $SkipExe) {
    Write-Host 'Building OpenGateSP.exe (icon + version)...' -ForegroundColor Cyan
    & (Join-Path $root 'tools\New-AppIcon.ps1')
    & (Join-Path $root 'tools\Build-Exe.ps1')
}

# Locate the Inno Setup compiler.
$iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
    foreach ($p in @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe")) {
        if (Test-Path -LiteralPath $p) { $iscc = $p; break }
    }
}
if (-not $iscc) {
    throw "Inno Setup (ISCC.exe) not found. Install it once:  winget install JRSoftware.InnoSetup"
}

$version = & (Join-Path $root 'tools\Get-OpenGateSPVersion.ps1')
Write-Host "Compiling installer $version with $iscc ..." -ForegroundColor Cyan
& $iscc "/DMyAppVersion=$version" (Join-Path $PSScriptRoot 'OpenGateSP.iss')
$setup = Join-Path $root 'dist\OpenGateSP-Setup.exe'
if (Test-Path -LiteralPath $setup) {
    Write-Host "Built $setup ($([Math]::Round((Get-Item $setup).Length/1mb,2)) MB)" -ForegroundColor Green
}
