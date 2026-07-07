function Disconnect-SPTool {
    <#
    .SYNOPSIS
        Sign out: close the current PnP connection, optionally clearing the persisted
        sign-in cache so the next connect prompts again.
    .DESCRIPTION
        The counterpart to Connect-SPTool -PersistLogin. Without -ClearPersistedLogin only
        the in-memory connection closes (a persisted sign-in will still reconnect silently).
        Not being connected is a friendly no-op, not an error.

        Note: the PnP token cache is per app (client id), not per environment — clearing it
        signs you out of every environment that shares the same app registration.
    .PARAMETER ClearPersistedLogin
        Also clear the PnP persisted token cache (Disconnect-PnPOnline -ClearPersistedLogin).
    .PARAMETER AsJson
        Emit the result as JSON.
    .EXAMPLE
        Disconnect-SPTool -ClearPersistedLogin
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$ClearPersistedLogin,
        [switch]$AsJson
    )

    $wasConnected = $false
    try { $wasConnected = [bool](Get-PnPConnection) } catch { }

    if ($wasConnected) {
        $p = @{}
        if ($ClearPersistedLogin) { $p['ClearPersistedLogin'] = $true }
        Disconnect-PnPOnline @p
        Write-SPLog "Disconnected$(if ($ClearPersistedLogin) { ' and cleared the persisted sign-in' })." -Level Success
    }
    else {
        Write-SPLog 'No active connection - nothing to disconnect.'
    }

    [pscustomobject]@{
        Disconnected          = $wasConnected
        ClearedPersistedLogin = [bool]($wasConnected -and $ClearPersistedLogin)
    } | ConvertTo-SPOutput -AsJson:$AsJson
}
