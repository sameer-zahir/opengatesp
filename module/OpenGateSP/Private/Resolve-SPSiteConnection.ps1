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

    # Reconnect to the requested site using saved config (delegated or app-only).
    $p = Get-SPConnectParams -Url $SiteUrl

    Write-SPLog "Connecting to $SiteUrl ..."
    Invoke-SPRetry -Operation "connect $SiteUrl" { Connect-PnPOnline @p }
    return $SiteUrl
}
