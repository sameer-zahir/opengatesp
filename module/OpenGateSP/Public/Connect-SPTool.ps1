function Connect-SPTool {
    <#
    .SYNOPSIS
        Connect to SharePoint Online using your own registered Entra ID app — interactive
        delegated auth by default, or app-only certificate auth for headless/unattended runs.
    .DESCRIPTION
        Wraps Connect-PnPOnline. Since 2024-09-09 PnP.PowerShell requires your own Entra ID app
        and a -ClientId. Connection defaults — including the auth mode — are saved with
        -SaveConfig and reused on later calls, so day-to-day you can just run `Connect-SPTool`.

        - Delegated (default): the tool can never exceed the signed-in user's permissions.
          See docs/02-entra-app-registration.md.
        - App-only (-Thumbprint or -CertificatePath): no browser; for scheduled jobs and the
          MCP server. See docs/05-app-only-auth.md.
    .PARAMETER Url
        Site URL. If omitted, falls back to saved config, or is derived from -Tenant.
    .PARAMETER ClientId
        Application (client) ID of your registered Entra ID app.
    .PARAMETER Tenant
        Tenant name, e.g. contoso.onmicrosoft.com.
    .PARAMETER Admin
        Connect to the SharePoint admin centre (needed for tenant-wide reports).
    .PARAMETER DeviceLogin
        Delegated device-code flow instead of an interactive browser window.
    .PARAMETER Thumbprint
        App-only auth using a certificate (by thumbprint) from the certificate store.
    .PARAMETER CertificatePath
        App-only auth using a .pfx certificate file. The password is taken from
        -CertificatePassword or the OPENGATESP_CERT_PASSWORD env var (never persisted).
    .PARAMETER CertificatePassword
        Password for the .pfx given by -CertificatePath.
    .PARAMETER SaveConfig
        Persist Url/ClientId/Tenant and the auth mode (and thumbprint/cert path, never the
        password) so future calls — and the GUI/MCP server — reconnect with no arguments.
    .EXAMPLE
        Connect-SPTool -Url https://contoso.sharepoint.com -ClientId 1111 -Tenant contoso.onmicrosoft.com -SaveConfig
    .EXAMPLE
        Connect-SPTool -Url https://contoso.sharepoint.com -ClientId 1111 -Tenant contoso.onmicrosoft.com -Thumbprint ABC123 -SaveConfig
        App-only (headless) using a certificate from the store.
    .EXAMPLE
        Connect-SPTool -Admin
        Reconnect to the admin centre using saved defaults.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Certificate password is supplied at runtime via env var for headless auth; never persisted.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string]$Url,

        [string]$ClientId,

        [string]$Tenant,

        [switch]$Admin,

        [switch]$DeviceLogin,

        [string]$Thumbprint,

        [string]$CertificatePath,

        [securestring]$CertificatePassword,

        [switch]$SaveConfig
    )

    $cfg = Get-SPConfig
    if (-not $ClientId) { $ClientId = $cfg.ClientId }
    if (-not $Tenant)   { $Tenant   = $cfg.Tenant }
    if (-not $Url)      { $Url      = $cfg.Url }

    if (-not $ClientId) {
        throw "No ClientId. Register an Entra ID app (docs/02 for delegated, docs/05 for app-only), then pass -ClientId (optionally with -SaveConfig)."
    }

    # Derive the root site URL from the tenant when no URL is known yet.
    if (-not $Url -and $Tenant) {
        $Url = "https://$($Tenant.Split('.')[0]).sharepoint.com"
    }
    if (-not $Url) {
        throw "No site URL. Pass -Url or -Tenant so the root site can be derived."
    }

    # Keep the base (non-admin) URL to persist as the saved default.
    $baseUrl    = $Url -replace '-admin\.sharepoint\.com', '.sharepoint.com'
    $connectUrl = if ($Admin) { $baseUrl -replace '\.sharepoint\.com', '-admin.sharepoint.com' } else { $Url }

    # App-only if cert args are given, or if no delegated flag is set and saved mode is AppOnly.
    $useAppOnly = [bool]($Thumbprint -or $CertificatePath -or (-not $DeviceLogin -and $cfg.AuthMode -eq 'AppOnly'))

    $p = @{ Url = $connectUrl; ClientId = $ClientId }
    if ($Tenant) { $p['Tenant'] = $Tenant }

    if ($useAppOnly) {
        $tp = if ($Thumbprint)      { $Thumbprint }      else { $cfg.Thumbprint }
        $cp = if ($CertificatePath) { $CertificatePath } else { $cfg.CertificatePath }
        if ($tp) {
            $p['Thumbprint'] = $tp
        }
        elseif ($cp) {
            $p['CertificatePath'] = $cp
            if ($CertificatePassword) {
                $p['CertificatePassword'] = $CertificatePassword
            }
            elseif ($env:OPENGATESP_CERT_PASSWORD) {
                $p['CertificatePassword'] = ConvertTo-SecureString $env:OPENGATESP_CERT_PASSWORD -AsPlainText -Force
            }
        }
        else {
            throw "App-only auth needs -Thumbprint or -CertificatePath (or saved app-only config). See docs/05-app-only-auth.md."
        }
        $mode = 'AppOnly'
    }
    else {
        if ($DeviceLogin) { $p['DeviceLogin'] = $true } else { $p['Interactive'] = $true }
        $mode = 'Delegated'
    }

    Write-SPLog "Connecting to $connectUrl ($mode) ..."
    Invoke-SPRetry -Operation 'connect' { Connect-PnPOnline @p }

    if ($SaveConfig) {
        $save = @{ Url = $baseUrl; ClientId = $ClientId; Tenant = $Tenant; AuthMode = $mode }
        if ($mode -eq 'AppOnly') {
            if ($Thumbprint)      { $save['Thumbprint']      = $Thumbprint }
            if ($CertificatePath) { $save['CertificatePath'] = $CertificatePath }
        }
        Set-SPConfig -Settings $save | Out-Null
    }

    $web = $null
    try { $web = Get-PnPWeb -ErrorAction Stop } catch { }

    Write-SPLog "Connected to $connectUrl" -Level Success

    [pscustomobject]@{
        Url       = $connectUrl
        Title     = $web.Title
        ClientId  = $ClientId
        Tenant    = $Tenant
        Mode      = $mode
        Admin     = [bool]$Admin
        Connected = $true
    }
}
