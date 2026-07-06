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

# A small splash shown on its own STA runspace so it keeps painting while the main thread blocks on
# the one-time PnP.PowerShell install. The compiled .exe runs with -NoConsole, so without this the
# first launch looks frozen for ~a minute. Dark to match the app's default theme.
function Show-BootSplash([string]$Title, [string]$Message) {
    try {
        $sync = [hashtable]::Synchronized(@{})
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
        $rs.SessionStateProxy.SetVariable('sync', $sync)
        $rs.SessionStateProxy.SetVariable('Title', $Title)
        $rs.SessionStateProxy.SetVariable('Message', $Message)
        $ps = [powershell]::Create(); $ps.Runspace = $rs
        $null = $ps.AddScript({
            Add-Type -AssemblyName PresentationFramework
            $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Topmost="True"
        Width="440" SizeToContent="Height" Background="#222436" AllowsTransparency="False">
  <Border BorderBrush="#3B5380" BorderThickness="1" Padding="26,22">
    <StackPanel>
      <TextBlock Text="OpenGateSP" FontFamily="Consolas" FontSize="18" FontWeight="Bold" Foreground="#82AAFF"/>
      <TextBlock x:Name="T" FontSize="15" FontWeight="SemiBold" Foreground="#C8D3F5" Margin="0,10,0,0" TextWrapping="Wrap"/>
      <TextBlock x:Name="M" FontSize="12" Foreground="#9AA5D6" Margin="0,6,0,0" TextWrapping="Wrap"/>
      <ProgressBar IsIndeterminate="True" Height="3" Margin="0,16,0,0" Background="Transparent" Foreground="#82AAFF" BorderThickness="0"/>
    </StackPanel>
  </Border>
</Window>
'@
            $win = [Windows.Markup.XamlReader]::Parse($xaml)
            $win.FindName('T').Text = $Title
            $win.FindName('M').Text = $Message
            $sync.Window = $win
            $win.Show()
            [System.Windows.Threading.Dispatcher]::Run()
        })
        $sync.PS = $ps; $sync.RS = $rs
        $null = $ps.BeginInvoke()
        $deadline = [datetime]::UtcNow.AddSeconds(5)
        while (-not $sync.Window -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 30 }
        return $sync
    }
    catch { return $null }
}

function Close-BootSplash($sync) {
    if (-not $sync -or -not $sync.Window) { return }
    try {
        $sync.Window.Dispatcher.Invoke([action] { $sync.Window.Close() })
        $sync.Window.Dispatcher.InvokeShutdown()
    } catch { }
    try { $sync.PS.Dispose(); $sync.RS.Dispose() } catch { }
}

Write-Host ""
Write-Host "  OpenGateSP - the free, open-source ShareGate alternative" -ForegroundColor Cyan
Write-Host ""

# 1. Ensure PnP.PowerShell (the SharePoint engine) is installed.
if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Write-Host "  First-time setup: installing PnP.PowerShell (about a minute)..." -ForegroundColor Yellow
    $splash = Show-BootSplash 'Setting up OpenGateSP' 'Installing the SharePoint engine (PnP.PowerShell). This one-time step takes about a minute...'
    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber
    }
    catch {
        Close-BootSplash $splash
        $msg = "Could not install PnP.PowerShell automatically:`n`n$($_.Exception.Message)`n`nPlease run this in PowerShell, then reopen OpenGateSP:`n  Install-Module PnP.PowerShell -Scope CurrentUser"
        Write-Host "  $msg" -ForegroundColor Red
        try { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show($msg, 'OpenGateSP setup', 'OK', 'Error') | Out-Null } catch { }
        return
    }
    Close-BootSplash $splash
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
