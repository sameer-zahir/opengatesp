#Requires -Version 7.4
<#
.SYNOPSIS
    Windows GUI for OpenGateSP — a simple ShareGate-style front end over the engine.
.DESCRIPTION
    Loads the OpenGateSP module into a dedicated background runspace (so the PnP connection
    persists and the UI never freezes during long operations) and drives it from a WPF
    window: Connect, Reports, Migrate, Provision. Results render in a grid and export to
    CSV/HTML. Windows-only (WPF).
.EXAMPLE
    pwsh -STA -File ./gui/Start-OpenGateSPGui.ps1
#>
[CmdletBinding()]
param(
    [string]$ModulePath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ModulePath) { $ModulePath = Join-Path (Split-Path $here -Parent) 'module\OpenGateSP\OpenGateSP.psd1' }
if (-not (Test-Path -LiteralPath $ModulePath)) { throw "OpenGateSP module not found at $ModulePath" }

# --- background worker runspace: holds the module + PnP connection ----------------------
$script:Worker = [runspacefactory]::CreateRunspace()
$script:Worker.ApartmentState = 'STA'
$script:Worker.ThreadOptions  = 'ReuseThread'
$script:Worker.Open()
$boot = [powershell]::Create()
$boot.Runspace = $script:Worker
$null = $boot.AddScript("Import-Module '$ModulePath' -Force -ErrorAction Stop").Invoke()
$boot.Dispose()
$script:Busy       = $false
$script:LastReport = @()

# --- load the window --------------------------------------------------------------------
[xml]$xamlDoc = Get-Content -LiteralPath (Join-Path $here 'MainWindow.xaml') -Raw
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlDoc))

# Bind every x:Name to a $script:<Name> variable for easy access in handlers.
$xamlDoc.SelectNodes("//*[@*[local-name()='Name']]") | ForEach-Object {
    $n = $_.Attributes['x:Name'].Value
    if ($n) { Set-Variable -Name $n -Value $window.FindName($n) -Scope script }
}

# --- helpers ----------------------------------------------------------------------------
function Set-Status([string]$text) { $script:StatusText.Text = $text }

function Show-Grid($grid, $data) {
    $arr = @($data)
    $grid.ItemsSource = $null
    if ($arr.Count -gt 0) { $grid.ItemsSource = $arr }
    $arr
}

function Confirm-Action([string]$message) {
    [System.Windows.MessageBox]::Show($message, 'Confirm', 'YesNo', 'Warning') -eq [System.Windows.MessageBoxResult]::Yes
}

function Select-FolderPath {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dlg.SelectedPath }
}

function Select-FilePath([string]$filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*') {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = $filter
    if ($dlg.ShowDialog()) { $dlg.FileName }
}

function Save-FilePath([string]$filter, [string]$default) {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = $filter; $dlg.FileName = $default
    if ($dlg.ShowDialog()) { $dlg.FileName }
}

