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
    .PARAMETER Environment
        Connect to (or create) a NAMED ENVIRONMENT — a saved tenant connection profile.
        An existing name loads its saved Url/ClientId/Tenant/auth mode (explicit parameters
        override); a new name plus -ClientId creates it. Connecting to an environment always
        saves/updates it and makes it the active one, so later plain Connect-SPTool calls
        and silent reconnects follow the switch. List with Get-SPEnvironment; remove with
        Remove-SPEnvironment. See docs/03.
    .PARAMETER Admin
        Connect to the SharePoint admin centre (needed for tenant-wide reports).
    .PARAMETER DeviceLogin
        Delegated device-code flow instead of an interactive browser window.
    .PARAMETER OSLogin
        Delegated Windows-native sign-in via the OS broker (WAM): Windows Hello, FIDO keys,
        conditional-access device auth — no browser. Requires the Entra app to have the
        broker redirect URI (see docs/02); falls back to the browser automatically if the
        broker sign-in fails. Windows only.
    .PARAMETER PersistLogin
        Keep the sign-in across PowerShell sessions and reboots (PnP token cache) — sign in
        once, reconnect silently afterwards. Opt-in; clear it with
        Disconnect-SPTool -ClearPersistedLogin. Saved with -SaveConfig
        (-PersistLogin:$false turns a saved opt-in off).
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
    .EXAMPLE
        Connect-SPTool -Environment Contoso -Url https://contoso.sharepoint.com -ClientId 1111 -Tenant contoso.onmicrosoft.com
        Save the connection as the named environment "Contoso" and make it active.
    .EXAMPLE
        Connect-SPTool -Environment Fabrikam
        Switch to the saved "Fabrikam" environment (browser SSO signs you in).
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

        [string]$Environment,

        [switch]$Admin,

        [switch]$DeviceLogin,

        [switch]$OSLogin,

        [switch]$PersistLogin,

        [string]$Thumbprint,

        [string]$CertificatePath,

        [securestring]$CertificatePassword,

        [switch]$SaveConfig
    )

    $cfg = Get-SPConfig
    $envKey = $null
    if ($Environment) {
        $problems = @(Test-SPEnvironmentName -Name $Environment)
        if ($problems.Count) { throw ($problems -join ' ') }
        $v2 = ConvertTo-SPEnvironmentsConfig -Config $cfg
        $envKey = Resolve-SPEnvironmentKey $v2.Environments $Environment
        if ($envKey) {
            $cfg = $v2.Environments.$envKey       # defaults come from the named environment
        }
        elseif ($ClientId) {
            $envKey = $Environment.Trim()          # a new environment from explicit parameters
            $cfg = [pscustomobject]@{}
        }
        else {
            $known = @($v2.Environments.PSObject.Properties.Name)
            throw "Unknown environment '$Environment' and no -ClientId to create it. Known environment(s): $(if ($known) { $known -join ', ' } else { '(none)' })."
        }
    }
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

    # Auth mode + delegated flavor: explicit switches beat saved config; any delegated
    # switch overrides a saved AuthMode=AppOnly. Pure helper, unit-tested.
    $choice = Resolve-SPAuthChoice -Cfg $cfg -Thumbprint $Thumbprint -CertificatePath $CertificatePath `
        -DeviceLogin:$DeviceLogin -OSLogin:$OSLogin

    $p = @{ Url = $connectUrl; ClientId = $ClientId }
    if ($Tenant) { $p['Tenant'] = $Tenant }

    if ($choice.Mode -eq 'AppOnly') {
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
        switch ($choice.Flow) {
            'DeviceLogin' { $p['DeviceLogin'] = $true }
            'OSLogin'     { $p['OSLogin'] = $true }
            default       { $p['Interactive'] = $true }
        }
        # Opt-in "stay signed in": an explicit switch wins; otherwise the saved opt-in. PnP
        # only needs it once, but re-passing is harmless and restores the choice on a new machine.
        $persist = if ($PSBoundParameters.ContainsKey('PersistLogin')) { [bool]$PersistLogin } else { [bool]$cfg.PersistLogin }
        if ($persist) { $p['PersistLogin'] = $true }
        $mode = 'Delegated'
    }

    Write-SPLog "Connecting to $connectUrl ($mode$(if ($choice.Flow) { "/$($choice.Flow)" })) ..."
    $fellBack = $false
    try {
        Invoke-SPRetry -Operation 'connect' { Connect-PnPOnline @p }
    }
    catch {
        # Windows-broker sign-in can fail when the app registration lacks the broker
        # redirect URI (or the user cancels the native prompt) — fall back to the browser
        # rather than dead-ending; the browser flow needs no extra app setup.
        if (-not $p.ContainsKey('OSLogin')) { throw }
        Write-SPLog "Windows sign-in (broker) failed: $($_.Exception.Message). Falling back to browser sign-in - to enable Windows sign-in, add the broker redirect URI to your app (docs/02)." -Level Warn
        $p.Remove('OSLogin')
        $p['Interactive'] = $true
        $fellBack = $true
        Invoke-SPRetry -Operation 'connect (browser fallback)' { Connect-PnPOnline @p }
    }
    $flow = if ($mode -ne 'Delegated') { $null } elseif ($fellBack) { 'Interactive' } else { $choice.Flow }

    if ($SaveConfig -or $Environment) {
        $save = @{ Url = $baseUrl; ClientId = $ClientId; Tenant = $Tenant; AuthMode = $mode }
        if ($mode -eq 'AppOnly') {
            if ($Thumbprint)      { $save['Thumbprint']      = $Thumbprint }
            if ($CertificatePath) { $save['CertificatePath'] = $CertificatePath }
        }
        else {
            # Persist the flavor so plain Connect-SPTool (and every silent reconnect via
            # Get-SPConnectParams) reuses it. After a broker fallback, save the flow that
            # actually worked. PersistLogin is only written when explicitly chosen.
            $save['DelegatedFlow'] = $flow
            if ($PSBoundParameters.ContainsKey('PersistLogin')) { $save['PersistLogin'] = [bool]$PersistLogin }
        }
        if ($Environment) {
            # Connecting to a named environment saves/updates it and makes it ACTIVE —
            # the flat projection is rebuilt so every silent reconnect follows the switch.
            $v2 = Set-SPEnvironmentInConfig -Config (Get-SPConfig) -Name $envKey -Settings $save -MakeActive
            Save-SPConfigObject -Config $v2 | Out-Null
            Write-SPLog "Environment '$envKey' saved and active." -Level Debug
        }
        else {
            Set-SPConfig -Settings $save | Out-Null
        }
    }

    $web = $null
    try { $web = Get-PnPWeb -ErrorAction Stop } catch { }

    Write-SPLog "Connected to $connectUrl" -Level Success

    [pscustomobject]@{
        Url         = $connectUrl
        Title       = $web.Title
        ClientId    = $ClientId
        Tenant      = $Tenant
        Environment = $envKey
        Mode        = $mode
        Flow        = $flow
        FellBack    = $fellBack
        Admin       = [bool]$Admin
        Connected   = $true
    }
}
