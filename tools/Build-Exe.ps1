#Requires -Version 7.4
<#
.SYNOPSIS
    Build OpenGateSP.exe from tools\Launch.ps1 using ps2exe. Output -> dist\OpenGateSP.exe.
.NOTES
    The .exe is a thin launcher that opens the GUI; the module/, gui/ and docs ship alongside
    it in the release zip. The .exe is unsigned (no certificate), so Windows SmartScreen will
    show a one-time "More info -> Run anyway".
#>
[CmdletBinding()]
param([string]$OutputDir)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutputDir) { $OutputDir = Join-Path $root 'dist' }
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe..." -ForegroundColor Yellow
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

$exe = Join-Path $OutputDir 'OpenGateSP.exe'
$params = @{
    InputFile   = Join-Path $PSScriptRoot 'ExeStub.ps1'
    OutputFile  = $exe
    NoConsole   = $true
    Title       = 'OpenGateSP'
    Product     = 'OpenGateSP'
    Description = 'Free, open-source ShareGate alternative for SharePoint Online'
    Company     = 'Sameer Zahir'
    Version     = '0.4.0.0'
    Copyright   = '(c) 2026 Sameer Zahir. MIT License.'
}
$ico = Join-Path $PSScriptRoot 'opengatesp.ico'
if (Test-Path -LiteralPath $ico) { $params['IconFile'] = $ico }

Invoke-PS2EXE @params
Write-Host "Built $exe" -ForegroundColor Green
