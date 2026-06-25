function Resolve-SPSiteConnection {
    <#
    .SYNOPSIS
        Ensures there is an active connection to the requested site, reconnecting
        with saved credentials if the current connection points elsewhere. Lets the
        site-scoped functions target any site by URL without the caller manually
        reconnecting each time. Returns the resolved site URL.
    .NOTES
        The first connection to a given site may open a browser; subsequent calls use
        the cached token and are silent.
    #>
    [CmdletBinding()]
    param(
        [string]$SiteUrl
    )

    $current = $null
    try { $current = (Get-PnPConnection -ErrorAction Stop).Url } catch { $current = $null }

    if (-not $SiteUrl) {
        if (-not $current) { throw "Not connected. Run Connect-SPTool first." }
        return $current
    }

    if ($current -and ($current.TrimEnd('/') -ieq $SiteUrl.TrimEnd('/'))) {
        return $current   # already connected to the right site
    }

    $cfg = Get-SPConfig
    if (-not $cfg.ClientId) {
        throw "No saved ClientId. Run 'Connect-SPTool -ClientId <id> -Tenant <t> -SaveConfig' once so functions can target any site by URL."
    }

    $p = @{ Url = $SiteUrl; ClientId = $cfg.ClientId; Interactive = $true }
    if ($cfg.Tenant) { $p['Tenant'] = $cfg.Tenant }

    Write-SPLog "Connecting to $SiteUrl ..."
    Invoke-SPRetry -Operation "connect $SiteUrl" { Connect-PnPOnline @p }
    return $SiteUrl
}
