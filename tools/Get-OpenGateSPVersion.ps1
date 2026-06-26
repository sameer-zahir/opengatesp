#Requires -Version 7.0
<#
.SYNOPSIS
    The single source of truth for the OpenGateSP version.
.DESCRIPTION
    Reads ModuleVersion from the module manifest (module\OpenGateSP\OpenGateSP.psd1) so the GUI,
    the launcher exe, the installer, and CI all stamp the same number — no more drift (the old
    Build-Exe.ps1 hard-coded 0.6.0.0 while everything else was 0.10.0).

    Returns the raw three-part string (e.g. '0.10.0'); pass -FourPart for the Win32 file-version
    form '0.10.0.0' that ps2exe and Inno Setup's VersionInfoVersion expect.
.EXAMPLE
    & .\tools\Get-OpenGateSPVersion.ps1            # 0.10.0
.EXAMPLE
    & .\tools\Get-OpenGateSPVersion.ps1 -FourPart  # 0.10.0.0
#>
[CmdletBinding()]
param([switch]$FourPart)

$psd1 = Join-Path (Split-Path $PSScriptRoot -Parent) 'module\OpenGateSP\OpenGateSP.psd1'
if (-not (Test-Path -LiteralPath $psd1)) { throw "Module manifest not found at $psd1" }

$version = [string](Import-PowerShellDataFile -LiteralPath $psd1).ModuleVersion
if (-not $version) { throw "ModuleVersion missing from $psd1" }

if ($FourPart) {
    $parts = @($version -split '\.')
    while ($parts.Count -lt 4) { $parts += '0' }
    ($parts[0..3]) -join '.'
}
else { $version }
