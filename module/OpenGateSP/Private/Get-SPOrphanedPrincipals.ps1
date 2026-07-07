function Get-SPOrphanedPrincipals {
    <#
    .SYNOPSIS
        Given site principals and the set of valid directory logins, return the principals that
        no longer exist in the directory (orphaned/stale access). Case-insensitive. Pure.
    .DESCRIPTION
        Keeps only principals that can actually exist in the user directory — Entra membership
        claims (i:0#.f|membership|...) and bare UPNs/emails — normalizes them via
        ConvertTo-SPPrincipalKey, then returns any whose login is absent from the supplied
        directory set — the accounts a governance review should clean up. App, ACS add-in and
        system principals are never orphan candidates.
    .PARAMETER SitePrincipal
        Objects with a .LoginName (typically also .Title/.Email).
    .PARAMETER DirectoryLogin
        The valid UPNs/emails present in the directory.
    .OUTPUTS
        The subset of SitePrincipal that is not in the directory.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [object[]]$SitePrincipal,
        [string[]]$DirectoryLogin
    )

    $valid = @{}
    foreach ($d in $DirectoryLogin) { if ($d) { $valid[$d.ToLowerInvariant()] = $true } }

    $out = foreach ($p in $SitePrincipal) {
        if (-not $p) { continue }
        $raw = "$($p.LoginName)".Trim()
        # Only real directory users can be "orphaned". A claims login is a directory user only when it is
        # an Entra membership claim (i:0#.f|membership|...); app/ACS/system principals (app@sharepoint,
        # i:0i.t|..., c:..., i:0#.w|...) are never in the user directory by design — matching them would
        # strip valid app grants. A bare UPN/email (no claim prefix) is treated as a user.
        $isDirUser = if ($raw -like '*|*') { $raw -match '(?i)^i:0#\.f\|membership\|' }
                     else { ($raw -like '*@*') -and ($raw.ToLowerInvariant() -ne 'app@sharepoint') }
        if (-not $isDirUser) { continue }
        $login = ConvertTo-SPPrincipalKey $raw
        if (-not $valid.ContainsKey($login)) { $p }
    }
    @($out)
}
