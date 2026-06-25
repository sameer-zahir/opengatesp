function Assert-SPConnection {
    <#
    .SYNOPSIS
        Guard used by every operation: throws a friendly error if there is no
        active PnP connection. Returns the current connection on success.
    #>
    [CmdletBinding()]
    param()

    $conn = $null
    try { $conn = Get-PnPConnection -ErrorAction Stop } catch { $conn = $null }

    if (-not $conn) {
        throw "Not connected to SharePoint. Run Connect-SPTool first (see docs/03-quickstart.md)."
    }
    $conn
}
