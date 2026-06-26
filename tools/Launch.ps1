#Requires -Version 7.4
<#
.SYNOPSIS
    OpenGateSP bootstrap: make sure prerequisites are present, then open the GUI.
    Works both as a script and compiled into OpenGateSP.exe (see Build-Exe.ps1).
#>
$ErrorActionPreference = 'Stop'

# Resolve the app root (the folder that contains gui\ and module\), whether we are run
# as a .ps1 (PSScriptRoot = tools\) or from the PS2EXE .exe (use the process path).
$root =
    if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent }
    elseif ($MyInvocation.MyCommand.Path) { Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent }
    else { Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent }

Write-Host ""
Write-Host "  OpenGateSP - the free, open-source ShareGate alternative" -ForegroundColor Cyan
Write-Host ""

# 1. Ensure PnP.PowerShell (the SharePoint engine) is installed.
if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Write-Host "  First-time setup: installing PnP.PowerShell (about a minute)..." -ForegroundColor Yellow
    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber
    }
    catch {
        Write-Host "  Could not install PnP.PowerShell automatically: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Please run:  Install-Module PnP.PowerShell -Scope CurrentUser" -ForegroundColor Gray
        Read-Host "  Press Enter to exit"
        return
    }
}

# 2. First-run Entra app setup is now guided inside the app itself (the GUI shows a
#    one-time welcome dialog when no connection is saved) — no console steps needed here.

# 3. Open the GUI.
$gui = Join-Path $root 'gui\Start-OpenGateSPGui.ps1'
if (-not (Test-Path -LiteralPath $gui)) {
    Write-Host "  Could not find the GUI at $gui" -ForegroundColor Red
    Read-Host "  Press Enter to exit"
    return
}
Write-Host "  Opening OpenGateSP..." -ForegroundColor Gray
& $gui
