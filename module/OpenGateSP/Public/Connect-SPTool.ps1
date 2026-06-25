function Connect-SPTool {
    <#
    .SYNOPSIS
        Connect to SharePoint Online using your own registered Entra ID app
        (interactive delegated auth by default).
    .DESCRIPTION
        Wraps Connect-PnPOnline. Since 2024-09-09 PnP.PowerShell requires your own
        Entra ID app registration and a -ClientId (see docs/02-entra-app-registration.md).
        Connection defaults (Url, ClientId, Tenant) can be saved with -SaveConfig and are
        reused on later calls, so day-to-day you can just run `Connect-SPTool`.

        Delegated auth means the tool can never do more than the signed-in user is
        already allowed to do in SharePoint.
    .PARAMETER Url
        Site URL, e.g. https://contoso.sharepoint.com/sites/Team. If omitted, falls back
        to saved config, or is derived from -Tenant (the root site).
    .PARAMETER ClientId
        Application (client) ID of your registered Entra ID app.
    .PARAMETER Tenant
        Tenant name, e.g. contoso.onmicrosoft.com.
    .PARAMETER Admin
        Connect to the SharePoint admin centre (https://<tenant>-admin.sharepoint.com),
        required for tenant-wide operations like Get-SPSiteInventory. Needs the
        SharePoint Administrator role.
    .PARAMETER DeviceLogin
        Use device-code flow instead of an interactive browser window (headless / SSH).
    .PARAMETER SaveConfig
        Persist Url/ClientId/Tenant to the user profile so future calls need no args.
    .EXAMPLE
        Connect-SPTool -Url https://contoso.sharepoint.com -ClientId 1111-2222 -Tenant contoso.onmicrosoft.com -SaveConfig
    .EXAMPLE
        Connect-SPTool -Admin
        Reconnect to the admin centre using saved defaults.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string]$Url,

        [string]$ClientId,

        [string]$Tenant,

        [switch]$Admin,

        [Parameter(ParameterSetName = 'DeviceLogin')]
        [switch]$DeviceLogin,

        [switch]$SaveConfig
    )

    $cfg = Get-SPConfig
    if (-not $ClientId) { $ClientId = $cfg.ClientId }
    if (-not $Tenant)   { $Tenant   = $cfg.Tenant }
    if (-not $Url)      { $Url      = $cfg.Url }

    if (-not $ClientId) {
        throw "No ClientId. Register an Entra ID app (docs/02-entra-app-registration.md), then pass -ClientId (optionally with -SaveConfig)."
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

    $connectParams = @{ Url = $connectUrl; ClientId = $ClientId }
    if ($Tenant)      { $connectParams['Tenant']      = $Tenant }
    if ($DeviceLogin) { $connectParams['DeviceLogin'] = $true }
    else              { $connectParams['Interactive'] = $true }

    Write-SPLog "Connecting to $connectUrl ..."
    Invoke-SPRetry -Operation 'connect' { Connect-PnPOnline @connectParams }

    if ($SaveConfig) {
        Set-SPConfig -Settings @{ Url = $baseUrl; ClientId = $ClientId; Tenant = $Tenant } | Out-Null
    }

    $web = $null
    try { $web = Get-PnPWeb -ErrorAction Stop } catch { }

    Write-SPLog "Connected to $connectUrl" -Level Success

    [pscustomobject]@{
        Url       = $connectUrl
        Title     = $web.Title
        ClientId  = $ClientId
        Tenant    = $Tenant
        Admin     = [bool]$Admin
        Connected = $true
    }
}