# Run a module command in the worker runspace; marshal the result back on the UI thread.
function Invoke-Worker {
    param(
        [Parameter(Mandatory)][string]$Command,
        [hashtable]$Parameters,
        [Parameter(Mandatory)][scriptblock]$OnDone
    )
    if ($script:Busy) { Set-Status 'Busy — wait for the current operation to finish.'; return }
    $script:Busy = $true
    Set-Status "Running $Command ..."

    $ps = [powershell]::Create()
    $ps.Runspace = $script:Worker
    $null = $ps.AddCommand($Command)
    if ($Parameters) { $null = $ps.AddParameters($Parameters) }
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    # Carry state on .Tag so the Tick handler needs no captured variables.
    $timer.Tag = @{ Ps = $ps; Handle = $handle; OnDone = $OnDone; Command = $Command }
    $timer.Add_Tick({
        $tmr = $args[0]
        $st  = $tmr.Tag
        if (-not $st.Handle.IsCompleted) { return }
        $tmr.Stop()

        $result = $null; $err = $null
        try { $result = $st.Ps.EndInvoke($st.Handle) }
        catch { $err = $_.Exception.Message }
        if (-not $err -and $st.Ps.Streams.Error.Count -gt 0) {
            $err = ($st.Ps.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n"
        }
        $st.Ps.Dispose()
        $script:Busy = $false
        & $st.OnDone $result $err
    })
    $timer.Start()
}

# --- prefill connection fields from saved config ----------------------------------------
$cfgPath = Join-Path $env:APPDATA 'OpenGateSP\spconfig.json'
if (Test-Path -LiteralPath $cfgPath) {
    try {
        $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
        if ($cfg.Url)      { $script:TbUrl.Text      = $cfg.Url }
        if ($cfg.ClientId) { $script:TbClientId.Text = $cfg.ClientId }
        if ($cfg.Tenant)   { $script:TbTenant.Text   = $cfg.Tenant }
    } catch { }
}

# --- Connect ----------------------------------------------------------------------------
$script:BtnConnect.Add_Click({
    $p = @{ ClientId = $script:TbClientId.Text.Trim(); SaveConfig = $true }
    if ($script:TbTenant.Text.Trim()) { $p.Tenant = $script:TbTenant.Text.Trim() }
    if ($script:TbUrl.Text.Trim())    { $p.Url    = $script:TbUrl.Text.Trim() }
    if ($script:CbAdmin.IsChecked)    { $p.Admin       = $true }
    if ($script:CbDevice.IsChecked)   { $p.DeviceLogin = $true }
    if (-not $p.ClientId) { Set-Status 'Client ID is required (see docs/02).'; return }

    $script:ConnStatus.Text = 'Connecting...'
    Invoke-Worker -Command 'Connect-SPTool' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) {
            $script:ConnStatus.Text = 'Not connected'
            $script:ConnStatus.Foreground = 'Salmon'
            Set-Status "Connect failed: $err"
        } else {
            $r = @($result)[0]
            $script:ConnStatus.Text = "Connected: $($r.Url)"
            $script:ConnStatus.Foreground = '#9ece6a'
            Set-Status 'Connected.'
        }
    }
})

# --- Reports ----------------------------------------------------------------------------
$script:BtnRunReport.Add_Click({
    $site = $script:TbReportSite.Text.Trim()
    $incl = [bool]$script:CbInclLists.IsChecked
    switch ($script:CbReport.SelectedIndex) {
        0 { $cmd = 'Get-SPSharingReport';    $p = @{ SiteUrl = $site; IncludeLinks = $incl } }
        1 { $cmd = 'Get-SPPermissionReport'; $p = @{ SiteUrl = $site; IncludeListPermissions = $incl } }
        2 { $cmd = 'Get-SPSiteInventory';    $p = @{ IncludeStorage = $true } }
        default { return }
    }
    if ($cmd -ne 'Get-SPSiteInventory' -and -not $site) { Set-Status 'Enter a Site URL for this report.'; return }

    Invoke-Worker -Command $cmd -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Report failed: $err"; return }
        $script:LastReport = Show-Grid $script:GridReport $result
        Set-Status "$($script:LastReport.Count) row(s)."
    }
})

$script:BtnExportCsv.Add_Click({
    if (-not $script:LastReport.Count) { Set-Status 'Nothing to export — run a report first.'; return }
    $path = Save-FilePath 'CSV (*.csv)|*.csv' 'report.csv'
    if ($path) { $script:LastReport | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8; Set-Status "Saved $path" }
})

$script:BtnExportHtml.Add_Click({
    if (-not $script:LastReport.Count) { Set-Status 'Nothing to export — run a report first.'; return }
    $path = Save-FilePath 'HTML (*.html)|*.html' 'report.html'
    if ($path) {
        $style = '<style>body{font-family:Segoe UI,Arial;background:#1b1d2b;color:#c0caf5}table{border-collapse:collapse;width:100%}th,td{border:1px solid #3b4261;padding:6px 10px;text-align:left}th{background:#24283b;color:#7aa2f7}</style>'
        $script:LastReport | ConvertTo-Html -Head $style | Out-File -LiteralPath $path -Encoding utf8
        Set-Status "Saved $path"
    }
})

