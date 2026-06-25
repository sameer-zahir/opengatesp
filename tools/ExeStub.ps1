# OpenGateSP.exe stub. Kept Windows PowerShell 5.1-safe (this is what ps2exe compiles).
# Its only job: find PowerShell 7 and open the app's bootstrap in it.
$root = if ($PSScriptRoot) {
    Split-Path $PSScriptRoot -Parent
}
else {
    Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
}
$launch = Join-Path $root 'tools\Launch.ps1'

$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwsh) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show(
        "OpenGateSP needs PowerShell 7. Install it once from https://aka.ms/powershell (or run: winget install Microsoft.PowerShell), then open OpenGateSP again.",
        "OpenGateSP")
    return
}

$argline = '-STA -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $launch
Start-Process -FilePath $pwsh.Source -ArgumentList $argline
