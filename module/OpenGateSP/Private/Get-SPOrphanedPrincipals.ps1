function Get-SPOrphanedPrincipals {
    <#
    .SYNOPSIS
        Given site principals and the set of valid directory logins, return the principals that
        no longer exist in the directory (orphaned/stale access). Case-insensitive. Pure.
    .DESCRIPTION
        Normalizes each site principal's login (claims prefix stripped, via
        ConvertTo-SPPrincipalKey) and keeps only user/guest principals (those with an '@'),
        then returns any whose login is absent from the supplied directory set — the accounts
        a governance review should clean up.
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
        $login = ConvertTo-SPPrincipalKey "$($p.LoginName)"
        if ($login -notlike '*@*') { continue }            # skip SP groups / system principals
        if (-not $valid.ContainsKey($login)) { $p }
    }
    @($out)
}