# --- Migrate ----------------------------------------------------------------------------
$script:BtnBrowseSource.Add_Click({ $f = Select-FolderPath; if ($f) { $script:TbSource.Text = $f } })

function Invoke-Migration([bool]$Preview) {
    $src  = $script:TbSource.Text.Trim()
    $site = $script:TbMigSite.Text.Trim()
    if (-not $src -or -not $site) { Set-Status 'Source folder and Site URL are required.'; return }

    $p = @{
        Source             = $src
        SiteUrl            = $site
        Library            = ($script:TbLibrary.Text.Trim()) ? $script:TbLibrary.Text.Trim() : 'Documents'
        TargetFolder       = $script:TbTargetFolder.Text.Trim()
        PreserveTimestamps = [bool]$script:CbPreserve.IsChecked
        Overwrite          = [bool]$script:CbOverwrite.IsChecked
    }
    if ($Preview) { $p.WhatIf = $true }
    else {
        if (-not (Confirm-Action "Upload files from `n$src`nto $site ?")) { Set-Status 'Cancelled.'; return }
        $p.Force = $true   # GUI confirmed; skip the engine's console prompt
    }

    Invoke-Worker -Command 'Start-SPFileMigration' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Migration failed: $err"; return }
        $rows = Show-Grid $script:GridMig $result
        Set-Status "$($rows.Count) file row(s). See ./logs for the full transcript."
    }
}
$script:BtnPreviewMig.Add_Click({ Invoke-Migration $true })
$script:BtnRunMig.Add_Click({ Invoke-Migration $false })

# --- Provision --------------------------------------------------------------------------
$script:BtnCreateSite.Add_Click({
    $title = $script:TbSiteTitle.Text.Trim()
    $alias = $script:TbSiteAlias.Text.Trim()
    $type  = @('TeamSite', 'CommunicationSite')[$script:CbSiteType.SelectedIndex]
    if (-not $title -or -not $alias) { Set-Status 'Title and Alias/URL are required.'; return }
    if (-not (Confirm-Action "Create $type '$title' ($alias)?")) { Set-Status 'Cancelled.'; return }

    $p = @{ Title = $title; Type = $type }
    if ($type -eq 'TeamSite') { $p.Alias = $alias } else { $p.Url = $alias }

    Invoke-Worker -Command 'New-SPSiteFromTemplate' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Create failed: $err"; return }
        Show-Grid $script:GridProvision $result | Out-Null
        Set-Status 'Site request submitted.'
    }
})

$script:BtnBrowseCsv.Add_Click({ $f = Select-FilePath; if ($f) { $script:TbBulkCsv.Text = $f } })

function Invoke-Bulk([bool]$Preview) {
    $site = $script:TbBulkSite.Text.Trim()
    $list = $script:TbBulkList.Text.Trim()
    $csv  = $script:TbBulkCsv.Text.Trim()
    if (-not $site -or -not $list -or -not $csv) { Set-Status 'Site, List and CSV are required.'; return }

    $p = @{ SiteUrl = $site; List = $list; CsvPath = $csv }
    if ($Preview) { $p.WhatIf = $true }
    else {
        if (-not (Confirm-Action "Apply metadata from`n$csv`nto '$list' on $site ?")) { Set-Status 'Cancelled.'; return }
        $p.Force = $true
    }

    Invoke-Worker -Command 'Set-SPBulkMetadata' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Bulk update failed: $err"; return }
        $rows = Show-Grid $script:GridProvision $result
        Set-Status "$($rows.Count) item row(s)."
    }
}
$script:BtnPreviewBulk.Add_Click({ Invoke-Bulk $true })
$script:BtnRunBulk.Add_Click({ Invoke-Bulk $false })

# --- shutdown ---------------------------------------------------------------------------
$window.Add_Closing({
    try { if ($script:Worker) { $script:Worker.Close(); $script:Worker.Dispose() } } catch { }
})

$null = $window.ShowDialog()
